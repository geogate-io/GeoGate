module geogate_internalstate

  !-----------------------------------------------------------------------------
  ! This is the module for shared routines related to internal state
  !-----------------------------------------------------------------------------

  use ESMF, only: operator(==)
  use ESMF, only: ESMF_GridComp, ESMF_GridCompGetInternalState
  use ESMF, only: ESMF_State, ESMF_StateGet, ESMF_StateItem_Flag
  use ESMF, only: ESMF_FieldBundle
  use ESMF, only: ESMF_UtilStringLowerCase, ESMF_LogWrite
  use ESMF, only: ESMF_SUCCESS, ESMF_LOGMSG_INFO
  use ESMF, only: ESMF_STATEITEM_STATE, ESMF_MAXSTR

  use NUOPC, only: NUOPC_GetAttribute
  use NUOPC_Model, only: NUOPC_ModelGet

  use geogate_share, only: ChkErr

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
     type(ESMF_State) :: NStateExp
     type(ESMF_FieldBundle) :: FBExp
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
    integer :: i, j
    integer :: importItemCount, nestedStateCount
    type(InternalState) :: is_local
    type(ESMF_State) :: importState
    type(ESMF_State) :: importNestedState
    character(ESMF_MAXSTR), allocatable     :: importItemNameList(:)
    type(ESMF_StateItem_Flag), allocatable  :: importItemTypeList(:)    
    character(ESMF_MAXSTR) :: message
    character(ESMF_MAXSTR) :: namespace
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
    else
       call ESMF_LogWrite(trim(subname)//': There is no nested states or connection to COP component!', ESMF_LOGMSG_INFO)
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
