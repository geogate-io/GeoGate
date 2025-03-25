module geogate_share

  !-----------------------------------------------------------------------------
  ! This is the module for shared routines 
  !-----------------------------------------------------------------------------

  use ESMF, only: operator(==)
  use ESMF, only: ESMF_LogFoundError, ESMF_FAILURE, ESMF_LogWrite
  use ESMF, only: ESMF_LOGERR_PASSTHRU, ESMF_LOGMSG_INFO, ESMF_SUCCESS
  use ESMF, only: ESMF_GeomType_Flag, ESMF_State, ESMF_StateGet
  use ESMF, only: ESMF_Field, ESMF_FieldGet, ESMF_FieldCreate
  use ESMF, only: ESMF_FieldBundle, ESMF_FieldBundleCreate, ESMF_FieldBundleAdd
  use ESMF, only: ESMF_AttributeGet, ESMF_Mesh, ESMF_MeshLoc
  use ESMF, only: ESMF_LOGMSG_ERROR, ESMF_INDEX_DELOCAL, ESMF_MAXSTR, ESMF_KIND_R8
  use ESMF, only: ESMF_GEOMTYPE_GRID, ESMF_GEOMTYPE_MESH
  use ESMF, only: ESMF_StateGet, ESMF_StateItem_Flag, ESMF_STATEITEM_STATE

  use NUOPC, only: NUOPC_GetAttribute

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: ChkErr
  public :: StringSplit
  public :: FB_init_pointer

  !-----------------------------------------------------------------------------
  ! Public module data
  !-----------------------------------------------------------------------------

  logical, public :: debugMode
  real(ESMF_KIND_R8), public, parameter :: constPi = 4.0d0*atan(1.0d0)
  real(ESMF_KIND_R8), public, parameter :: constHalfPi = 0.5d0*constPi
  real(ESMF_KIND_R8), public, parameter :: rad2Deg = 180.0d0/constPi
  real(ESMF_KIND_R8), public, parameter :: deg2Rad = constPi/180.0d0

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(*), parameter :: modName =  "(geogate_share)" 
  character(len=*), parameter :: u_FILE_u = __FILE__ 

!===============================================================================  
  contains
!===============================================================================

  logical function ChkErr(rc, line, file)

    integer, intent(in) :: rc
    integer, intent(in) :: line
    character(len=*), intent(in) :: file

    integer :: lrc

    ChkErr = .false.
    lrc = rc
    if (ESMF_LogFoundError(rcToCheck=lrc, msg=ESMF_LOGERR_PASSTHRU, line=line, file=file)) then
       ChkErr = .true.
    endif
  end function ChkErr

  !-----------------------------------------------------------------------------

  function StringSplit(str, delim) result(parts)
    implicit none

    ! ----------------------------------------------
    ! The `split` function splits a given string into an array of substrings
    ! based on a specified delimiter.
    ! ----------------------------------------------

    ! input/output variables
    character(len=*), intent(in) :: str
    character(len=*), intent(in) :: delim
    character(len=:), allocatable :: parts(:)

    ! local variables
    integer :: i, start, count
    character(*), parameter :: subName = '(StringSplit)'
    !---------------------------------------------------------------------------

    ! Count the number of delimiters to determine the size of the parts array
    count = 0
    do i = 1, len(trim(str))
      if (str(i:i) == delim) count = count+1
    end do

    ! Allocate the parts array
    allocate(character(len=len(trim(str))) :: parts(count+1))

    ! Split the string
    start = 1
    count = 1
    do i = 1, len(trim(str))
      if (str(i:i) == delim) then
        parts(count) = str(start:i-1)
        start = i+1
        count = count+1
      end if
    end do
    parts(count) = str(start:)

    ! Trim the parts to remove any trailing spaces
    do i = 1, count
      parts(i) = trim(parts(i))
    end do

  end function StringSplit

  !-----------------------------------------------------------------------------

  subroutine FB_init_pointer(StateIn, FBout, name, rc)

    ! input/output variables
    type(ESMF_State), intent(in) :: StateIn
    type(ESMF_FieldBundle), intent(inout) :: FBout
    character(len=*), intent(in) :: name
    integer, intent(out), optional :: rc

    ! local variables
    integer :: n
    integer :: fieldCount, lrank
    integer :: ungriddedCount
    integer :: ungriddedLBound(1)
    integer :: ungriddedUBound(1)
    logical :: isPresent
    type(ESMF_Field) :: oldField, newField
    type(ESMF_MeshLoc) :: meshloc
    type(ESMF_Mesh) :: lmesh
    real(ESMF_KIND_R8), pointer :: dataptr1d(:)
    real(ESMF_KIND_R8), pointer :: dataptr2d(:,:)
    character(ESMF_MAXSTR), allocatable :: lfieldNameList(:)
    character(len=*), parameter :: subname = trim(modName)//':(FB_init_pointer) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Create empty field bundle, FBout
    FBout = ESMF_FieldBundleCreate(name=trim(name), rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return

    ! Get list of fields from state
    call ESMF_StateGet(StateIn, itemCount=fieldCount, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return

    allocate(lfieldNameList(fieldCount))

    call ESMF_StateGet(StateIn, itemNameList=lfieldNameList, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return

    ! Add them to the FB
    if (fieldCount > 0) then
       do n = 1, fieldCount
          ! Get field from state
          call ESMF_StateGet(StateIn, itemName=lfieldNameList(n), field=oldField, rc=rc)
          if (chkerr(rc,__LINE__,u_FILE_u)) return

          ! Query mesh location
          if (n == 1) then
             call ESMF_FieldGet(oldField, mesh=lmesh, meshloc=meshloc, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return
          end if

          ! Check rank of the field
          call ESMF_FieldGet(oldField, rank=lrank, rc=rc)
          if (chkerr(rc,__LINE__,u_FILE_u)) return

          ! Add ungridded dimension to field if rank > 1
          if (lrank == 2) then
             ! Determine ungridded lower and upper bounds for field
             call ESMF_AttributeGet(oldField, name="UngriddedLBound", convention="NUOPC", &
                  purpose="Instance", itemCount=ungriddedCount,  isPresent=isPresent, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return

             if (ungriddedCount /= 1) then
                call ESMF_LogWrite(trim(subname)//": ERROR ungriddedCount for "// &
                     trim(lfieldnamelist(n))//" must be 1 if rank is 2 ", ESMF_LOGMSG_ERROR)
                rc = ESMF_FAILURE
                return
             end if

             ! Set ungridded dimensions for field
             call ESMF_AttributeGet(oldField, name="UngriddedLBound", convention="NUOPC", &
                  purpose="Instance", valueList=ungriddedLBound, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return
             call ESMF_AttributeGet(oldField, name="UngriddedUBound", convention="NUOPC", &
                  purpose="Instance", valueList=ungriddedUBound, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return

             ! Get 2d pointer for field
             call ESMF_FieldGet(oldField, farrayptr=dataptr2d, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return

             ! Create new field with an ungridded dimension
             newField = ESMF_FieldCreate(lmesh, dataptr2d, ESMF_INDEX_DELOCAL, &
                  meshloc=meshloc, name=lfieldNameList(n), &
                  ungriddedLbound=ungriddedLbound, ungriddedUbound=ungriddedUbound, gridToFieldMap=(/2/), rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return

          else if (lrank == 1) then
             ! Get 1d pointer for field
             call ESMF_FieldGet(oldField, farrayptr=dataptr1d, rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return

             ! Create new field without an ungridded dimension
             newField = ESMF_FieldCreate(lmesh, dataptr1d, ESMF_INDEX_DELOCAL, &
                  meshloc=meshloc, name=lfieldNameList(n), rc=rc)
             if (chkerr(rc,__LINE__,u_FILE_u)) return

          else
             call ESMF_LogWrite(trim(subname)//": Rank can be 1 or 2!", ESMF_LOGMSG_ERROR)
             rc = ESMF_FAILURE
             return
          end if

          ! Add field to FB
          call ESMF_FieldBundleAdd(FBout, (/ newfield /), rc=rc)
          if (chkerr(rc,__LINE__,u_FILE_u)) return
       end do ! fieldCount
    end if

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine FB_init_pointer

end module geogate_share
