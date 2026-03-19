#include <conduit.hpp>
#include <conduit_cpp_to_c.hpp>
// conduit python module capi header
#include "conduit_python.hpp"
// embedded interp
#include "python_interpreter.hpp"

// single python interp instance
PythonInterpreter *interp = NULL;

extern "C" {

  //----------------------------------------------------------------------------
  // returns our static instance of our python interpreter
  // if not already inited initializes it
  //----------------------------------------------------------------------------

  PythonInterpreter *init_python_interpreter()
  {
      if( interp == NULL)
      {
          interp = new PythonInterpreter();
          if( !interp->initialize() )
          {
              std::cout << "ERROR: interp->initialize() failed " << std::endl;
              return NULL;
          }
          // setup for conduit python c api
          if(!interp->run_script("import conduit"))
          {
              std::cout << "ERROR: `import conduit` failed" << std::endl;
              return NULL;
          }

          if(import_conduit() < 0)
          {
             std::cout << "failed to import Conduit Python C-API";
             return NULL;
          }
      }
      return interp;
  }

  //----------------------------------------------------------------------------
  // access node passed from fortran to python
  //----------------------------------------------------------------------------

  void conduit_fort_to_py(conduit_node *data, const char *py_script,
                          const char *node_in_name) {
    // create python interpreter
    PythonInterpreter *pyintp = init_python_interpreter();

    // get global dict and insert wrapped conduit node
    PyObject *py_mod_dict = pyintp->global_dict();

    // get cpp ref to passed node
    conduit::Node &n = conduit::cpp_node_ref(data);

    // create py object to wrap the conduit node
    PyObject *py_node = PyConduit_Node_Python_Wrap(&n, 0); // python owns => false

    // insert node into global dict under the given name
    pyintp->set_dict_object(py_mod_dict, py_node, node_in_name);

    // trigger script
    bool err = pyintp->run_script_file(py_script, py_mod_dict);

    // check error
    if (err) {
       pyintp->check_error();
    }
  }

  //----------------------------------------------------------------------------
  // run python script and return node created by script
  //----------------------------------------------------------------------------

  conduit_node* conduit_fort_from_py(const char *py_script,
                                     const char *node_out_name) {
    // create python interpreter
    PythonInterpreter *pyintp = init_python_interpreter();

    // get global dict
    PyObject *py_mod_dict = pyintp->global_dict();

    // trigger script
    bool err = pyintp->run_script_file(py_script, py_mod_dict);

    // check error
    if (err) {
       pyintp->check_error();
    }

    // fetch output node from global dict
    PyObject *py_obj = PyDict_GetItemString(py_mod_dict, node_out_name);

    if (py_obj != NULL) {
       // get cpp ref from python node
       conduit::Node *n_res = PyConduit_Node_Get_Node_Ptr(py_obj);

       // return the c pointer
       return conduit::c_node(n_res);
    } else {
       std::cout << "INFO: could not find '" << node_out_name
                 << "' key returned from Python!" << std::endl;
       return NULL;
    }
  }

  //----------------------------------------------------------------------------
  // run python script, pass input node, and return node created by script
  //----------------------------------------------------------------------------

  conduit_node* conduit_fort_to_py_to_fort(conduit_node *data, const char *py_script,
                                           const char *node_in_name,
                                           const char *node_out_name) {
    // create python interpreter
    PythonInterpreter *pyintp = init_python_interpreter();

    // get global dict and insert wrapped conduit node
    PyObject *py_mod_dict = pyintp->global_dict();

    // get cpp ref to passed node
    conduit::Node &n = conduit::cpp_node_ref(data);

    // create py object to wrap the conduit node
    PyObject *py_node = PyConduit_Node_Python_Wrap(&n, 0); // python owns => false

    // insert node into global dict under the given name
    pyintp->set_dict_object(py_mod_dict, py_node, node_in_name);

    // trigger script
    bool err = pyintp->run_script_file(py_script, py_mod_dict);

    // check error
    if (err) {
       pyintp->check_error();
    }

    // fetch output node from global dict
    PyObject *py_obj = PyDict_GetItemString(py_mod_dict, node_out_name);

    if (py_obj != NULL) {
       // get cpp ref from python node
       conduit::Node *n_res = PyConduit_Node_Get_Node_Ptr(py_obj);

       // return the c pointer
       return conduit::c_node(n_res);
    } else {
       std::cout << "INFO: could not find '" << node_out_name
                 << "' key returned from Python!" << std::endl;
       return NULL;
    }
  }
}
