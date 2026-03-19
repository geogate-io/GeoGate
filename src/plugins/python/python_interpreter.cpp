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
//-----------------------------------------------------------------------------

#include "python_interpreter.hpp"

// standard lib includes
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string.h>
#include <limits.h>
#include <cstdlib>
#include <conduit.hpp>

//-----------------------------------------------------------------------------
///
/// PythonInterpreter Constructor
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
PythonInterpreter::PythonInterpreter()
{
    m_handled_init = false;
    m_running      = false;
    m_error        = false;
    m_echo         = false;

    m_py_main_module = NULL;
    m_py_global_dict = NULL;

    m_py_trace_module               = NULL;
    m_py_sio_module                 = NULL;
    m_py_trace_print_exception_func = NULL;
    m_py_sio_class                  = NULL;
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
    wchar_t *w_prog_name = Py_DecodeLocale(prog_name, NULL);
    Py_SetProgramName(w_prog_name);
    PyMem_RawFree(w_prog_name);
}


//-----------------------------------------------------------------------------
///
/// PythonInterpreter::set_argv
///
//-----------------------------------------------------------------------------
void
PythonInterpreter::set_argv(int argc, char **argv)
{
    // alloc ptrs for encoded ver
    std::vector<wchar_t*> wargv(argc);

    for(int i = 0; i < argc; i++)
    {
        wargv[i] = Py_DecodeLocale(argv[i], NULL);
    }

    PySys_SetArgv(argc, &wargv[0]);

    for(int i = 0; i < argc; i++)
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
    if(m_running)
        return true;

    // Check Py_IsInitialized(), some one else may have inited python
    if(Py_IsInitialized())
    {
        // make sure we know we don't need to clean up the interp
        m_handled_init = false;
    }
    else
    {
        // set prog name
        const char *prog_name = "flow_embedded_py";

        if(argc == 0 || argv == NULL)
        {
            set_program_name(prog_name);
        }
        else
        {
            set_program_name(argv[0]);
        }

        // Init Python
        Py_Initialize();
        PyEval_InitThreads();

        // set sys argvs
        if(argc == 0 || argv == NULL)
        {
            set_argv(1, const_cast<char**>(&prog_name));
        }
        else
        {
            set_argv(argc, argv);
        }

        // make sure we know we need to cleanup the interp
        m_handled_init = true;
    }

    // do to setup b/c we need for c++ connection,
    // even if python was already inited

    // setup up __main__ and capture StdErr
    PyRun_SimpleString("import os,sys\n");
    if(check_error())
        return false;

    // all of these PyObject*s are borrowed refs
    m_py_main_module = PyImport_AddModule((char*)"__main__");

    if(m_py_main_module == NULL)
    {
        std::cout << "PythonInterpreter failed to import `__main__` module" << std::endl;
        return false;
    }

    m_py_global_dict = PyModule_GetDict(m_py_main_module);

    if(m_py_global_dict == NULL)
    {
        CONDUIT_INFO("PythonInterpreter failed to access `__main__` dictionary");
        return false;
    }

    // get objects that help us print exceptions
    PyRun_SimpleString("import traceback\n");
    if(check_error())
        return false;

    // get ref to traceback.print_exception method
    m_py_trace_module = PyImport_AddModule("traceback");

    if(m_py_trace_module == NULL)
    {
        CONDUIT_INFO("PythonInterpreter failed to import `traceback` module");
        return false;
    }

    PyObject *py_trace_dict = PyModule_GetDict(m_py_trace_module);

    if(py_trace_dict == NULL)
    {
        CONDUIT_INFO("PythonInterpreter failed to access `traceback` dictionary");
        return false;
    }

    m_py_trace_print_exception_func = PyDict_GetItemString(py_trace_dict,
                                                           "print_exception");

    if(m_py_trace_print_exception_func == NULL)
    {
        CONDUIT_INFO("PythonInterpreter failed to access `print_exception` function");
        return false;
    }

    // get ref to StringIO class
    PyRun_SimpleString("import io\n");
    if(check_error())
        return false;

    m_py_sio_module = PyImport_ImportModule("io");

    if(m_py_sio_module == NULL)
    {
        CONDUIT_INFO("PythonInterpreter failed to import `io` module");
        return false;
    }

    PyObject *py_sio_dict = PyModule_GetDict(m_py_sio_module);

    if(py_sio_dict == NULL)
    {
        CONDUIT_INFO("PythonInterpreter failed to access `io` dictionary");
        return false;
    }

    m_py_sio_class = PyDict_GetItemString(py_sio_dict, "StringIO");

    if(m_py_sio_class == NULL)
    {
        CONDUIT_INFO("PythonInterpreter failed to access StringIO class");
        return false;
    }

    m_running = true;

    return true;
}


//-----------------------------------------------------------------------------
///
/// Shuts down the interpreter if it is running
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
void
PythonInterpreter::shutdown()
{
    if(m_running)
    {
        // release cached compiled code objects before finalizing
        for(std::map<std::string, PyObject*>::iterator it = m_script_cache.begin();
            it != m_script_cache.end(); ++it)
        {
            Py_DECREF(it->second);
        }
        m_script_cache.clear();

        if(m_handled_init)
        {
            Py_Finalize();
        }

        m_running      = false;
        m_handled_init = false;
    }
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
/// Executes passed python script file in the interpreter
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
PythonInterpreter::run_script(const std::string &script,
                              PyObject *py_dict)
{
    bool res = false;
    if(m_running)
    {
        // show contents of the script via conduit info if echo option
        // is enabled
        if(m_echo)
        {
            CONDUIT_INFO("PythonInterpreter::run_script " << script);
        }

        PyRun_String((char*)script.c_str(),
                     Py_file_input,
                     py_dict,
                     py_dict);
        if(!check_error())
            res = true;
    }
    return res;
}

//-----------------------------------------------------------------------------
///
/// Executes passed python script in the interpreter.
/// The script is compiled on first use and the resulting code object is
/// cached so that subsequent calls skip both file I/O and Python compilation.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::run_script_file(const std::string &fname,
                                   PyObject *py_dict)
{
    if(!m_running)
        return false;

    // look up compiled code object in cache
    PyObject *code_obj = NULL;
    std::map<std::string, PyObject*>::iterator it = m_script_cache.find(fname);

    if(it == m_script_cache.end())
    {
        // first call: read and compile the script
        std::ifstream ifs(fname.c_str());
        if(!ifs.is_open())
        {
            CONDUIT_ERROR("PythonInterpreter::run_script_file "
                          " failed to open " << fname);
            return false;
        }
        std::string py_script((std::istreambuf_iterator<char>(ifs)),
                              std::istreambuf_iterator<char>());
        ifs.close();

        if(m_echo)
        {
            CONDUIT_INFO("PythonInterpreter::run_script_file compiling " << fname);
        }

        code_obj = Py_CompileString(py_script.c_str(), fname.c_str(), Py_file_input);
        if(code_obj == NULL)
        {
            check_error();
            return false;
        }

        // store in cache; we hold the reference
        m_script_cache[fname] = code_obj;
    }
    else
    {
        code_obj = it->second;
    }

    // execute the cached code object
    PyObject *result = PyEval_EvalCode(code_obj, py_dict, py_dict);
    if(result == NULL)
    {
        check_error();
        return false;
    }
    Py_DECREF(result);
    return !check_error();
}


//-----------------------------------------------------------------------------
///
/// Adds C python object to the given dictionary.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::set_dict_object(PyObject *py_dict,
                                   PyObject *py_obj,
                                   const std::string &py_name)
{
    PyDict_SetItemString(py_dict, py_name.c_str(), py_obj);
    return !check_error();
}

//-----------------------------------------------------------------------------
///
/// Get C python object from the given dictionary.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
PyObject *
PythonInterpreter::get_dict_object(PyObject *py_dict,
                                   const std::string &py_name)
{
    PyObject *res = PyDict_GetItemString(py_dict, py_name.c_str());
    if(check_error())
        res = NULL;
    return res;
}

//-----------------------------------------------------------------------------
///
/// Checks python error state and constructs appropriate error message
/// if an error did occur. It can be used to check for errors in both
/// python scripts & calls to the C-API. The difference between these
/// two cases is the existence of a python traceback.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::check_error()
{
    if(PyErr_Occurred())
    {
        m_error = true;
        m_error_msg = "<Unknown Error>";

        std::string sval = "";
        PyObject *py_etype;
        PyObject *py_eval;
        PyObject *py_etrace;

        PyErr_Fetch(&py_etype, &py_eval, &py_etrace);

        if(py_etype)
        {
            PyErr_NormalizeException(&py_etype, &py_eval, &py_etrace);

            if(PyObject_to_string(py_etype, sval))
            {
                m_error_msg = sval;
            }

            if(py_eval)
            {
                if(PyObject_to_string(py_eval, sval))
                {
                    m_error_msg += sval;
                }
            }

            if(py_etrace)
            {
                if(PyTraceback_to_string(py_etype, py_eval, py_etrace, sval))
                {
                    m_error_msg += "\n" + sval;
                }
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
/// Helper that converts a python object to a C++ string.
/// Returns true if the conversion succeeds.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::PyObject_to_string(PyObject *py_obj, std::string &res)
{
    PyObject *py_obj_str = PyObject_Str(py_obj);
    if(py_obj_str == NULL)
        return false;

    const char *str = PyUnicode_AsUTF8(py_obj_str);
    if(str != NULL)
        res = str;
    Py_DECREF(py_obj_str);
    return true;
}


//-----------------------------------------------------------------------------
///
/// Helper to turns a python traceback into a human readable string.
///
/// Note: Adapted from VisIt: src/avt/PythonFilters/PythonInterpreter.cpp
//-----------------------------------------------------------------------------
bool
PythonInterpreter::PyTraceback_to_string(PyObject *py_etype,
                                         PyObject *py_eval,
                                         PyObject *py_etrace,
                                         std::string &res)
{
    if(!py_eval)
        py_eval = Py_None;

    // we can only print traceback if we have fully
    // inited the interpreter, since it uses imported helpers
    if(!m_running)
    {
        return false;
    }

    // create a StringIO object "buffer" to print traceback into.
    PyObject *py_args   = Py_BuildValue("()");
    PyObject *py_buffer = PyObject_CallObject(m_py_sio_class, py_args);
    Py_DECREF(py_args);

    if(!py_buffer)
    {
        PyErr_Print();
        return false;
    }

    // call traceback.print_exception(etype, eval, etrace, file=buffer)
    PyObject *py_res = PyObject_CallFunction(m_py_trace_print_exception_func,
                                             (char*)"OOOOO",
                                             py_etype,
                                             py_eval,
                                             py_etrace,
                                             Py_None,
                                             py_buffer);
    if(!py_res)
    {
        PyErr_Print();
        return false;
    }

    // call buffer.getvalue() to get python string object
    PyObject *py_str = PyObject_CallMethod(py_buffer, (char*)"getvalue", NULL);

    if(!py_str)
    {
        PyErr_Print();
        return false;
    }

    // convert python string object to std::string
    const char *str = PyUnicode_AsUTF8(py_str);
    if(str != NULL)
        res = str;

    Py_DECREF(py_buffer);
    Py_DECREF(py_res);
    Py_DECREF(py_str);

    return true;
}
