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

  use geogate_share, only: ChkErr, StringSplit

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines and data structures
  !-----------------------------------------------------------------------------

  public :: HydroConfigRead

  private :: ReadStringSeq
  private :: ParseExportNames

  type, public :: HydroConfigType
     character(len=ESMF_MAXSTR) :: coordFile = ""
     character(len=ESMF_MAXSTR) :: idVarName = ""
     character(len=ESMF_MAXSTR) :: latVarName = ""
     character(len=ESMF_MAXSTR) :: lonVarName = ""
     character(len=ESMF_MAXSTR) :: orderVarName = ""
     character(ESMF_MAXSTR), allocatable :: dataFiles(:)
     character(len=ESMF_MAXSTR) :: timeVarName = ""
     character(len=ESMF_MAXSTR) :: timeSelection = "nearest"
     character(ESMF_MAXSTR), allocatable :: variableNames(:)
     character(ESMF_MAXSTR), allocatable :: exportVarNames(:)
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

    ! Load plugin configuration from the YAML file into an ESMF_HConfig handle
    hconfig = ESMF_HConfigCreate(filename=trim(configFile), rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Create a sub-handle for the "hydro:" section of the config file
    hconfigHydro = ESMF_HConfigCreateAt(hconfig, keyString="hydro", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Read the required configuration values from the "hydro:" section of the config file
    config%coordFile = trim(ESMF_HConfigAsString(hconfigHydro, keyString="coord_file", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    config%idVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="id_variable", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    config%latVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="lat_variable", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    config%lonVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="lon_variable", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Read optional configuration values
    isDefined = ESMF_HConfigIsDefined(hconfigHydro, keyString="order_variable", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    if (isDefined) then
       config%orderVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="order_variable", rc=rc))
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end if

    ! Query the list of data files to read
    call ReadStringSeq(hconfigHydro, "data_files", config%dataFiles, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Name of the time coordinate variable in each data file
    config%timeVarName = trim(ESMF_HConfigAsString(hconfigHydro, keyString="time_variable", rc=rc))
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Optional time selection method for each data file (default is "nearest")
    isDefined = ESMF_HConfigIsDefined(hconfigHydro, keyString="time_selection", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    if (isDefined) then
       config%timeSelection = trim(ESMF_HConfigAsString(hconfigHydro, keyString="time_selection", rc=rc))
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
    end if

    ! Query the list of variable names to read from each data file
    call ReadStringSeq(hconfigHydro, "variables", config%variableNames, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Each "variables" entry may optionally map a data-file variable name to
    ! a different export-state field name as "dataVarName:exportName" (the
    ! coupled system's own field naming convention, from its field
    ! dictionary, does not always match the data file's variable names). A
    ! bare name (no colon) exports under that same name.
    call ParseExportNames(config%variableNames, config%exportVarNames, rc)
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
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Create a sub-handle for the sequence of strings under hconfigParent(keyString:)
    hconfigSeq = ESMF_HConfigCreateAt(hconfigParent, keyString=trim(keyString), rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Query the number of items in the sequence
    nitem = ESMF_HConfigGetSize(hconfigSeq, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Check that at least one item was found
    if (nitem <= 0) then
       call ESMF_LogWrite(trim(subname)//": ERROR at least one entry is required under '"// &
          trim(keyString)//":'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Allocate the output array
    allocate(valueList(nitem))

    ! Loop over the sequence items and read each one as a string
    do n = 1, nitem
       ! Read the nth item in the sequence as a string
       valueList(n) = trim(ESMF_HConfigAsString(hconfigSeq, index=n, rc=rc))
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Log the value read for debugging purposes
       write(message, fmt='(A,I3,A)') trim(subname)//': '//trim(keyString)//'(', n, ') = '//trim(valueList(n))
       call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
    end do

    ! Clean up the sequence sub-handle
    call ESMF_HConfigDestroy(hconfigSeq, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ReadStringSeq

  !-----------------------------------------------------------------------------

  subroutine ParseExportNames(variableNames, exportVarNames, rc)

    ! Splits each variableNames(n) on ':' into (data variable name, export
    ! name); a bare name (no colon) exports under that same name. Rewrites
    ! variableNames(n) in place to just the data-variable part.

    ! input/output variables
    character(ESMF_MAXSTR), intent(inout) :: variableNames(:)
    character(ESMF_MAXSTR), allocatable, intent(out) :: exportVarNames(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: n
    character(len=:), allocatable :: parts(:)
    character(len=*), parameter :: subname = trim(modName)//':(ParseExportNames) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Allocate the exportVarNames array to hold the export names corresponding to each variable name
    allocate(exportVarNames(size(variableNames)))

    ! Loop over each variable name and split it on ':' to determine the data variable name and export name
    do n = 1, size(variableNames)
       ! Split variableNames(n) on ':' into parts
       parts = StringSplit(trim(variableNames(n)), ":")

       ! Determine the export name based on the number of parts obtained from the split
       if (size(parts, dim=1) == 1) then
          exportVarNames(n) = trim(variableNames(n))
          call ESMF_LogWrite(trim(subname)//": no export name given for variable '"// &
             trim(variableNames(n))//"' -- using the same name for export", ESMF_LOGMSG_INFO)
       else if (size(parts, dim=1) == 2) then
          variableNames(n) = trim(parts(1))
          exportVarNames(n) = trim(parts(2))
       else
          call ESMF_LogWrite(trim(subname)//": ERROR malformed 'variables' entry '"// &
             trim(variableNames(n))//"' -- expected 'dataVarName' or 'dataVarName:exportName'", &
             ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ParseExportNames

end module geogate_hydro_config
