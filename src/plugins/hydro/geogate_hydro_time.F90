module geogate_hydro_time

  !-----------------------------------------------------------------------------
  ! Small, replicated NetCDF read of a data file's time coordinate variable,
  ! generically parsing its CF "units" attribute (e.g. "hours since
  ! 2000-01-01 00:00:00") rather than assuming any fixed reference epoch or
  ! time resolution. See docs/source/hydro.rst.
  !-----------------------------------------------------------------------------

  use netcdf
  use ESMF, only: ESMF_Time, ESMF_TimeSet
  use ESMF, only: ESMF_TimeInterval, ESMF_TimeIntervalSet
  use ESMF, only: ESMF_CALKIND_GREGORIAN
  use ESMF, only: operator(+)
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE, ESMF_KIND_R8

  use geogate_share, only: ChkErr

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: HydroReadFileTimes

  private :: ParseCFTimeUnits

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(*), parameter :: modName = "(geogate_hydro_time)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine HydroReadFileTimes(dataFile, timeVarName, validTimes, ntimes, rc)

    ! Reads every time value in a data file's time_variable as ESMF_Time

    ! input/output variables
    character(len=*), intent(in) :: dataFile
    character(len=*), intent(in) :: timeVarName
    type(ESMF_Time), allocatable, intent(out) :: validTimes(:)
    integer, intent(out) :: ntimes
    integer, intent(out) :: rc

    ! local variables
    integer :: ncid, varid
    integer :: dimids(1)
    integer :: n
    real(ESMF_KIND_R8), allocatable :: timeValues(:)
    character(len=256) :: unitsAttr
    type(ESMF_Time) :: refTime
    type(ESMF_TimeInterval) :: offset
    real(ESMF_KIND_R8) :: secondsPerUnit
    character(len=*), parameter :: subname = trim(modName)//':(HydroReadFileTimes) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(dataFile), ESMF_LOGMSG_INFO)

    ! Open the NetCDF file
    call NcChk(nf90_open(trim(dataFile), NF90_NOWRITE, ncid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Read the time variable's values and units attribute
    call NcChk(nf90_inq_varid(ncid, trim(timeVarName), varid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call NcChk(nf90_inquire_variable(ncid, varid, dimids=dimids), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call NcChk(nf90_inquire_dimension(ncid, dimids(1), len=ntimes), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Allocate and read the time values
    allocate(timeValues(ntimes))
    call NcChk(nf90_get_var(ncid, varid, timeValues), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Read the time variable's units attribute and parse it into a reference time and seconds per unit
    call NcChk(nf90_get_att(ncid, varid, "units", unitsAttr), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Close the NetCDF file
    call NcChk(nf90_close(ncid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Parse the CF time units string into a reference time and seconds per unit
    call ParseCFTimeUnits(trim(unitsAttr), refTime, secondsPerUnit, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Allocate the output array of valid times and compute each valid time as refTime + offset
    allocate(validTimes(ntimes))
    do n = 1, ntimes
       call ESMF_TimeIntervalSet(offset, s_r8=timeValues(n)*secondsPerUnit, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       validTimes(n) = refTime + offset
    end do

    ! Clean memory
    deallocate(timeValues)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine HydroReadFileTimes

  !-----------------------------------------------------------------------------

  subroutine ParseCFTimeUnits(unitsStr, refTime, secondsPerUnit, rc)

    ! Parses a CF time "units" attribute

    ! input/output variables
    character(len=*), intent(in) :: unitsStr
    type(ESMF_Time), intent(out) :: refTime
    real(ESMF_KIND_R8), intent(out) :: secondsPerUnit
    integer, intent(out) :: rc

    ! local variables
    integer :: sincePos, n
    character(len=64) :: periodWord
    character(len=32) :: dateTimeStr
    integer :: yy, mm, dd, hh, mi, ss
    character(len=*), parameter :: subname = trim(modName)//':(ParseCFTimeUnits) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Check for the " since " separator in the units string
    sincePos = index(unitsStr, " since ")
    if (sincePos <= 0) then
       call ESMF_LogWrite(trim(subname)//": ERROR could not find ' since ' in units string '"// &
          trim(unitsStr)//"'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Parse the time period word (e.g. "hours")
    periodWord = adjustl(unitsStr(1:sincePos-1))
    do n = 1, len_trim(periodWord)
       if (periodWord(n:n) >= 'A' .and. periodWord(n:n) <= 'Z') &
          periodWord(n:n) = achar(iachar(periodWord(n:n)) + 32)
    end do

    ! Determine the number of seconds per unit based on the period word
    select case (trim(periodWord))
    case ("second", "seconds", "sec", "secs", "s")
       secondsPerUnit = 1.0d0
    case ("minute", "minutes", "min", "mins")
       secondsPerUnit = 60.0d0
    case ("hour", "hours", "hr", "hrs", "h")
       secondsPerUnit = 3600.0d0
    case ("day", "days", "d")
       secondsPerUnit = 86400.0d0
    case default
       call ESMF_LogWrite(trim(subname)//": ERROR unsupported time period '"//trim(periodWord)// &
          "' in units string '"//trim(unitsStr)//"'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end select

    ! Normalize the date/time part: trim, replace a 'T' separator with a
    ! space, drop any trailing zone indicator (e.g. "Z", "UTC")
    dateTimeStr = adjustl(unitsStr(sincePos+7:))
    do n = 1, len_trim(dateTimeStr)
       if (dateTimeStr(n:n) == 'T' .or. dateTimeStr(n:n) == 't') dateTimeStr(n:n) = ' '
    end do

    ! Check that the date/time string is at least 10 characters long (YYYY-MM-DD)
    if (len_trim(dateTimeStr) < 10) then
       call ESMF_LogWrite(trim(subname)//": ERROR could not parse date from units string '"// &
          trim(unitsStr)//"'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Parse the date/time string into year, month, day, hour, minute, second
    read(dateTimeStr(1:4),  '(I4)') yy
    read(dateTimeStr(6:7),  '(I2)') mm
    read(dateTimeStr(9:10), '(I2)') dd

    ! Parse optional time components (hh:mm:ss) if present, otherwise default to 00:00:00
    hh = 0
    mi = 0
    ss = 0
    if (len_trim(dateTimeStr) >= 19) then
       read(dateTimeStr(12:13), '(I2)') hh
       read(dateTimeStr(15:16), '(I2)') mi
       read(dateTimeStr(18:19), '(I2)') ss
    end if

    ! Set the reference time using ESMF_TimeSet
    call ESMF_TimeSet(refTime, yy=yy, mm=mm, dd=dd, h=hh, m=mi, s=ss, &
       calkindflag=ESMF_CALKIND_GREGORIAN, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ParseCFTimeUnits

  !-----------------------------------------------------------------------------

  subroutine NcChk(status, rc)

    ! input/output variables
    integer, intent(in) :: status
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(NcChk) '
    !---------------------------------------------------------------------------

    ! Check the NetCDF status code and log an error if it indicates failure
    if (status /= nf90_noerr) then
       call ESMF_LogWrite(trim(subname)//': NetCDF error: '//trim(nf90_strerror(status)), ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
    else
       rc = ESMF_SUCCESS
    end if

  end subroutine NcChk

end module geogate_hydro_time
