project(geogate_shared Fortran)
set(SRCFILES geogate_internalstate.F90
             geogate_share.F90
             geogate_types.F90)
add_library(geogate_shared ${SRCFILES})
install(TARGETS geogate_shared
        EXPORT  geogate_shared
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        COMPONENT Library)
install(EXPORT  geogate_shared
        DESTINATION geogate/cmake)
