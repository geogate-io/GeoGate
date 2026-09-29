module geogate_phases_hydro

  !-----------------------------------------------------------------------------
  ! Hydro plugin: build a correctly parallel-decomposed ESMF_LocStream from
  ! NWM RouteLink coordinates, and one ESMF_Field per configured variable
  ! name on it, filled with synthetic data (each point's value is its
  ! global, ascending/feature_id-order sequence index -- not real streamflow
  ! data). This is intentionally scoped to just geometry + field creation:
  ! no time-varying data ingest, no temporal interpolation, no destination
  ! Mesh/regrid, no NUOPC export-state realization. Those are follow-on
  ! steps once this decomposition is verified.
  !
  ! Decomposition: RouteLink's on-disk ("link") order is a different
  ! permutation of the same points than the ascending/"feature_id" order
  ! shared by every NWM channel_rt-style file, so a PET's contiguous block
  ! of the TARGET order maps to scattered on-disk positions -- not a plain
  ! hyperslab. So:
  !   1. Every PET reads RouteLink's small "ascendingIndex" array in full
  !      (geogate_hydro_io: HydroReadAscendingIndex) -- cheap, one-time.
  !   2. An ESMF_DistGrid of the true global size is built (ESMF picks the
  !      default decomposition across this component's PETs), and each
  !      PET's local global (target-order) sequence indices are queried
  !      from it.
  !   3. Those local target-order indices are translated through
  !      ascendingIndex into the corresponding scattered on-disk positions
  !      ("compdof"), and ParallelIO's explicit decomposition-map read
  !      (geogate_hydro_pio: PioReadCoords) fetches just this PET's lat/lon
  !      (and link/feature_id) values directly -- no full-file replication
  !      of the (large) lat/lon arrays.
  !   4. The ESMF_LocStream is created directly from that same DistGrid, so
  !      its decomposition matches PIO's read exactly.
  !
  ! Also writes one hydro_locstream_check_PET<nnnn>.csv per PET (feature_id,
  ! lat, lon for each locally-owned point) -- a temporary verification aid
  ! so the decomposition/coordinates can be cross-checked against an
  ! independently-computed (e.g. Python) reading of RouteLink_CONUS.nc.
  ! Remove once the parallel read has been validated.
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_GridComp, ESMF_GridCompGet
  use ESMF, only: ESMF_VM, ESMF_VMGet
  use ESMF, only: ESMF_DistGrid, ESMF_DistGridCreate, ESMF_DistGridGet
  use ESMF, only: ESMF_LocStream, ESMF_LocStreamCreate, ESMF_LocStreamAddKey
  use ESMF, only: ESMF_COORDSYS_SPH_DEG, ESMF_DATACOPY_REFERENCE
  use ESMF, only: ESMF_Field, ESMF_FieldCreate, ESMF_FieldGet
  use ESMF, only: ESMF_TYPEKIND_R8
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE, ESMF_MAXSTR, ESMF_KIND_R8

  use NUOPC, only: NUOPC_CompAttributeGet

  use geogate_share, only: ChkErr

  use geogate_hydro_config, only: HydroConfigType, HydroConfigRead
  use geogate_hydro_io, only: HydroReadAscendingIndex
  use geogate_hydro_pio, only: PioReadCoords

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

  ! Referenced (not copied) by ESMF_LocStreamAddKey below (datacopyflag=
  ! ESMF_DATACOPY_REFERENCE), so these must outlive this module's first call
  ! -- hence SAVE, not ordinary subroutine-local allocatables.
  real(ESMF_KIND_R8), allocatable, save :: lat(:), lon(:)

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
    integer :: iounit
    logical :: isPresent, isSet
    character(ESMF_MAXSTR) :: cvalue
    character(ESMF_MAXSTR) :: message
    character(ESMF_MAXSTR) :: dumpFile
    type(ESMF_VM) :: vm
    integer :: mpiComm, myPet, petCount
    integer :: nfeatGlobal, localCount
    integer, allocatable :: ascendingIndexGlobal(:)
    integer, allocatable :: seqIndexList(:)
    integer, allocatable :: compdof(:)
    integer, allocatable :: linkId(:)
    real(ESMF_KIND_R8), pointer :: dataptr(:)
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_hydro_run) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    if (.not. first_call) then
       call ESMF_LogWrite(trim(subname)//': LocStream and fields already built, nothing to do', &
          ESMF_LOGMSG_INFO)
       return
    end if

    !------------------
    ! Read configuration (route link file + field name list)
    !------------------

    ! Allow the config file path to be set via nuopc.runconfig, e.g.:
    !   geogate_attributes::
    !     HydroConfigFile = hydro_config.yaml
    !   ::
    call NUOPC_CompAttributeGet(gcomp, name="HydroConfigFile", value=cvalue, &
       isPresent=isPresent, isSet=isSet, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    if (isPresent .and. isSet) hydroConfigFile = trim(cvalue)

    call HydroConfigRead(hydroConfigFile, config, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! This component's PET info (needed for PIO's own communicator scope)
    !------------------

    call ESMF_GridCompGet(gcomp, vm=vm, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_VMGet(vm, localPet=myPet, petCount=petCount, mpiCommunicator=mpiComm, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Every PET reads the small, full ascendingIndex array (and learns the
    ! true global feature count from the same file)
    !------------------

    call HydroReadAscendingIndex(config%routeLinkFile, ascendingIndexGlobal, nfeatGlobal, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Build the global DistGrid (default decomposition across this
    ! component's PETs) and find this PET's local, target-order indices
    !------------------

    distgridHydro = ESMF_DistGridCreate(minIndex=(/1/), maxIndex=(/nfeatGlobal/), rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_DistGridGet(distgridHydro, localDe=0, elementCount=localCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    allocate(seqIndexList(localCount))
    call ESMF_DistGridGet(distgridHydro, localDe=0, seqIndexList=seqIndexList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Translate this PET's target-order indices into the scattered on-disk
    ! RouteLink positions PIO needs to fetch (ascendingIndex is 0-based;
    ! PIO's compdof is 1-based)
    allocate(compdof(localCount))
    do n = 1, localCount
       compdof(n) = ascendingIndexGlobal(seqIndexList(n)) + 1
    end do
    deallocate(ascendingIndexGlobal)

    !------------------
    ! Parallel, decomposed read of just this PET's lat/lon (+ link) values
    !------------------

    call PioReadCoords(config%routeLinkFile, mpiComm, myPet, nfeatGlobal, compdof, lat, lon, linkId, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    deallocate(compdof)

    !------------------
    ! Verification aid: dump feature_id,lat,lon for this PET's points, to be
    ! cross-checked against an independently-computed reading of
    ! RouteLink_CONUS.nc (see verify_hydro_locstream.py). Remove once the
    ! parallel read/decomposition has been validated.
    !------------------

    write(dumpFile, fmt='(A,I4.4,A)') 'hydro_locstream_check_PET', myPet, '.csv'
    open(newunit=iounit, file=trim(dumpFile), status='replace', action='write')
    write(iounit, '(A)') 'feature_id,lat,lon'
    do n = 1, localCount
       write(iounit, '(I0,",",F0.6,",",F0.6)') linkId(n), lat(n), lon(n)
    end do
    close(iounit)
    deallocate(linkId)

    !------------------
    ! Create the LocStream from the same DistGrid used for the PIO read
    !------------------

    locstreamHydro = ESMF_LocStreamCreate(distgrid=distgridHydro, coordSys=ESMF_COORDSYS_SPH_DEG, &
       name="hydro", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LocStreamAddKey(locstreamHydro, keyName="ESMF:Lat", farray=lat, &
       datacopyflag=ESMF_DATACOPY_REFERENCE, keyUnits="Degrees", keyLongName="Latitude", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LocStreamAddKey(locstreamHydro, keyName="ESMF:Lon", farray=lon, &
       datacopyflag=ESMF_DATACOPY_REFERENCE, keyUnits="Degrees", keyLongName="Longitude", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Create one field per configured name and fill with synthetic data:
    ! each point's value is its global (ascending/feature_id-order)
    ! sequence index -- not real data, but enough to sanity-check that the
    ! decomposition is gap-free/overlap-free across PETs.
    !------------------

    allocate(fieldsHydro(size(config%variableNames)))
    do n = 1, size(config%variableNames)
       fieldsHydro(n) = ESMF_FieldCreate(locstreamHydro, typekind=ESMF_TYPEKIND_R8, &
          name=trim(config%variableNames(n)), rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       call ESMF_FieldGet(fieldsHydro(n), farrayptr=dataptr, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       dataptr(:) = real(seqIndexList(:), ESMF_KIND_R8)
    end do

    write(message, fmt='(A,I4,A,I8,A,I8,A,I4,A)') trim(subname)//': PET ', myPet, &
       ' owns ', localCount, ' of ', nfeatGlobal, ' points, created ', &
       size(config%variableNames), ' field(s) with synthetic data'
    call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)

    deallocate(seqIndexList)

    first_call = .false.

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_hydro_run

end module geogate_phases_hydro
