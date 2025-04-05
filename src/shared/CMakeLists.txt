project(geogate_shared Fortran)
set(SRCFILES geogate_internalstate.F90
             geogate_share.F90
             geogate_types.F90)
add_library(geogate_shared ${SRCFILES})
target_include_directories(geogate_shared PRIVATE ${ESMF_F90COMPILEPATHS})
install(TARGETS geogate_shared
        EXPORT  geogate_shared
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        COMPONENT Library)
install(EXPORT  geogate_shared
        DESTINATION geogate/cmake)
