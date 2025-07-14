module geogate_phases_io

  !-----------------------------------------------------------------------------
  ! Write imported fields
  !-----------------------------------------------------------------------------

  use ESMF , only: operator(==)
  use ESMF, only: ESMF_GridComp, ESMF_GridCompGetInternalState
  use ESMF, only: ESMF_Time, ESMF_TimeGet
  use ESMF, only: ESMF_Clock, ESMF_ClockGet
  use ESMF, only: ESMF_LogFoundError, ESMF_FAILURE, ESMF_LogWrite
  use ESMF, only: ESMF_LOGERR_PASSTHRU, ESMF_LOGMSG_INFO, ESMF_SUCCESS
  use ESMF, only: ESMF_Field, ESMF_FieldGet, ESMF_FieldWrite, ESMF_FieldWriteVTK
  use ESMF, only: ESMF_FieldBundle, ESMF_FieldBundleGet
  use ESMF, only: ESMF_MAXSTR, ESMF_GEOMTYPE_GRID, ESMF_GEOMTYPE_MESH

  use NUOPC_Model, only: NUOPC_ModelGet

  use geogate_share, only: ChkErr
  use geogate_internalstate, only: InternalState

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: geogate_phases_io_run

  !-----------------------------------------------------------------------------
  ! Private module routines
  !-----------------------------------------------------------------------------

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  integer :: dbug = 0
  character(len=*), parameter :: modName = "(geogate_phases_io)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine geogate_phases_io_run(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    type(InternalState) :: is_local
    type(ESMF_Time) :: currTime
    type(ESMF_Clock) :: clock
    character(len=ESMF_MAXSTR) :: timeStr
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_io_run) '
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

    ! Query current time
    call ESMF_ClockGet(clock, currTime=currTime, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_TimeGet(currTime, timeStringISOFrac=timeStr , rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Loop over FBs
    do n = 1, is_local%wrap%numComp
       ! Write state
       call FBWrite(is_local%wrap%FBImp(n), trim(is_local%wrap%compName(n))//'_import_'//trim(timeStr), rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_io_run

  !-----------------------------------------------------------------------------

  subroutine FBWrite(FBin, prefix, rc)

    ! input/output variables
    type(ESMF_FieldBundle) :: FBin
    character(len=*), intent(in) :: prefix
    integer, intent(out), optional :: rc

    ! local variables
    integer :: n
    integer :: fieldCount
    type(ESMF_Field) :: field
    character(len=ESMF_MAXSTR) :: msg
    character(ESMF_MAXSTR), allocatable :: fieldNameList(:)
    character(len=*), parameter :: subname = trim(modName)//':(FBWrite) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Query number of item in the FB
    call ESMF_FieldBundleGet(FBin, fieldCount=fieldCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    allocate(fieldNameList(fieldCount))

    call ESMF_FieldBundleGet(FBin, fieldNameList=fieldNameList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    write(msg, fmt='(A,I8)') subname//' number of fields in FB ', fieldCount
    call ESMF_LogWrite(trim(msg), ESMF_LOGMSG_INFO)

    ! Loop over fields
    do n = 1, fieldCount
       ! Debug information
       call ESMF_LogWrite(subname//' writing '//trim(fieldNameList(n)), ESMF_LOGMSG_INFO)

       ! Query field
       call ESMF_FieldBundleGet(FBin, fieldName=trim(fieldNameList(n)), field=field, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return

       ! Write field
       call ESMF_FieldWriteVTK(field, trim(prefix)//'_'//trim(fieldNameList(n)), rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end do

    ! Clean memory
    deallocate(fieldNameList)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine FBWrite

end module geogate_phases_io
