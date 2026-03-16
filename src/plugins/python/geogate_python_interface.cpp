#include <conduit.hpp>
#include <conduit_cpp_to_c.hpp>
// conduit python module capi header
#include "conduit_python.hpp"
// embedded interp
#include "python_interpreter.hpp"

// single python interp instance for our example.
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

          // Turn this on if you want to see every line
          // the python interpreter executes
          //interp->set_echo(true);
      }
      return interp;
  }

  //----------------------------------------------------------------------------
  // access node passed from fortran to python
  //----------------------------------------------------------------------------

  void conduit_fort_to_py(conduit_node *data, const char *py_script) {
    // create python interpreter
    PythonInterpreter *pyintp = init_python_interpreter();

    // add extra system paths
    // pyintp->add_system_path("/usr/local/lib/python3.9/site-packages");

    // show code
    // pyintp->set_echo(true);

    // get global dict and insert wrapped conduit node
    PyObject *py_mod_dict =  pyintp->global_dict();

    // get cpp ref to passed node
    conduit::Node &n = conduit::cpp_node_ref(data);

    // create py object to wrap the conduit node
    PyObject *py_node = PyConduit_Node_Python_Wrap(&n, 0); // python owns => false

    // my_node is set in here statically, it will be used to access node under python
    pyintp->set_dict_object(py_mod_dict, py_node, "my_node"); 

    // trigger script
    bool err = pyintp->run_script_file(py_script, py_mod_dict);

    // check error
    if (err) {
       pyintp->check_error();
    }
  }

  conduit_node* conduit_fort_from_py(const char *py_script) {
    // create python interpreter
    PythonInterpreter *pyintp = init_python_interpreter();

    // trigger script
    bool err = pyintp->run_script_file(py_script);

    // check error
    if (err) {
       pyintp->check_error();
    }
    // get global dict and insert wrapped conduit node
    PyObject *py_mod_dict =  pyintp->global_dict();

    // create py object to get the conduit node
    PyObject *py_obj = pyintp->get_dict_object(py_mod_dict, "my_node_return");

    // get cpp ref from python node
    conduit::Node *n_res = PyConduit_Node_Get_Node_Ptr(py_obj);

    // return the c pointer
    return conduit::c_node(n_res);
  }

  conduit_node* conduit_fort_to_py_to_fort(conduit_node *data, const char *py_script) {
    // create python interpreter
    PythonInterpreter *pyintp = init_python_interpreter();

    // get global dict and insert wrapped conduit node
    PyObject *py_mod_dict =  pyintp->global_dict();

    // get cpp ref to passed node
    conduit::Node &n = conduit::cpp_node_ref(data);

    // create py object to wrap the conduit node
    PyObject *py_node = PyConduit_Node_Python_Wrap(&n, 0); // python owns => false

    // my_node is set in here statically, it will be used to access node under python
    pyintp->set_dict_object(py_mod_dict, py_node, "my_node");

    // trigger script
    bool err = pyintp->run_script_file(py_script, py_mod_dict);

    // check error
    if (err) {
       pyintp->check_error();
    }

    // get global dict and fetch wrapped conduit node
    py_mod_dict = pyintp->global_dict();

    // check my_node_return in dictionary
    std::string cpp_key = "my_node_return";
    PyObject *py_key = PyUnicode_FromString(cpp_key.c_str());
    int contains = PyDict_Contains(py_mod_dict, py_key);
    Py_DECREF(py_key);

    if (contains == 1) {
       // create py object to get the conduit node
       PyObject *py_obj = pyintp->get_dict_object(py_mod_dict, cpp_key.c_str());

       // get cpp ref from python node
       conduit::Node *n_res = PyConduit_Node_Get_Node_Ptr(py_obj);

       // return the c pointer
       return conduit::c_node(n_res);
    } else {
       std::cout << "INFO: could not find 'my_node_return' key returned from Python!" << std::endl;
       return NULL;
    }
  }
}
