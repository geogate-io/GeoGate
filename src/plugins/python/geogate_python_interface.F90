module geogate_python_interface

  !-----------------------------------------------------------------------------
  ! Void phase for Python interaction
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_LogWrite, ESMF_LOGMSG_INFO
  use ESMF, only: ESMF_TraceRegionEnter, ESMF_TraceRegionExit

  use, intrinsic :: iso_c_binding, only : C_PTR, C_CHAR, C_NULL_CHAR

  implicit none

  !-----------------------------------------------------------------------------
  ! Public module interface
  !-----------------------------------------------------------------------------

  interface
    subroutine c_geogate_python_preload(preload_modules) bind(C, name="geogate_python_preload")
      use iso_c_binding
      implicit none
      character(kind=C_CHAR), intent(in) :: preload_modules(*)
    end subroutine c_geogate_python_preload

    subroutine c_conduit_fort_to_py(nodeIn, py_script, node_in_name) bind(C, name="conduit_fort_to_py")
      use iso_c_binding
      implicit none
      type(C_PTR), value, intent(in) :: nodeIn
      character(kind=C_CHAR), intent(in) :: py_script(*)
      character(kind=C_CHAR), intent(in) :: node_in_name(*)
    end subroutine c_conduit_fort_to_py

    function c_conduit_fort_from_py(py_script, node_out_name) result(resOut) bind(C, name="conduit_fort_from_py")
      use iso_c_binding
      implicit none
      character(kind=C_CHAR), intent(in) :: py_script(*)
      character(kind=C_CHAR), intent(in) :: node_out_name(*)
      type(C_PTR) :: resOut
    end function c_conduit_fort_from_py

    function c_conduit_fort_to_py_to_fort(nodeIn, py_script, node_in_name, node_out_name) result(nodeOut) bind(C, name="conduit_fort_to_py_to_fort")
      use iso_c_binding
      implicit none
      type(C_PTR), value, intent(in) :: nodeIn
      character(kind=C_CHAR), intent(in) :: py_script(*)
      character(kind=C_CHAR), intent(in) :: node_in_name(*)
      character(kind=C_CHAR), intent(in) :: node_out_name(*)
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

  subroutine geogate_python_preload(preload_modules)
    use iso_c_binding
    implicit none

    ! input/output variables
    character(*), intent(in), optional :: preload_modules

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(geogate_python_preload) '
    !---------------------------------------------------------------------------

    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)
    call ESMF_TraceRegionEnter('geogate_python_preload')
    if (present(preload_modules)) then
      call c_geogate_python_preload(trim(preload_modules)//C_NULL_CHAR)
    else
      call c_geogate_python_preload(C_NULL_CHAR)
    end if
    call ESMF_TraceRegionExit('geogate_python_preload')
    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_python_preload

  subroutine conduit_fort_to_py(nodeIn, py_script, node_in_name)
    use iso_c_binding
    implicit none

    ! input/output variables
    type(C_PTR), intent(in) :: nodeIn
    character(*), intent(in) :: py_script
    character(*), intent(in), optional :: node_in_name

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(conduit_fort_to_py) '
    !---------------------------------------------------------------------------

    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Enter trace region
    call ESMF_TraceRegionEnter('conduit_fort_to_py')

    ! Run Python script
    if (present(node_in_name)) then
      call c_conduit_fort_to_py(nodeIn, trim(py_script)//C_NULL_CHAR, &
                                trim(node_in_name)//C_NULL_CHAR)
    else
      call c_conduit_fort_to_py(nodeIn, trim(py_script)//C_NULL_CHAR, &
                                'my_node'//C_NULL_CHAR)
    end if

    ! Exit trace region
    call ESMF_TraceRegionExit('conduit_fort_to_py')

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine conduit_fort_to_py

  function conduit_fort_from_py(py_script, node_out_name) result(nodeOut)
    use iso_c_binding
    implicit none

    ! input/output variables
    character(*), intent(in) :: py_script
    character(*), intent(in), optional :: node_out_name
    type(C_PTR) :: nodeOut

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(conduit_fort_from_py) '
    !---------------------------------------------------------------------------

    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Enter trace region
    call ESMF_TraceRegionEnter('conduit_fort_from_py')

    ! Run Python script
    if (present(node_out_name)) then
      nodeOut = c_conduit_fort_from_py(trim(py_script)//C_NULL_CHAR, &
                                       trim(node_out_name)//C_NULL_CHAR)
    else
      nodeOut = c_conduit_fort_from_py(trim(py_script)//C_NULL_CHAR, &
                                       'my_node_return'//C_NULL_CHAR)
    end if

    ! Exit trace region
    call ESMF_TraceRegionExit('conduit_fort_from_py')

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end function conduit_fort_from_py

  function conduit_fort_to_py_to_fort(nodeIn, py_script, node_in_name, node_out_name) result(nodeOut)
    use iso_c_binding
    implicit none

    ! input/output variables
    type(C_PTR), intent(in) :: nodeIn
    character(*), intent(in) :: py_script
    character(*), intent(in), optional :: node_in_name
    character(*), intent(in), optional :: node_out_name
    type(C_PTR) :: nodeOut

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(conduit_fort_to_py_to_fort) '
    !---------------------------------------------------------------------------

    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    ! Enter trace region
    call ESMF_TraceRegionEnter('conduit_fort_to_py_to_fort')

    ! Run Python script
    if (present(node_in_name) .and. present(node_out_name)) then
      nodeOut = c_conduit_fort_to_py_to_fort(nodeIn, trim(py_script)//C_NULL_CHAR, &
                                             trim(node_in_name)//C_NULL_CHAR, &
                                             trim(node_out_name)//C_NULL_CHAR)
    else if (present(node_in_name)) then
      nodeOut = c_conduit_fort_to_py_to_fort(nodeIn, trim(py_script)//C_NULL_CHAR, &
                                             trim(node_in_name)//C_NULL_CHAR, &
                                             'my_node_return'//C_NULL_CHAR)
    else if (present(node_out_name)) then
      nodeOut = c_conduit_fort_to_py_to_fort(nodeIn, trim(py_script)//C_NULL_CHAR, &
                                             'my_node'//C_NULL_CHAR, &
                                             trim(node_out_name)//C_NULL_CHAR)
    else
      nodeOut = c_conduit_fort_to_py_to_fort(nodeIn, trim(py_script)//C_NULL_CHAR, &
                                             'my_node'//C_NULL_CHAR, &
                                             'my_node_return'//C_NULL_CHAR)
    end if

    ! Exit trace region
    call ESMF_TraceRegionExit('conduit_fort_to_py_to_fort')

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end function conduit_fort_to_py_to_fort

end module geogate_python_interface
