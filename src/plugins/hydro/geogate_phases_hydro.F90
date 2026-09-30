module geogate_phases_hydro

  !-----------------------------------------------------------------------------
  ! Hydro plugin: builds a parallel-decomposed ESMF_LocStream from a
  ! configured coordinate file, and fills one ESMF_Field per configured
  ! variable from a configured list of time-varying data files. Fully
  ! data-source agnostic (see docs/source/hydro.rst for the config format,
  ! decomposition design, time_selection modes, and verification).
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_GridComp, ESMF_GridCompGet
  use ESMF, only: ESMF_VM, ESMF_VMGet
  use ESMF, only: ESMF_Clock, ESMF_ClockGet
  use ESMF, only: ESMF_Time, ESMF_TimeGet
  use ESMF, only: ESMF_TimeInterval, ESMF_TimeIntervalGet
  use ESMF, only: operator(-), operator(<=), operator(>=)
  use ESMF, only: ESMF_DistGrid, ESMF_DistGridCreate, ESMF_DistGridGet
  use ESMF, only: ESMF_LocStream, ESMF_LocStreamCreate, ESMF_LocStreamAddKey
  use ESMF, only: ESMF_COORDSYS_SPH_DEG, ESMF_DATACOPY_REFERENCE
  use ESMF, only: ESMF_Field, ESMF_FieldCreate, ESMF_FieldGet
  use ESMF, only: ESMF_TYPEKIND_R8
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE, ESMF_MAXSTR, ESMF_KIND_R8

  use NUOPC, only: NUOPC_CompAttributeGet
  use NUOPC_Model, only: NUOPC_ModelGet

  use geogate_share, only: ChkErr, fillValue

  use geogate_hydro_config, only: HydroConfigType, HydroConfigRead
  use geogate_hydro_io, only: HydroReadReorderIndex, HydroReadVarMeta
  use geogate_hydro_pio, only: PioReadCoords, PioReadVariable
  use geogate_hydro_time, only: HydroReadFileTimes

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: geogate_phases_hydro_run

  !-----------------------------------------------------------------------------
  ! Private module data (built once on the first call, reused thereafter)
  !-----------------------------------------------------------------------------

  logical, save :: first_call = .true.
  type(HydroConfigType), save :: config
  type(ESMF_DistGrid), save :: distgridHydro
  type(ESMF_LocStream), save :: locstreamHydro
  type(ESMF_Field), allocatable, save :: fieldsHydro(:)
  integer, save :: mpiComm, myPet, localCount, nptsGlobal

  real(ESMF_KIND_R8), allocatable, save :: lat(:), lon(:)   ! SAVE: referenced by ESMF_LocStreamAddKey below
  integer, allocatable, save :: seqIndexList(:)             ! local target-order global sequence indices
  integer, allocatable, save :: pointIdLocal(:)             ! local points' id_variable values

  ! Flat (file, time-record) index spanning config%dataFiles(:)
  integer, allocatable, save :: timeFileIndex(:)
  integer, allocatable, save :: timeFrameIndex(:)
  type(ESMF_Time), allocatable, save :: timeValid(:)

  ! Per-variable metadata, and the (file,frame) selection currently loaded
  integer, allocatable, save :: varXtype(:), varNdims(:)
  real(ESMF_KIND_R8), allocatable, save :: varScaleFactor(:), varAddOffset(:)
  logical, allocatable, save :: varHasFillValue(:)
  real(ESMF_KIND_R8), allocatable, save :: varFillValueRaw(:)
  integer, save :: selectedTimeIndex = -1

  logical, save :: dataDumpStarted = .false.   ! hydro_data_check_PET*.csv: replace once, append after

  character(ESMF_MAXSTR), save :: hydroConfigFile = "hydro_config.yaml"
  character(*), parameter :: modName = "(geogate_phases_hydro)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine geogate_phases_hydro_run(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    logical :: isPresent, isSet
    character(ESMF_MAXSTR) :: cvalue
    character(ESMF_MAXSTR) :: message
    type(ESMF_VM) :: vm
    integer :: petCount
    integer :: nearestTimeIndex
    type(ESMF_Clock) :: clock
    type(ESMF_Time) :: currTime
    character(ESMF_MAXSTR) :: currTimeStr
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_hydro_run) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    !------------------
    ! First call: read configuration, build the LocStream and fields, and
    ! index every data file's valid time(s)
    !------------------

    if (first_call) then

       call NUOPC_CompAttributeGet(gcomp, name="HydroConfigFile", value=cvalue, &
          isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       if (isPresent .and. isSet) hydroConfigFile = trim(cvalue)

       call HydroConfigRead(hydroConfigFile, config, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       if (trim(config%timeSelection) == "linear") then
          call ESMF_LogWrite(trim(subname)//": ERROR time_selection 'linear' is not yet implemented; "// &
             "use 'nearest', 'lower', or 'upper'", ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       else if (trim(config%timeSelection) /= "nearest" .and. trim(config%timeSelection) /= "lower" &
          .and. trim(config%timeSelection) /= "upper") then
          call ESMF_LogWrite(trim(subname)//": ERROR time_selection '"//trim(config%timeSelection)// &
             "' is not recognized; must be 'nearest', 'lower', 'upper', or 'linear'", ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if

       call ESMF_GridCompGet(gcomp, vm=vm, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       call ESMF_VMGet(vm, localPet=myPet, petCount=petCount, mpiCommunicator=mpiComm, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       call BuildLocStreamAndFields(rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       call IndexDataFileTimes(rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       call ReadVariableMetadata(rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       first_call = .false.
    end if

    !------------------
    ! Every call: pick a single data file/time record per config%timeSelection,
    ! and (re-)read the configured variables only if that selection changed
    !------------------

    call NUOPC_ModelGet(gcomp, modelClock=clock, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_ClockGet(clock, currTime=currTime, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Logged every call (regardless of whether the selection changes) so the
    ! run phase's actual calling cadence can be confirmed against the
    ! configured coupling interval, e.g. via:
    !   grep 'geogate_phases_hydro_run) currTime=' PET0000.ESMF_LogFile
    call ESMF_TimeGet(currTime, timeStringISOFrac=currTimeStr, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_LogWrite(subname//' currTime='//trim(currTimeStr), ESMF_LOGMSG_INFO)

    select case (trim(config%timeSelection))
    case ("lower")
       call FindLowerTime(currTime, nearestTimeIndex, rc)
    case ("upper")
       call FindUpperTime(currTime, nearestTimeIndex, rc)
    case default
       call FindNearestTime(currTime, nearestTimeIndex, rc)
    end select
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    if (nearestTimeIndex /= selectedTimeIndex) then
       call ReadAndFillFields(nearestTimeIndex, currTime, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       selectedTimeIndex = nearestTimeIndex
    end if

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_hydro_run

  !-----------------------------------------------------------------------------

  subroutine BuildLocStreamAndFields(rc)

    ! Builds the DistGrid/LocStream/fields from the coordinate file, and
    ! writes the coordinate verification dump. Runs once, from first_call.

    ! input/output variables
    integer, intent(out) :: rc

    ! local variables
    integer :: n, iounit
    character(ESMF_MAXSTR) :: dumpFile
    integer, allocatable :: reorderIndexGlobal(:)
    integer, allocatable :: compdof(:)
    character(len=*), parameter :: subname = trim(modName)//':(BuildLocStreamAndFields) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS

    call HydroReadReorderIndex(config%coordFile, config%idVarName, config%orderVarName, &
       reorderIndexGlobal, nptsGlobal, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    distgridHydro = ESMF_DistGridCreate(minIndex=(/1/), maxIndex=(/nptsGlobal/), rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_DistGridGet(distgridHydro, localDe=0, elementCount=localCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    allocate(seqIndexList(localCount))
    call ESMF_DistGridGet(distgridHydro, localDe=0, seqIndexList=seqIndexList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! reorderIndex is 0-based; PIO's compdof is 1-based
    allocate(compdof(localCount))
    do n = 1, localCount
       compdof(n) = reorderIndexGlobal(seqIndexList(n)) + 1
    end do
    deallocate(reorderIndexGlobal)

    call PioReadCoords(config%coordFile, mpiComm, myPet, nptsGlobal, compdof, &
       config%idVarName, config%latVarName, config%lonVarName, lat, lon, pointIdLocal, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    deallocate(compdof)

    ! Coordinate verification dump (see docs/source/hydro.rst: Verification)
    write(dumpFile, fmt='(A,I4.4,A)') 'hydro_locstream_check_PET', myPet, '.csv'
    open(newunit=iounit, file=trim(dumpFile), status='replace', action='write')
    write(iounit, '(A)') 'id,lat,lon'
    do n = 1, localCount
       write(iounit, '(I0,",",F0.6,",",F0.6)') pointIdLocal(n), lat(n), lon(n)
    end do
    close(iounit)

    locstreamHydro = ESMF_LocStreamCreate(distgrid=distgridHydro, coordSys=ESMF_COORDSYS_SPH_DEG, &
       name="hydro", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LocStreamAddKey(locstreamHydro, keyName="ESMF:Lat", farray=lat, &
       datacopyflag=ESMF_DATACOPY_REFERENCE, keyUnits="Degrees", keyLongName="Latitude", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LocStreamAddKey(locstreamHydro, keyName="ESMF:Lon", farray=lon, &
       datacopyflag=ESMF_DATACOPY_REFERENCE, keyUnits="Degrees", keyLongName="Longitude", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    allocate(fieldsHydro(size(config%variableNames)))
    do n = 1, size(config%variableNames)
       fieldsHydro(n) = ESMF_FieldCreate(locstreamHydro, typekind=ESMF_TYPEKIND_R8, &
          name=trim(config%variableNames(n)), rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine BuildLocStreamAndFields

  !-----------------------------------------------------------------------------

  subroutine IndexDataFileTimes(rc)

    ! Builds the flat (file, time-record) list spanning config%dataFiles(:)

    ! input/output variables
    integer, intent(out) :: rc

    ! local variables
    integer :: f, t, k, ntimes, totalEntries
    type(ESMF_Time), allocatable :: fileTimes(:)
    character(len=*), parameter :: subname = trim(modName)//':(IndexDataFileTimes) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS

    totalEntries = 0
    do f = 1, size(config%dataFiles)
       call HydroReadFileTimes(config%dataFiles(f), config%timeVarName, fileTimes, ntimes, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       totalEntries = totalEntries + ntimes
       deallocate(fileTimes)
    end do

    allocate(timeFileIndex(totalEntries))
    allocate(timeFrameIndex(totalEntries))
    allocate(timeValid(totalEntries))

    k = 0
    do f = 1, size(config%dataFiles)
       call HydroReadFileTimes(config%dataFiles(f), config%timeVarName, fileTimes, ntimes, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       do t = 1, ntimes
          k = k + 1
          timeFileIndex(k) = f
          timeFrameIndex(k) = t
          timeValid(k) = fileTimes(t)
       end do
       deallocate(fileTimes)
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine IndexDataFileTimes

  !-----------------------------------------------------------------------------

  subroutine ReadVariableMetadata(rc)

    ! Reads each configured variable's on-disk type/rank/packing metadata
    ! once, from config%dataFiles(1)

    ! input/output variables
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    character(len=*), parameter :: subname = trim(modName)//':(ReadVariableMetadata) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS

    allocate(varXtype(size(config%variableNames)))
    allocate(varNdims(size(config%variableNames)))
    allocate(varScaleFactor(size(config%variableNames)))
    allocate(varAddOffset(size(config%variableNames)))
    allocate(varHasFillValue(size(config%variableNames)))
    allocate(varFillValueRaw(size(config%variableNames)))

    do n = 1, size(config%variableNames)
       call HydroReadVarMeta(config%dataFiles(1), trim(config%variableNames(n)), &
          varXtype(n), varNdims(n), varScaleFactor(n), varAddOffset(n), &
          varHasFillValue(n), varFillValueRaw(n), rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ReadVariableMetadata

  !-----------------------------------------------------------------------------

  subroutine FindNearestTime(currTime, nearestIndex, rc)

    ! time_selection=nearest (see docs/source/hydro.rst: Runtime Configuration Options)

    ! input/output variables
    type(ESMF_Time), intent(in) :: currTime
    integer, intent(out) :: nearestIndex
    integer, intent(out) :: rc

    ! local variables
    integer :: k
    real(ESMF_KIND_R8) :: diffSeconds, bestDiffSeconds
    character(len=*), parameter :: subname = trim(modName)//':(FindNearestTime) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    nearestIndex = -1
    bestDiffSeconds = -1.0d0

    ! On an exact tie (currTime exactly midway between two entries), <=
    ! favors the later entry (round-half-up) so the switch lands exactly on
    ! the midpoint instead of one step after it (see docs/source/hydro.rst)
    do k = 1, size(timeValid)
       call ESMF_TimeIntervalGet(currTime - timeValid(k), s_r8=diffSeconds, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       diffSeconds = abs(diffSeconds)
       if (nearestIndex == -1 .or. diffSeconds <= bestDiffSeconds) then
          nearestIndex = k
          bestDiffSeconds = diffSeconds
       end if
    end do

  end subroutine FindNearestTime

  !-----------------------------------------------------------------------------

  subroutine FindLowerTime(currTime, lowerIndex, rc)

    ! time_selection=lower (see docs/source/hydro.rst: Runtime Configuration Options)

    ! input/output variables
    type(ESMF_Time), intent(in) :: currTime
    integer, intent(out) :: lowerIndex
    integer, intent(out) :: rc

    ! local variables
    integer :: k
    real(ESMF_KIND_R8) :: diffSeconds, bestDiffSeconds
    character(ESMF_MAXSTR) :: currTimeStr
    character(len=*), parameter :: subname = trim(modName)//':(FindLowerTime) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    lowerIndex = -1
    bestDiffSeconds = -1.0d0

    do k = 1, size(timeValid)
       if (timeValid(k) <= currTime) then
          call ESMF_TimeIntervalGet(currTime - timeValid(k), s_r8=diffSeconds, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (lowerIndex == -1 .or. diffSeconds < bestDiffSeconds) then
             lowerIndex = k
             bestDiffSeconds = diffSeconds
          end if
       end if
    end do

    if (lowerIndex == -1) then
       call ESMF_TimeGet(currTime, timeStringISOFrac=currTimeStr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       call ESMF_LogWrite(trim(subname)//': ERROR current time '//trim(currTimeStr)// &
          ' is before every configured data_files entry (time_selection=lower does not extrapolate)', &
          ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

  end subroutine FindLowerTime

  !-----------------------------------------------------------------------------

  subroutine FindUpperTime(currTime, upperIndex, rc)

    ! time_selection=upper, the mirror image of FindLowerTime (see
    ! docs/source/hydro.rst: Runtime Configuration Options)

    ! input/output variables
    type(ESMF_Time), intent(in) :: currTime
    integer, intent(out) :: upperIndex
    integer, intent(out) :: rc

    ! local variables
    integer :: k
    real(ESMF_KIND_R8) :: diffSeconds, bestDiffSeconds
    character(ESMF_MAXSTR) :: currTimeStr
    character(len=*), parameter :: subname = trim(modName)//':(FindUpperTime) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    upperIndex = -1
    bestDiffSeconds = -1.0d0

    do k = 1, size(timeValid)
       if (timeValid(k) >= currTime) then
          call ESMF_TimeIntervalGet(timeValid(k) - currTime, s_r8=diffSeconds, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (upperIndex == -1 .or. diffSeconds < bestDiffSeconds) then
             upperIndex = k
             bestDiffSeconds = diffSeconds
          end if
       end if
    end do

    if (upperIndex == -1) then
       call ESMF_TimeGet(currTime, timeStringISOFrac=currTimeStr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       call ESMF_LogWrite(trim(subname)//': ERROR current time '//trim(currTimeStr)// &
          ' is after every configured data_files entry (time_selection=upper does not extrapolate)', &
          ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

  end subroutine FindUpperTime

  !-----------------------------------------------------------------------------

  subroutine ReadAndFillFields(timeIndex, currTime, rc)

    ! Reads every configured variable from the selected data file/record,
    ! unpacks it, writes it into the matching field, and appends a block to
    ! the per-PET data verification dump (see docs/source/hydro.rst:
    ! Data Ingest, Verification).

    ! input/output variables
    integer, intent(in) :: timeIndex
    type(ESMF_Time), intent(in) :: currTime
    integer, intent(out) :: rc

    ! local variables
    integer :: n, m, iounit
    character(ESMF_MAXSTR) :: dumpFile
    character(ESMF_MAXSTR) :: message
    character(ESMF_MAXSTR) :: header
    character(ESMF_MAXSTR) :: lineBuf
    character(32) :: fieldStr
    character(ESMF_MAXSTR) :: dataFile
    character(ESMF_MAXSTR) :: validTimeStr
    character(ESMF_MAXSTR) :: currTimeStr
    real(ESMF_KIND_R8), allocatable :: raw(:)
    real(ESMF_KIND_R8), pointer :: dataptr(:)
    real(ESMF_KIND_R8), allocatable, save :: unpacked(:,:)
    character(len=*), parameter :: subname = trim(modName)//':(ReadAndFillFields) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS

    dataFile = config%dataFiles(timeFileIndex(timeIndex))

    if (.not. allocated(unpacked)) allocate(unpacked(localCount, size(config%variableNames)))

    do n = 1, size(config%variableNames)
       call PioReadVariable(dataFile, mpiComm, myPet, nptsGlobal, seqIndexList, &
          trim(config%variableNames(n)), varXtype(n), varNdims(n), timeFrameIndex(timeIndex), raw, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       unpacked(:,n) = raw(:)*varScaleFactor(n) + varAddOffset(n)
       if (varHasFillValue(n)) then
          do m = 1, localCount
             if (raw(m) == varFillValueRaw(n)) unpacked(m,n) = fillValue
          end do
       end if
       deallocate(raw)

       call ESMF_FieldGet(fieldsHydro(n), farrayptr=dataptr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       dataptr(:) = unpacked(:,n)
    end do

    call ESMF_TimeGet(timeValid(timeIndex), timeStringISOFrac=validTimeStr, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_TimeGet(currTime, timeStringISOFrac=currTimeStr, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    write(message, fmt='(A,I4,A,I8,A,I8,A)') trim(subname)//': PET ', myPet, &
       ' filled fields from '//trim(dataFile)//' record ', timeFrameIndex(timeIndex), &
       ' (time index ', timeIndex, '), valid_time='//trim(validTimeStr)//', curr_time='//trim(currTimeStr)
    call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)

    write(dumpFile, fmt='(A,I4.4,A)') 'hydro_data_check_PET', myPet, '.csv'
    header = 'id'
    do n = 1, size(config%variableNames)
       header = trim(header)//','//trim(config%variableNames(n))
    end do
    if (.not. dataDumpStarted) then
       open(newunit=iounit, file=trim(dumpFile), status='replace', action='write')
       dataDumpStarted = .true.
    else
       open(newunit=iounit, file=trim(dumpFile), status='old', position='append', action='write')
    end if
    write(iounit, '(A)') '# curr_time='//trim(currTimeStr)
    write(iounit, '(A)') '# valid_time='//trim(validTimeStr)
    write(iounit, '(A)') '# data_file='//trim(dataFile)
    write(iounit, '(A,I0)') '# time_record=', timeFrameIndex(timeIndex)
    write(iounit, '(A)') trim(header)
    do m = 1, localCount
       write(fieldStr, fmt='(I0)') pointIdLocal(m)
       lineBuf = trim(fieldStr)
       do n = 1, size(config%variableNames)
          write(fieldStr, fmt='(F0.6)') unpacked(m,n)
          lineBuf = trim(lineBuf)//','//trim(fieldStr)
       end do
       write(iounit, '(A)') trim(lineBuf)
    end do
    close(iounit)

  end subroutine ReadAndFillFields

end module geogate_phases_hydro
