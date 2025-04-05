module geogate_phases_catalyst

  !-----------------------------------------------------------------------------
  ! Phase for ParaView Catalyst interaction
  !-----------------------------------------------------------------------------

  use ESMF, only: operator(==), operator(/=), operator(-), operator(/)
  use ESMF, only: ESMF_GridComp, ESMF_GridCompGet, ESMF_GridCompGetInternalState
  use ESMF, only: ESMF_VM, ESMF_VMGet
  use ESMF, only: ESMF_Time, ESMF_TimeGet
  use ESMF, only: ESMF_TimeInterval, ESMF_TimeIntervalGet
  use ESMF, only: ESMF_Clock, ESMF_ClockGet
  use ESMF, only: ESMF_LogFoundError, ESMF_FAILURE, ESMF_LogWrite
  use ESMF, only: ESMF_LOGERR_PASSTHRU, ESMF_LOGMSG_ERROR, ESMF_LOGMSG_INFO, ESMF_SUCCESS
  use ESMF, only: ESMF_Field, ESMF_FieldGet
  use ESMF, only: ESMF_FieldBundle, ESMF_FieldBundleGet
  use ESMF, only: ESMF_MAXSTR, ESMF_KIND_R8
  use ESMF, only: ESMF_Mesh, ESMF_MeshGet
  use ESMF, only: ESMF_CoordSys_Flag, ESMF_COORDSYS_SPH_DEG, ESMF_COORDSYS_SPH_RAD

  use NUOPC, only: NUOPC_CompAttributeGet
  use NUOPC_Model, only: NUOPC_ModelGet

  use catalyst_api
  use catalyst_conduit

  use geogate_share, only: ChkErr, StringSplit
  use geogate_types, only: IngestMeshData, meshType
  use geogate_share, only: rad2Deg, deg2Rad, constHalfPi
  use geogate_share, only: debugMode
  use geogate_internalstate, only: InternalState

  use, intrinsic :: iso_c_binding, only: C_PTR

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: geogate_phases_catalyst_run

  !-----------------------------------------------------------------------------
  ! Private module routines
  !-----------------------------------------------------------------------------

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  logical :: convertToCart
  type(meshType), allocatable :: myMesh(:)
  character(len=*), parameter :: modName = "(geogate_phases_catalyst)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine geogate_phases_catalyst_run(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    type(C_PTR) :: node
    type(C_PTR) :: info
    type(C_PTR) :: scriptArgsItem, scriptArgs
    integer(kind(catalyst_status)) :: err
    integer :: n, numScripts, step
    integer :: mpiComm, localPet, petCount
    real(kind=8) :: time
    logical :: isPresent, isSet, res
    logical, save :: first_time = .true.
    type(InternalState) :: is_local
    type(ESMF_VM) :: vm
    type(ESMF_TimeInterval) :: timeStep
    type(ESMF_Time) :: startTime, currTime
    type(ESMF_Clock) :: clock
    character(ESMF_MAXSTR) :: cvalue, tmpStr, scriptName
    character(ESMF_MAXSTR) :: timeStr
    character(ESMF_MAXSTR) :: message
    character(ESMF_MAXSTR) :: catalystImpl, paraviewImplDir
    character(ESMF_MAXSTR), allocatable :: scriptNames(:)
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_catalyst_run) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Get internal state
    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query component clock
    call NUOPC_ModelGet(gcomp, modelClock=clock, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query VM and communicator
    call ESMF_GridCompGet(gcomp, vm=vm, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_VMGet(vm, mpiCommunicator=mpiComm, localPet=localPet, petCount=petCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query current time
    call ESMF_ClockGet(clock, startTime=startTime, currTime=currTime, timeStep=timeStep, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_TimeGet(currTime, timeStringISOFrac=timeStr , rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_TimeIntervalGet(currTime-startTime, s_r8=time, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Initialize
    if (first_time) then
       ! This node will hold the information nessesary to initialize ParaViewCatalyst
       node = catalyst_conduit_node_create()

       ! Option to enable converting lat-lon to cartesian coordinates
       call NUOPC_CompAttributeGet(gcomp, name="CatalystConvertToCart", value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       convertToCart = .false.
       if (isPresent .and. isSet) then
          if (trim(cvalue) .eq. '.true.' .or. trim(cvalue) .eq. 'true') convertToCart = .true.
       end if
       write(message, fmt='(A,L)') trim(subname)//' : CatalystConvertToCart = ', convertToCart
       call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)

       ! Query name of Catalyst script
       call NUOPC_CompAttributeGet(gcomp, name="CatalystScripts", value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       if (isPresent .and. isSet) then
          scriptNames = StringSplit(trim(cvalue), ":")
          do n = 1, size(scriptNames, dim=1)
             write(message, fmt='(A,I1,A)') trim(subname)//": CatalystScript (", n, ") = "//trim(scriptNames(n))
             call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
          end do
       endif

       ! Set script name and arguments
       do n = 1, size(scriptNames, dim=1)
          ! Add script
          write(tmpStr, '(A,I1)') 'catalyst/scripts/script', n
          call catalyst_conduit_node_set_path_char8_str(node, trim(tmpStr)//"/filename", trim(scriptNames(n)))
          ! Add arguments
          !scriptArgs = catalyst_conduit_node_fetch(node, trim(tmpStr)//"/args")
          !scriptArgsItem = catalyst_conduit_node_append(scriptArgs)
          !call catalyst_conduit_node_set_char8_str(scriptArgsItem, "--channel-name=ocn")
       end do

       ! Set implementation type
       call get_environment_variable("CATALYST_IMPLEMENTATION_NAME", catalystImpl)
       if (trim(catalystImpl) == '') then
          call catalyst_conduit_node_set_path_char8_str(node, "catalyst_load/implementation", "paraview")
       else
          call ESMF_LogWrite(trim(subname)//": CATALYST_IMPLEMENTATION_NAME = "//trim(catalystImpl), ESMF_LOGMSG_INFO)
       end if

       ! Set Paraview/Catalyst search path
       call get_environment_variable("CATALYST_IMPLEMENTATION_PATHS", paraviewImplDir)
       if (trim(paraviewImplDir) == '') then
          call NUOPC_CompAttributeGet(gcomp, name="CatalystLoadPath", value=cvalue, &
            isPresent=isPresent, isSet=isSet, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (isPresent .and. isSet) then
             call catalyst_conduit_node_set_path_char8_str(node, "catalyst_load/search_paths/paraview", trim(cvalue))
             call ESMF_LogWrite(trim(subname)//": CatalystLoadPath = "//trim(cvalue), ESMF_LOGMSG_INFO)
          end if
       else
          call ESMF_LogWrite(trim(subname)//": CATALYST_IMPLEMENTATION_PATHS = "//trim(paraviewImplDir), ESMF_LOGMSG_INFO)
       end if

       ! Add MPI communicator
       call catalyst_conduit_node_set_path_int32(node, "catalyst/mpi_comm", mpiComm)

       ! Debug statements
       if (debugMode) then
          ! Save node information
          write(message, fmt='(A,I3.3,A,I3.3)') "init_node_"//trim(timeStr)//"_", localPet, "_", petCount
          call catalyst_conduit_node_save(node, trim(message)//".json", "json")

          ! Print node information with details about memory allocation
          info = catalyst_conduit_node_create()
          call catalyst_conduit_node_info(node, info)
          call catalyst_conduit_node_print(info)
          call catalyst_conduit_node_destroy(info)
       end if

       ! Initialize catalyst
       err = c_catalyst_initialize(node)
       if (err /= catalyst_status_ok) then
          write(message, fmt='(A,I2)') trim(subname)//": Failed to initialize Catalyst: ", err
          call ESMF_LogWrite(trim(message), ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if

       ! Destroy node which is not required
       call catalyst_conduit_node_destroy(node)

       ! Allocate arrays to store mesh information for each connected component
       allocate(myMesh(is_local%wrap%numComp))

       ! Set flag
       first_time = .false.
    end if

    ! This node will hold the information nessesary to execute ParaViewCatalyst
    node = catalyst_conduit_node_create()

    ! Add time/cycle information - Catalyst-specific variables
    step = int((currTime-startTime)/timeStep)
    call catalyst_conduit_node_set_path_int32(node, "catalyst/state/timestep", step)
    call catalyst_conduit_node_set_path_float64(node, "catalyst/state/time", time)

    ! Allocate myMesh
    if (.not. allocated(myMesh)) allocate(myMesh(is_local%wrap%numComp))

    ! Add channel for all components
    do n = 1, is_local%wrap%numComp
       ! Add content of FB to Conduit node
       call FB2Channel(is_local%wrap%FBImp(n), trim(is_local%wrap%compName(n)), myMesh(n), node, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end do

    ! Debug statements
    if (debugMode) then
       ! Save node information
       write(message, fmt='(A,I3.3,A,I3.3)') "exec_node_"//trim(timeStr)//"_", localPet, "_", petCount
       call catalyst_conduit_node_save(node, trim(message)//".json", "json")

       ! Print node information with details about memory allocation
       info = catalyst_conduit_node_create()
       call catalyst_conduit_node_info(node, info)
       call catalyst_conduit_node_print(info)
       call catalyst_conduit_node_destroy(info)
    end if

    ! Execute catalyst
    err = c_catalyst_execute(node)
    if (err /= catalyst_status_ok) then
       write(message, fmt='(A,I2)') trim(subname)//": Failed to execute Catalyst: ", err
       call ESMF_LogWrite(trim(message), ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Destroy nodes
    call catalyst_conduit_node_destroy(node)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_catalyst_run

  !-----------------------------------------------------------------------------

  subroutine FB2Channel(FBin, compName, myMesh, node, rc)

    ! input/output variables
    type(ESMF_FieldBundle), intent(in) :: FBin 
    character(len=*), intent(in) :: compName
    type(meshType), intent(inout) :: myMesh
    type(C_PTR), intent(inout) :: node
    integer, intent(out), optional :: rc

    ! local variables
    type(C_PTR) :: channel
    type(C_PTR) :: mesh
    type(C_PTR) :: fields
    integer :: n, m
    integer :: fieldCount, dataSize
    type(ESMF_Mesh) :: fmesh
    type(ESMF_Field) :: field
    real(ESMF_KIND_R8), pointer :: farrayPtr(:)
    character(ESMF_MAXSTR), allocatable :: fieldNameList(:)
    character(len=*), parameter :: subname = trim(modName)//':(FB2Channel) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(compName), ESMF_LOGMSG_INFO)

    ! Add channel
    channel = catalyst_conduit_node_fetch(node, "catalyst/channels/"//trim(compName))

    ! Query number of item in the FB
    call ESMF_FieldBundleGet(FBin, fieldCount=fieldCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    allocate(fieldNameList(fieldCount))

    call ESMF_FieldBundleGet(FBin, fieldNameList=fieldNameList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Loop over fields
    do n = 1, fieldCount
       ! Query field
       call ESMF_FieldBundleGet(FBin, fieldName=trim(fieldNameList(n)), field=field, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return

       ! Query coordinate information from first field
       if (n == 1) then
          ! Add mesh to channel
          call catalyst_conduit_node_set_path_char8_str(channel, "type", "mesh")

          ! Create mesh node
          mesh = catalyst_conduit_node_fetch(channel, "data")

          ! Set type of mesh, construct as an unstructured mesh
          call catalyst_conduit_node_set_path_char8_str(mesh, "coordsets/coords/type", "explicit")

          if (.not. allocated(myMesh%nodeCoordsX)) then
             ! Query mesh
             call ESMF_FieldGet(field, mesh=fmesh, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return

             ! Ingest ESMF mesh
             call IngestMeshData(fmesh, myMesh, trim(compName), cartesian=convertToCart, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return
          end if

          ! Add coordinates
          call catalyst_conduit_node_set_path_external_float64_ptr(mesh, "coordsets/coords/values/x", &
             myMesh%nodeCoordsX, int8(myMesh%nodeCount))
          call catalyst_conduit_node_set_path_external_float64_ptr(mesh, "coordsets/coords/values/y", &
             myMesh%nodeCoordsY, int8(myMesh%nodeCount))
          call catalyst_conduit_node_set_path_external_float64_ptr(mesh, "coordsets/coords/values/z", &
             myMesh%nodeCoordsZ, int8(myMesh%nodeCount))

          ! Add topology
          call catalyst_conduit_node_set_path_char8_str(mesh, "topologies/mesh/type", "unstructured")
          call catalyst_conduit_node_set_path_char8_str(mesh, "topologies/mesh/coordset", "coords")
          call catalyst_conduit_node_set_path_char8_str(mesh, "topologies/mesh/elements/shape", trim(myMesh%elementShape))
          do m = 1, size(myMesh%elementShapeMapName, dim=1)
             call catalyst_conduit_node_set_path_int32(mesh, "topologies/mesh/elements/shape_map/"// &
               trim(myMesh%elementShapeMapName(m)), myMesh%elementShapeMapValue(m))
          end do
          call catalyst_conduit_node_set_path_int32_ptr(mesh, "topologies/mesh/elements/shapes", myMesh%elementTypesShape, int8(myMesh%elementCount))
          call catalyst_conduit_node_set_path_int32_ptr(mesh, "topologies/mesh/elements/sizes", myMesh%elementTypes, int8(myMesh%elementCount))
          call catalyst_conduit_node_set_path_int32_ptr(mesh, "topologies/mesh/elements/offsets", myMesh%elementTypesOffset, int8(myMesh%elementCount))
          call catalyst_conduit_node_set_path_int32_ptr(mesh, "topologies/mesh/elements/connectivity", myMesh%elementConn, int8(myMesh%numElementConn))

          ! Create node for fields
          fields = catalyst_conduit_node_fetch(mesh, "fields")

          ! Add mask information
          if (myMesh%elementMaskIsPresent) then
             call catalyst_conduit_node_set_path_char8_str(fields, "element_mask/association", "element")
             call catalyst_conduit_node_set_path_char8_str(fields, "element_mask/topology", "mesh")
             call catalyst_conduit_node_set_path_char8_str(fields, "element_mask/volume_dependent", "false")
             call catalyst_conduit_node_set_path_external_int32_ptr(fields, "element_mask/values", &
                myMesh%elementMask, int8(myMesh%elementCount))
          end if
          if (myMesh%nodeMaskIsPresent) then
             call catalyst_conduit_node_set_path_char8_str(fields, "node_mask/association", "vertex")
             call catalyst_conduit_node_set_path_char8_str(fields, "node_mask/topology", "mesh")
             call catalyst_conduit_node_set_path_char8_str(fields, "node_mask/volume_dependent", "false")
             call catalyst_conduit_node_set_path_external_int32_ptr(fields, "node_mask/values", &
                myMesh%nodeMask, int8(myMesh%nodeCount))
          end if
       end if ! n == 1

       ! Query field pointer
       call ESMF_FieldGet(field, farrayPtr=farrayPtr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Add fields to node
       if (size(farrayPtr, dim=1) == myMesh%elementCount) then
          dataSize = myMesh%elementCount
          call catalyst_conduit_node_set_path_char8_str(fields, trim(fieldNameList(n))//"/association", "element")
       else
          dataSize = myMesh%nodeCount
          call catalyst_conduit_node_set_path_char8_str(fields, trim(fieldNameList(n))//"/association", "vertex")
       end if

       call catalyst_conduit_node_set_path_char8_str(fields, trim(fieldNameList(n))//"/topology", "mesh")
       call catalyst_conduit_node_set_path_char8_str(fields, trim(fieldNameList(n))//"/volume_dependent", "false")
       call catalyst_conduit_node_set_path_external_float64_ptr(fields, &
          trim(fieldNameList(n))//"/values", farrayPtr, int8(dataSize))

       ! Init pointers
       nullify(farrayPtr)
    end do ! fieldCount

    ! Clean memeory
    deallocate(fieldNameList)

    call ESMF_LogWrite(subname//' done for '//trim(compName), ESMF_LOGMSG_INFO)

  end subroutine FB2Channel

end module geogate_phases_catalyst
