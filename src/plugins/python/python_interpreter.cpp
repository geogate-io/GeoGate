// Copyright (c) Lawrence Livermore National Security, LLC and other Conduit
// Project developers. See top-level LICENSE AND COPYRIGHT files for dates and
// other details. No copyright assignment is required to contribute to Conduit.

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
// Copyright (c) 2015-2021, Lawrence Livermore National Security, LLC.
//
// Produced at the Lawrence Livermore National Laboratory
//
// LLNL-CODE-716457
//
// All rights reserved.
//
// This file is part of Ascent.
//
// For details, see: http://ascent.readthedocs.io/.
//
// Please also read ascent/LICENSE
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the disclaimer below.
//
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the disclaimer (as noted below) in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the LLNS/LLNL nor the names of its contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL LAWRENCE LIVERMORE NATIONAL SECURITY,
// LLC, THE U.S. DEPARTMENT OF ENERGY OR CONTRIBUTORS BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
// OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
// IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//


//-----------------------------------------------------------------------------
///
/// file: python_interpreter.cpp
///
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
///
/// Simple C++ Embeddable Python Interpreter.
///
/// ADAPTED FROM https://github.com/Alpine-DAV/ascent/tree/develop/src/flow
///
/// OPTIMIZED: Python 3 only (Python 2 EOL), improved error handling
//-----------------------------------------------------------------------------

#include "python_interpreter.hpp"

// standard lib includes
#include <iostream>
#include <fstream>
#include <sstream>
#include <string.h>
#include <limits.h>
#include <cstdlib>
#include <vector>
#include <conduit.hpp>

using namespace std;

//-----------------------------------------------------------------------------
// Python 3 string conversion helpers
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
/// Convert Python string to C string (caller must free)
//-----------------------------------------------------------------------------
static char* PyString_AsString_Alloc(PyObject *py_obj)
{
    char *res = nullptr;
    if (PyUnicode_Check(py_obj))
    {
        PyObject *temp_bytes = PyUnicode_AsEncodedString(py_obj, "UTF-8", "strict");
        if (temp_bytes != nullptr)
        {
            res = strdup(PyBytes_AS_STRING(temp_bytes));
            Py_DECREF(temp_bytes);
        }
        else
        {
            CONDUIT_ERROR("Failed to encode Unicode string to UTF-8");
        }
    }
    else if (PyBytes_Check(py_obj))
    {
        res = strdup(PyBytes_AS_STRING(py_obj));
    }
    else
    {
        // Try to convert to string
        PyObject *str_obj = PyObject_Str(py_obj);
        if (str_obj)
        {
            res = PyString_AsString_Alloc(str_obj);
            Py_DECREF(str_obj);
        }
        else
        {
            CONDUIT_ERROR("Failed to convert Python object to string");
        }
    }
    return res;
}

//-----------------------------------------------------------------------------
/// Convert Python string to C++ string
//-----------------------------------------------------------------------------
static void PyString_To_CPP_String(PyObject *py_obj, std::string &res)
{
    char *str = PyString_AsString_Alloc(py_obj);
    if (str)
    {
        res = str;
        free(str);
    }
    else
    {
        res = "";
    }
}

//-----------------------------------------------------------------------------
///
/// PythonInterpreter Constructor
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
PythonInterpreter::PythonInterpreter() noexcept
    : m_handled_init(false)
    , m_running(false)
    , m_error(false)
    , m_echo(false)
    , m_py_main_module(nullptr)
    , m_py_global_dict(nullptr)
    , m_py_trace_print_exception_func(nullptr)
    , m_py_sio_class(nullptr)
{
}

//-----------------------------------------------------------------------------
///
/// PythonInterpreter Destructor
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
PythonInterpreter::~PythonInterpreter()
{
    // Shutdown the interpreter if running.
    shutdown();
 }


//-----------------------------------------------------------------------------
///
/// PythonInterpreter::set_program_name
///
//-----------------------------------------------------------------------------
void
PythonInterpreter::set_program_name(const char *prog_name)
{
    wchar_t *w_prog_name = Py_DecodeLocale(prog_name, nullptr);
    if (w_prog_name)
    {
        Py_SetProgramName(w_prog_name);
        PyMem_RawFree(w_prog_name);
    }
    else
    {
        CONDUIT_ERROR("Failed to decode program name");
    }
}


//-----------------------------------------------------------------------------
///
/// PythonInterpreter::set_argv
///
//-----------------------------------------------------------------------------
void
PythonInterpreter::set_argv(int argc, char **argv)
{
    // Allocate pointers for wide character version
    std::vector<wchar_t*> wargv(argc);
    
    for (int i = 0; i < argc; i++)
    {
        wargv[i] = Py_DecodeLocale(argv[i], nullptr);
        if (!wargv[i])
        {
            // Cleanup already allocated strings
            for (int j = 0; j < i; j++)
            {
                PyMem_RawFree(wargv[j]);
            }
            CONDUIT_ERROR("Failed to decode argv[" << i << "]");
            return;
        }
    }
    
    PySys_SetArgv(argc, wargv.data());
    
    // Cleanup
    for (int i = 0; i < argc; i++)
    {
        PyMem_RawFree(wargv[i]);
    }
}

//-----------------------------------------------------------------------------
///
/// Starts the python interpreter. If no arguments are passed creates
/// suitable dummy arguments
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::initialize(int argc, char **argv)
{
    // if already running, ignore
    if (m_running)
        return true;

    // Check Py_IsInitialized(), someone else may have initialized Python
    if (Py_IsInitialized())
    {
        // We don't need to clean up the interpreter
        m_handled_init = false;
    }
    else
    {
        // Set program name
        const char *prog_name = "geogate_embedded_py";

        if (argc == 0 || argv == nullptr)
        { 
            set_program_name(prog_name);
        }
        else
        {   
            set_program_name(argv[0]);
        }

        // Initialize Python
        Py_Initialize();
        PyEval_InitThreads();

        // Set sys.argv
        if (argc == 0 || argv == nullptr)
        {
            set_argv(1, const_cast<char**>(&prog_name));
        }
        else
        {
            set_argv(argc, argv);
        }

        // Mark that we need to cleanup the interpreter
        m_handled_init = true;
    }

    // Setup required for C++ connection, even if Python was already initialized

    // Setup __main__ module
    PyRun_SimpleString("import os,sys\n");
    if (check_error())
        return false;

    // All of these PyObject*s are borrowed references
    m_py_main_module = PyImport_AddModule("__main__");
    
    if (m_py_main_module == nullptr)
    {
        CONDUIT_ERROR("PythonInterpreter failed to import `__main__` module");
        return false;
    }
    
    m_py_global_dict = PyModule_GetDict(m_py_main_module);

    if (m_py_global_dict == nullptr)
    {
        CONDUIT_ERROR("PythonInterpreter failed to access `__main__` dictionary");
        return false;
    }

    // Get objects that help us print exceptions
    PyRun_SimpleString("import traceback\n");
    if (check_error())
        return false;

    // Get reference to traceback.print_exception method
    PyObject *py_trace_module = PyImport_AddModule("traceback");

    if (py_trace_module == nullptr)
    {
        CONDUIT_ERROR("PythonInterpreter failed to import `traceback` module");
        return false;
    }

    PyObject *py_trace_dict = PyModule_GetDict(py_trace_module);

    if (py_trace_dict == nullptr)
    {
        CONDUIT_ERROR("PythonInterpreter failed to access `traceback` dictionary");
        return false;
    }
    
    m_py_trace_print_exception_func = PyDict_GetItemString(py_trace_dict, "print_exception");

    if (m_py_trace_print_exception_func == nullptr)
    {
        CONDUIT_ERROR("PythonInterpreter failed to access `print_exception` function");
        return false;
    }

    // Get reference to io.StringIO class
    PyRun_SimpleString("import io\n");
    if (check_error())
        return false;

    PyObject *py_sio_module = PyImport_ImportModule("io");
    
    if (py_sio_module == nullptr)
    {
        CONDUIT_ERROR("PythonInterpreter failed to import `io` module");
        return false;
    }
    
    PyObject *py_sio_dict = PyModule_GetDict(py_sio_module);
    
    if (py_sio_dict == nullptr)
    {
        CONDUIT_ERROR("PythonInterpreter failed to access `io` dictionary");
        return false;
    }

    // Get the StringIO class
    m_py_sio_class = PyDict_GetItemString(py_sio_dict, "StringIO");

    if (m_py_sio_class == nullptr)
    {
        CONDUIT_ERROR("PythonInterpreter failed to access StringIO class");
        return false;
    }
    
    m_running = true;

    return true;
}


//-----------------------------------------------------------------------------
///
/// Resets the state of the interpreter if it is running
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
void
PythonInterpreter::reset()
{
    if (m_running)
    {
        // Clear global dictionary
        PyDict_Clear(m_py_global_dict);
    }
}

//-----------------------------------------------------------------------------
///
/// Shuts down the interpreter if it is running
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
void
PythonInterpreter::shutdown() noexcept
{
    if (m_running)
    {
        if (m_handled_init)
        {
            Py_Finalize();
        }

        m_running = false;
        m_handled_init = false;
    }
}


//-----------------------------------------------------------------------------
///
/// Adds passed path to "sys.path"
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::add_system_path(const std::string &path)
{
    return run_script("sys.path.insert(1,r'" + path + "')\n");
}

//-----------------------------------------------------------------------------
///
/// Executes passed python script in the interpreter
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::run_script(const std::string &script)
{
    return run_script(script, m_py_global_dict);
}

//-----------------------------------------------------------------------------
///
/// Executes passed python script in the interpreter
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::run_script_file(const std::string &fname)
{
    return run_script_file(fname, m_py_global_dict);
}

//-----------------------------------------------------------------------------
///
/// Executes passed python script in the interpreter
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::run_script(const std::string &script, PyObject *py_dict)
{
    if (!m_running)
        return false;

    // Show contents of the script if echo option is enabled
    if (m_echo)
    {
        CONDUIT_INFO("PythonInterpreter::run_script " << script);
    }

    PyRun_String(script.c_str(), Py_file_input, py_dict, py_dict);
    return !check_error();
}

//-----------------------------------------------------------------------------
///
/// Executes passed python script from file
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::run_script_file(const std::string &fname, PyObject *py_dict)
{
    ifstream ifs(fname.c_str());
    if (!ifs.is_open())
    {        
        CONDUIT_ERROR("PythonInterpreter::run_script_file failed to open " << fname);
        return false;
    }

    string py_script((istreambuf_iterator<char>(ifs)), istreambuf_iterator<char>());
    ifs.close();

    return run_script(py_script, py_dict);
}

//-----------------------------------------------------------------------------
///
/// Adds C python object to the global dictionary.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::set_global_object(PyObject *py_obj,
                                     const string &py_name)
{
    return set_dict_object(m_py_global_dict, py_obj, py_name);
}

//-----------------------------------------------------------------------------
///
/// Get C python object from the global dictionary.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
PyObject *
PythonInterpreter::get_global_object(const string &py_name)
{
    return get_dict_object(m_py_global_dict, py_name);
}


//-----------------------------------------------------------------------------
///
/// Set object into given dictionary
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::set_dict_object(PyObject *py_dict,
                                   PyObject *py_obj,
                                   const string &py_name)
{
    PyDict_SetItemString(py_dict, py_name.c_str(), py_obj);
    return !check_error();
}

//-----------------------------------------------------------------------------
///
/// Get object from given dictionary (returns borrowed reference)
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
PyObject *
PythonInterpreter::get_dict_object(PyObject *py_dict, const string &py_name)
{
    PyObject *res = PyDict_GetItemString(py_dict, py_name.c_str());
    if (check_error())
        res = nullptr;
    return res;
}

//-----------------------------------------------------------------------------
///
/// Checks python error state and constructs appropriate error message
/// if an error occurred. Can be used to check for errors in both
/// python scripts & calls to the C-API.
///
/// Note: This method clears the python error state, but continues
/// to return "true" indicating an error until clear_error() is called.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::check_error()
{
    if (PyErr_Occurred())
    {
        m_error = true;
        m_error_msg = "<Unknown Error>";

        string sval;
        PyObject *py_etype = nullptr;
        PyObject *py_eval = nullptr;
        PyObject *py_etrace = nullptr;

        PyErr_Fetch(&py_etype, &py_eval, &py_etrace);

        if (py_etype)
        {
            PyErr_NormalizeException(&py_etype, &py_eval, &py_etrace);

            if (PyObject_to_string(py_etype, sval))
            {
                m_error_msg = sval;
            }

            if (py_eval && PyObject_to_string(py_eval, sval))
            {
                m_error_msg += sval;
            }

            if (py_etrace && PyTraceback_to_string(py_etype, py_eval, py_etrace, sval))
            {
                m_error_msg += "\n" + sval;
            }
        }

        CONDUIT_INFO("Error when running script:\n" << m_error_msg);

        PyErr_Restore(py_etype, py_eval, py_etrace);
        PyErr_Clear();
    }

    return m_error;
}

//-----------------------------------------------------------------------------
///
/// Clears error flag and message
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
void
PythonInterpreter::clear_error() noexcept
{
    m_error = false;
    m_error_msg.clear();
}

//-----------------------------------------------------------------------------
///
/// Helper that converts a python object to a double.
/// Returns true if the conversion succeeds.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::PyObject_to_double(PyObject *py_obj, double &res)
{
    if (PyFloat_Check(py_obj))
    {
        res = PyFloat_AS_DOUBLE(py_obj);
        return true;
    }

    if (PyLong_Check(py_obj))
    {
        res = static_cast<double>(PyLong_AsLong(py_obj));
        return true;
    }

    if (PyNumber_Check(py_obj) != 1)
        return false;

    PyObject *py_val = PyNumber_Float(py_obj);
    if (py_val == nullptr)
        return false;

    res = PyFloat_AS_DOUBLE(py_val);
    Py_DECREF(py_val);
    return true;
}

//-----------------------------------------------------------------------------
///
/// Helper that converts a python object to an int.
/// Returns true if the conversion succeeds.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::PyObject_to_int(PyObject *py_obj, int &res)
{
    if (PyLong_Check(py_obj))
    {
        res = static_cast<int>(PyLong_AsLong(py_obj));
        return true;
    }

    if (PyNumber_Check(py_obj) != 1)
        return false;

    PyObject *py_val = PyNumber_Long(py_obj);
    if (py_val == nullptr)
        return false;

    res = static_cast<int>(PyLong_AsLong(py_val));
    Py_DECREF(py_val);
    return true;
}

//-----------------------------------------------------------------------------
///
/// Helper that converts a python object to a C++ string.
/// Returns true if the conversion succeeds.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::PyObject_to_string(PyObject *py_obj, std::string &res)
{
    PyObject *py_obj_str = PyObject_Str(py_obj);
    if (py_obj_str == nullptr)
        return false;

    PyString_To_CPP_String(py_obj_str, res);
    Py_DECREF(py_obj_str);
    return true;
}


//-----------------------------------------------------------------------------
///
/// Helper that turns a python traceback into a human readable string.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::PyTraceback_to_string(PyObject *py_etype,
                                         PyObject *py_eval,
                                         PyObject *py_etrace,
                                         std::string &res)
{
    if (!py_eval)
        py_eval = Py_None;
  
    // We can only print traceback if we have fully initialized the interpreter
    if (!m_running)
        return false;

    // Create a StringIO object "buffer" to print traceback into
    PyObject *py_args = Py_BuildValue("()");
    PyObject *py_buffer = PyObject_CallObject(m_py_sio_class, py_args);
    Py_DECREF(py_args);

    if (!py_buffer)
    {
        PyErr_Print();
        return false;
    }

    // Call traceback.print_exception(etype, eval, etrace, None, buffer)
    PyObject *py_res = PyObject_CallFunction(m_py_trace_print_exception_func,
                                             "OOOOO",
                                             py_etype,
                                             py_eval,
                                             py_etrace,
                                             Py_None,
                                             py_buffer);
    if (!py_res)
    {
        PyErr_Print();
        Py_DECREF(py_buffer);
        return false;
    }

    // Call buffer.getvalue() to get python string object
    PyObject *py_str = PyObject_CallMethod(py_buffer, "getvalue", nullptr);

    if (!py_str)
    {
        PyErr_Print();
        Py_DECREF(py_buffer);
        Py_DECREF(py_res);
        return false;
    }

    // Convert python string object to std::string
    PyString_To_CPP_String(py_str, res);

    Py_DECREF(py_buffer);
    Py_DECREF(py_res);
    Py_DECREF(py_str);

    return true;
}