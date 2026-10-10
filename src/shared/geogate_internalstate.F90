module geogate_internalstate

  !-----------------------------------------------------------------------------
  ! This is the module for shared routines related to internal state
  !-----------------------------------------------------------------------------

  use ESMF, only: operator(==)
  use ESMF, only: ESMF_GridComp, ESMF_GridCompGetInternalState
  use ESMF, only: ESMF_State, ESMF_StateGet, ESMF_StateItem_Flag
  use ESMF, only: ESMF_FieldBundle, ESMF_RouteHandle
  use ESMF, only: ESMF_UtilStringLowerCase, ESMF_LogWrite
  use ESMF, only: ESMF_Mesh, ESMF_SUCCESS, ESMF_LOGMSG_INFO, ESMF_LOGMSG_ERROR, ESMF_LOGMSG_WARNING
  use ESMF, only: ESMF_STATEITEM_STATE, ESMF_MAXSTR

  use NUOPC, only: NUOPC_GetAttribute, NUOPC_CompAttributeGet
  use NUOPC_Model, only: NUOPC_ModelGet

  use geogate_share, only: ChkErr, StringSplit

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Private module routines and data structures
  !-----------------------------------------------------------------------------

  ! Internal state to keep instance data
  type InternalStateStruct
     integer :: numComp
     character(ESMF_MAXSTR), allocatable :: compName(:)
     type(ESMF_State), pointer :: NStateImp(:)
     type(ESMF_FieldBundle), pointer :: FBImp(:)
     type(ESMF_FieldBundle), pointer :: FBImpIntp(:)
     type(ESMF_State) :: NStateExp
     type(ESMF_FieldBundle) :: FBExp
     type(ESMF_Mesh) :: meshExp
     type(ESMF_RouteHandle), pointer :: RHImp2Exp(:)
     ! Per-connection (compName(n)) land/ocean mask values for FB_copy's masked regrid, see ImportMaskValues
     integer, allocatable :: importSrcMaskValue(:)
     integer, allocatable :: importDstMaskValue(:)
     logical, allocatable :: importMaskIsSet(:)
  end type InternalStateStruct

  !-----------------------------------------------------------------------------
  ! Public module routines and data structures
  !-----------------------------------------------------------------------------

  public :: InternalStateInit

  type, public :: InternalState
     type(InternalStateStruct), pointer :: wrap
  end type InternalState

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(*), parameter :: modName =  "(geogate_internalstate)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================  
  contains
!===============================================================================

  subroutine InternalStateInit(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp) :: gcomp
    integer, intent(out) :: rc

    ! local variables
    integer :: i, j, m
    integer :: importItemCount, nestedStateCount
    type(InternalState) :: is_local
    type(ESMF_State) :: importState
    type(ESMF_State) :: importNestedState
    character(ESMF_MAXSTR), allocatable     :: importItemNameList(:)
    type(ESMF_StateItem_Flag), allocatable  :: importItemTypeList(:)
    character(ESMF_MAXSTR) :: message
    character(ESMF_MAXSTR) :: namespace
    character(ESMF_MAXSTR) :: cvalue
    character(ESMF_MAXSTR), allocatable :: maskPairList(:), maskKV(:)
    logical :: isPresent, isSet, matched
    character(len=*), parameter :: subname = trim(modName)//':(InternalStateInit) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    !------------------
    ! Query for internal state 
    !------------------

    nullify(is_local%wrap)
    call ESMF_GridCompGetInternalState(gcomp, is_local, rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    !------------------
    ! Check number of connections
    !------------------

    call NUOPC_ModelGet(gcomp, importState=importState, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    call ESMF_StateGet(importState, nestedFlag=.false., itemCount=importItemCount, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    nestedStateCount = 0
    if (importItemCount > 0) then
       ! Allocate temporary data structures
       allocate(importItemNameList(importItemCount))
       allocate(importItemTypeList(importItemCount))

       ! Query state
       call ESMF_StateGet(importState, nestedFlag=.false., itemNameList=importItemNameList, itemTypeList=importItemTypeList, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Set flag if nested state is found
       do i = 1, importItemCount
          if (importItemTypeList(i) == ESMF_STATEITEM_STATE) then
             nestedStateCount = nestedStateCount+1
          end if
       end do

       write(message, fmt='(A,I2)') trim(subname)//': number of nested state = ', nestedStateCount
       call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
    end if

    !------------------
    ! Allocate memory
    !------------------

    if (nestedStateCount > 0) then
       is_local%wrap%numComp = nestedStateCount
       allocate(is_local%wrap%compName(nestedStateCount))
       allocate(is_local%wrap%FBImp(nestedStateCount))
       allocate(is_local%wrap%NStateImp(nestedStateCount))
       allocate(is_local%wrap%FBImpIntp(nestedStateCount))
       allocate(is_local%wrap%RHImp2Exp(nestedStateCount))
       allocate(is_local%wrap%importSrcMaskValue(nestedStateCount))
       allocate(is_local%wrap%importDstMaskValue(nestedStateCount))
       allocate(is_local%wrap%importMaskIsSet(nestedStateCount))
       is_local%wrap%importMaskIsSet(:) = .false.
    else
       is_local%wrap%numComp = 0
       call ESMF_LogWrite(trim(subname)//': There is no nested states or connection to the component!', ESMF_LOGMSG_INFO)
    end if

    !------------------
    ! Fill component names and link states
    !------------------

    if (nestedStateCount > 0) then
       j = 1
       do i = 1, importItemCount
          if (importItemTypeList(i) == ESMF_STATEITEM_STATE) then
             ! Get the associated nested state
             call ESMF_StateGet(importState, itemName=importItemNameList(i), nestedState=importNestedState, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return

             ! Query namespace
             call NUOPC_GetAttribute(importNestedState, name="Namespace", value=namespace, rc=rc)
             if (ChkErr(rc,__LINE__,u_FILE_u)) return
             namespace = ESMF_UtilStringLowerCase(trim(namespace))

             ! Set provider component name
             is_local%wrap%compName(j) = trim(namespace)
             call ESMF_LogWrite(trim(subname)//': Provider component '//trim(is_local%wrap%compName(j))//' is added.', ESMF_LOGMSG_INFO)
             j = j+1
          end if
       end do

       ! Per-connection land/ocean mask values, format "namespace:srcMaskValue:dstMaskValue,..."
       call NUOPC_CompAttributeGet(gcomp, name='ImportMaskValues', value=cvalue, &
         isPresent=isPresent, isSet=isSet, rc=rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return
       if (isPresent .and. isSet) then
          maskPairList = StringSplit(trim(cvalue), ",")
          do i = 1, size(maskPairList, dim=1)
             maskKV = StringSplit(trim(maskPairList(i)), ":")
             if (size(maskKV, dim=1) /= 3) then
                call ESMF_LogWrite(trim(subname)//': malformed ImportMaskValues entry: '//trim(maskPairList(i)), ESMF_LOGMSG_ERROR)
                cycle
             end if
             matched = .false.
             do m = 1, is_local%wrap%numComp
                if (trim(ESMF_UtilStringLowerCase(trim(maskKV(1)))) == trim(is_local%wrap%compName(m))) then
                   read(maskKV(2), *) is_local%wrap%importSrcMaskValue(m)
                   read(maskKV(3), *) is_local%wrap%importDstMaskValue(m)
                   is_local%wrap%importMaskIsSet(m) = .true.
                   matched = .true.
                   write(message, fmt='(A,I0,A,I0)') trim(subname)//': ImportMaskValues: '//trim(is_local%wrap%compName(m))// &
                     ' src=', is_local%wrap%importSrcMaskValue(m), ' dst=', is_local%wrap%importDstMaskValue(m)
                   call ESMF_LogWrite(trim(message), ESMF_LOGMSG_INFO)
                end if
             end do
             ! Catches a typo'd/unconnected namespace in ImportMaskValues, which would otherwise fail silently
             if (.not. matched) then
                call ESMF_LogWrite(trim(subname)//': ImportMaskValues names an unconnected component: '//trim(maskKV(1)), ESMF_LOGMSG_WARNING)
             end if
          end do
       end if
    end if

    !------------------
    ! Deallocate temporary data structures
    !------------------

    if (importItemCount > 0) then
       deallocate(importItemNameList)
       deallocate(importItemTypeList)
    end if   

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine InternalStateInit

end module geogate_internalstate
