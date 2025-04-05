project(geogate_catalyst Fortran)
if(GEOGATE_USE_CATALYST)
  set(SRCFILES geogate_phases_catalyst.F90)
else()
  set(SRCFILES geogate_phases_catalyst_void.F90)
endif()

add_library(geogate_catalyst ${SRCFILES})
add_dependencies(geogate_catalyst geogate_shared)

if(catalyst_FOUND)
  message(INFO " catalyst_DIR = ${catalyst_DIR}")
  include_directories(${catalyst_DIR}/../../../include/catalyst-${catalyst_VERSION})
  if(EXISTS ${catalyst_DIR}/../../../include/catalyst-${catalyst_VERSION}/conduit)
    include_directories(${catalyst_DIR}/../../../include/catalyst-${catalyst_VERSION}/conduit)
  endif()
  if(CONDUIT_FOUND)
    include_directories(${CONDUIT_INCLUDE_DIRS})
  endif()
endif()

install(TARGETS geogate_catalyst
        EXPORT  geogate_catalyst
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        COMPONENT Library)
install(EXPORT  geogate_catalyst 
        DESTINATION lib/cmake)
