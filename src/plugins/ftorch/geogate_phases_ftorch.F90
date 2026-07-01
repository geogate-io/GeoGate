module geogate_phases_ftorch

  !-----------------------------------------------------------------------------
  ! Phase for ML model inference using FTorch (Fortran bindings for PyTorch)
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_GridComp, ESMF_GridCompGetInternalState
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_FAILURE, ESMF_SUCCESS, ESMF_MAXSTR, ESMF_KIND_R8
  use ESMF, only: ESMF_Field, ESMF_FieldGet
  use ESMF, only: ESMF_FieldBundle, ESMF_FieldBundleGet, ESMF_FieldBundleIsCreated
  use ESMF, only: ESMF_UtilStringLowerCase

  use NUOPC, only: NUOPC_CompAttributeGet

  use geogate_share, only: ChkErr, StringSplit
  use geogate_internalstate, only: InternalState

  use ftorch, only: torch_model, torch_tensor
  use ftorch, only: torch_kCPU, torch_kCUDA
  use ftorch, only: torch_model_load, torch_model_forward, torch_delete
  use ftorch, only: torch_tensor_from_array

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: geogate_phases_ftorch_run

  !-----------------------------------------------------------------------------
  ! Private module routines
  !-----------------------------------------------------------------------------

  private :: FindFieldInFBImp

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  type(torch_model) :: model
  integer :: deviceType = torch_kCPU
  integer :: deviceIndex = 0
  character(ESMF_MAXSTR), allocatable :: inputFieldNames(:)
  character(ESMF_MAXSTR), allocatable :: outputFieldNames(:)
  character(len=*), parameter :: modName = "(geogate_phases_ftorch)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine geogate_phases_ftorch_run(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    logical :: isPresent, isSet
    logical, save :: first_time = .true.
    type(InternalState) :: is_local
    type(ESMF_Field) :: field
    type(torch_tensor), allocatable :: inTensors(:)
    type(torch_tensor), allocatable :: outTensors(:)
    real(ESMF_KIND_R8), pointer, contiguous :: farrayPtr(:)
    character(ESMF_MAXSTR) :: cvalue, message
    character(ESMF_MAXSTR) :: modelFile
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_ftorch_run) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Get internal state
    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Initialize
    if (first_time) then
       ! TorchScript model file (required)
       call NUOPC_CompAttributeGet(gcomp, name="FtorchModelFile", value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       if (.not. (isPresent .and. isSet)) then
          call ESMF_LogWrite(trim(subname)//": FtorchModelFile is required to load a TorchScript model!", &
            ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if
       modelFile = trim(cvalue)
       call ESMF_LogWrite(trim(subname)//": FtorchModelFile = "//trim(modelFile), ESMF_LOGMSG_INFO)

       ! Device type used to run the model (optional, default cpu)
       call NUOPC_CompAttributeGet(gcomp, name="FtorchDevice", value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       deviceType = torch_kCPU
       if (isPresent .and. isSet) then
          if (trim(ESMF_UtilStringLowerCase(trim(cvalue))) == 'cuda') deviceType = torch_kCUDA
       end if
       write(message, fmt='(A,I2)') trim(subname)//' : FtorchDevice = ', deviceType
       call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)

       ! Device index used for GPU devices (optional, default 0)
       call NUOPC_CompAttributeGet(gcomp, name="FtorchDeviceIndex", value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       deviceIndex = 0
       if (isPresent .and. isSet) then
          read(cvalue, *) deviceIndex
       end if

       ! List of import fields used as model input, in the order expected by the model (required)
       call NUOPC_CompAttributeGet(gcomp, name="FtorchInputFields", value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       if (.not. (isPresent .and. isSet)) then
          call ESMF_LogWrite(trim(subname)//": FtorchInputFields is required to determine the model input tensor order!", &
            ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if
       inputFieldNames = StringSplit(trim(cvalue), ":")
       do n = 1, size(inputFieldNames, dim=1)
          write(message, fmt='(A,I2.2,A)') trim(subname)//': FtorchInputFields(',n,') = '//trim(inputFieldNames(n))
          call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
       end do

       ! List of export fields filled with model output, in the order produced by the model (required)
       ! Field names need to match entries already present in the export field bundle (i.e. the
       ! ExportFields runtime configuration option)
       call NUOPC_CompAttributeGet(gcomp, name="FtorchOutputFields", value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       if (.not. (isPresent .and. isSet)) then
          call ESMF_LogWrite(trim(subname)//": FtorchOutputFields is required to determine the model output tensor order!", &
            ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if
       outputFieldNames = StringSplit(trim(cvalue), ":")
       do n = 1, size(outputFieldNames, dim=1)
          write(message, fmt='(A,I2.2,A)') trim(subname)//': FtorchOutputFields(',n,') = '//trim(outputFieldNames(n))
          call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
       end do

       ! Load TorchScript model
       if (deviceType == torch_kCPU) then
          call torch_model_load(model, trim(modelFile), deviceType)
       else
          call torch_model_load(model, trim(modelFile), deviceType, device_index=deviceIndex)
       end if

       ! Set flag
       first_time = .false.
    end if

    ! Export field bundle needs to be created to hold the model output
    if (.not. ESMF_FieldBundleIsCreated(is_local%wrap%FBExp)) then
       call ESMF_LogWrite(trim(subname)//": export field bundle is not created, skip FTorch inference!", &
         ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Create input tensors directly pointing at the import field data
    allocate(inTensors(size(inputFieldNames, dim=1)))
    do n = 1, size(inputFieldNames, dim=1)
       call FindFieldInFBImp(is_local, trim(inputFieldNames(n)), field, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       call ESMF_FieldGet(field, farrayPtr=farrayPtr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       if (deviceType == torch_kCPU) then
          call torch_tensor_from_array(inTensors(n), farrayPtr, deviceType)
       else
          call torch_tensor_from_array(inTensors(n), farrayPtr, deviceType, device_index=deviceIndex)
       end if
       nullify(farrayPtr)
    end do

    ! Create output tensors directly pointing at the export field data so that the forward pass
    ! writes the model output in place. Output tensors always live on the CPU since they are
    ! subsequently consumed by Fortran/ESMF.
    allocate(outTensors(size(outputFieldNames, dim=1)))
    do n = 1, size(outputFieldNames, dim=1)
       call ESMF_FieldBundleGet(is_local%wrap%FBExp, fieldName=trim(outputFieldNames(n)), field=field, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       call ESMF_FieldGet(field, farrayPtr=farrayPtr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       call torch_tensor_from_array(outTensors(n), farrayPtr, torch_kCPU)
       nullify(farrayPtr)
    end do

    ! Run inference
    call torch_model_forward(model, inTensors, outTensors)

    ! Clean up tensors (the model itself is kept loaded and reused across time steps)
    call torch_delete(inTensors)
    call torch_delete(outTensors)
    deallocate(inTensors)
    deallocate(outTensors)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_ftorch_run

  !-----------------------------------------------------------------------------

  subroutine FindFieldInFBImp(is_local, fieldName, field, rc)

    ! input/output variables
    type(InternalState), intent(in) :: is_local
    character(len=*), intent(in) :: fieldName
    type(ESMF_Field), intent(out) :: field
    integer, intent(out), optional :: rc

    ! local variables
    integer :: n, m, fieldCount
    logical :: found
    character(ESMF_MAXSTR), allocatable :: fieldNameList(:)
    character(len=*), parameter :: subname = trim(modName)//':(FindFieldInFBImp) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS

    ! Loop over import field bundles of all connected components and return the first match
    found = .false.
    do n = 1, is_local%wrap%numComp
       call ESMF_FieldBundleGet(is_local%wrap%FBImp(n), fieldCount=fieldCount, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       allocate(fieldNameList(fieldCount))
       call ESMF_FieldBundleGet(is_local%wrap%FBImp(n), fieldNameList=fieldNameList, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       do m = 1, fieldCount
          if (trim(fieldNameList(m)) == trim(fieldName)) then
             call ESMF_FieldBundleGet(is_local%wrap%FBImp(n), fieldName=trim(fieldName), field=field, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return
             found = .true.
             exit
          end if
       end do
       deallocate(fieldNameList)
       if (found) exit
    end do

    if (.not. found) then
       call ESMF_LogWrite(trim(subname)//": field "//trim(fieldName)//" was not found in any import field bundle!", &
         ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

  end subroutine FindFieldInFBImp

end module geogate_phases_ftorch
