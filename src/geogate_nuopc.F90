module geogate_nuopc

  !-----------------------------------------------------------------------------
  ! This is the NUOPC cap for GeoGate 
  !-----------------------------------------------------------------------------

  use ESMF, only: operator(==)
  use ESMF, only: ESMF_GridComp, ESMF_MethodRemove
  use ESMF, only: ESMF_Field, ESMF_FieldGet, ESMF_FieldEmptySet
  use ESMF, only: ESMF_State, ESMF_StateGet, ESMF_StateRemove
  use ESMF, only: ESMF_Clock, ESMF_LogWrite, ESMF_LogFoundAllocError
  use ESMF, only: ESMF_StateGet, ESMF_GridCompSetEntryPoint
  use ESMF, only: ESMF_GridCompGetInternalState, ESMF_GridCompSetInternalState
  use ESMF, only: ESMF_AttributeGet, ESMF_DistGridConnection
  use ESMF, only: ESMF_Grid, ESMF_GridCreate, ESMF_GridGet
  use ESMF, only: ESMF_Mesh, ESMF_MeshCreate, ESMF_MeshGet, ESMF_MeshEmptyCreate
  use ESMF, only: ESMF_DistGrid, ESMF_DistGridCreate, ESMF_DistGridGet
  use ESMF, only: ESMF_FAILURE, ESMF_LOGMSG_INFO, ESMF_SUCCESS
  use ESMF, only: ESMF_METHOD_INITIALIZE, ESMF_MAXSTR, ESMF_LOGMSG_WARNING
  use ESMF, only: ESMF_GEOMTYPE_GRID, ESMF_GEOMTYPE_MESH
  use ESMF, only: ESMF_FIELDSTATUS_GRIDSET, ESMF_FIELDSTATUS_EMPTY
  use ESMF, only: ESMF_FIELDSTATUS_COMPLETE, ESMF_StateItem_Flag
  use ESMF, only: ESMF_STATEITEM_STATE, ESMF_STATEITEM_FIELD
  use ESMF, only: ESMF_LOGMSG_ERROR, ESMF_METHOD_RUN
  use ESMF, only: ESMF_GeomType_Flag, ESMF_FieldStatus_Flag
  use ESMF, only: ESMF_Time, ESMF_TimeGet, ESMF_TimeInterval
  use ESMF, only: ESMF_Clock, ESMF_ClockGet, ESMF_ClockSet
  use ESMF, only: ESMF_Info, ESMF_InfoGetFromHost, ESMF_InfoSet
  use ESMF, only: ESMF_UtilStringLowerCase
  use ESMF, only: ESMF_DistGridGet, ESMF_DistGridConnection
  use ESMF, only: ESMF_FieldCreate, ESMF_StateIsCreated
  use ESMF, only: ESMF_GridGetCoord, ESMF_STAGGERLOC_CORNER
  use ESMF, only: ESMF_TYPEKIND_R8, ESMF_MESHLOC_ELEMENT
  use ESMF, only: ESMF_FieldFill, ESMF_FILEFORMAT_ESMFMESH

  use NUOPC, only: NUOPC_CompDerive
  use NUOPC, only: NUOPC_CompSpecialize
  use NUOPC, only: NUOPC_CompFilterPhaseMap, NUOPC_CompSetEntryPoint
  use NUOPC, only: NUOPC_SetAttribute, NUOPC_GetAttribute
  use NUOPC, only: NUOPC_CompAttributeGet, NUOPC_CompAttributeSet
  use NUOPC, only: NUOPC_CompCheckSetClock
  use NUOPC, only: NUOPC_Advertise
  use NUOPC, only: NUOPC_Realize
  use NUOPC, only: NUOPC_FieldDictionarySetAutoAdd, NUOPC_AddNamespace
  use NUOPC, only: NUOPC_NoOP
 
  use NUOPC_Model, only: SetVM
  use NUOPC_Model, only: NUOPC_ModelGet
  use NUOPC_Model, only: model_routine_SS => SetServices
  use NUOPC_Model, only: model_routine_Run => routine_Run
  use NUOPC_Model, only: model_label_DataInitialize => label_DataInitialize
  use NUOPC_Model, only: model_label_Advance => label_Advance
  use NUOPC_Model, only: label_Advertise
  use NUOPC_Model, only: label_ModifyAdvertised
  use NUOPC_Model, only: label_AcceptTransfer
  use NUOPC_Model, only: label_RealizeAccepted
  use NUOPC_Model, only: label_RealizeProvided
  use NUOPC_Model, only: label_Advance
  use NUOPC_Model, only: label_CheckImport
  use NUOPC_Model, only: label_SetRunClock

  use geogate_share, only: ChkErr
  use geogate_share, only: FB_init_pointer
  use geogate_share, only: StringSplit
  use geogate_share, only: debugMode
  use geogate_share, only: fillValue
  
  use geogate_internalstate, only: InternalState
  use geogate_internalstate, only: InternalStateInit 

  use geogate_phases_io, only: geogate_phases_io_run
  use geogate_phases_python, only: geogate_phases_python_run
  use geogate_phases_catalyst, only: geogate_phases_catalyst_run

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: SetServices
  public :: SetVM

  !-----------------------------------------------------------------------------
  ! Private module routines
  !-----------------------------------------------------------------------------

  private :: DataInitialize
  private :: SetRunClock

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  integer :: dbug = 0
  character(len=ESMF_MAXSTR), allocatable :: exportFieldNameList(:)
  character(len=*), parameter :: modName = "(geogate_nuopc)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine SetServices(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(SetServices) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    !------------------
    ! register the generic methods
    !------------------

    call NUOPC_CompDerive(gcomp, model_routine_SS, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! specialize model
    !------------------
    
    ! It is used to set FieldTransferPolicy 
    call NUOPC_CompSpecialize(gcomp, specLabel=label_Advertise, specRoutine=Advertise, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! It is used to remove some fields from the list of mirrored fields
    call NUOPC_CompSpecialize(gcomp, specLabel=label_ModifyAdvertised, specRoutine=ModifyAdvertised, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! It is used to change domain decomposition
    call NUOPC_CompSpecialize(gcomp, specLabel=label_AcceptTransfer, specRoutine=AcceptTransfer, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! It is used to realized mirrored fields and also update decomposition
    call NUOPC_CompSpecialize(gcomp, specLabel=label_RealizeAccepted, specRoutine=RealizeAccepted, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! It is used to realize export fields
    call NUOPC_CompSpecialize(gcomp, specLabel=label_RealizeProvided, specRoutine=RealizeProvided, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! It is used for data initialization
    call NUOPC_CompSpecialize(gcomp, specLabel=model_label_DataInitialize, specRoutine=DataInitialize, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! It is used to run user specified phase to process the data
    call NUOPC_CompSpecialize(gcomp, specLabel=model_label_Advance, specRoutine=Advance, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! setup custom phases
    !------------------

    ! I/O phase
    call NUOPC_CompSetEntryPoint(gcomp, ESMF_METHOD_RUN, phaseLabelList=(/ 'geogate_phases_io' /), userRoutine=model_routine_Run, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NUOPC_CompSpecialize(gcomp, specLabel=model_label_Advance, specPhaseLabel="geogate_phases_io", specRoutine=geogate_phases_io_run, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Python phase
    call NUOPC_CompSetEntryPoint(gcomp, ESMF_METHOD_RUN, phaseLabelList=(/ 'geogate_phases_python' /), userRoutine=model_routine_Run, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NUOPC_CompSpecialize(gcomp, specLabel=model_label_Advance, specPhaseLabel="geogate_phases_python", specRoutine=geogate_phases_python_run, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! ParaView Catalyst phase
    call NUOPC_CompSetEntryPoint(gcomp, ESMF_METHOD_RUN, phaseLabelList=(/"geogate_phases_catalyst"/), userRoutine=model_routine_Run, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NUOPC_CompSpecialize(gcomp, specLabel=model_label_Advance, specPhaseLabel="geogate_phases_catalyst", specRoutine=geogate_phases_catalyst_run, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Attach specializing method(s)
    !------------------

    call ESMF_MethodRemove(gcomp, label_CheckImport, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NUOPC_CompSpecialize(gcomp, specLabel=label_CheckImport, specRoutine=NUOPC_NoOp, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! This is called every time you enter a component phase
    call ESMF_MethodRemove(gcomp, label_SetRunClock, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NUOPC_CompSpecialize(gcomp, specLabel=label_SetRunClock, specRoutine=SetRunClock, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine SetServices

  !-----------------------------------------------------------------------------

  subroutine Advertise(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: stat, n, itemCount
    logical :: isPresent, isSet
    type(InternalState) :: is_local
    type(ESMF_State) :: importState, exportState
    character(len=*), parameter :: subname = trim(modName)//':(Advertise) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    !------------------
    ! Allocate memory for the internal state
    !------------------

    allocate(is_local%wrap, stat=stat)
    if (ESMF_LogFoundAllocError(statusToCheck=stat, &
         msg="Allocation of the internal state memory failed.", line=__LINE__, file=u_FILE_u)) then
       return
    end if

    call ESMF_GridCompSetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Query for importState and exportState
    !------------------

    call NUOPC_ModelGet(gcomp, importState=importState, exportState=exportState, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Set attribute for field mirroring
    ! It indicates that fields should be mirrored in the State of a connected component
    !------------------

    call NUOPC_SetAttribute(importState, "FieldTransferPolicy", "transferAllWithNamespace", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Add fields to export state
    !------------------

    ! Check number of export fields
    itemCount = 0
    call NUOPC_CompAttributeGet(gcomp, name="ExportFields", itemCount=itemCount, &
      isPresent=isPresent, isSet=isSet, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    if (itemCount > 0) then
       ! Allocate array for field list
       allocate(exportFieldNameList(itemCount))

       ! Query for list of export fields
       call NUOPC_CompAttributeGet(gcomp, name="ExportFields", valueList=exportFieldNameList, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Add fields to export state
       do n = 1, itemCount
          call NUOPC_Advertise(exportState, standardName=trim(exportFieldNameList(n)), &
             TransferOfferGeomObject='will provide', rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
       end do
    end if

    !------------------
    ! Enable adding fields to field dictionary automatically
    ! Note that NUOPC_FieldDictionarySetAutoAdd() is not part of the public API and not documented
    !------------------

    call NUOPC_FieldDictionarySetAutoAdd(.true., rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine Advertise

  !-----------------------------------------------------------------------------

  subroutine ModifyAdvertised(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp  
    integer, intent(out) :: rc

    ! local variables
    integer :: i, j, k, n
    integer :: stat
    integer :: fieldCount, itemCount
    integer :: importItemCount, importNestedItemCount
    logical :: isPresent, isSet, isFound
    type(InternalState) :: is_local
    type(ESMF_Field) :: field
    type(ESMF_State) :: importState
    type(ESMF_State) :: importNestedState
    character(ESMF_MAXSTR), allocatable :: fieldNamesToKeep(:)
    character(ESMF_MAXSTR), allocatable :: lfieldnamelist(:)
    character(ESMF_MAXSTR), allocatable :: fieldNamesToRemove(:)
    character(ESMF_MAXSTR) :: namespace
    character(ESMF_MAXSTR) :: message, cname, cvalue, scalar_field_name = ''
    character(ESMF_MAXSTR), allocatable     :: importItemNameList(:)
    type(ESMF_StateItem_Flag), allocatable  :: importItemTypeList(:)
    character(ESMF_MAXSTR), allocatable     :: importNestedItemNameList(:)
    type(ESMF_StateItem_Flag), allocatable  :: importNestedItemTypeList(:)

    character(len=*), parameter :: subname = trim(modName)//':(ModifyAdvertised) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    !------------------
    ! Query internal state 
    !------------------

    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Query for ScalarFieldName
    !------------------

    scalar_field_name = ""
    call NUOPC_CompAttributeGet(gcomp, name="ScalarFieldName", value=cvalue, &
      isPresent=isPresent, isSet=isSet, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    if (isPresent .and. isSet) then
       scalar_field_name = trim(cvalue)
       call ESMF_LogWrite(trim(subname)//": ScalarFieldName = "//trim(scalar_field_name), ESMF_LOGMSG_INFO)
    endif

    !------------------
    ! Query for KeepFieldList (only list of fields will be available)
    !------------------

    call NUOPC_CompAttributeGet(gcomp, name="KeepFieldList", value=cvalue, &
      isPresent=isPresent, isSet=isSet, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    if (isPresent .and. isSet) then
       ! Split string
       fieldNamesToKeep = StringSplit(trim(cvalue), ":")
       do n = 1, size(fieldNamesToKeep, dim=1)
          write(message, fmt='(A,I2.2,A)') trim(subname)//': KeepFieldList(',n,') = '//trim(fieldNamesToKeep(n))
          call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
       end do
    endif

    !------------------
    ! Query for RemoveFieldList (remove fields from mirrored field list)
    !------------------

    if (size(fieldNamesToKeep, dim=1) > 0) then
       call ESMF_LogWrite(trim(subname)//': KeepFieldList is provided. Neglecting entries of RemoveFieldList!', ESMF_LOGMSG_INFO)
    else
       call NUOPC_CompAttributeGet(gcomp, name="RemoveFieldList", value=cvalue, &
          isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       if (isPresent .and. isSet) then
          ! Add scalar field to remove list
          if (trim(scalar_field_name) /= '') then
             if (trim(cvalue) == '') then
                cvalue = trim(scalar_field_name)
             else
                cvalue = trim(cvalue)//':'//trim(scalar_field_name)
             end if
          end if
          ! Split string
          fieldNamesToRemove = StringSplit(trim(cvalue), ":")
          do n = 1, size(fieldNamesToKeep, dim=1)
             write(message, fmt='(A,I2.2,A)') trim(subname)//': RemoveFieldList(',n,') = '//trim(fieldNamesToRemove(n))
             call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
          end do
       else
          ! Allocate temporary array for field list
          if (trim(scalar_field_name) /= "") then
             allocate(fieldNamesToRemove(1))
             fieldNamesToRemove(1) = trim(scalar_field_name)
          end if
       end if
    end if

    !------------------
    ! Query for importState
    !------------------

    call NUOPC_ModelGet(gcomp, importState=importState, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Loop over import fields and remove/keep requested fields if there are
    !------------------

    call ESMF_StateGet(importState, nestedFlag=.false., itemCount=importItemCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Allocate temporary data structures
    allocate(importItemNameList(importItemCount))
    allocate(importItemTypeList(importItemCount))

    ! Query state
    call ESMF_StateGet(importState, nestedFlag=.false., itemNameList=importItemNameList, itemTypeList=importItemTypeList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Loop over nested states if they are found and filter fields 
    do i = 1, importItemCount
       if (importItemTypeList(i) == ESMF_STATEITEM_STATE) then
          ! Get the associated nested state
          call ESMF_StateGet(importState, itemName=importItemNameList(i), nestedState=importNestedState, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Query nested state
          call ESMF_StateGet(importNestedState, itemCount=importNestedItemCount, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Allocate temporary data structures
          allocate(importNestedItemNameList(importNestedItemCount))
          allocate(importNestedItemTypeList(importNestedItemCount))

          ! Query item name and types in the nested state
          call ESMF_StateGet(importNestedState, itemNameList=importNestedItemNameList, &
             itemTypeList=importNestedItemTypeList, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Query namespace
          call NUOPC_GetAttribute(importNestedState, name="Namespace", value=namespace, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          namespace = ESMF_UtilStringLowerCase(trim(namespace))

          ! Print debug information
          write(message, fmt='(A,I5,A)') trim(subname)//': nested import state from '//trim(namespace)//' has ', importNestedItemCount, ' item'
          call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)

          ! Keep only desired fields
          if (size(fieldNamesToKeep, dim=1) > 0) then
             do j = 1, importNestedItemCount
                call ESMF_LogWrite(trim(subname)//': '//trim(importNestedItemNameList(j)), ESMF_LOGMSG_INFO)

                ! Check field is in the keep list
                isFound = .false.
                do k = 1, size(fieldNamesToKeep, dim=1)
                   if (trim(importNestedItemNameList(j)) == trim(fieldNamesToKeep(k))) then
                      isFound = .true.
                      cycle
                   end if
                end do

                ! Remove field from import state if it is not specified in the keep list
                if (.not. isFound) then
                   call ESMF_LogWrite(trim(subname)//': '//trim(importNestedItemNameList(j))//' will be removed', ESMF_LOGMSG_INFO)
                   call ESMF_StateRemove(importNestedState, itemNameList=(/trim(importNestedItemNameList(j))/), relaxedFlag=.true., rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return
                   cycle
                end if
             end do
          end if

          if (allocated(fieldNamesToRemove)) then
             if (size(fieldNamesToRemove, dim=1) > 0) then
                ! Print out field names that will be removed
                do j = 1, size(fieldNamesToRemove, dim=1)
                   call ESMF_LogWrite(trim(subname)//': '//trim(fieldNamesToRemove(j))//' will be removed', ESMF_LOGMSG_INFO)
                end do
                ! Remove field/s from state
                call ESMF_StateRemove(importNestedState, itemNameList=fieldNamesToRemove, relaxedFlag=.true., rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return
             end if
          end if

          ! Clean memory
          deallocate(importNestedItemNameList)
          deallocate(importNestedItemTypeList)
       end if
    end do

    ! Clean memory
    deallocate(importItemNameList)
    deallocate(importItemTypeList)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)
    
  end subroutine ModifyAdvertised

  !-----------------------------------------------------------------------------

  subroutine AcceptTransfer(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    integer :: itemCount
    logical :: hasNestedState
    type(InternalState) :: is_local
    type(ESMF_State) :: importState
    character(ESMF_MAXSTR), allocatable     :: itemNameList(:)
    type(ESMF_StateItem_Flag), allocatable  :: itemTypeList(:)
    character(len=*), parameter :: subname = trim(modName)//':(AcceptTransfer) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Get the internal state
    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Initialize internal state
    call InternalStateInit(gcomp, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query import state
    call NUOPC_ModelGet(gcomp, importState=importState, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query state for nested states
    call ESMF_StateGet(importState, nestedFlag=.false., itemCount=itemCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Check for nested states
    hasNestedState = .false.
    if (itemCount > 0) then
       ! Allocate temporary data structures
       allocate(itemNameList(itemCount))
       allocate(itemTypeList(itemCount))

       ! Query state
       call ESMF_StateGet(importState, nestedFlag=.false., itemNameList=itemNameList, itemTypeList=itemTypeList, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Set flag if nested state is found
       do n = 1, itemCount
          if (itemTypeList(n) == ESMF_STATEITEM_STATE) hasNestedState = .true.
       end do
    end if

    ! Loop over nested states
    if (hasNestedState) then
       do n = 1, itemCount
          if (itemTypeList(n) == ESMF_STATEITEM_STATE) then
             ! Get the associated nested state
             call ESMF_StateGet(importState, itemName=itemNameList(n), nestedState=is_local%wrap%NStateImp(n), rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ! Replace decomposition
             call ModifyDecomp(is_local%wrap%NStateImp(n), rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return
          end if
       end do
    end if

    ! Clean memory
    if (allocated(itemNameList)) deallocate(itemNameList)
    if (allocated(itemTypeList)) deallocate(itemTypeList)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine AcceptTransfer

  !-----------------------------------------------------------------------------

  subroutine RealizeAccepted(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n, m
    integer :: itemCount
    type(InternalState) :: is_local
    character(ESMF_MAXSTR), allocatable     :: itemNameList(:)
    type(ESMF_StateItem_Flag), allocatable  :: itemTypeList(:)
    character(len=*), parameter :: subname = trim(modName)//':(RealizeAccepted) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Get the internal state
    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Loop over import states
    do n = 1, is_local%wrap%numComp
       ! Query state
       call ESMF_StateGet(is_local%wrap%NStateImp(n), itemCount=itemCount, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Check if any connected component
       if (itemCount > 0) then
          ! Allocate temporary data structures
          allocate(itemNameList(itemCount))
          allocate(itemTypeList(itemCount))

          ! Query state
          call ESMF_StateGet(is_local%wrap%NStateImp(n), nestedFlag=.false., itemNameList=itemNameList, itemTypeList=itemTypeList, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Loop over fields and realize them
          do m = 1, itemCount
             if (itemTypeList(m) == ESMF_STATEITEM_FIELD) then
                ! Replace grid with mesh
                call GridToMesh(is_local%wrap%NStateImp(n), rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                ! Realize field
                call NUOPC_Realize(is_local%wrap%NStateImp(n), fieldName=trim(itemNameList(m)), rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return
             end if
          end do

          ! Clean memory
          if (allocated(itemNameList)) deallocate(itemNameList)
          if (allocated(itemTypeList)) deallocate(itemTypeList)
       end if
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)
 
  end subroutine RealizeAccepted

  !-----------------------------------------------------------------------------

  subroutine RealizeProvided(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    logical :: isPresent, isSet
    type(ESMF_Field) :: meshField
    type(InternalState) :: is_local
    character(len=ESMF_MAXSTR) :: mesh_file
    character(len=ESMF_MAXSTR) :: cvalue
    character(len=*), parameter :: subname = trim(modName)//':(RealizeProvided) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Get the internal state
    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query for ESMF mesh file for export fields
    mesh_file = ""
    call NUOPC_CompAttributeGet(gcomp, name="ExportMeshFile", value=cvalue, &
      isPresent=isPresent, isSet=isSet, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    if (isPresent .and. isSet) then
       mesh_file = trim(cvalue)
       call ESMF_LogWrite(trim(subname)//": ExportMeshFile = "//trim(mesh_file), ESMF_LOGMSG_INFO)
    else
       call ESMF_LogWrite(trim(subname)//": ExportMeshFile needs to be set to add fields. "// &
          "Skip adding fields to export state!", ESMF_LOGMSG_INFO)
       return
    endif

    ! Check number of export fields
    if (size(exportFieldNameList) > 0) then
       ! Create mesh from mesh file
       is_local%wrap%meshExp = ESMF_MeshCreate(trim(mesh_file), fileformat=ESMF_FILEFORMAT_ESMFMESH, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Query for exportState
       call NUOPC_ModelGet(gcomp, exportState=is_local%wrap%NStateExp, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Create fields
       ! Assuming that all fields share the same grid/mesh
       do n = 1, size(exportFieldNameList)
          ! Create field on mesh
          meshField = ESMF_FieldCreate(is_local%wrap%meshExp, typekind=ESMF_TYPEKIND_R8, &
            meshloc=ESMF_MESHLOC_ELEMENT, name=trim(exportFieldNameList(n)), rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Initialize field
          call ESMF_FieldFill(meshField, dataFillScheme="const", const1=fillValue, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Realize field
          call NUOPC_Realize(is_local%wrap%NStateExp, field=meshField, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
       end do

       ! Add field to FB for easy access
       call FB_init_pointer(is_local%wrap%NStateExp, is_local%wrap%FBExp, name='FBExp', rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end if

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine RealizeProvided

  !-----------------------------------------------------------------------------

  subroutine DataInitialize(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    type(InternalState) :: is_local
    logical :: isPresent, isSet
    logical, save :: first_call = .true.
    character(len=255) :: cvalue
    character(len=255) :: msg
    character(len=*), parameter :: subname = trim(modName)//':(DataInitialize) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Get the internal state
    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! First call block
    if (first_call) then
       ! Create field bundle FBImp
       do n = 1, is_local%wrap%numComp
          if (ESMF_StateIsCreated(is_local%wrap%NStateImp(n), rc=rc)) then
             ! Print debug info
             call ESMF_LogWrite(trim(subname)//': initializing FBs for '//trim(is_local%wrap%compName(n)), ESMF_LOGMSG_INFO)

             ! Create FBImp(:) with pointers directly into NStateImp(:)
             call FB_init_pointer(is_local%wrap%NStateImp(n), is_local%wrap%FBImp(n), name='FBImp'//trim(is_local%wrap%compName(n)), rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return
          end if
       end do

       ! Set first call flag
       first_call = .false.

       ! Return
       return
    end if

    ! Set InitializeDataComplete Component Attribute to "true", indicating
    ! to the driver that this Component has fully initialized its data
    call NUOPC_CompAttributeSet(gcomp, name="InitializeDataComplete", value="true", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_LogWrite("COP - Initialize-Data-Dependency allDone check Passed", ESMF_LOGMSG_INFO)

    ! Get generic options
    call NUOPC_CompAttributeGet(gcomp, name='DebugMode', value=cvalue, isPresent=isPresent, isSet=isSet, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return
    debugMode = .false.
    if (isPresent .and. isSet) then
       if (trim(cvalue) .eq. '.true.' .or. trim(cvalue) .eq. 'true' .or. trim(adjustl(cvalue)) .eq. 'T') debugMode = .true.
    end if
    write(msg, fmt='(A,L)') trim(subname)//' : DebugMode = ', debugMode
    call ESMF_LogWrite(trim(msg), ESMF_LOGMSG_INFO)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine DataInitialize

  !-----------------------------------------------------------------------------

  subroutine GridToMesh(state, rc)
    ! input/output variables
    type(ESMF_State), intent(inout) :: state
    integer, intent(out) :: rc

    ! local variables
    integer :: n, m
    integer :: itemCount
    logical :: isPresent, meshCreated
    integer :: gridToFieldMapCount, ungriddedCount
    integer, allocatable :: gridToFieldMap(:)
    integer, allocatable :: ungriddedLBound(:), ungriddedUBound(:)
    type(ESMF_Field) :: field, meshField
    type(ESMF_Grid) :: grid
    type(ESMF_Mesh) :: mesh
    type(ESMF_FieldStatus_Flag) :: fieldStatus
    type(ESMF_GeomType_Flag) :: geomtype
    character(ESMF_MAXSTR), allocatable :: itemNameList(:)
    character(ESMF_MAXSTR) :: fieldName
    character(ESMF_MAXSTR) :: message
    character(len=*), parameter :: subname = trim(modName)//':(GridToMesh) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Query state
    call ESMF_StateGet(state, itemCount=itemCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Allocate temporary data structures
    allocate(itemNameList(itemCount))

    ! Query item name in nested state
    call ESMF_StateGet(state, itemNameList=itemNameList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Loop over fields
    meshCreated = .false.
    do n = 1, itemCount
       ! Query state to get field
       call ESMF_StateGet(state, field=field, itemName=itemNameList(n), rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Query field for its geom type
       call ESMF_FieldGet(field, geomtype=geomtype, status=fieldStatus, name=fieldName, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Input fields contains grid - need to convert to mesh
       if (geomtype == ESMF_GEOMTYPE_GRID) then
          ! Grab grid
          call ESMF_FieldGet(field, grid=grid, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Check corner stagger
          call ESMF_GridGetCoord(grid, staggerloc=ESMF_STAGGERLOC_CORNER, isPresent=isPresent, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          write(message,'(A,L)') trim(subname)//': has ESMF_STAGGERLOC_CORNER =', isPresent
          call ESMF_LogWrite(message, ESMF_LOGMSG_INFO)

          ! Convert grid to mesh
          if (.not. meshCreated) then
             call ESMF_LogWrite(trim(subname)//": create mesh from grid using "//trim(fieldName), ESMF_LOGMSG_INFO)
             mesh = ESMF_MeshCreate(grid, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return
             meshCreated = .true.
          end if

          ! Create field on mesh
          meshField = ESMF_FieldCreate(mesh, typekind=ESMF_TYPEKIND_R8, meshloc=ESMF_MESHLOC_ELEMENT, name=trim(itemNameList(n)), rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Swap grid for mesh, at this point, only connected fields are in the state
          call NUOPC_Realize(state, field=meshField, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Check field
          call ESMF_FieldGet(meshField, status=fieldStatus, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (fieldStatus == ESMF_FIELDSTATUS_GRIDSET) then
             call ESMF_LogWrite(trim(subname)//": ERROR fieldStatus not complete ", ESMF_LOGMSG_ERROR)
             rc = ESMF_FAILURE
             return
          end if ! fieldStatus

       else
          ! Check for field status
          if (fieldStatus == ESMF_FIELDSTATUS_GRIDSET) then
             ! Check attribute in the field
             call ESMF_AttributeGet(field, name="GridToFieldMap", convention="NUOPC", &
               purpose="Instance", itemCount=gridToFieldMapCount, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             allocate(gridToFieldMap(gridToFieldMapCount))

             call ESMF_AttributeGet(field, name="GridToFieldMap", convention="NUOPC", &
               purpose="Instance", valueList=gridToFieldMap, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ungriddedCount = 0

             call ESMF_AttributeGet(field, name="UngriddedLBound", convention="NUOPC", &
               purpose="Instance", itemCount=ungriddedCount,  isPresent=isPresent, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             allocate(ungriddedLBound(ungriddedCount), ungriddedUBound(ungriddedCount))

             ! Query ungridded dimensions
             if (ungriddedCount > 0) then
                call ESMF_AttributeGet(field, name="UngriddedLBound", convention="NUOPC", &
                  purpose="Instance", valueList=ungriddedLBound, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                call ESMF_AttributeGet(field, name="UngriddedUBound", convention="NUOPC", &
                  purpose="Instance", valueList=ungriddedUBound, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return
             end if

             ! Add as a new field to the state
             call NUOPC_Realize(state, trim(fieldName), typekind=ESMF_TYPEKIND_R8, gridToFieldMap=gridToFieldMap, &
               ungriddedLbound=ungriddedLbound, ungriddedUbound=ungriddedUbound, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ! Clean memory
             deallocate(gridToFieldMap)
             deallocate(ungriddedLBound)
             deallocate(ungriddedUBound)
          end if ! fieldStatus

       end if ! geomType
    end do ! itemCount

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine GridToMesh

  !-----------------------------------------------------------------------------

  subroutine ModifyDecomp(state, rc)

    ! input/output variables
    type(ESMF_State), intent(inout) :: state
    integer, intent(out) :: rc

    ! local variables
    integer :: n, m
    integer :: itemCount, arbDimCount
    integer :: dimCount, tileCount, connectionCount
    type(ESMF_Grid) :: grid, newgrid
    type(ESMF_Mesh) :: mesh, newmesh
    type(ESMF_DistGrid) :: distgrid
    type(ESMF_DistGrid) :: elemdistgrid, newelemdistgrid
    type(ESMF_Field) :: field
    type(ESMF_GeomType_Flag) :: geomtype
    type(ESMF_FieldStatus_Flag) :: fieldStatus
    type(ESMF_DistGridConnection), allocatable :: connectionList(:)
    integer, allocatable :: minIndexPTile(:,:), maxIndexPTile(:,:)
    character(ESMF_MAXSTR), allocatable :: itemNameList(:)
    character(ESMF_MAXSTR) :: message
    character(len=*), parameter :: subname = trim(modName)//':(ModifyDecomp) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Query state
    call ESMF_StateGet(state, itemCount=itemCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Allocate temporary data structures
    allocate(itemNameList(itemCount))

    ! Query item name in nested state
    call ESMF_StateGet(state, itemNameList=itemNameList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Loop over fields
    ! Assuming that all fields share the same grid/mesh and because it is more efficient
    do n = 1, min(itemCount, 1)
       ! Query state to get field
       call ESMF_StateGet(state, field=field, itemName=itemNameList(n), rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Query field to get its status
       call ESMF_FieldGet(field, status=fieldStatus, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       if (fieldStatus == ESMF_FIELDSTATUS_GRIDSET) then
          ! Query field to get geom type
          call ESMF_FieldGet(field, geomtype=geomtype, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          if (geomtype == ESMF_GEOMTYPE_GRID) then
             call ESMF_LogWrite(trim(subname)//": geomtype is ESMF_GEOMTYPE_GRID for "//trim(itemNameList(n)), ESMF_LOGMSG_INFO)

             ! Query field to get arbitrary dimension count
             call ESMF_AttributeGet(field, name="ArbDimCount", value=arbDimCount, &
                convention="NUOPC", purpose="Instance", rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ! Make decision on whether the incoming Grid is arbDistr or not
             if (arbDimCount > 0) then
                ! Allocate temporary data arrays
                allocate(minIndexPTile(arbDimCount,1),maxIndexPTile(arbDimCount,1))

                ! Query min and max indexes
                call ESMF_AttributeGet(field, name="MinIndex", valueList=minIndexPTile(:,1), convention="NUOPC", purpose="Instance", rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return
                call ESMF_AttributeGet(field, name="MaxIndex", valueList=maxIndexPTile(:,1), convention="NUOPC", purpose="Instance", rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                ! Create new distgrid for new decomposition
                distgrid = ESMF_DistGridCreate(minIndexPTile=minIndexPTile, maxIndexPTile=maxIndexPTile, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                ! Create new grid from new distgrid
                newgrid = ESMF_GridCreate(distgrid, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return
                do m = 1, arbDimCount
                   write(message,'(A,3i8)') trim(subname)//':PTile =', m, minIndexPTile(m,1), maxIndexPTile(m,1)
                   call ESMF_LogWrite(message, ESMF_LOGMSG_INFO)
                end do
             else ! arbdimcount <= 0
                ! Query field for its grid
                call ESMF_FieldGet(field, grid=grid, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                ! Query grid for distgrid
                call ESMF_GridGet(grid, distgrid=distgrid, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                ! Query distgrid properties
                call ESMF_DistGridGet(distgrid, dimCount=dimCount, tileCount=tileCount, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                ! Allocate temporary data arrays
                allocate(minIndexPTile(dimCount, tileCount))
                allocate(maxIndexPTile(dimCount, tileCount))

                ! Query distgrid
                call ESMF_DistGridGet(distgrid, minIndexPTile=minIndexPTile, maxIndexPTile=maxIndexPTile, rc=rc)                
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                if (dimCount == 2) then
                   ! Query distgrid to get connection count     
                   call ESMF_DistGridGet(distgrid, connectionCount=connectionCount, rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return

                   ! Allocate temporary data array
                   allocate(connectionList(connectionCount))

                   ! Query distgrid for connectionList
                   call ESMF_DistGridGet(distgrid, connectionList=connectionList, rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return
                   distgrid = ESMF_DistGridCreate(minIndexPTile=minIndexPTile, maxIndexPTile=maxIndexPTile, connectionList=connectionList, rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return

                   ! Create new grid with new distgrid
                   newgrid = ESMF_GridCreate(distgrid, gridEdgeLWidth=(/0,0/), gridEdgeUWidth=(/0,0/), rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return

                   ! Clean memory
                   deallocate(connectionList)
                else
                   ! Create new distgrid
                   distgrid = ESMF_DistGridCreate(minIndexPTile=minIndexPTile, maxIndexPTile=maxIndexPTile, rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return

                   ! Create new grid
                   newgrid = ESMF_GridCreate(distgrid, gridEdgeLWidth=(/0/), gridEdgeUWidth=(/0/), rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return
                end if ! dimCount

                ! Clean memory
                deallocate(minIndexPTile, maxIndexPTile)

             endif ! arbdimCount

             ! Swap all grids in the state
             do m = 1, itemCount
                ! Query state to get field
                call ESMF_StateGet(state, field=field, itemName=itemNameList(m), rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                ! Query field to get its status
                call ESMF_FieldGet(field, status=fieldStatus, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                if (fieldStatus == ESMF_FIELDSTATUS_EMPTY .or. fieldStatus == ESMF_FIELDSTATUS_GRIDSET) then
                   call ESMF_FieldEmptySet(field, grid=newgrid, rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return

                   call ESMF_LogWrite(trim(subname)//": attach grid for "//trim(itemNameList(m)), ESMF_LOGMSG_INFO)
                else
                   call ESMF_LogWrite(trim(subname)//": NOT replacing grid for field: "//trim(itemNameList(m)), ESMF_LOGMSG_WARNING)
                end if ! field status

             end do ! fields

          else if (geomtype == ESMF_GEOMTYPE_MESH) then
             call ESMF_LogWrite(trim(subname)//": geomtype is ESMF_GEOMTYPE_MESH for "//trim(itemNameList(n)), ESMF_LOGMSG_INFO)

             ! Query field to get mesh
             call ESMF_FieldGet(field, mesh=mesh, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ! Query mesh to get decomposition information
             call ESMF_MeshGet(mesh, elementDistGrid=elemDistGrid, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ! Create new decomposition based on existing one
             newelemDistGrid = ESMF_DistGridCreate(elemDistGrid, balanceflag=.true., rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ! Create new mesh with new decomposition
             newmesh = ESMF_MeshEmptyCreate(elementDistGrid=newelemDistGrid, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ! Swap all meshes in the state
             do m = 1, itemCount
                ! Query state to get field
                call ESMF_StateGet(state, field=field, itemName=itemNameList(m), rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                ! Query field to get its status
                call ESMF_FieldGet(field, status=fieldStatus, rc=rc)
                if (ChkErr(rc,__LINE__,u_FILE_u)) return

                if (fieldStatus == ESMF_FIELDSTATUS_EMPTY .or. fieldStatus == ESMF_FIELDSTATUS_GRIDSET) then
                   call ESMF_FieldEmptySet(field, mesh=newmesh, rc=rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return

                   call ESMF_LogWrite(trim(subname)//": attach mesh for "//trim(itemNameList(m)), ESMF_LOGMSG_INFO)
                else
                   call ESMF_LogWrite(trim(subname)//": NOT replacing mesh for field: "//trim(itemNameList(m)), ESMF_LOGMSG_WARNING)
                end if ! field status

             end do ! fields
          else
             call ESMF_LogWrite(trim(subname)//": ERROR geomtype not supported ", ESMF_LOGMSG_ERROR)
             rc=ESMF_FAILURE
             return
          end if ! geomtype

       elseif (fieldStatus == ESMF_FIELDSTATUS_EMPTY) then
          call ESMF_LogWrite(trim(subname)//": provide grid for "//trim(itemNameList(n)), ESMF_LOGMSG_INFO)

       elseif (fieldStatus == ESMF_FIELDSTATUS_COMPLETE) then
          call ESMF_LogWrite(trim(subname)//": no grid provided for "//trim(itemNameList(n)), ESMF_LOGMSG_INFO)

       end if ! field status

    end do ! fields

    ! Clean memory
    deallocate(itemNameList)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ModifyDecomp

  !-----------------------------------------------------------------------------

  subroutine SetRunClock(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    type(ESMF_Clock) :: modelClock, driverClock
    type(ESMF_Time) :: currTime
    type(ESMF_TimeInterval) :: timeStep
    character(len=*), parameter :: subname = trim(modName)//':(SetRunClock) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Query component
    call NUOPC_ModelGet(gcomp, modelClock=modelClock, driverClock=driverClock, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Set the modelClock to have the current start time as the driverClock
    call ESMF_ClockGet(driverClock, currTime=currTime, timeStep=timeStep, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_ClockSet(modelClock, currTime=currTime, timeStep=timeStep, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Check and set the component clock against the driver clock
    call NUOPC_CompCheckSetClock(gcomp, driverClock, checkTimeStep=.false., rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine SetRunClock

  !-----------------------------------------------------------------------------

  subroutine Advance(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    type(ESMF_Time) :: currTime
    type(ESMF_Clock) :: clock
    type(ESMF_State) :: importState, exportState
    logical :: isPresent, isSet 
    character(len=ESMF_MAXSTR) :: message
    character(len=ESMF_MAXSTR) :: cvalue 
    character(len=ESMF_MAXSTR) :: timeStr
    character(len=*), parameter :: subname = trim(modName)//':(Advance) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)


    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine Advance

end module geogate_nuopc
