cmake_minimum_required(VERSION 3.19)

project(geogate
        VERSION 1.0
        LANGUAGES C CXX Fortran)

###############################################################################
### Add module directory 
###############################################################################

list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)

###############################################################################
### Build options
###############################################################################

option(GEOGATE_USE_CATALYST "Support to Use Catalyst for Insitu Visualization" OFF)
option(GEOGATE_USE_PYTHON   "Support to Interact with Python"                  OFF)

###############################################################################
### Set required packages
###############################################################################

# Find MPI
if(NOT MPI_FOUND)
  find_package(MPI REQUIRED)
endif()
add_definitions(${MPI_Fortran_COMPILE_FLAGS})
include_directories(${MPI_Fortran_INCLUDE_PATH})

# Find ESMF
if(NOT ESMF_FOUND)
  find_package(ESMF 8.6.0 REQUIRED)
endif()

# Find Catalyst
if(GEOGATE_USE_CATALYST)
  message("ParaView Catalyst plugin is activated.")
  find_package(catalyst 2.0 REQUIRED)
endif()

# Find Conduit
if(GEOGATE_USE_PYTHON)
  message("Python plugin is activated.")
  find_package(Conduit REQUIRED)
endif()

if(CONDUIT_PYTHON_ENABLED OR CATALYST_USE_PYTHON)
  # Find Python
  set(Python_FIND_STRATEGY "LOCATION")
  find_package(Python COMPONENTS Interpreter Development)
  set(PYTHON_EXECUTABLE "${Python_EXECUTABLE}")
  # Setup Python
  include(cmake/SetupPython.cmake)
  # Conduit requires c++14 support
  set(CMAKE_CXX_STANDARD 14)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)

  message("Python_INCLUDE_DIRS  = ${Python_INCLUDE_DIRS}")
  message("Python_EXECUTABLE    = ${Python_EXECUTABLE}")
  message("Python_EXECUTABLE    = ${PYTHON_EXECUTABLE}")
  message("Python_LIBRARY_DIRS  = ${Python_LIBRARY_DIRS}")
  message("PYTHON_CONFIG_LIBDIR = ${PYTHON_CONFIG_LIBDIR}")
endif()

###############################################################################
### File lists and macros
###############################################################################

list(APPEND geogate_src_files geogate_nuopc.F90)

###############################################################################
### Set variables
###############################################################################

set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod)

###############################################################################
### Application
###############################################################################

add_library(geogate STATIC  ${geogate_src_files})
target_include_directories(geogate PRIVATE ${ESMF_F90COMPILEPATHS}) 
target_link_libraries(geogate PRIVATE esmf)

# Support for I/O, which is provided by ESMF/NUOPC
add_subdirectory(plugins/io)
add_dependencies(geogate geogate_io)
target_link_libraries(geogate PRIVATE geogate_io)

# Support for ParaView Catalyst
add_subdirectory(plugins/catalyst)
add_dependencies(geogate geogate_catalyst)
target_link_libraries(geogate PRIVATE geogate_catalyst)
if(GEOGATE_USE_CATALYST)
  target_include_directories(geogate PUBLIC ${CATALYST_PYTHONPATH})
  target_link_libraries(geogate PRIVATE catalyst::catalyst catalyst::catalyst_fortran)
endif()

# Support for Python
add_subdirectory(plugins/python)
add_dependencies(geogate geogate_python)
target_link_libraries(geogate PRIVATE geogate_python)
if(GEOGATE_USE_PYTHON)
  target_include_directories(geogate PUBLIC ${PYTHON_INCLUDE_DIR})
  target_link_libraries(geogate PRIVATE conduit::conduit conduit::conduit_python conduit::conduit_mpi)
  target_link_libraries(geogate PRIVATE ${PYTHON_LIBRARY})
endif()

# Add shared code
add_subdirectory(shared)
add_dependencies(geogate geogate_shared)
target_link_libraries(geogate PRIVATE geogate_shared)
target_include_directories(geogate PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>)

# List all variables (for debugging)
#get_cmake_property(_variableNames VARIABLES)
#list (SORT _variableNames)
#foreach (_variableName ${_variableNames})
#    if (_variableName MATCHES catalyst OR _variableName MATCHES Catalyst OR _variableName MATCHES CATALYST)
#        message(STATUS "${_variableName}=${${_variableName}}")
#    endif()
#endforeach()

###############################################################################
### Install
###############################################################################

install(
  TARGETS geogate
  EXPORT  geogate-config
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  COMPONENT Library)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod DESTINATION ${CMAKE_INSTALL_PREFIX})

install(EXPORT      geogate-config
        DESTINATION lib/cmake )
