module geogate_phases_hydro

  ! Hydro plugin: builds a parallel-decomposed LocStream and fills configured fields from time-varying data files

  use ESMF, only: ESMF_GridComp, ESMF_GridCompGet
  use ESMF, only: ESMF_VM, ESMF_VMGet
  use ESMF, only: ESMF_Clock, ESMF_ClockGet
  use ESMF, only: ESMF_Time, ESMF_TimeGet
  use ESMF, only: ESMF_TimeInterval, ESMF_TimeIntervalGet
  use ESMF, only: operator(-), operator(<=), operator(>=), operator(==)
  use ESMF, only: ESMF_DistGrid, ESMF_DistGridCreate, ESMF_DistGridGet
  use ESMF, only: ESMF_LocStream, ESMF_LocStreamCreate, ESMF_LocStreamAddKey
  use ESMF, only: ESMF_COORDSYS_SPH_DEG, ESMF_DATACOPY_REFERENCE
  use ESMF, only: ESMF_Field, ESMF_FieldGet
  use ESMF, only: ESMF_State, ESMF_StateGet
  use ESMF, only: ESMF_GeomType_Flag, ESMF_GEOMTYPE_LOCSTREAM
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_WARNING, ESMF_LOGMSG_ERROR
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

  ! Points at either an export field's own memory or a local fallback buffer
  type :: HydroFieldPtr
     real(ESMF_KIND_R8), pointer :: p(:) => null()
  end type HydroFieldPtr
  type(HydroFieldPtr), allocatable, save :: varData(:)

  ! Plugin configuration, LocStream, MPI communicator, and local decomposition info
  type(HydroConfigType), save :: config
  type(ESMF_LocStream), save :: locstream
  integer, save :: mpiComm, myPet, localCount, nptsGlobal

  ! Flat (global) index of the local points in the global coordinate file, and their local IDs
  integer, allocatable, save :: seqIndexList(:)
  integer, allocatable, save :: pointIdLocal(:)

  ! Flat (file, time-record) index spanning config%dataFiles(:)
  integer, allocatable, save :: timeFileIndex(:)
  integer, allocatable, save :: timeFrameIndex(:)
  type(ESMF_Time), allocatable, save :: timeValid(:)

  ! Per-variable metadata, and the (file,frame) selection currently loaded
  integer, allocatable, save :: varXtype(:), varNdims(:)
  real(ESMF_KIND_R8), allocatable, save :: varScaleFactor(:), varAddOffset(:)
  logical, allocatable, save :: varHasFillValue(:)
  real(ESMF_KIND_R8), allocatable, save :: varFillValueRaw(:)

  ! Cached raw bracket data so BlendAndFillFields can reblend every call without re-reading from disk
  real(ESMF_KIND_R8), allocatable, save :: rawLower(:,:), rawUpper(:,:)

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
    logical, save :: first_call = .true.
    integer, save :: selectedLowerIndex = -1
    integer, save :: selectedUpperIndex = -1
    integer :: n
    logical :: isPresent, isSet
    character(ESMF_MAXSTR) :: cvalue
    character(ESMF_MAXSTR) :: message
    character(ESMF_MAXSTR) :: hydroConfigFile
    type(ESMF_VM) :: vm
    integer :: petCount
    integer :: lowerIndex, upperIndex
    type(ESMF_Clock) :: clock
    type(ESMF_Time) :: currTime
    character(ESMF_MAXSTR) :: currTimeStr
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_hydro_run) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Initialize
    if (first_call) then
       ! Get name of configuration file
       hydroConfigFile = "hydro_config.yaml"
       call NUOPC_CompAttributeGet(gcomp, name="HydroConfigFile", value=cvalue, &
          isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       if (isPresent .and. isSet) then
          hydroConfigFile = trim(cvalue)
       end if

       ! Read configuration file and validate time_selection option
       call HydroConfigRead(hydroConfigFile, config, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       if (trim(config%timeSelection) /= "nearest" .and. trim(config%timeSelection) /= "lower" &
          .and. trim(config%timeSelection) /= "upper" .and. trim(config%timeSelection) /= "linear") then
          call ESMF_LogWrite(trim(subname)//": ERROR time_selection '"//trim(config%timeSelection)// &
             "' is not recognized; must be 'nearest', 'lower', 'upper', or 'linear'", ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if

       ! Get the ESMF VM and MPI communicator, so the plugin can pass them to PIO
       call ESMF_GridCompGet(gcomp, vm=vm, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       call ESMF_VMGet(vm, localPet=myPet, petCount=petCount, mpiCommunicator=mpiComm, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Build the LocStream and fields
       call BuildLocStreamAndFields(rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Match each configured variable's export name against the export state and points varData(n)%p at it
       call ResolveExportFields(gcomp, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Build the flat (file, time-record) list spanning config%dataFiles(:)
       call IndexDataFileTimes(rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Read each configured variable's on-disk type/rank/packing metadata once, from first file
       call ReadVariableMetadata(rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       first_call = .false.
    end if

    ! Query model clock and current time
    call NUOPC_ModelGet(gcomp, modelClock=clock, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_ClockGet(clock, currTime=currTime, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Debug logging of current time
    call ESMF_TimeGet(currTime, timeStringISOFrac=currTimeStr, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_LogWrite(subname//' currTime='//trim(currTimeStr), ESMF_LOGMSG_INFO)

    ! Find the lower/upper bracket indices for the current time to read the data file/s
    select case (trim(config%timeSelection))
    case ("lower")
       call FindLowerTime(currTime, lowerIndex, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       upperIndex = lowerIndex
    case ("upper")
       call FindUpperTime(currTime, upperIndex, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       lowerIndex = upperIndex
    case ("linear")
       call FindLowerTime(currTime, lowerIndex, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       call FindUpperTime(currTime, upperIndex, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    case default
       call FindNearestTime(currTime, lowerIndex, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       upperIndex = lowerIndex
    end select
    
    ! Only re-read data from disk when the bracket (lower, upper) changes
    if (lowerIndex /= selectedLowerIndex .or. upperIndex /= selectedUpperIndex) then
       call ReadBracketData(lowerIndex, upperIndex, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       selectedLowerIndex = lowerIndex
       selectedUpperIndex = upperIndex
    end if

    ! Blend the bracket data by currTime's fractional position in the bracket and update the export fields
    call BlendAndFillFields(lowerIndex, upperIndex, currTime, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_hydro_run

  !-----------------------------------------------------------------------------

  subroutine BuildLocStreamAndFields(rc)

    ! Builds the DistGrid/LocStream from the coordinate file (see docs/source/hydro.rst).

    ! input/output variables
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    integer, allocatable :: reorderIndexGlobal(:)
    integer, allocatable :: compdof(:)
    type(ESMF_DistGrid) :: distgrid
    real(ESMF_KIND_R8), allocatable, save :: lat(:), lon(:)
    character(len=*), parameter :: subname = trim(modName)//':(BuildLocStreamAndFields) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Read the coordinate file to build the DistGrid/LocStream
    call HydroReadReorderIndex(config%coordFile, config%idVarName, &
       config%orderVarName, reorderIndexGlobal, nptsGlobal, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Build the DistGrid and get the local count and sequence indices
    distgrid = ESMF_DistGridCreate(minIndex=(/1/), maxIndex=(/nptsGlobal/), rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query the local count and sequence indices for this PET
    call ESMF_DistGridGet(distgrid, localDe=0, elementCount=localCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    allocate(seqIndexList(localCount))
    
    call ESMF_DistGridGet(distgrid, localDe=0, seqIndexList=seqIndexList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! The index is 0-based; PIO's compdof is 1-based
    allocate(compdof(localCount))
    do n = 1, localCount
       compdof(n) = reorderIndexGlobal(seqIndexList(n)) + 1
    end do
    deallocate(reorderIndexGlobal)

    ! Read the coordinate file to get the lat/lon arrays and the local point IDs
    call PioReadCoords(config%coordFile, mpiComm, myPet, nptsGlobal, compdof, &
       config%idVarName, config%latVarName, config%lonVarName, lat, lon, pointIdLocal, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    deallocate(compdof)

    ! Create the LocStream and add the lat/lon keys
    locstream = ESMF_LocStreamCreate(distgrid=distgrid, coordSys=ESMF_COORDSYS_SPH_DEG, &
       name="hydro", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LocStreamAddKey(locstream, keyName="ESMF:Lat", farray=lat, &
       datacopyflag=ESMF_DATACOPY_REFERENCE, keyUnits="Degrees", &
       keyLongName="Latitude", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LocStreamAddKey(locstream, keyName="ESMF:Lon", farray=lon, &
       datacopyflag=ESMF_DATACOPY_REFERENCE, keyUnits="Degrees", &
       keyLongName="Longitude", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine BuildLocStreamAndFields

  !-----------------------------------------------------------------------------

  subroutine ResolveExportFields(gcomp, rc)

    ! Matches each configured variable's export name against the export state and points varData(n)%p at it

    ! input/output variables
    type(ESMF_GridComp), intent(in) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n, k, itemCount
    type(ESMF_State) :: exportState
    type(ESMF_Field) :: field
    type(ESMF_GeomType_Flag) :: geomtype
    character(ESMF_MAXSTR), allocatable :: itemNameList(:)
    logical, allocatable :: hasExportField(:)
    logical :: isFound
    character(len=*), parameter :: subname = trim(modName)//':(ResolveExportFields) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Allocate the varData array and a boolean array to track which export fields were found
    allocate(hasExportField(size(config%variableNames)))
    allocate(varData(size(config%variableNames)))
    hasExportField(:) = .false.

    ! Query the export state from the model and get its item count
    call NUOPC_ModelGet(gcomp, exportState=exportState, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_StateGet(exportState, itemCount=itemCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    if (itemCount > 0) then
       ! Get the list of item names in the export state
       allocate(itemNameList(itemCount))
       call ESMF_StateGet(exportState, itemNameList=itemNameList, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Loop over each configured variable and check if its export name is present in the export state
       do n = 1, size(config%variableNames)
          ! Check if the export field is present in the export state
          isFound = .false.
          do k = 1, itemCount
             if (trim(itemNameList(k)) == trim(config%exportVarNames(n))) then
                isFound = .true.
                exit
             end if
          end do

          ! Debug logging of export field presence
          if (.not. isFound) then
             call ESMF_LogWrite(trim(subname)//": WARNING export field '"// &
                trim(config%exportVarNames(n))//"' (mapped from data variable '"// &
                trim(config%variableNames(n))//"') not found in export state -- skipping", &
                ESMF_LOGMSG_WARNING)
             cycle
          end if

          ! Get the field from the export state
          call ESMF_StateGet(exportState, itemName=trim(config%exportVarNames(n)), field=field, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Check that the field is on a LocStream
          call ESMF_FieldGet(field, geomtype=geomtype, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          if (.not. (geomtype == ESMF_GEOMTYPE_LOCSTREAM)) then
             call ESMF_LogWrite(trim(subname)//": WARNING export field '"// &
                trim(config%exportVarNames(n))//"' (mapped from data variable '"// &
                trim(config%variableNames(n))//"') is not on a LocStream -- skipping", &
                ESMF_LOGMSG_WARNING)
             cycle
          end if

          ! Get the field's data pointer and point varData(n)%p at it
          call ESMF_FieldGet(field, farrayptr=varData(n)%p, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Guard against a mismatched export LocStream size (see docs/source/hydro.rst: Limitations)
          if (size(varData(n)%p) /= localCount) then
             call ESMF_LogWrite(trim(subname)//": ERROR export field '"// &
                trim(config%exportVarNames(n))//"' (mapped from data variable '"// &
                trim(config%variableNames(n))//"') local size does not match hydro's own "// &
                "decomposition -- check that ExportMeshFile matches coord_file (same point "// &
                "count/order)", ESMF_LOGMSG_ERROR)
             rc = ESMF_FAILURE
             return
          end if

          hasExportField(n) = .true.
       end do

       ! Clean memory
       deallocate(itemNameList)
    else
       ! Debug logging when the export state has no fields (e.g., a model with no export fields configured)
       call ESMF_LogWrite(trim(subname)//": export state has no fields -- hydro export disabled", &
          ESMF_LOGMSG_INFO)
    end if

    ! Clean memory
    do n = 1, size(config%variableNames)
       if (.not. hasExportField(n)) allocate(varData(n)%p(localCount))
    end do
    deallocate(hasExportField)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ResolveExportFields

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
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Count the total number of time records across all configured data files
    totalEntries = 0
    do f = 1, size(config%dataFiles)
       call HydroReadFileTimes(config%dataFiles(f), config%timeVarName, fileTimes, ntimes, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       totalEntries = totalEntries + ntimes
       deallocate(fileTimes)
    end do

    ! Allocate the flat (file, time-record) index arrays
    allocate(timeFileIndex(totalEntries))
    allocate(timeFrameIndex(totalEntries))
    allocate(timeValid(totalEntries))

    ! Build the flat (file, time-record) index arrays
    k = 0
    do f = 1, size(config%dataFiles)
       ! Read the time records from the current data file
       call HydroReadFileTimes(config%dataFiles(f), config%timeVarName, fileTimes, ntimes, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Fill the flat (file, time-record) index arrays for the current data file
       do t = 1, ntimes
          k = k + 1
          timeFileIndex(k) = f
          timeFrameIndex(k) = t
          timeValid(k) = fileTimes(t)
       end do

       ! Clean memory
       deallocate(fileTimes)
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine IndexDataFileTimes

  !-----------------------------------------------------------------------------

  subroutine ReadVariableMetadata(rc)

    ! Reads each configured variable's on-disk type/rank/packing metadata once, from config%dataFiles(1)

    ! input/output variables
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    character(len=*), parameter :: subname = trim(modName)//':(ReadVariableMetadata) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Allocate the per-variable metadata arrays
    allocate(varXtype(size(config%variableNames)))
    allocate(varNdims(size(config%variableNames)))
    allocate(varScaleFactor(size(config%variableNames)))
    allocate(varAddOffset(size(config%variableNames)))
    allocate(varHasFillValue(size(config%variableNames)))
    allocate(varFillValueRaw(size(config%variableNames)))

    ! Loop over each configured variable and read its metadata from the first data file
    do n = 1, size(config%variableNames)
       ! Read the variable's metadata from the first data file
       call HydroReadVarMeta(config%dataFiles(1), trim(config%variableNames(n)), &
          varXtype(n), varNdims(n), varScaleFactor(n), varAddOffset(n), &
          varHasFillValue(n), varFillValueRaw(n), rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ReadVariableMetadata

  !-----------------------------------------------------------------------------

  subroutine FindNearestTime(currTime, nearestIndex, rc)

    ! time_selection=nearest

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
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Initialize the nearest index and best difference to invalid values
    nearestIndex = -1
    bestDiffSeconds = -1.0d0

    ! Loop over each valid time and find the index of the nearest time to currTime
    do k = 1, size(timeValid)
       ! Compute the absolute difference in seconds between currTime and timeValid(k)
       call ESMF_TimeIntervalGet(currTime - timeValid(k), s_r8=diffSeconds, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Take the absolute value of the difference in seconds
       diffSeconds = abs(diffSeconds)
       if (nearestIndex == -1 .or. diffSeconds <= bestDiffSeconds) then
          nearestIndex = k
          bestDiffSeconds = diffSeconds
       end if
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine FindNearestTime

  !-----------------------------------------------------------------------------

  subroutine FindLowerTime(currTime, lowerIndex, rc)

    ! time_selection=lower

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
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Initialize the lower index and best difference to invalid values
    lowerIndex = -1
    bestDiffSeconds = -1.0d0

    ! Loop over each valid time and find the index of the largest time that is less than or equal to currTime
    do k = 1, size(timeValid)
       ! Check if timeValid(k) is less than or equal to currTime
       if (timeValid(k) <= currTime) then
          ! Compute the difference in seconds between currTime and timeValid(k)
          call ESMF_TimeIntervalGet(currTime - timeValid(k), s_r8=diffSeconds, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Update the lower index if this is the first valid time or if the difference is smaller than the best difference found so far
          if (lowerIndex == -1 .or. diffSeconds < bestDiffSeconds) then
             lowerIndex = k
             bestDiffSeconds = diffSeconds
          end if
       end if
    end do

    ! If no valid time was found that is less than or equal to currTime, log an error and return failure
    if (lowerIndex == -1) then
       ! Query the current time as a string for logging
       call ESMF_TimeGet(currTime, timeStringISOFrac=currTimeStr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Log an error message indicating that the current time is before every configured data_files entry
       call ESMF_LogWrite(trim(subname)//': ERROR current time '//trim(currTimeStr)// &
          ' is before every configured data_files entry (time_selection=lower does not extrapolate)', &
          ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine FindLowerTime

  !-----------------------------------------------------------------------------

  subroutine FindUpperTime(currTime, upperIndex, rc)

    ! time_selection=upper

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
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Initialize the upper index and best difference to invalid values
    upperIndex = -1
    bestDiffSeconds = -1.0d0

    ! Loop over each valid time and find the index of the smallest time that is greater than or equal to currTime
    do k = 1, size(timeValid)
       ! Check if timeValid(k) is greater than or equal to currTime
       if (timeValid(k) >= currTime) then
          ! Compute the difference in seconds between timeValid(k) and currTime
          call ESMF_TimeIntervalGet(timeValid(k) - currTime, s_r8=diffSeconds, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Update the upper index if this is the first valid time or if the difference is smaller than the best difference found so far
          if (upperIndex == -1 .or. diffSeconds < bestDiffSeconds) then
             upperIndex = k
             bestDiffSeconds = diffSeconds
          end if
       end if
    end do

    ! If no valid time was found that is greater than or equal to currTime, log an error and return failure
    if (upperIndex == -1) then
       ! Query the current time as a string for logging
       call ESMF_TimeGet(currTime, timeStringISOFrac=currTimeStr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Log an error message indicating that the current time is after every configured data_files entry
       call ESMF_LogWrite(trim(subname)//': ERROR current time '//trim(currTimeStr)// &
          ' is after every configured data_files entry (time_selection=upper does not extrapolate)', &
          ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

   call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine FindUpperTime

  !-----------------------------------------------------------------------------

  subroutine ReadBracketData(lowerIndex, upperIndex, rc)

    ! Reads raw bracket data into rawLower/rawUpper, only when the bracket changes

    ! input/output variables
    integer, intent(in) :: lowerIndex, upperIndex
    integer, intent(out) :: rc

    ! local variables
    integer :: n, nVars
    character(ESMF_MAXSTR) :: message
    character(ESMF_MAXSTR) :: lowerFile, upperFile
    real(ESMF_KIND_R8), allocatable :: raw(:)
    character(len=*), parameter :: subname = trim(modName)//':(ReadBracketData) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Allocate the rawLower/rawUpper arrays if they are not already allocated
    nVars = size(config%variableNames)
    if (.not. allocated(rawLower)) then
       allocate(rawLower(localCount, nVars))
       allocate(rawUpper(localCount, nVars))
    end if

    ! Lower-bracket file and time record
    lowerFile = config%dataFiles(timeFileIndex(lowerIndex))

    ! Loop over each configured variable and read its data from the lower-bracket file and time record
    do n = 1, nVars
       ! Read the variable's data from the lower-bracket file and time record
       call PioReadVariable(lowerFile, mpiComm, myPet, nptsGlobal, seqIndexList, &
          trim(config%variableNames(n)), varXtype(n), varNdims(n), timeFrameIndex(lowerIndex), raw, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Store the raw data in the rawLower array
       rawLower(:,n) = raw(:)

       ! Clean memory
       deallocate(raw)
    end do

    ! Debug logging of lower-bracket read
    write(message, fmt='(A,I4,A,I8,A,I8,A)') trim(subname)//': PET ', myPet, &
       ' read lower-bracket data from '//trim(lowerFile)//' record ', timeFrameIndex(lowerIndex), &
       ' (time index ', lowerIndex, ')'
    call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)

    ! Check if the upper index is the same as the lower index; if so, copy rawLower to rawUpper
    if (upperIndex == lowerIndex) then
       rawUpper = rawLower
    else
       ! Upper-bracket file and time record
       upperFile = config%dataFiles(timeFileIndex(upperIndex))

       ! Loop over each configured variable and read its data from the upper-bracket file and time record
       do n = 1, nVars
          ! Read the variable's data from the upper-bracket file and time record
          call PioReadVariable(upperFile, mpiComm, myPet, nptsGlobal, seqIndexList, &
             trim(config%variableNames(n)), varXtype(n), varNdims(n), timeFrameIndex(upperIndex), raw, rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return

          ! Store the raw data in the rawUpper array
          rawUpper(:,n) = raw(:)

          ! Clean memory
          deallocate(raw)
       end do

       ! Debug logging of upper-bracket read
       write(message, fmt='(A,I4,A,I8,A,I8,A)') trim(subname)//': PET ', myPet, &
          ' read upper-bracket data from '//trim(upperFile)//' record ', timeFrameIndex(upperIndex), &
          ' (time index ', upperIndex, ')'
       call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
    end if

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ReadBracketData

  !-----------------------------------------------------------------------------

  subroutine BlendAndFillFields(lowerIndex, upperIndex, currTime, rc)

    ! Blends rawLower/rawUpper by currTime's fractional position in the bracket and fills varData

    ! input/output variables
    integer, intent(in) :: lowerIndex, upperIndex
    type(ESMF_Time), intent(in) :: currTime
    integer, intent(out) :: rc

    ! local variables
    integer :: n, m
    real(ESMF_KIND_R8) :: weight, numer, denom
    type(ESMF_TimeInterval) :: diffNumer, diffDenom
    character(ESMF_MAXSTR) :: message
    character(ESMF_MAXSTR) :: validTimeStr
    character(ESMF_MAXSTR) :: currTimeStr
    character(len=*), parameter :: subname = trim(modName)//':(BlendAndFillFields) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Compute the weight for linear interpolation based on currTime's position between the lower and upper valid times
    if (lowerIndex == upperIndex) then
       weight = 0.0d0
    else
       ! Compute the time difference between currTime and the lower valid time, and between the upper and lower valid times
       diffNumer = currTime - timeValid(lowerIndex)
       diffDenom = timeValid(upperIndex) - timeValid(lowerIndex)

       ! Get the time differences in seconds
       call ESMF_TimeIntervalGet(diffNumer, s_r8=numer, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       call ESMF_TimeIntervalGet(diffDenom, s_r8=denom, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Compute the weight as the ratio of the time differences
       weight = numer/denom
    end if

    ! Loop over each configured variable
    do n = 1, size(config%variableNames)
       ! Blend the lower and upper raw data for variable n, applying scale factor and add offset
       varData(n)%p(:) = (rawLower(:,n) + weight*(rawUpper(:,n) - rawLower(:,n)))*varScaleFactor(n) + varAddOffset(n)

       ! Fill any points that have the fill value in either the lower or upper raw data
       if (varHasFillValue(n)) then
          do m = 1, localCount
             if (rawLower(m,n) == varFillValueRaw(n) .or. rawUpper(m,n) == varFillValueRaw(n)) then
                varData(n)%p(m) = fillValue
             end if
          end do
       end if
    end do

    ! Debug logging of the blending operation
    call ESMF_TimeGet(timeValid(lowerIndex), timeStringISOFrac=validTimeStr, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_TimeGet(currTime, timeStringISOFrac=currTimeStr, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    write(message, fmt='(A,I4,A,F8.5,A)') trim(subname)//': PET ', myPet, &
       ' blended fields, weight=', weight, ', lower_valid_time='//trim(validTimeStr)// &
       ', curr_time='//trim(currTimeStr)
    call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine BlendAndFillFields

end module geogate_phases_hydro
