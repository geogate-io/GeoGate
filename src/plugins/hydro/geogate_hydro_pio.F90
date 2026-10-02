module geogate_hydro_pio

  !-----------------------------------------------------------------------------
  ! Parallel (PIO-based), decomposed NetCDF reads: each PET fetches only the
  ! on-disk positions it owns via PIO_initdecomp + a "compdof" array.
  !-----------------------------------------------------------------------------

  use netcdf, only: NF90_INT, NF90_FLOAT, NF90_DOUBLE

  use pio, only: iosystem_desc_t, file_desc_t, io_desc_t, var_desc_t
  use pio, only: PIO_init, PIO_finalize
  use pio, only: PIO_openfile, PIO_closefile
  use pio, only: PIO_initdecomp, PIO_freedecomp
  use pio, only: PIO_inq_varid, PIO_setframe
  use pio, only: PIO_read_darray
  use pio, only: PIO_real, PIO_int, PIO_double, PIO_iotype_netcdf, PIO_rearr_subset
  use pio, only: PIO_noerr, PIO_offset_kind

  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE, ESMF_KIND_R8

  use geogate_share, only: ChkErr

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: PioReadCoords
  public :: PioReadVariable

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(*), parameter :: modName = "(geogate_hydro_pio)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine PioReadCoords(coordFile, mpiComm, myPet, npts, compdof, &
       idVarName, latVarName, lonVarName, lat, lon, pointId, rc)

    ! input/output variables
    character(len=*), intent(in) :: coordFile
    integer, intent(in) :: mpiComm
    integer, intent(in) :: myPet
    integer, intent(in) :: npts
    integer, intent(in) :: compdof(:)
    character(len=*), intent(in) :: idVarName
    character(len=*), intent(in) :: latVarName
    character(len=*), intent(in) :: lonVarName
    real(ESMF_KIND_R8), allocatable, intent(out) :: lat(:)
    real(ESMF_KIND_R8), allocatable, intent(out) :: lon(:)
    integer, allocatable, intent(out) :: pointId(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: ierr
    integer :: localCount
    real(kind=4), allocatable :: latLocal_r4(:), lonLocal_r4(:)
    type(iosystem_desc_t) :: iosystem
    type(file_desc_t) :: pioFile
    type(io_desc_t) :: iodescReal
    type(io_desc_t) :: iodescInt
    type(var_desc_t) :: latVardesc, lonVardesc, idVardesc
    character(len=*), parameter :: subname = trim(modName)//':(PioReadCoords) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(coordFile), ESMF_LOGMSG_INFO)

    ! Allocate local buffers for the decomposed read of lat/lon/pointId.
    localCount = size(compdof)
    allocate(latLocal_r4(localCount), lonLocal_r4(localCount))
    allocate(lat(localCount), lon(localCount), pointId(localCount))

    ! Initialize PIO
    call PIO_init(comp_rank=myPet, comp_comm=mpiComm, num_iotasks=1, num_aggregator=0, &
       stride=1, rearr=PIO_rearr_subset, iosystem=iosystem)

    ! Open the coordinate file and inquire the variable IDs for lat/lon/pointId.
    ierr = PIO_openfile(iosystem, pioFile, PIO_iotype_netcdf, trim(coordFile))
    if (PioChk(ierr, 'PIO_openfile for '//trim(coordFile), rc)) return

    ierr = PIO_inq_varid(pioFile, trim(latVarName), latVardesc)
    if (PioChk(ierr, 'PIO_inq_varid for '//trim(latVarName), rc)) return

    ierr = PIO_inq_varid(pioFile, trim(lonVarName), lonVardesc)
    if (PioChk(ierr, 'PIO_inq_varid for '//trim(lonVarName), rc)) return

    ierr = PIO_inq_varid(pioFile, trim(idVarName), idVardesc)
    if (PioChk(ierr, 'PIO_inq_varid for '//trim(idVarName), rc)) return

    ! Initialize the decompositions for the lat/lon/pointId reads, then read the data into local buffers.
    call PIO_initdecomp(iosystem, PIO_real, (/ npts /), compdof, iodescReal)
    call PIO_initdecomp(iosystem, PIO_int, (/ npts /), compdof, iodescInt)

    call PIO_read_darray(pioFile, latVardesc, iodescReal, latLocal_r4, ierr)
    if (PioChk(ierr, 'PIO_read_darray for '//trim(latVarName), rc)) return

    call PIO_read_darray(pioFile, lonVardesc, iodescReal, lonLocal_r4, ierr)
    if (PioChk(ierr, 'PIO_read_darray for '//trim(lonVarName), rc)) return

    call PIO_read_darray(pioFile, idVardesc, iodescInt, pointId, ierr)
    if (PioChk(ierr, 'PIO_read_darray for '//trim(idVarName), rc)) return

    ! Convert the local lat/lon buffers from real*4 to real*8 for the output arrays.
    lat(:) = real(latLocal_r4(:), ESMF_KIND_R8)
    lon(:) = real(lonLocal_r4(:), ESMF_KIND_R8)

    ! Free the PIO decompositions
    call PIO_freedecomp(iosystem, iodescReal)
    call PIO_freedecomp(iosystem, iodescInt)

    ! Close the PIO file
    call PIO_closefile(pioFile)

    ! Finalize PIO
    call PIO_finalize(iosystem, ierr)

    ! Clean memory
    deallocate(latLocal_r4, lonLocal_r4)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine PioReadCoords

  !-----------------------------------------------------------------------------

  subroutine PioReadVariable(dataFile, mpiComm, myPet, npts, compdof, varName, &
       xtype, ndims, frameIndex, values, rc)

    ! Decomposed read of one data variable, raw/unpacked real*8 regardless
    ! of on-disk type. See docs/source/hydro.rst: Data Ingest for frameIndex/
    ! ndims and the xtype dispatch below.

    ! input/output variables
    character(len=*), intent(in) :: dataFile
    integer, intent(in) :: mpiComm
    integer, intent(in) :: myPet
    integer, intent(in) :: npts
    integer, intent(in) :: compdof(:)
    character(len=*), intent(in) :: varName
    integer, intent(in) :: xtype
    integer, intent(in) :: ndims
    integer, intent(in) :: frameIndex
    real(ESMF_KIND_R8), allocatable, intent(out) :: values(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: ierr
    integer :: localCount
    integer(kind=PIO_offset_kind) :: frame
    integer, allocatable :: intBuf(:)
    real(kind=4), allocatable :: r4Buf(:)
    real(kind=8), allocatable :: r8Buf(:)
    type(iosystem_desc_t) :: iosystem
    type(file_desc_t) :: pioFile
    type(io_desc_t) :: iodesc
    type(var_desc_t) :: varDesc
    character(len=*), parameter :: subname = trim(modName)//':(PioReadVariable) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(varName)//' in '//trim(dataFile), ESMF_LOGMSG_INFO)

    ! Allocate the output array for the decomposed read of the variable
    localCount = size(compdof)
    allocate(values(localCount))

    ! Initialize PIO
    call PIO_init(comp_rank=myPet, comp_comm=mpiComm, num_iotasks=1, num_aggregator=0, &
       stride=1, rearr=PIO_rearr_subset, iosystem=iosystem)

    ! Open the data file and inquire the variable ID for the requested variable
    ierr = PIO_openfile(iosystem, pioFile, PIO_iotype_netcdf, trim(dataFile))
    if (PioChk(ierr, 'PIO_openfile for '//trim(dataFile), rc)) return

    ierr = PIO_inq_varid(pioFile, trim(varName), varDesc)
    if (PioChk(ierr, 'PIO_inq_varid for '//trim(varName), rc)) return

    ! If the variable has more than one dimension, set the frame index for the read
    if (ndims > 1) then
       frame = int(frameIndex, kind(frame))
       call PIO_setframe(pioFile, varDesc, frame)
    end if

    ! Read the variable data into a local buffer based on its on-disk type, then convert to real*8 for the output array
    select case (xtype)
    case (NF90_INT)
       ! Allocate a local integer buffer for the decomposed read of the variable
       allocate(intBuf(localCount))

       ! Initialize the PIO decomposition for the integer read, then read the data into the local buffer
       call PIO_initdecomp(iosystem, PIO_int, (/ npts /), compdof, iodesc)
       call PIO_read_darray(pioFile, varDesc, iodesc, intBuf, ierr)
       if (PioChk(ierr, 'PIO_read_darray for '//trim(varName), rc)) return

       ! Convert the local integer buffer to real*8 for the output array
       values(:) = real(intBuf(:), ESMF_KIND_R8)

       ! Clean up the local integer buffer
       deallocate(intBuf)
    case (NF90_FLOAT)
       ! Allocate a local real*4 buffer for the decomposed read of the variable
       allocate(r4Buf(localCount))

       ! Initialize the PIO decomposition for the real*4 read, then read the data into the local buffer
       call PIO_initdecomp(iosystem, PIO_real, (/ npts /), compdof, iodesc)
       call PIO_read_darray(pioFile, varDesc, iodesc, r4Buf, ierr)
       if (PioChk(ierr, 'PIO_read_darray for '//trim(varName), rc)) return

       ! Convert the local real*4 buffer to real*8 for the output array
       values(:) = real(r4Buf(:), ESMF_KIND_R8)

       ! Clean up the local real*4 buffer
       deallocate(r4Buf)
    case (NF90_DOUBLE)
       ! Allocate a local real*8 buffer for the decomposed read of the variable
       allocate(r8Buf(localCount))
       
       ! Initialize the PIO decomposition for the real*8 read, then read the data into the local buffer
       call PIO_initdecomp(iosystem, PIO_double, (/ npts /), compdof, iodesc)
       call PIO_read_darray(pioFile, varDesc, iodesc, r8Buf, ierr)
       if (PioChk(ierr, 'PIO_read_darray for '//trim(varName), rc)) return

       ! Copy the local real*8 buffer to the output array
       values(:) = r8Buf(:)

       ! Clean up the local real*8 buffer
       deallocate(r8Buf)
    case default
       ! Unsupported on-disk type for the variable; log an error and return failure
       call ESMF_LogWrite(trim(subname)//': ERROR unsupported on-disk type for '//trim(varName)// &
          ' (only NF90_INT, NF90_FLOAT, NF90_DOUBLE are supported)', ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end select

    ! Free the PIO decomposition
    call PIO_freedecomp(iosystem, iodesc)

    ! Close the PIO file
    call PIO_closefile(pioFile)

    ! Finalize PIO
    call PIO_finalize(iosystem, ierr)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine PioReadVariable

  !-----------------------------------------------------------------------------

  logical function PioChk(ierr, msg, rc)

    ! input/output variables
    integer, intent(in) :: ierr
    character(len=*), intent(in) :: msg
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(PioChk) '
    !---------------------------------------------------------------------------

    ! Check the PIO error code and log an error message if it indicates failure. Return a logical flag indicating whether an error occurred.
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
