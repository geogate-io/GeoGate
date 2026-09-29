module geogate_hydro_pio

  !-----------------------------------------------------------------------------
  ! Parallel (PIO-based), decomposed read of RouteLink's lat/lon coordinates
  ! (plus the "link" feature id, mainly so callers can tag/verify each point
  ! against an externally-computed value rather than relying on array
  ! position alone).
  !
  ! Unlike a plain NetCDF hyperslab read, this uses ParallelIO's explicit
  ! decomposition-map API (PIO_initdecomp with a "compdof" array) so each PET
  ! reads only the on-disk positions it actually needs. That is required
  ! here because the target point ordering (ascending link id, matching NWM
  ! channel_rt "feature_id" order) is a different permutation of RouteLink's
  ! own on-disk ("link") order -- a PET's contiguous block of the TARGET
  ! order corresponds to scattered, non-contiguous positions in the file's
  ! on-disk order, which a plain hyperslab read cannot express, but a
  ! decomposition map (PIO's "compdof") can. Only a small number of PETs
  ! (num_iotasks below) actually touch the filesystem; PIO's rearranger
  ! ships each PET's slice to it over MPI internally.
  !
  ! NOTE: the PIO call signatures below (PIO_init, PIO_openfile, PIO_inq_varid,
  ! PIO_initdecomp with an integer(i4) compdof, PIO_read_darray, PIO_closefile,
  ! PIO_freedecomp, PIO_finalize) were cross-checked against the ParallelIO
  ! 2.6.2 source (src/flib/piolib_mod.F90, piodarray.F90.in, pio_nf.F90,
  ! pio_types.F90) at https://github.com/NCAR/ParallelIO/tree/pio2_6_2,
  ! matching the install at .../parallelio-2.6.2-fo32vuo -- this module has
  ! not been compiled/tested yet.
  !-----------------------------------------------------------------------------

  use pio, only: iosystem_desc_t, file_desc_t, io_desc_t, var_desc_t
  use pio, only: PIO_init, PIO_finalize
  use pio, only: PIO_openfile, PIO_closefile
  use pio, only: PIO_initdecomp, PIO_freedecomp
  use pio, only: PIO_inq_varid
  use pio, only: PIO_read_darray
  use pio, only: PIO_real, PIO_int, PIO_iotype_netcdf, PIO_rearr_subset
  use pio, only: PIO_noerr

  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE, ESMF_KIND_R8

  use geogate_share, only: ChkErr

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: PioReadCoords

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(*), parameter :: modName = "(geogate_hydro_pio)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine PioReadCoords(routeLinkFile, mpiComm, myPet, nfeatGlobal, compdof, lat, lon, linkId, rc)

    ! input/output variables
    character(len=*), intent(in) :: routeLinkFile
    integer, intent(in) :: mpiComm
    integer, intent(in) :: myPet             ! 0-based rank of this PET within mpiComm
    integer, intent(in) :: nfeatGlobal
    integer, intent(in) :: compdof(:)        ! 1-based on-disk RouteLink positions this PET owns (target order)
    real(ESMF_KIND_R8), allocatable, intent(out) :: lat(:)
    real(ESMF_KIND_R8), allocatable, intent(out) :: lon(:)
    integer, allocatable, intent(out) :: linkId(:)   ! RouteLink "link" (feature_id) for each local point
    integer, intent(out) :: rc

    ! local variables
    integer :: ierr
    integer :: localCount
    ! Explicit KIND=4, NOT bare "real": this project's build adds
    ! -real-size 64 (see ufs-weather-model/cmake/Intel.cmake) to
    ! CMAKE_Fortran_FLAGS globally, which silently promotes bare "real" to
    ! 8 bytes everywhere, including here. RouteLink's lat/lon are on-disk
    ! 4-byte float, and PIO_initdecomp below is told basepiotype=PIO_real
    ! (4-byte) -- a bare "real" buffer would (under that flag) actually be
    ! 8-byte, so the compiler binds PIO_read_darray's generic to its
    ! double-precision specific while the iodesc still expects 4-byte
    ! elements, corrupting every value read (confirmed: this exact bug
    ! produced garbage lat/lon while integer "link" values, unaffected by
    ! -real-size, came out correct).
    real(kind=4), allocatable :: latLocal_r4(:), lonLocal_r4(:)
    type(iosystem_desc_t) :: iosystem
    type(file_desc_t) :: pioFile
    type(io_desc_t) :: iodescReal
    type(io_desc_t) :: iodescInt
    type(var_desc_t) :: latVardesc, lonVardesc, linkVardesc
    character(len=*), parameter :: subname = trim(modName)//':(PioReadCoords) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(routeLinkFile), ESMF_LOGMSG_INFO)

    localCount = size(compdof)
    allocate(latLocal_r4(localCount), lonLocal_r4(localCount))
    allocate(lat(localCount), lon(localCount), linkId(localCount))

    ! One IOSystem scoped to just this component's PETs. num_iotasks=1 means
    ! only a single PET actually opens/reads the file; PIO's SUBSET
    ! rearranger ships each PET's slice to it over MPI.
    call PIO_init(comp_rank=myPet, comp_comm=mpiComm, num_iotasks=1, num_aggregator=0, &
       stride=1, rearr=PIO_rearr_subset, iosystem=iosystem)

    ierr = PIO_openfile(iosystem, pioFile, PIO_iotype_netcdf, trim(routeLinkFile))
    if (PioChk(ierr, 'PIO_openfile for '//trim(routeLinkFile), rc)) return

    ierr = PIO_inq_varid(pioFile, "lat", latVardesc)
    if (PioChk(ierr, 'PIO_inq_varid for lat', rc)) return

    ierr = PIO_inq_varid(pioFile, "lon", lonVardesc)
    if (PioChk(ierr, 'PIO_inq_varid for lon', rc)) return

    ierr = PIO_inq_varid(pioFile, "link", linkVardesc)
    if (PioChk(ierr, 'PIO_inq_varid for link', rc)) return

    ! Same compdof (index mapping) for all three variables since they share
    ! the feature_id dimension, but a separate iodesc per on-disk type
    ! (float for lat/lon, int for link)
    call PIO_initdecomp(iosystem, PIO_real, (/ nfeatGlobal /), compdof, iodescReal)
    call PIO_initdecomp(iosystem, PIO_int, (/ nfeatGlobal /), compdof, iodescInt)

    call PIO_read_darray(pioFile, latVardesc, iodescReal, latLocal_r4, ierr)
    if (PioChk(ierr, 'PIO_read_darray for lat', rc)) return

    call PIO_read_darray(pioFile, lonVardesc, iodescReal, lonLocal_r4, ierr)
    if (PioChk(ierr, 'PIO_read_darray for lon', rc)) return

    call PIO_read_darray(pioFile, linkVardesc, iodescInt, linkId, ierr)
    if (PioChk(ierr, 'PIO_read_darray for link', rc)) return

    lat(:) = real(latLocal_r4(:), ESMF_KIND_R8)
    lon(:) = real(lonLocal_r4(:), ESMF_KIND_R8)

    call PIO_freedecomp(iosystem, iodescReal)
    call PIO_freedecomp(iosystem, iodescInt)
    call PIO_closefile(pioFile)
    call PIO_finalize(iosystem, ierr)

    deallocate(latLocal_r4, lonLocal_r4)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine PioReadCoords

  !-----------------------------------------------------------------------------

  logical function PioChk(ierr, msg, rc)

    ! input/output variables
    integer, intent(in) :: ierr
    character(len=*), intent(in) :: msg
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(PioChk) '
    !---------------------------------------------------------------------------

    PioChk = .false.
    if (ierr /= PIO_noerr) then
       call ESMF_LogWrite(trim(subname)//': ERROR '//trim(msg)//' failed', ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       PioChk = .true.
    else
       rc = ESMF_SUCCESS
    end if

  end function PioChk

end module geogate_hydro_pio
