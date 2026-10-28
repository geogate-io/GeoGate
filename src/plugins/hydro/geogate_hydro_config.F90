module geogate_hydro_config

  !-----------------------------------------------------------------------------
  ! Reads the hydro plugin YAML configuration file using ESMF_HConfig.
  ! See docs/source/hydro.rst for the config file format and notes on the
  ! ESMF_HConfig API used here.
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_HConfig, ESMF_HConfigCreate, ESMF_HConfigDestroy
  use ESMF, only: ESMF_HConfigCreateAt, ESMF_HConfigAsString, ESMF_HConfigAsI4, ESMF_HConfigGetSize
  use ESMF, only: ESMF_HConfigIsDefined
  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR
  use ESMF, only: ESMF_SUCCESS, ESMF_FAILURE, ESMF_MAXSTR, ESMF_KIND_R8

  use geogate_share, only: ChkErr, StringSplit

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines and data structures
  !-----------------------------------------------------------------------------

  public :: HydroConfigRead

  private :: ReadStringSeq
  private :: ReadIntSeq
  private :: ParseExportNames
  private :: ReadExportSelection
  private :: ReadIntListFile
  private :: ReadElementMapFile
  private :: CheckNoDuplicates
  private :: CheckNoDuplicatePairs
  private :: CheckWeightSums

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
     ! Export selection (optional; see docs/source/hydro.rst: Export Side).
     ! At most one of exportIds / exportElementMapIds is ever populated:
     !   neither populated       -> export every point (today's behavior)
     !   exportIds populated     -> export only this subset of flow ids
     !   exportElementMapIds/
     !   exportElementMapElements/exportElementMapWeights populated ->
     !     export onto an external mesh. The mapping is many-to-many: the
     !     same element may appear more than once (its contributors' values
     !     are summed), and the same flow id may appear more than once
     !     (e.g. split across several elements via exportElementMapWeights,
     !     which multiplies each entry's value before summing -- defaults
     !     to 1.0 when the map file gives no weight column). Every element
     !     with no matching entry is left at the fill sentinel.
     integer, allocatable :: exportIds(:)
     integer, allocatable :: exportElementMapIds(:)
     integer, allocatable :: exportElementMapElements(:)
     real(ESMF_KIND_R8), allocatable :: exportElementMapWeights(:)
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

    ! Optional export selection: export_ids/export_ids_file (subset of flow
    ! ids) or export_element_map_file (flow id -> ocean element map); none
    ! given -> today's export-everything behavior (see docs/source/hydro.rst)
    call ReadExportSelection(hconfigHydro, config, rc)
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

  subroutine ReadIntSeq(hconfigParent, keyString, valueList, rc)

    ! Reads a YAML sequence of scalar integers under hconfigParent(keyString:),
    ! element-by-element (same approach as ReadStringSeq, for an integer list)

    ! input/output variables
    type(ESMF_HConfig), intent(in) :: hconfigParent
    character(len=*), intent(in) :: keyString
    integer, allocatable, intent(inout) :: valueList(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: n, nitem
    integer :: rcSave
    character(ESMF_MAXSTR) :: message
    type(ESMF_HConfig) :: hconfigSeq
    character(len=*), parameter :: subname = trim(modName)//':(ReadIntSeq) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Create a sub-handle for the sequence of integers under hconfigParent(keyString:)
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

    ! Allocate the output array for the integer values
    allocate(valueList(nitem))

    ! Loop over the sequence items and read each one as an integer
    do n = 1, nitem
       ! Read the nth item in the sequence as an integer
       valueList(n) = ESMF_HConfigAsI4(hconfigSeq, index=n, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) exit

       ! Log the value read for debugging purposes
       write(message, fmt='(A,I3,A,I0)') trim(subname)//': '//trim(keyString)//'(', n, ') = ', valueList(n)
       call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
    end do

    ! Clean up the sequence sub-handle (on every exit path, including an
    ! ESMF_HConfigAsI4 failure above) -- the destroy's own rc is only
    ! allowed to override the loop's rc when the loop itself succeeded, so
    ! an original AsI4 failure is never masked by a successful destroy
    rcSave = rc
    call ESMF_HConfigDestroy(hconfigSeq, rc=rc)
    if (rcSave /= ESMF_SUCCESS) then
       rc = rcSave
       return
    end if
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ReadIntSeq

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

  !-----------------------------------------------------------------------------

  subroutine ReadExportSelection(hconfigHydro, config, rc)

    ! Reads the optional export selection: export_ids/export_ids_file (a
    ! subset of flow ids) or export_element_map_file (flow id -> ocean
    ! element map) -- at most one of the two mechanisms may be given;
    ! none given leaves config%exportIds/exportElementMap* unallocated
    ! (case 1, export everything, today's behavior).

    ! input/output variables
    type(ESMF_HConfig), intent(in) :: hconfigHydro
    type(HydroConfigType), intent(inout) :: config
    integer, intent(out) :: rc

    ! local variables
    logical :: hasIds, hasIdsFile, hasMapFile
    character(ESMF_MAXSTR) :: idsFile, mapFile
    character(len=*), parameter :: subname = trim(modName)//':(ReadExportSelection) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Check which export selection keys are defined in the configuration
    hasIds = ESMF_HConfigIsDefined(hconfigHydro, keyString="export_ids", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    hasIdsFile = ESMF_HConfigIsDefined(hconfigHydro, keyString="export_ids_file", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    
    hasMapFile = ESMF_HConfigIsDefined(hconfigHydro, keyString="export_element_map_file", rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Check for mutually exclusive export selection options
    if (hasIds .and. hasIdsFile) then
       call ESMF_LogWrite(trim(subname)//": ERROR give at most one of 'export_ids'/'export_ids_file'", &
          ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Check for mutually exclusive export selection options
    if ((hasIds .or. hasIdsFile) .and. hasMapFile) then
       call ESMF_LogWrite(trim(subname)//": ERROR 'export_ids'/'export_ids_file' and "// &
          "'export_element_map_file' are mutually exclusive", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Read the export selection based on which option is defined in the configuration
    if (hasIds) then
       ! Read the export_ids sequence directly from the configuration
       call ReadIntSeq(hconfigHydro, "export_ids", config%exportIds, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Check for duplicate export IDs in the export_ids sequence
       call CheckNoDuplicates(config%exportIds, "export_ids", rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

    else if (hasIdsFile) then
       ! Read the export_ids from the specified file
       idsFile = trim(ESMF_HConfigAsString(hconfigHydro, keyString="export_ids_file", rc=rc))
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Read the integer list from the file and populate config%exportIds
       call ReadIntListFile(idsFile, config%exportIds, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Check for duplicate export IDs in the export_ids_file
       call CheckNoDuplicates(config%exportIds, "export_ids_file", rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

    else if (hasMapFile) then
       ! Read the export_element_map_file and populate config%exportElementMapIds,
       ! config%exportElementMapElements, and config%exportElementMapWeights
       mapFile = trim(ESMF_HConfigAsString(hconfigHydro, keyString="export_element_map_file", rc=rc))
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Read the element map file and populate the corresponding arrays in the config
       call ReadElementMapFile(mapFile, config%exportElementMapIds, config%exportElementMapElements, &
          config%exportElementMapWeights, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! The mapping is many-to-many (see HydroConfigType), so neither
       ! column is checked for duplicates on its own -- only an exact
       ! repeated (flow_id, element) pair indicates a real mistake
       call CheckNoDuplicatePairs(config%exportElementMapIds, config%exportElementMapElements, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! A flow id split across multiple elements must not be over-allocated
       call CheckWeightSums(config%exportElementMapIds, config%exportElementMapWeights, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

    else
       call ESMF_LogWrite(trim(subname)//": no export selection given -- exporting every point (default)", &
          ESMF_LOGMSG_INFO)
    end if

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ReadExportSelection

  !-----------------------------------------------------------------------------

  subroutine ReadIntListFile(filename, values, rc)

    ! Reads a plain-text file of one integer per line (blank lines and
    ! '#'-prefixed comment lines are skipped) -- used for export_ids_file

    ! input/output variables
    character(len=*), intent(in) :: filename
    integer, allocatable, intent(out) :: values(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: iounit, ios, n, nitem
    character(ESMF_MAXSTR) :: line
    character(len=*), parameter :: subname = trim(modName)//':(ReadIntListFile) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(filename), ESMF_LOGMSG_INFO)

    ! Open the specified file for reading, using a new unit number
    open(newunit=iounit, file=trim(filename), status='old', action='read', iostat=ios)
    if (ios /= 0) then
       call ESMF_LogWrite(trim(subname)//": ERROR could not open '"//trim(filename)//"'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Count the number of valid integer entries in the file (skipping blank lines and comments)
    nitem = 0
    do
       read(iounit, '(A)', iostat=ios) line
       if (ios /= 0) exit
       line = adjustl(line)
       if (len_trim(line) == 0 .or. line(1:1) == '#') cycle
       nitem = nitem + 1
    end do

    ! Check that at least one valid entry was found in the file
    if (nitem <= 0) then
       call ESMF_LogWrite(trim(subname)//": ERROR no entries found in '"//trim(filename)//"'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       close(iounit)
       return
    end if

    ! Allocate the output array to hold the integer values read from the file
    allocate(values(nitem))

    ! Rewind the file to read the integer values into the allocated array
    rewind(iounit)
    n = 0
    do
       read(iounit, '(A)', iostat=ios) line
       if (ios /= 0) exit
       line = adjustl(line)
       if (len_trim(line) == 0 .or. line(1:1) == '#') cycle
       n = n + 1
       read(line, *) values(n)
    end do

    ! Close file after reading all integer values
    close(iounit)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ReadIntListFile

  !-----------------------------------------------------------------------------

  subroutine ReadElementMapFile(filename, mapIds, mapElements, mapWeights, rc)

    ! Reads a plain-text file of "flow_id element_index [weight]" entries,
    ! one per line (whitespace-separated; blank lines and '#'-prefixed
    ! comments skipped) -- used for export_element_map_file. element_index
    ! is the target mesh's own 1-based element position (see
    ! docs/source/hydro.rst: Export Side). weight is optional and defaults
    ! to 1.0 when a line gives only the first two columns -- used to split
    ! a single flow id's value across more than one element (e.g. an equal
    ! 1/N share to each); the same element may also appear on more than one
    ! line, with its contributors' (weighted) values summed.

    ! input/output variables
    character(len=*), intent(in) :: filename
    integer, allocatable, intent(out) :: mapIds(:)
    integer, allocatable, intent(out) :: mapElements(:)
    real(ESMF_KIND_R8), allocatable, intent(out) :: mapWeights(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: iounit, ios, iosLine, n, nitem
    character(ESMF_MAXSTR) :: line
    character(len=*), parameter :: subname = trim(modName)//':(ReadElementMapFile) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called for '//trim(filename), ESMF_LOGMSG_INFO)

    ! Open the specified file for reading, using a new unit number
    open(newunit=iounit, file=trim(filename), status='old', action='read', iostat=ios)
    if (ios /= 0) then
       call ESMF_LogWrite(trim(subname)//": ERROR could not open '"//trim(filename)//"'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       return
    end if

    ! Count the number of valid entries in the file (skipping blank lines and comments)
    nitem = 0
    do
       read(iounit, '(A)', iostat=ios) line
       if (ios /= 0) exit
       line = adjustl(line)
       if (len_trim(line) == 0 .or. line(1:1) == '#') cycle
       nitem = nitem + 1
    end do

    ! Check that at least one valid entry was found in the file
    if (nitem <= 0) then
       call ESMF_LogWrite(trim(subname)//": ERROR no entries found in '"//trim(filename)//"'", ESMF_LOGMSG_ERROR)
       rc = ESMF_FAILURE
       close(iounit)
       return
    end if

    ! Allocate the output arrays to hold the flow IDs, element indices, and weights
    allocate(mapIds(nitem), mapElements(nitem), mapWeights(nitem))

    ! Rewind the file to read the flow ID / element index / optional weight entries
    rewind(iounit)
    n = 0
    do
       read(iounit, '(A)', iostat=ios) line
       if (ios /= 0) exit
       line = adjustl(line)
       if (len_trim(line) == 0 .or. line(1:1) == '#') cycle
       n = n + 1
       ! Try reading all three columns first; a line with only the first
       ! two falls short of the list-directed read and leaves iosLine /= 0,
       ! so fall back to reading just those two and default weight to 1.0
       read(line, *, iostat=iosLine) mapIds(n), mapElements(n), mapWeights(n)
       if (iosLine /= 0) then
          read(line, *) mapIds(n), mapElements(n)
          mapWeights(n) = 1.0d0
       end if
    end do

   ! Close file after reading all entries
    close(iounit)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine ReadElementMapFile

  !-----------------------------------------------------------------------------

  subroutine CheckNoDuplicates(values, label, rc)

    ! Hard error on any duplicate value in values(:) (e.g. a repeated flow
    ! id in export_ids/export_element_map_file), rather than silently
    ! exporting that point/element twice or ambiguously

    ! input/output variables
    integer, intent(in) :: values(:)
    character(len=*), intent(in) :: label
    integer, intent(out) :: rc

    ! local variables
    integer :: i, j
    character(ESMF_MAXSTR) :: message
    character(len=*), parameter :: subname = trim(modName)//':(CheckNoDuplicates) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Check for duplicate values in the input array
    do i = 1, size(values)
       do j = i+1, size(values)
          if (values(i) == values(j)) then
             write(message, fmt='(A,I0,A)') trim(subname)//": ERROR duplicate id ", values(i), &
                " found in '"//trim(label)//"'"
             call ESMF_LogWrite(trim(message), ESMF_LOGMSG_ERROR)
             rc = ESMF_FAILURE
             return
          end if
       end do
    end do

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine CheckNoDuplicates

  !-----------------------------------------------------------------------------

  subroutine CheckNoDuplicatePairs(ids, elements, rc)

    ! Hard error on an exact duplicate (id, element) pair -- used for
    ! export_element_map_file's many-to-many mapping (see HydroConfigType),
    ! where a repeated id alone or a repeated element alone is expected and
    ! allowed, but the identical pair appearing twice indicates a mistake
    ! (e.g. the same line duplicated, or present in both a merged sources
    ! and sinks mapping).

    ! input/output variables
    integer, intent(in) :: ids(:)
    integer, intent(in) :: elements(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: i, j
    character(ESMF_MAXSTR) :: message
    character(len=*), parameter :: subname = trim(modName)//':(CheckNoDuplicatePairs) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS

    do i = 1, size(ids)
       do j = i+1, size(ids)
          if (ids(i) == ids(j) .and. elements(i) == elements(j)) then
             write(message, fmt='(A,I0,A,I0,A)') trim(subname)//": ERROR duplicate (flow_id, element) pair (", &
                ids(i), ', ', elements(i), ") found in export_element_map_file"
             call ESMF_LogWrite(trim(message), ESMF_LOGMSG_ERROR)
             rc = ESMF_FAILURE
             return
          end if
       end do
    end do

  end subroutine CheckNoDuplicatePairs

  !-----------------------------------------------------------------------------

  subroutine CheckWeightSums(ids, weights, rc)

    ! Hard error if any flow id's weights (across every element it's split
    ! across) sum to more than 1.0 -- that would mean more of its flow is
    ! being distributed than actually exists. A small tolerance absorbs
    ! floating-point rounding from an exact fraction like 1/3 + 1/3 + 1/3.

    ! input/output variables
    integer, intent(in) :: ids(:)
    real(ESMF_KIND_R8), intent(in) :: weights(:)
    integer, intent(out) :: rc

    ! local variables
    integer :: i, j
    real(ESMF_KIND_R8) :: wsum
    real(ESMF_KIND_R8), parameter :: tol = 1.0d-6
    logical, allocatable :: counted(:)
    character(ESMF_MAXSTR) :: message
    character(len=*), parameter :: subname = trim(modName)//':(CheckWeightSums) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS

    allocate(counted(size(ids)))
    counted(:) = .false.

    do i = 1, size(ids)
       if (counted(i)) cycle
       wsum = weights(i)
       do j = i+1, size(ids)
          if (ids(j) == ids(i)) then
             wsum = wsum + weights(j)
             counted(j) = .true.
          end if
       end do
       if (wsum > 1.0d0 + tol) then
          write(message, fmt='(A,I0,A,F0.6,A)') trim(subname)//": ERROR weights for flow id ", &
             ids(i), " sum to ", wsum, " -- this exceeds 1.0, check export_element_map_file"
          call ESMF_LogWrite(trim(message), ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          deallocate(counted)
          return
       end if
    end do

    deallocate(counted)

  end subroutine CheckWeightSums

end module geogate_hydro_config
