project(geogate_python Fortran C)
if(GEOGATE_USE_PYTHON)
  set(SRCFILES geogate_phases_python.F90
               geogate_python_interface.F90
               geogate_python_interface.cpp
               python_interpreter.cpp)
else()
  set(SRCFILES geogate_phases_python_void.F90)
endif()

add_library(geogate_python ${SRCFILES})
add_dependencies(geogate_python geogate_shared)
target_include_directories(geogate_python PRIVATE ${ESMF_F90COMPILEPATHS})

if(GEOGATE_USE_PYTHON)
  target_include_directories(geogate_python PRIVATE ${CONDUIT_INCLUDE_DIRS})
  target_include_directories(geogate_python PRIVATE ${Python_INCLUDE_DIRS})
  target_include_directories(geogate_python PRIVATE ${CONDUIT_PYTHON_MODULE_DIR}/conduit)
endif()

install(TARGETS geogate_python
        EXPORT  geogate_python
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        COMPONENT Library)
install(EXPORT  geogate_python
        DESTINATION lib/cmake)
