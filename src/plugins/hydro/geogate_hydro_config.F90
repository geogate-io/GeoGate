module geogate_hydro_config

  !-----------------------------------------------------------------------------
  ! Reads the hydro plugin YAML configuration file using ESMF_HConfig.
  ! See docs/source/hydro.rst for the config file format and notes on the
  ! ESMF_HConfig API used here.
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_HConfig, ESMF_HConfigCreate, ESMF_HConfigDestroy
  use ESMF, only: ESMF_HConfigCreateAt, ESMF_HConfigAsString, ESMF_HConfigGetSize
  use ESMF, only: ESMF_HConfigIsDefined
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
     character(len=ESMF_MAXSTR) :: coordFile = ""
     character(len=ESMF_MAXSTR) :: idVarName = ""
     character(len=ESMF_MAXSTR) :: latVarName = ""
     character(len=ESMF_MAXSTR) :: lonVarName = ""
     character(len=ESMF_MAXSTR) :: orderVarName = ""   ! optional; blank => use on-disk order as-is
     character(ESMF_MAXSTR), allocatable :: dataFiles(:)
     character(len=ESMF_MAXSTR) :: timeVarName = ""
     character(len=ESMF_MAXSTR) :: timeSelection = "nearest"   ! "nearest" | "lower" | "upper" | "linear" (not yet implemented)
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
    logical :: isDefined
    character(ESMF_MAXSTR) :: cvalue
    type(ESMF_HConfig) :: hconfig
    type(ESMF_HConfig) :: hconfigHydro
    character(len=*), parameter :: subname = trim(modName)//':(HydroConfigRead) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(configFile), ESMF_LOGMSG_INFO)

    ! Load the YAML document and descend into the top-level "hydro:" map
    hconfig = ESMF_HConfigCreate(filename=trim(configFile), rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    hconfigHydro = ESMF_HConfigCreateAt(hconfig, keyString="hydro", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Required scalar entries
    config%coordFile = trim(ESMF_HConfigAsString(hconfigHydro, keyString="coord_file", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    config%idVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="id_variable", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    config%latVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="lat_variable", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    config%lonVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="lon_variable", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Optional (see docs/source/hydro.rst: Runtime Configuration Options)
    isDefined = ESMF_HConfigIsDefined(hconfigHydro, keyString="order_variable", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    if (isDefined) then
       config%orderVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="order_variable", rc=rc))
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end if

    call ReadStringSeq(hconfigHydro, "data_files", config%dataFiles, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Name of the time coordinate variable in each data file
    config%timeVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="time_variable", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Optional (see docs/source/hydro.rst: Runtime Configuration Options)
    isDefined = ESMF_HConfigIsDefined(hconfigHydro, keyString="time_selection", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    if (isDefined) then
       config%timeSelection = trim(ESMF_HConfigAsString(hconfigHydro, keyString="time_selection", rc=rc))
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end if

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

    ! Reads a YAML sequence of scalar strings under hconfigParent(keyString:),
    ! element-by-element (see docs/source/hydro.rst for why not AsStringSeq)

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
