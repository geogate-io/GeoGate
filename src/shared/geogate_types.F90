module geogate_types

  !-----------------------------------------------------------------------------
  ! This is the module for shared data types and supporting routines 
  !-----------------------------------------------------------------------------

  use ESMF, only: operator(==)
  use ESMF, only: ESMF_Mesh, ESMF_MeshGet
  use ESMF, only: ESMF_MAXSTR, ESMF_KIND_R8
  use ESMF, only: ESMF_COORDSYS_SPH_DEG, ESMF_COORDSYS_SPH_RAD
  use ESMF, only: ESMF_CoordSys_Flag
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR

  use geogate_share, only: ChkErr
  use geogate_share, only: rad2Deg, deg2Rad, constHalfPi

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: IngestMeshData

  !-----------------------------------------------------------------------------
  ! Private module routines
  !-----------------------------------------------------------------------------

  !-----------------------------------------------------------------------------
  ! Public module data
  !-----------------------------------------------------------------------------

  ! Mesh type
  type meshType 
    integer :: spatialDim
    integer :: nodeCount
    integer :: elementCount
    integer :: numElementConn
    integer :: maxNodePElement
    character(ESMF_MAXSTR) :: elementShape
    character(ESMF_MAXSTR), allocatable :: elementShapeMapName(:)
    integer, allocatable :: elementShapeMapValue(:)
    real(ESMF_KIND_R8), allocatable :: nodeCoordsLon(:)
    real(ESMF_KIND_R8), allocatable :: nodeCoordsLat(:)
    real(ESMF_KIND_R8), allocatable :: nodeCoordsX(:)
    real(ESMF_KIND_R8), allocatable :: nodeCoordsY(:)
    real(ESMF_KIND_R8), allocatable :: nodeCoordsZ(:)
    real(ESMF_KIND_R8), allocatable :: elementCoordsLon(:)
    real(ESMF_KIND_R8), allocatable :: elementCoordsLat(:)
    real(ESMF_KIND_R8), allocatable :: elementCoordsX(:)
    real(ESMF_KIND_R8), allocatable :: elementCoordsY(:)
    real(ESMF_KIND_R8), allocatable :: elementCoordsZ(:)
    integer, allocatable :: elementTypes(:)
    integer, allocatable :: elementTypesShape(:)
    integer, allocatable :: elementTypesOffset(:)
    integer, allocatable :: elementConn(:)
    integer, allocatable :: elementConn2d(:,:)
    logical :: elementMaskIsPresent
    integer, allocatable :: elementMask(:)
    logical :: nodeMaskIsPresent
    integer, allocatable :: nodeMask(:)
  end type meshType

  public :: meshType

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(len=*), parameter :: modName = "(geogate_types)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine IngestMeshData(mesh, myMesh, compName, cartesian, rc)

    ! input/output variables
    type(ESMF_Mesh), intent(in) :: mesh
    type(meshType), intent(inout) :: myMesh
    character(len=*), intent(in) :: compName
    logical, intent(in), optional :: cartesian
    integer, intent(out), optional :: rc

    ! local variables
    integer :: m, num_modes, offset
    logical :: convertCartesian
    logical :: hasTri = .false.
    logical :: hasQuad = .false.
    real(ESMF_KIND_R8) :: theta, phi
    real(ESMF_KIND_R8), allocatable :: nodeCoords(:)
    real(ESMF_KIND_R8), allocatable :: elementCoords(:)
    type(ESMF_CoordSys_Flag) :: coordSys
    character(ESMF_MAXSTR) :: message
    character(len=*), parameter :: subname = trim(modName)//':(IngestMeshData) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(compName), ESMF_LOGMSG_INFO)

    ! Handle optional arguments
    convertCartesian = .false.
    if (present(cartesian)) convertCartesian = cartesian

    ! Extract required information from mesh
    call ESMF_MeshGet(mesh, spatialDim=myMesh%spatialDim, nodeCount=myMesh%nodeCount, &
       elementCount=myMesh%elementCount, nodeMaskIsPresent=myMesh%nodeMaskIsPresent, &
       elementMaskIsPresent=myMesh%elementMaskIsPresent, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Allocate required variables
    allocate(myMesh%nodeCoordsLon(myMesh%nodeCount))
    allocate(myMesh%nodeCoordsLat(myMesh%nodeCount))
    allocate(myMesh%nodeCoordsX(myMesh%nodeCount))
    allocate(myMesh%nodeCoordsY(myMesh%nodeCount))
    allocate(myMesh%nodeCoordsZ(myMesh%nodeCount))
    allocate(myMesh%elementCoordsLon(myMesh%elementCount))
    allocate(myMesh%elementCoordsLat(myMesh%elementCount))
    allocate(myMesh%elementCoordsX(myMesh%elementCount))
    allocate(myMesh%elementCoordsY(myMesh%elementCount))
    allocate(myMesh%elementCoordsZ(myMesh%elementCount))
    allocate(myMesh%elementTypes(myMesh%elementCount))
    allocate(myMesh%elementTypesShape(myMesh%elementCount))
    allocate(myMesh%elementTypesOffset(myMesh%elementCount))

    ! Get element types to find final numElementConn
    call ESMF_MeshGet(mesh, elementTypes=myMesh%elementTypes, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    myMesh%numElementConn = sum(myMesh%elementTypes, dim=1)
    myMesh%maxNodePElement = max(myMesh%elementTypes, dim=1)

    ! Allocate element connection array
    allocate(myMesh%elementConn(myMesh%numElementConn))
    allocate(myMesh%elementConn2d(myMesh%elementCount,myMesh%maxNodePElement))

    ! Get coordinates
    allocate(nodeCoords(myMesh%spatialDim*myMesh%nodeCount))
    allocate(elementCoords(myMesh%spatialDim*myMesh%elementCount))

    call ESMF_MeshGet(mesh, nodeCoords=nodeCoords, elementCoords=elementCoords, &
       coordSys=coordSys, elementConn=myMesh%elementConn, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    do m = 1, myMesh%nodeCount
       myMesh%nodeCoordsLon(m) = nodeCoords(2*m-1)
       myMesh%nodeCoordsLat(m) = nodeCoords(2*m)
    end do
    do m = 1, myMesh%elementCount
       myMesh%elementCoordsLon(m) = elementCoords(2*m-1)
       myMesh%elementCoordsLat(m) = elementCoords(2*m)
    end do

    deallocate(nodeCoords)
    deallocate(elementCoords)

    ! Construct 2d element connection array
    myMesh%elementConn2d(:,:) = 0
    offset = 0
    do m = 1, myMesh%elementCount
       num_modes = myMesh%elementTypes(m)
       myMesh%elementConn2d(m,:num_modes) = myMesh%elementConn(offset:offset+num_modes)
       offset = offset+num_modes
    end do

    ! Convert lat-lon to cartesian
    if (convertCartesian) then
       ! Calculate cartesian coordinates for nodes
       if (coordSys == ESMF_COORDSYS_SPH_DEG) then
          do m = 1, myMesh%nodeCount
             if (myMesh%nodeCoordsLat(m) == 90.0d0) then
                myMesh%nodeCoordsX(m) = 0.0d0
                myMesh%nodeCoordsY(m) = 0.0d0
                myMesh%nodeCoordsZ(m) = 1.0d0
             else if (myMesh%nodeCoordsLat(m) == -90.0d0) then
                myMesh%nodeCoordsX(m) = 0.0d0
                myMesh%nodeCoordsY(m) = 0.0d0
                myMesh%nodeCoordsZ(m) = -1.0d0
             else
                theta = myMesh%nodeCoordsLon(m)*deg2Rad
                phi = (90.0d0-myMesh%nodeCoordsLat(m))*deg2Rad
                myMesh%nodeCoordsX(m) = cos(theta)*sin(phi)
                myMesh%nodeCoordsY(m) = sin(theta)*sin(phi)
                myMesh%nodeCoordsZ(m) = cos(phi)
             end if
          end do
       else if (coordSys == ESMF_COORDSYS_SPH_RAD) then
          do m = 1, myMesh%nodeCount
             theta = myMesh%nodeCoordsLon(m)
             phi = constHalfPi-myMesh%nodeCoordsLat(m)
             myMesh%nodeCoordsX(m) = cos(theta)*sin(phi)
             myMesh%nodeCoordsY(m) = sin(theta)*sin(phi)
             myMesh%nodeCoordsZ(m) = cos(phi)
          end do
       end if

       ! Calculate cartesian coordinates for elements 
       if (coordSys == ESMF_COORDSYS_SPH_DEG) then
          do m = 1, myMesh%elementCount
             if (myMesh%elementCoordsLat(m) == 90.0d0) then
                myMesh%elementCoordsX(m) = 0.0d0
                myMesh%elementCoordsY(m) = 0.0d0
                myMesh%elementCoordsZ(m) = 1.0d0
             else if (myMesh%elementCoordsLat(m) == -90.0d0) then
                myMesh%elementCoordsX(m) = 0.0d0
                myMesh%elementCoordsY(m) = 0.0d0
                myMesh%elementCoordsZ(m) = -1.0d0
             else
                theta = myMesh%elementCoordsLon(m)*deg2Rad
                phi = (90.0d0-myMesh%elementCoordsLat(m))*deg2Rad
                myMesh%elementCoordsX(m) = cos(theta)*sin(phi)
                myMesh%elementCoordsY(m) = sin(theta)*sin(phi)
                myMesh%elementCoordsZ(m) = cos(phi)
             end if
          end do
       else if (coordSys == ESMF_COORDSYS_SPH_RAD) then
          ! Calculate cartesian coordinates for nodes
          do m = 1, myMesh%nodeCount
             theta = myMesh%nodeCoordsLon(m)
             phi = constHalfPi-myMesh%nodeCoordsLat(m)
             myMesh%nodeCoordsX(m) = cos(theta)*sin(phi)
             myMesh%nodeCoordsY(m) = sin(theta)*sin(phi)
             myMesh%nodeCoordsZ(m) = cos(phi)
          end do

          ! Calculate cartesian coordinates for elements
          do m = 1, myMesh%elementCount
             theta = myMesh%elementCoordsLon(m)
             phi = constHalfPi-myMesh%elementCoordsLat(m)
             myMesh%elementCoordsX(m) = cos(theta)*sin(phi)
             myMesh%elementCoordsY(m) = sin(theta)*sin(phi)
             myMesh%elementCoordsZ(m) = cos(phi)
          end do
       end if
    else
       ! No conversion to cartesian coordinates is requested
       ! Simply copy latitude and longitude
       ! Nodes
       myMesh%nodeCoordsX(:) = myMesh%nodeCoordsLon(:)
       myMesh%nodeCoordsY(:) = myMesh%nodeCoordsLat(:)
       myMesh%nodeCoordsZ(:) = 0.0d0
       ! Elements
       myMesh%elementCoordsX(:) = myMesh%elementCoordsLon(:)
       myMesh%elementCoordsY(:) = myMesh%elementCoordsLat(:)
       myMesh%elementCoordsZ(:) = 0.0d0
    end if

    ! Get mask information
    if (myMesh%elementMaskIsPresent) then
       allocate(myMesh%elementMask(myMesh%elementCount))
       call ESMF_MeshGet(mesh, elementMask=myMesh%elementMask, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end if

    if (myMesh%nodeMaskIsPresent) then
       allocate(myMesh%nodeMask(myMesh%nodeCount))
       call ESMF_MeshGet(mesh, nodeMask=myMesh%nodeMask, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end if

    ! Find out element types, it maps them to VTK shape types
    ! At this point only supports triangles (3) and quads (4) and their mixtures
    do m = 1, myMesh%elementCount
       if (myMesh%elementTypes(m) == 3) then
          hasTri = .true.
          myMesh%elementShape = "tri"
          myMesh%elementTypesShape(m) = 5 ! VTK_TRIANGLE
       else if (myMesh%elementTypes(m) == 4) then
          hasQuad = .true.
          myMesh%elementShape = "quad"
          myMesh%elementTypesShape(m) = 9 ! VTK_QUAD
       else
          write(message, fmt='(A,I2,A)') trim(subname)//": Only tri, quad and their mixtures "// &
             "are supported as element shape. The given mesh has elements with ", myMesh%elementTypes(m), " nodes."
          call ESMF_LogWrite(trim(message), ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if
    end do

    ! Fill arrays for mapping and set elementShape to mixed if it is required
    if (hasTri .and. hasQuad) then
       myMesh%elementShape = "mixed"
       allocate(myMesh%elementShapeMapName(2))
       allocate(myMesh%elementShapeMapValue(2))
       myMesh%elementShapeMapName(1) = "tri"
       myMesh%elementShapeMapValue(1) = 5
       myMesh%elementShapeMapName(2) = "quad"
       myMesh%elementShapeMapValue(2) = 9
    else
       allocate(myMesh%elementShapeMapName(1))
       allocate(myMesh%elementShapeMapValue(1))
       if (hasTri) then
          myMesh%elementShapeMapName(1) = "tri"
          myMesh%elementShapeMapValue(1) = 5
       else
          myMesh%elementShapeMapName(1) = "quad"
          myMesh%elementShapeMapValue(1) = 9
       end if
    end if

    ! Calculate element offsets
    myMesh%elementTypesOffset(1) = 0
    do m = 2, myMesh%elementCount
       myMesh%elementTypesOffset(m) = myMesh%elementTypesOffset(m-1)+myMesh%elementTypes(m-1)
    end do

    ! Set element connection (Conduit uses 0-based indexes but ESMF is 1-based)
    myMesh%elementConn(:) = myMesh%elementConn(:)-1

    call ESMF_LogWrite(subname//' done for '//trim(compName), ESMF_LOGMSG_INFO)

  end subroutine IngestMeshData

end module geogate_types
