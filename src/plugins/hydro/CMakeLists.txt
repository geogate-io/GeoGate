project(geogate_hydro Fortran)
if(GEOGATE_USE_HYDRO)
  set(SRCFILES geogate_hydro_config.F90
               geogate_hydro_io.F90
               geogate_hydro_pio.F90
               geogate_hydro_time.F90
               geogate_phases_hydro.F90)
else()
  set(SRCFILES geogate_phases_hydro_void.F90)
endif()

add_library(geogate_hydro ${SRCFILES})
add_dependencies(geogate_hydro geogate_shared)
target_include_directories(geogate_hydro PRIVATE ${ESMF_F90COMPILEPATHS})

if(GEOGATE_USE_HYDRO)
  target_include_directories(geogate_hydro PRIVATE ${NETCDF_INCLUDE_DIR})
  target_link_libraries(geogate_hydro PRIVATE ${NETCDF_FORTRAN_LIBS} PIO::PIO_Fortran)
endif()

install(TARGETS geogate_hydro
        EXPORT  geogate_hydro
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        COMPONENT Library)
install(EXPORT  geogate_hydro
        DESTINATION geogate/cmake)
