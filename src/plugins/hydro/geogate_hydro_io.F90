module geogate_hydro_io

  !-----------------------------------------------------------------------------
  ! Small, replicated (every-PET-reads-the-same-thing) NetCDF reads. This is
  ! only used for RouteLink's "ascendingIndex" array, which every PET needs
  ! in full (it is small, ~11MB for CONUS) to translate its local, contiguous
  ! slice of the ascending/feature_id target order into the scattered set of
  ! on-disk RouteLink positions PIO needs to fetch (see geogate_hydro_pio.F90
  ! for the actual, genuinely parallel/decomposed coordinate read).
  !-----------------------------------------------------------------------------

  use netcdf
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE

  use geogate_share, only: ChkErr

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: HydroReadAscendingIndex

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(*), parameter :: modName = "(geogate_hydro_io)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine HydroReadAscendingIndex(routeLinkFile, ascendingIndex, nfeat, rc)

    ! Reads the global feature_id count and the full "ascendingIndex"
    ! array from a NWM RouteLink file. ascendingIndex(i) (0-based) gives the
    ! on-disk RouteLink record for the i-th point in ascending link-id order,
    ! which is the same order used by NWM forecast output (channel_rt)
    ! files' "feature_id" dimension -- verified to match exactly for the
    ! CONUS domain (RouteLink "link" sorted ascending == channel_rt
    ! "feature_id").

    ! input/output variables
    character(len=*), intent(in) :: routeLinkFile
    integer, allocatable, intent(out) :: ascendingIndex(:)
    integer, intent(out) :: nfeat
    integer, intent(out) :: rc

    ! local variables
    integer :: ncid, dimid, varid
    character(len=*), parameter :: subname = trim(modName)//':(HydroReadAscendingIndex) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(routeLinkFile), ESMF_LOGMSG_INFO)

    call NcChk(nf90_open(trim(routeLinkFile), NF90_NOWRITE, ncid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call NcChk(nf90_inq_dimid(ncid, "feature_id", dimid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NcChk(nf90_inquire_dimension(ncid, dimid, len=nfeat), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    allocate(ascendingIndex(nfeat))

    call NcChk(nf90_inq_varid(ncid, "ascendingIndex", varid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NcChk(nf90_get_var(ncid, varid, ascendingIndex), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call NcChk(nf90_close(ncid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine HydroReadAscendingIndex

  !-----------------------------------------------------------------------------

  subroutine NcChk(status, rc)

    ! input/output variables
    integer, intent(in) :: status
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(NcChk) '
    !---------------------------------------------------------------------------

    if (status /= nf90_noerr) then
       call ESMF_LogWrite(trim(subname)//': NetCDF error: '//trim(nf90_strerror(status)), ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
    else
       rc = ESMF_SUCCESS
    end if

  end subroutine NcChk

end module geogate_hydro_io
