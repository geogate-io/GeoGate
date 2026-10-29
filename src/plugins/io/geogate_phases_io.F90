module geogate_phases_io

  !-----------------------------------------------------------------------------
  ! Write imported fields: ESMF_FieldWriteVTK for Mesh/Grid-based fields
  ! (FBWriteVTK), a plain per-PET CSV writer for LocStream-based fields
  ! (FBWriteCSV, since ESMF_FieldWriteVTK does not support LocStream).
  !-----------------------------------------------------------------------------

  use ESMF, only: operator(==)
  use ESMF, only: ESMF_GridComp, ESMF_GridCompGet, ESMF_GridCompGetInternalState
  use ESMF, only: ESMF_VM, ESMF_VMGet
  use ESMF, only: ESMF_Time, ESMF_TimeGet
  use ESMF, only: ESMF_Clock, ESMF_ClockGet
  use ESMF, only: ESMF_LogFoundError, ESMF_FAILURE, ESMF_LogWrite
  use ESMF, only: ESMF_LOGERR_PASSTHRU, ESMF_LOGMSG_INFO, ESMF_SUCCESS
  use ESMF, only: ESMF_Field, ESMF_FieldGet, ESMF_FieldWrite, ESMF_FieldWriteVTK
  use ESMF, only: ESMF_FieldBundle, ESMF_FieldBundleGet
  use ESMF, only: ESMF_LocStream
  use ESMF, only: ESMF_MAXSTR, ESMF_KIND_R8
  use ESMF, only: ESMF_GeomType_Flag
  use ESMF, only: ESMF_GEOMTYPE_GRID, ESMF_GEOMTYPE_MESH, ESMF_GEOMTYPE_LOCSTREAM
  use ESMF, only: ESMF_LocStreamGetBounds, ESMF_LocStreamGetKey

  use NUOPC_Model, only: NUOPC_ModelGet

  use geogate_share, only: ChkErr
  use geogate_internalstate, only: InternalState

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: geogate_phases_io_init
  public :: geogate_phases_io_run
  public :: geogate_phases_io_final

  !-----------------------------------------------------------------------------
  ! Private module routines
  !-----------------------------------------------------------------------------

  private :: FBWriteVTK
  private :: FBWriteCSV

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  ! Wraps a pointer so an array of them can each independently reference one
  ! field's own memory -- see FBWriteCSV
  type :: IOFieldPtr
     real(ESMF_KIND_R8), pointer :: p(:) => null()
  end type IOFieldPtr

  integer :: dbug = 0
  character(len=*), parameter :: modName = "(geogate_phases_io)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine geogate_phases_io_init(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_io_init) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)
    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_io_init

  !-----------------------------------------------------------------------------

  subroutine geogate_phases_io_run(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    integer :: fieldCount
    integer :: myPet
    type(ESMF_VM) :: vm
    type(InternalState) :: is_local
    type(ESMF_Time) :: currTime
    type(ESMF_Clock) :: clock
    type(ESMF_Field) :: field
    type(ESMF_GeomType_Flag) :: geomtype
    character(ESMF_MAXSTR), allocatable :: fieldNameList(:)
    character(len=ESMF_MAXSTR) :: timeStr
    character(len=ESMF_MAXSTR) :: prefix
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_io_run) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Get internal state
    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query this PET's number (needed by FBWriteCSV; ESMF_FieldWriteVTK
    ! handles per-PET decomposition internally so FBWriteVTK doesn't need it)
    call ESMF_GridCompGet(gcomp, vm=vm, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_VMGet(vm, localPet=myPet, rc=rc)
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
       ! Query number of fields in this FB
       call ESMF_FieldBundleGet(is_local%wrap%FBImp(n), fieldCount=fieldCount, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Skip empty FBs (e.g., if a component has no fields to import at this time)
       if (fieldCount == 0) cycle
       allocate(fieldNameList(fieldCount))

       ! Determine this FB's geomtype from its first field
       call ESMF_FieldBundleGet(is_local%wrap%FBImp(n), fieldNameList=fieldNameList, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Query first field in the FB to determine geomtype
       call ESMF_FieldBundleGet(is_local%wrap%FBImp(n), fieldName=trim(fieldNameList(1)), field=field, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Query geomtype of the field
       call ESMF_FieldGet(field, geomtype=geomtype, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Write the FB to disk, using either VTK or CSV depending on geomtype
       prefix = trim(is_local%wrap%compName(n))//'_import_'//trim(timeStr)
       if (geomtype == ESMF_GEOMTYPE_LOCSTREAM) then
          call FBWriteCSV(is_local%wrap%FBImp(n), trim(prefix), myPet, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
       else
          call FBWriteVTK(is_local%wrap%FBImp(n), trim(prefix), rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
       end if

       ! Clean memory
       deallocate(fieldNameList)
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_io_run

  !-----------------------------------------------------------------------------

  subroutine geogate_phases_io_final(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_io_final) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)
    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_io_final

  !-----------------------------------------------------------------------------

  subroutine FBWriteVTK(FBin, prefix, rc)

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
    character(len=*), parameter :: subname = trim(modName)//':(FBWriteVTK) '
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

  end subroutine FBWriteVTK

  !-----------------------------------------------------------------------------

  subroutine FBWriteCSV(FBin, prefix, myPet, rc)

    ! Writes a LocStream-based FieldBundle to a plain per-PET CSV file
    ! (lat,lon,<field1>,<field2>,...), since ESMF_FieldWriteVTK does not
    ! support LocStream. All fields in FBin are assumed to share the same
    ! LocStream (see geogate_share.F90's FB_init_pointer).

    ! input/output variables
    type(ESMF_FieldBundle) :: FBin
    character(len=*), intent(in) :: prefix
    integer, intent(in) :: myPet
    integer, intent(out), optional :: rc

    ! local variables
    integer :: n, m, iounit
    integer :: fieldCount, localCount
    type(ESMF_Field) :: field
    type(ESMF_LocStream) :: locstream
    type(IOFieldPtr), allocatable :: fieldData(:)
    real(ESMF_KIND_R8), pointer :: lat(:), lon(:)
    character(ESMF_MAXSTR) :: msg
    character(ESMF_MAXSTR) :: dumpFile
    character(ESMF_MAXSTR) :: header
    character(ESMF_MAXSTR) :: lineBuf
    character(32) :: fieldStr
    character(ESMF_MAXSTR), allocatable :: fieldNameList(:)
    character(len=*), parameter :: subname = trim(modName)//':(FBWriteCSV) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Query number of item in the FB
    call ESMF_FieldBundleGet(FBin, fieldCount=fieldCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Debug information
    write(msg, fmt='(A,I8)') subname//' number of fields in FB ', fieldCount
    call ESMF_LogWrite(trim(msg), ESMF_LOGMSG_INFO)

    ! Query field names in the FB
    allocate(fieldNameList(fieldCount))
    call ESMF_FieldBundleGet(FBin, fieldNameList=fieldNameList, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query LocStream, from the first field
    call ESMF_FieldBundleGet(FBin, fieldName=trim(fieldNameList(1)), field=field, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_FieldGet(field, locstream=locstream, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query number of local elements in the LocStream
    call ESMF_LocStreamGetBounds(locstream, localDe=0, exclusiveCount=localCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Extract lat/lon arrays from the LocStream
    nullify(lat, lon)
    call ESMF_LocStreamGetKey(locstream, keyName="ESMF:Lat", farray=lat, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_LocStreamGetKey(locstream, keyName="ESMF:Lon", farray=lon, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Loop over fields in the FB, extracting their data arrays into fieldData
    allocate(fieldData(fieldCount))
    do n = 1, fieldCount
       ! Debug information
       call ESMF_LogWrite(subname//' writing '//trim(fieldNameList(n)), ESMF_LOGMSG_INFO)

       ! Query field
       call ESMF_FieldBundleGet(FBin, fieldName=trim(fieldNameList(n)), field=field, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

        ! Extract field data array into fieldData(n)%p
       call ESMF_FieldGet(field, farrayptr=fieldData(n)%p, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end do

    ! Create filename for this PET's CSV dump file, e.g., "atm_import_2023-01-01T00:00:00.000_PET0001.csv"
    write(dumpFile, fmt='(A,I4.4,A)') trim(prefix)//'_PET', myPet, '.csv'

    ! Write CSV file
    header = 'lat,lon'
    do n = 1, fieldCount
       header = trim(header)//','//trim(fieldNameList(n))
    end do

    open(newunit=iounit, file=trim(dumpFile), status='replace', action='write')
    write(iounit, '(A)') trim(header)
    do m = 1, localCount
       write(fieldStr, fmt='(F0.6)') lat(m)
       lineBuf = trim(fieldStr)
       write(fieldStr, fmt='(F0.6)') lon(m)
       lineBuf = trim(lineBuf)//','//trim(fieldStr)
       do n = 1, fieldCount
          write(fieldStr, fmt='(F0.6)') fieldData(n)%p(m)
          lineBuf = trim(lineBuf)//','//trim(fieldStr)
       end do
       write(iounit, '(A)') trim(lineBuf)
    end do
    close(iounit)

    ! Clean memory
    deallocate(fieldNameList)
    deallocate(fieldData)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine FBWriteCSV

end module geogate_phases_io
