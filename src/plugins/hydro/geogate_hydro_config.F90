module geogate_hydro_config

  !-----------------------------------------------------------------------------
  ! Reads the hydro plugin YAML configuration file using ESMF_HConfig.
  !
  ! NOTE: ESMF_HConfigAsString/AsLogical/GetSize/IsDefined/CreateAt are all
  ! FUNCTIONS (their result is the return value, not a "value=" argument),
  ! and their dummy argument names (hconfig, keyString, index, rc, ...) were
  ! cross-checked against the compiled esmf_hconfigmod.mod for ESMF 8.9.1
  ! (intel-oneapi-compilers/2025.2.1) on Derecho. If you build against a
  ! different ESMF release/compiler, re-check with e.g.:
  !   strings <path-to>/esmf_hconfigmod.mod | grep '^ESMF_HCONFIGASSTRING%'
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_HConfig, ESMF_HConfigCreate, ESMF_HConfigDestroy
  use ESMF, only: ESMF_HConfigCreateAt, ESMF_HConfigAsString, ESMF_HConfigGetSize
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE, ESMF_MAXSTR

  use geogate_share, only: ChkErr

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines and data structures
  !-----------------------------------------------------------------------------

  public :: HydroConfigRead

  private :: ReadStringSeq

  type, public :: HydroConfigType
     character(len=ESMF_MAXSTR) :: routeLinkFile = ""
     character(ESMF_MAXSTR), allocatable :: variableNames(:)
  end type HydroConfigType

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(*), parameter :: modName = "(geogate_hydro_config)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine HydroConfigRead(configFile, config, rc)

    ! input/output variables
    character(len=*), intent(in) :: configFile
    type(HydroConfigType), intent(inout) :: config
    integer, intent(out) :: rc

    ! local variables
    type(ESMF_HConfig) :: hconfig
    type(ESMF_HConfig) :: hconfigHydro
    character(len=*), parameter :: subname = trim(modName)//':(HydroConfigRead) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(configFile), ESMF_LOGMSG_INFO)

    ! Load the YAML document and descend into the top-level "hydro:" map.
    ! NOTE: ESMF_HConfigAsString/AsLogical/GetSize/IsDefined are all FUNCTIONS
    ! (not subroutines) that take the value/size/flag as their return value,
    ! not as a "value=" dummy argument -- confirmed against the installed
    ! esmf_hconfigmod.mod for this build (no VALUE argument exists for any of
    ! them).
    hconfig = ESMF_HConfigCreate(filename=trim(configFile), rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    hconfigHydro = ESMF_HConfigCreateAt(hconfig, keyString="hydro", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Required scalar entry
    config%routeLinkFile = trim(ESMF_HConfigAsString(hconfigHydro, keyString="route_link_file", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! List of field names to create on the hydro LocStream, e.g.:
    !   variables:
    !     - streamflow
    !     - velocity
    call ReadStringSeq(hconfigHydro, "variables", config%variableNames, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Clean up HConfig handles
    call ESMF_HConfigDestroy(hconfigHydro, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    call ESMF_HConfigDestroy(hconfig, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine HydroConfigRead

  !-----------------------------------------------------------------------------

  subroutine ReadStringSeq(hconfigParent, keyString, valueList, rc)

    ! Reads a YAML sequence of scalar strings under hconfigParent(keyString:)
    ! by descending into that sequence node and reading it element-by-element
    ! with index= (rather than ESMF_HConfigAsStringSeq, whose "stringLen"
    ! argument's optionality was not confirmed against this build -- this
    ! avoids that ambiguity entirely).

    ! input/output variables
    type(ESMF_HConfig), intent(in) :: hconfigParent
    character(len=*), intent(in) :: keyString
    character(ESMF_MAXSTR), allocatable, intent(inout) :: valueList(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: n, nitem
    character(ESMF_MAXSTR) :: message
    type(ESMF_HConfig) :: hconfigSeq
    character(len=*), parameter :: subname = trim(modName)//':(ReadStringSeq) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS

    hconfigSeq = ESMF_HConfigCreateAt(hconfigParent, keyString=trim(keyString), rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    nitem = ESMF_HConfigGetSize(hconfigSeq, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    if (nitem <= 0) then
       call ESMF_LogWrite(trim(subname)//": ERROR at least one entry is required under '"// &
          trim(keyString)//":'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    allocate(valueList(nitem))
    do n = 1, nitem
       valueList(n) = trim(ESMF_HConfigAsString(hconfigSeq, index=n, rc=rc))
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       write(message, fmt='(A,I3,A)') trim(subname)//': '//trim(keyString)//'(', n, ') = '//trim(valueList(n))
       call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
    end do

    call ESMF_HConfigDestroy(hconfigSeq, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

  end subroutine ReadStringSeq

end module geogate_hydro_config
