#include <conduit.hpp>
#include <conduit_cpp_to_c.hpp>
// conduit python module capi header
#include "conduit_python.hpp"
// embedded interp
#include "python_interpreter.hpp"

// single python interp instance for our example.
static PythonInterpreter *interp = NULL;
static bool interp_initialized = false;
static bool interp_init_failed = false;

extern "C" {

  //----------------------------------------------------------------------------
  // returns our static instance of our python interpreter
  // if not already inited initializes it
  // Uses cached flags to avoid overhead on subsequent calls
  //----------------------------------------------------------------------------

  PythonInterpreter *init_python_interpreter() 
  {
      // Fast path: return immediately if already initialized
      if (interp_initialized) {
          return interp;
      }

      // Return NULL immediately if initialization previously failed
      if (interp_init_failed) {
          return NULL;
      }

      // First-time initialization
      if (interp == NULL) {
          interp = new PythonInterpreter();
          if (!interp->initialize()) {
              std::cout << "ERROR: interp->initialize() failed" << std::endl;
              interp_init_failed = true;
              delete interp;
              interp = NULL;
              return NULL;
          }

          // Setup for conduit python c api (only done once)
          if (!interp->run_script("import conduit")) {
              std::cout << "ERROR: `import conduit` failed" << std::endl;
              interp_init_failed = true;
              delete interp;
              interp = NULL;
              return NULL;
          }

          if (import_conduit() < 0) {
              std::cout << "ERROR: failed to import Conduit Python C-API" << std::endl;
              interp_init_failed = true;
              delete interp;
              interp = NULL;
              return NULL;
          }

          // Mark as successfully initialized
          interp_initialized = true;

          // Turn this on if you want to see every line
          // the python interpreter executes
          //interp->set_echo(true);
      }
      return interp;
  }

  //----------------------------------------------------------------------------
  // Inline helper to get interpreter with minimal overhead
  // This avoids function call when already initialized
  //----------------------------------------------------------------------------
  inline PythonInterpreter *get_interpreter() {
      // Fast path: if already initialized, return directly without function call
      if (interp_initialized) {
          return interp;
      }
      // Slow path: needs initialization
      return init_python_interpreter();
  }

  //----------------------------------------------------------------------------
  // access node passed from fortran to python
  //----------------------------------------------------------------------------

  void conduit_fort_to_py(conduit_node *data, const char *py_script) {
    // Get python interpreter (fast path if already initialized)
    PythonInterpreter *pyintp = get_interpreter();
    if (!pyintp) {
        std::cout << "ERROR: Failed to get Python interpreter" << std::endl;
        return;
    }

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
    // Get python interpreter (fast path if already initialized)
    PythonInterpreter *pyintp = get_interpreter();
    if (!pyintp) {
        std::cout << "ERROR: Failed to get Python interpreter" << std::endl;
        return NULL;
    }

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
    // Get python interpreter (fast path if already initialized)
    PythonInterpreter *pyintp = get_interpreter();
    if (!pyintp) {
        std::cout << "ERROR: Failed to get Python interpreter" << std::endl;
        return NULL;
    }

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
