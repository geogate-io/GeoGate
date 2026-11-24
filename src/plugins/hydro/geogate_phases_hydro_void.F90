module geogate_phases_hydro

  !-----------------------------------------------------------------------------
  ! Void phase for hydrology data ingestion
  !-----------------------------------------------------------------------------

  use ESMF, only: ESMF_GridComp, ESMF_LogWrite, ESMF_FAILURE, ESMF_SUCCESS
  use ESMF, only: ESMF_LOGMSG_ERROR, ESMF_LOGMSG_INFO

  implicit none
  private

  !-----------------------------------------------------------------------------
  ! Public module routines
  !-----------------------------------------------------------------------------

  public :: geogate_phases_hydro_run
  public :: geogate_phases_hydro_datainit

  !-----------------------------------------------------------------------------
  ! Private module routines
  !-----------------------------------------------------------------------------

  !-----------------------------------------------------------------------------
  ! Private module data
  !-----------------------------------------------------------------------------

  integer :: dbug = 0
  character(len=*), parameter :: modName = "(geogate_phases_hydro_void)"
  character(len=*), parameter :: u_FILE_u = __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine geogate_phases_hydro_run(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_hydro_run) '
    !---------------------------------------------------------------------------

    rc = ESMF_FAILURE
    call ESMF_LogWrite(subname//' called', ESMF_LOGMSG_INFO)

    call ESMF_LogWrite(subname//' Please recompile with -DGEOGATE_USE_HYDRO=ON', ESMF_LOGMSG_ERROR)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_hydro_run

  !-----------------------------------------------------------------------------

  subroutine geogate_phases_hydro_datainit(gcomp, rc)

    ! input/output variables
    type(ESMF_GridComp)  :: gcomp
    integer, intent(out) :: rc

    ! local variables
    character(len=*), parameter :: subname = trim(modName)//':(geogate_phases_hydro_datainit) '
    !---------------------------------------------------------------------------

    rc = ESMF_SUCCESS
    call ESMF_LogWrite(subname//' called (void, no-op)', ESMF_LOGMSG_INFO)

    call ESMF_LogWrite(subname//' done', ESMF_LOGMSG_INFO)

  end subroutine geogate_phases_hydro_datainit

end module geogate_phases_hydro
