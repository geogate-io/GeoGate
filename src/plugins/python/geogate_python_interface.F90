module geogate_python_interface

  !-----------------------------------------------------------------------------
  ! Void phase for Python interaction 
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO
  use, intrinsic :: iso_c_binding, only : C_PTR, C_CHAR

  implicit none

  !-----------------------------------------------------------------------------
  ! Public module interface
  !-----------------------------------------------------------------------------

  interface
    subroutine conduit_fort_to_py(nodeIn, py_script) bind(C, name="conduit_fort_to_py")
      use iso_c_binding
      implicit none
      type(C_PTR), value, intent(in) :: nodeIn
      character(kind=C_CHAR), intent(in) :: py_script(*)
    end subroutine conduit_fort_to_py

    function c_conduit_fort_from_py(py_script) result(resOut) bind(C, name="conduit_fort_from_py")
      use iso_c_binding
      implicit none
      character(kind=C_CHAR), intent(in) :: py_script(*)
      type(C_PTR) :: resOut
    end function c_conduit_fort_from_py

    function c_conduit_fort_to_py_to_fort(nodeIn, py_script) result(nodeOut) bind(C, name="conduit_fort_to_py_to_fort")
      use iso_c_binding
      implicit none
      type(C_PTR), value, intent(in) :: nodeIn
      character(kind=C_CHAR), intent(in) :: py_script(*)
      type(C_PTR) :: nodeOut
    end function c_conduit_fort_to_py_to_fort
  end interface

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  character(len=*), parameter :: modName = "(geogate_python_interface)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  function conduit_fort_from_py(py_script) result(nodeOut)
    use iso_c_binding
    implicit none

    ! input/output variables
    character(*), intent(in) :: py_script
    type(C_PTR) :: nodeOut

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(conduit_fort_from_py) '
    !---------------------------------------------------------------------------

    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    nodeOut = c_conduit_fort_from_py(trim(py_script)//C_NULL_CHAR)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end function conduit_fort_from_py

  function conduit_fort_to_py_to_fort(nodeIn, py_script) result(nodeOut)
    use iso_c_binding
    implicit none

    ! input/output variables
    type(C_PTR), intent(in) :: nodeIn
    character(*), intent(in) :: py_script
    type(C_PTR) :: nodeOut

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(conduit_fort_to_py_to_fort) '
    !---------------------------------------------------------------------------

    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    nodeOut = c_conduit_fort_to_py_to_fort(nodeIn, trim(py_script)//C_NULL_CHAR)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end function conduit_fort_to_py_to_fort

end module geogate_python_interface
