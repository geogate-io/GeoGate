project(geogate_io Fortran)
set(SRCFILES geogate_phases_io.F90)
add_library(geogate_io ${SRCFILES})
add_dependencies(geogate_io geogate_shared)
target_include_directories(geogate_io PRIVATE ${ESMF_F90COMPILEPATHS})
install(TARGETS geogate_io
        EXPORT  geogate_io
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        COMPONENT Library)
install(EXPORT  geogate_io 
        DESTINATION geogate/cmake)
