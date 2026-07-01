project(geogate_ftorch Fortran)
if(GEOGATE_USE_FTORCH)
  set(SRCFILES geogate_phases_ftorch.F90)
else()
  set(SRCFILES geogate_phases_ftorch_void.F90)
endif()

add_library(geogate_ftorch ${SRCFILES})
add_dependencies(geogate_ftorch geogate_shared)
target_include_directories(geogate_ftorch PRIVATE ${ESMF_F90COMPILEPATHS})

if(GEOGATE_USE_FTORCH)
  target_link_libraries(geogate_ftorch PRIVATE FTorch::ftorch)
endif()

install(TARGETS geogate_ftorch
        EXPORT  geogate_ftorch
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        COMPONENT Library)
install(EXPORT  geogate_ftorch
        DESTINATION lib/cmake)
