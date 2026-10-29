module geogate_hydro_io

  !-----------------------------------------------------------------------------
  ! Small, replicated (every-PET-reads-the-same-thing) NetCDF reads: an
  ! optional point-reordering index, and a data variable's small metadata
  ! (on-disk type/rank/packing attributes, as opposed to its bulk data,
  ! which is read in a decomposed way by geogate_hydro_pio.F90). See
  ! docs/source/hydro.rst for why the reordering index is read in full by
  ! every PET while lat/lon/data are not.
  !-----------------------------------------------------------------------------

  use netcdf
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE, ESMF_KIND_R8

  use geogate_share, only: ChkErr

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: HydroReadReorderIndex
  public :: HydroReadVarMeta

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(*), parameter :: modName = "(geogate_hydro_io)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine HydroReadReorderIndex(coordFile, idVarName, orderVarName, reorderIndex, npts, rc)

    ! Reads the point count and reorderIndex(:) (0-based; identity if orderVarName is blank).

    ! input/output variables
    character(len=*), intent(in) :: coordFile
    character(len=*), intent(in) :: idVarName
    character(len=*), intent(in) :: orderVarName
    integer, allocatable, intent(out) :: reorderIndex(:)
    integer, intent(out) :: npts
    integer, intent(out) :: rc

    ! local variables
    integer :: ncid, idvarid, varid
    integer :: dimids(1)
    integer :: n
    character(len=*), parameter :: subname = trim(modName)//':(HydroReadReorderIndex) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(coordFile), ESMF_LOGMSG_INFO)

    ! Open the coordinate file in read-only mode
    call NcChk(nf90_open(trim(coordFile), NF90_NOWRITE, ncid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Point count comes from the id variable's own (single) dimension
    call NcChk(nf90_inq_varid(ncid, trim(idVarName), idvarid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NcChk(nf90_inquire_variable(ncid, idvarid, dimids=dimids), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NcChk(nf90_inquire_dimension(ncid, dimids(1), len=npts), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Allocate the reorderIndex array to hold the point reordering indices
    allocate(reorderIndex(npts))

    ! If orderVarName is non-blank, read the reorderIndex variable from the file; otherwise, fill it with the identity mapping
    if (len_trim(orderVarName) > 0) then
       call NcChk(nf90_inq_varid(ncid, trim(orderVarName), varid), rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       call NcChk(nf90_get_var(ncid, varid, reorderIndex), rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    else
       do n = 1, npts
          reorderIndex(n) = n - 1
       end do
    end if

    ! Close the NetCDF file
    call NcChk(nf90_close(ncid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine HydroReadReorderIndex

  !-----------------------------------------------------------------------------

  subroutine HydroReadVarMeta(dataFile, varName, xtype, ndims, scaleFactor, addOffset, &
       hasFillValue, fillValueRaw, rc)

    ! Reads a data variable's on-disk type/rank/packing metadata

    ! input/output variables
    character(len=*), intent(in) :: dataFile
    character(len=*), intent(in) :: varName
    integer, intent(out) :: xtype
    integer, intent(out) :: ndims
    real(ESMF_KIND_R8), intent(out) :: scaleFactor
    real(ESMF_KIND_R8), intent(out) :: addOffset
    logical, intent(out) :: hasFillValue
    real(ESMF_KIND_R8), intent(out) :: fillValueRaw
    integer, intent(out) :: rc

    ! local variables
    integer :: ncid, varid, statusAtt
    real(ESMF_KIND_R8) :: attValue
    character(len=*), parameter :: subname = trim(modName)//':(HydroReadVarMeta) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(varName)//' in '//trim(dataFile), ESMF_LOGMSG_INFO)

    ! Open the data file in read-only mode
    call NcChk(nf90_open(trim(dataFile), NF90_NOWRITE, ncid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Read the variable's metadata: on-disk type, rank, and packing attributes (scale_factor, add_offset, _FillValue/missing_value)
    call NcChk(nf90_inq_varid(ncid, trim(varName), varid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call NcChk(nf90_inquire_variable(ncid, varid, xtype=xtype, ndims=ndims), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Read the packing attributes, if they exist; otherwise, use default values
    scaleFactor = 1.0d0
    statusAtt = nf90_get_att(ncid, varid, "scale_factor", attValue)
    if (statusAtt == nf90_noerr) scaleFactor = attValue

    addOffset = 0.0d0
    statusAtt = nf90_get_att(ncid, varid, "add_offset", attValue)
    if (statusAtt == nf90_noerr) addOffset = attValue

    ! Read the fill value attribute, if it exists; otherwise, indicate that there is no fill value
    hasFillValue = .false.
    statusAtt = nf90_get_att(ncid, varid, "_FillValue", attValue)
    if (statusAtt /= nf90_noerr) statusAtt = nf90_get_att(ncid, varid, "missing_value", attValue)
    if (statusAtt == nf90_noerr) then
       hasFillValue = .true.
       fillValueRaw = attValue
    end if

    ! Close the NetCDF file    
    call NcChk(nf90_close(ncid), rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine HydroReadVarMeta

  !-----------------------------------------------------------------------------

  subroutine NcChk(status, rc)

    ! input/output variables
    integer, intent(in) :: status
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(NcChk) '
    !---------------------------------------------------------------------------

    ! Check the NetCDF status code and log an error if it indicates a failure; otherwise, set rc to success
    if (status /= nf90_noerr) then
       call ESMF_LogWrite(trim(subname)//': NetCDF error: '//trim(nf90_strerror(status)), ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
    else
       rc = ESMF_SUCCESS
    end if

  end subroutine NcChk

end module geogate_hydro_io
