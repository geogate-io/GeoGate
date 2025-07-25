module geogate_phases_python

  !-----------------------------------------------------------------------------
  ! Phase for Python interaction 
  !-----------------------------------------------------------------------------

  use ESMF, only: operator(==)
  use ESMF, only: ESMF_GridComp, ESMF_GridCompGet, ESMF_GridCompGetInternalState
  use ESMF, only: ESMF_Time, ESMF_TimeGet
  use ESMF, only: ESMF_Clock, ESMF_ClockGet, ESMF_KIND_R8
  use ESMF, only: ESMF_LogFoundError, ESMF_FAILURE, ESMF_LogWrite
  use ESMF, only: ESMF_LOGERR_PASSTHRU, ESMF_LOGMSG_INFO, ESMF_SUCCESS
  use ESMF, only: ESMF_Field, ESMF_FieldGet, ESMF_FieldWrite, ESMF_FieldWriteVTK
  use ESMF, only: ESMF_FieldBundle, ESMF_FieldBundleGet
  use ESMF, only: ESMF_Info, ESMF_InfoGetFromHost
  use ESMF, only: ESMF_VM, ESMF_VMGet, ESMF_VMBarrier, ESMF_Mesh, ESMF_MeshGet
  use ESMF, only: ESMF_MAXSTR, ESMF_GEOMTYPE_GRID, ESMF_GEOMTYPE_MESH

  use NUOPC, only: NUOPC_CompAttributeGet
  use NUOPC_Model, only: NUOPC_ModelGet

  use conduit
  use, intrinsic :: iso_c_binding, only : C_PTR

  use geogate_share, only: ChkErr, StringSplit, debugMode
  use geogate_types, only: IngestMeshData, meshType
  use geogate_internalstate, only: InternalState
  use geogate_python_interface, only: conduit_fort_to_py

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: geogate_phases_python_run

  !-----------------------------------------------------------------------------
  ! Private module routines
  !-----------------------------------------------------------------------------

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  type(meshType), allocatable :: myMesh(:)
  character(ESMF_MAXSTR), allocatable :: scriptNames(:)
  character(len=*), parameter :: modName = "(geogate_phases_python)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine geogate_phases_python_run(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    type(C_PTR) :: node
    type(C_PTR) :: info
    integer :: n, mpiComm, localPet, petCount
    logical :: isPresent, isSet
    logical, save :: first_time = .true.
    type(InternalState) :: is_local
    type(ESMF_Time) :: currTime
    type(ESMF_Clock) :: clock
    type(ESMF_VM) :: vm
    integer, save :: timeStep = 0
    character(ESMF_MAXSTR) :: cvalue, message, timeStr
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_python_run) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Get internal state
    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query component
    call NUOPC_ModelGet(gcomp, modelClock=clock, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_GridCompGet(gcomp, vm=vm, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query VM
    call ESMF_VMGet(vm, mpiCommunicator=mpiComm, localPet=localPet, petCount=petCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query current time
    call ESMF_ClockGet(clock, currTime=currTime, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_TimeGet(currTime, timeStringISOFrac=timeStr , rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Initialize
    if (first_time) then
       ! Python script/s
       call NUOPC_CompAttributeGet(gcomp, name="PythonScripts", value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       if (isPresent .and. isSet) then
          scriptNames = StringSplit(trim(cvalue), ":")
          do n = 1, size(scriptNames, dim=1)
             write(message, fmt='(A,I1,A)') trim(subname)//": PythonScript (", n, ") = "//trim(scriptNames(n))
             call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
          end do
       endif

       ! Set flag
       first_time = .false.
    end if

    ! Create Conduit node
    node = conduit_node_create()

    ! Add time information
    call conduit_node_set_path_int32(node, 'state/time_step', timeStep)
    call conduit_node_set_path_char8_str(node, 'state/time_str', trim(timeStr)//char(0))

    ! Add MPI related information
    call conduit_node_set_path_int32(node, "mpi/comm", mpiComm)
    call conduit_node_set_path_int32(node, "mpi/localpet", localPet)
    call conduit_node_set_path_int32(node, "mpi/petcount", petCount)

    ! Allocate myMesh
    if (.not. allocated(myMesh)) allocate(myMesh(is_local%wrap%numComp))

    ! Loop over FBs
    do n = 1, is_local%wrap%numComp
       ! Load content of FB to Conduit node
       call FB2Node(is_local%wrap%FBImp(n), trim(is_local%wrap%compName(n)), myMesh(n), node, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end do

    ! Debug statements
    if (debugMode) then
       ! Save node information
       write(message, fmt='(A,I3.3,A,I3.3)') "node_"//trim(timeStr)//"_", localPet, "_", petCount
       call conduit_node_save(node, trim(message)//".json", "json")

       ! Print node information with details about memory allocation
       info = conduit_node_create()
       call conduit_node_info(node, info)
       call conduit_node_print(info)
       call conduit_node_destroy(info)
    end if

    ! Pass node to Python scripts
    do n = 1, size(scriptNames, dim=1)
       call conduit_fort_to_py(node, trim(scriptNames(n))//char(0))
    end do

    ! Clean memory
    call conduit_node_destroy(node)

    ! Increase time step
    timeStep = timeStep+1

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_python_run

  !-----------------------------------------------------------------------------

  subroutine FB2Node(FBin, compName, myMesh, node, rc)

    ! input/output variables
    type(ESMF_FieldBundle) :: FBin
    character(len=*), intent(in) :: compName
    type(meshType), intent(inout) :: myMesh
    type(C_PTR), intent(inout) :: node
    integer, intent(out), optional :: rc

    ! local variables
    integer :: n, m
    integer :: fieldCount, dataSize
    type(C_PTR) :: channel, mesh, fields
    real(ESMF_KIND_R8), pointer :: farrayPtr(:)
    type(ESMF_Mesh) :: fmesh
    type(ESMF_Field) :: field
    type(ESMF_Info) :: info
    character(ESMF_MAXSTR), allocatable :: fieldNameList(:)
    character(len=*), parameter :: subname = trim(modName)//':(FB2Node) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(compName), ESMF_LOGMSG_INFO)

    ! Add channel
    channel = conduit_node_fetch(node, "channels/"//trim(compName))

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

       ! Query dimension information
       call ESMF_InfoGetFromHost(field, info, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Query coordinate information from first field
       if (n == 1) then
          ! Create mesh node
          mesh = conduit_node_fetch(channel, "data")

          if (.not. allocated(myMesh%nodeCoordsX)) then
             ! Query mesh
             call ESMF_FieldGet(field, mesh=fmesh, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return

             ! Ingest ESMF mesh
             call IngestMeshData(fmesh, myMesh, trim(compName), rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return
          end if

          ! Add dimension sizes
          call conduit_node_set_path_int32(mesh, "dimension/n_node", myMesh%nodeCount)
          call conduit_node_set_path_int32(mesh, "dimension/n_face", myMesh%elementCount)
          call conduit_node_set_path_int32(mesh, "dimension/n_max_face_nodes", myMesh%maxNodePElement)

          ! Add coordinates
          call conduit_node_set_path_external_float64_ptr(mesh, "coords/values/node_lon", &
             myMesh%nodeCoordsLon, int8(myMesh%nodeCount))
          call conduit_node_set_path_external_float64_ptr(mesh, "coords/values/node_lat", &
             myMesh%nodeCoordsLat, int8(myMesh%nodeCount))
          call conduit_node_set_path_external_float64_ptr(mesh, "coords/values/face_lon", &
             myMesh%elementCoordsLon, int8(myMesh%elementCount))
          call conduit_node_set_path_external_float64_ptr(mesh, "coords/values/face_lat", &
             myMesh%elementCoordsLat, int8(myMesh%elementCount))

          ! Add topology
          call conduit_node_set_path_external_int32_ptr(mesh, "topologies/mesh/elements/n_nodes_per_face", &
             myMesh%elementTypes, int8(myMesh%elementCount))
          call conduit_node_set_path_external_int32_ptr(mesh, "topologies/mesh/elements/face_node_connectivity", &
             myMesh%elementConn, int8(myMesh%numElementConn))

          ! Add mask information
          if (myMesh%elementMaskIsPresent) then
             call conduit_node_set_path_external_int32_ptr(mesh, "mask/values/face_mask", &
                myMesh%elementMask, int8(myMesh%elementCount))
          end if
          if (myMesh%nodeMaskIsPresent) then
             call conduit_node_set_path_external_int32_ptr(mesh, "mask/values/node_mask", &
                myMesh%nodeMask, int8(myMesh%nodeCount))
          end if

          ! Create node for fields
          fields = conduit_node_fetch(mesh, "fields")
       end if

       ! Query field pointer
       call ESMF_FieldGet(field, farrayPtr=farrayPtr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Add fields to node
       if (size(farrayPtr, dim=1) == myMesh%elementCount) then
          dataSize = myMesh%elementCount
          call conduit_node_set_path_char8_str(fields, trim(fieldNameList(n))//"/association", "face")
       else
          dataSize = myMesh%nodeCount
          call conduit_node_set_path_char8_str(fields, trim(fieldNameList(n))//"/association", "node")
       end if
       call conduit_node_set_path_external_float64_ptr(fields, trim(fieldNameList(n))//"/values", farrayPtr, int8(dataSize))

       ! Init pointers
       nullify(farrayPtr)
    end do

    ! Clean memeory
    deallocate(fieldNameList)

    call ESMF_LogWrite(subname//' done for '//trim(compName), ESMF_LOGMSG_INFO)

  end subroutine FB2Node

end module geogate_phases_python
