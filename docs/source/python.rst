.. _python:

******
Python
******

========================================
Plugin Specific Third-party Dependencies
========================================

The Python plugin requires the following third-party libraries/tools to function:

- `Conduit Library <https://llnl-conduit.readthedocs.io/en/latest/>`_

- `Python <https://www.python.org>`_ and other third-party modules that will be used.

.. note::
  All dependencies can be installed using a combination of `Spack <https://spack.io>`_ and Python (i.e., `pip <https://pip.pypa.io/en/stable/#>`_, `Conda <https://conda-forge.org>`_) package managers.

===========================================
Building GeoGate with Python Plugin Support
===========================================

To build the Catalyst plugin, the user needs to provide the ``-DGEOGATE_USE_PYTHON=ON`` CMake option at build time. Otherwise, GeoGate will not build with Python plugin support.

=============================
Runtime Configuration Options
=============================

In GeoGate, each specific plugin comes with its own set of runtime configuration options. For the Python plugin, users can specify the following options:

- **PythonScripts**: This option allows users to provide a list of Python scripts, which can be used to process or generate data. The list can be provided as a double-column-separated list like ``"scriptA.py:scriptB.py"``.

The GeoGate can create its own export state, which is the basic data object utilized by the ESMF library for exchanging data among model components. In this scenario, users must provide the following additional run-time configuration options.

.. note::
  More information about the ESMF State class can be found in the `ESMF reference manual <https://earthsystemmodeling.org/docs/nightly/develop/ESMF_refdoc/node4.html#SECTION04070000000000000000>`_.

- **ExportMeshFile**: This refers to the ESMF mesh file that will be utilized to create the underlying mesh for the ESMF fields attached to the ESMF export state.

.. note::
  ESMF supports a custom unstructured grid file format for describing meshes. This format is more compatible than the SCRIP format with the methods used to create an ESMF Mesh object, which reduces the amount of conversion required to create a Mesh. For more information about the format of the ESMF Mesh file, refer to the `ESMF reference documentation <https://earthsystemmodeling.org/docs/nightly/develop/ESMF_refdoc/node3.html#SECTION03028200000000000000>`_.

- **ExportFields**: This refers to the list of export fields that will be created on the GeoGate export state. You can provide the list in one of two formats: as a double-column-separated list (e.g., "fieldA:fieldB") or as a YAML-formatted list (e.g., [fieldA, fieldB]), which is applicable if you are using ESMX as a driver component.

.. note::
  Unlike ``PythonScripts`` and ``KeepFieldList``, which GeoGate reads as a single string and splits internally, ``ExportFields`` is read through NUOPC's own multi-value attribute API. When using ESMX, this means the value must be given as a YAML list (e.g., ``[fieldA, fieldB]``); a double-column-separated string arrives as a single item and fails with ``is not a StandardName in the NUOPC_FieldDictionary!``.

- **ImportOnExportMesh**: When set to ``.true.``, GeoGate remaps import fields (e.g., ocean fields flowing into an ATM component) from their native mesh to the export mesh before the Python script executes. This ensures that both import and export fields share the same spatial decomposition, which is required for MPI-parallel gather/scatter operations in multi-rank Python scripts.

- **PreloadPythonModules**: A list of Python statements executed **once** at startup, before the first coupling timestep. This is the preferred place to import heavy Python modules—such as ``torch``, ``aurora``, or domain-specific libraries—so that the import cost is paid only once rather than on every coupling step. Statements are joined with newlines and passed to the Python interpreter as a single script block. Example:

  .. code-block:: yaml

    attributes:
      PreloadPythonModules:
        - "import torch"
        - "import numpy as np"
        - "from aurora import AuroraPretrained"

- **KeepFieldList**: A colon-separated list of field names that GeoGate should retain from the import state. When provided, only the named fields are accessible under ``channels/<direction>/<comp>/data/fields/``; all other import fields are discarded. If ``KeepFieldList`` is given, ``RemoveFieldList`` is ignored. Example: ``"So_t:So_omask"``.

- **DebugMode**: When set to ``.true.`` (also accepts ``true`` or ``T``), GeoGate writes each Conduit node to a JSON file on disk and emits additional diagnostic log messages. This is useful for inspecting the exact structure and content of ``my_node`` during development.

=======================
Interacting with Python
=======================

The interaction with the Python script is primarily managed by the Conduit library. The GeoGate generic data component is implemented in Fortran, a programming language that does not support direct interaction with Python. Consequently, any data transferred from GeoGate to Python, or data generated by the Python script that must be sent back to GeoGate, must traverse multiple programming layers written in different languages, including Fortran, C/C++, and Python. 

The Conduit library provides an API that supports Fortran, C/C++, and Python to describe hierarchal data using a JSON-inspired data model and a dynamic API for rapid construction and consumption of hierarchical objects.

To access the nodes provided by the GeoGate, the user needs to use the Conduit Python module that is explained in `The Conduit Python Tutorial <https://llnl-conduit.readthedocs.io/en/latest/tutorial_python.html>`_.

Import: Data consumed by Python
-------------------------------

The Conduit node named ``my_node`` can be accessed from Python to process data provided by the GeoGate. Please refer to the Conduit User Guide for more information about the `Conduit nodes <https://llnl-conduit.readthedocs.io/en/latest/tutorial_python_basics.html#node-basics>`_.

The ``my_node`` includes the following information in a hierarchical way:

.. code-block:: json

  {
    "state": {
      "time_step": "<integer coupling step index>",
      "time_str":  "<ISO-8601 timestamp, e.g. 2021-01-01T00:00:00>"
    },
    "mpi": {
      "comm":     "<Fortran MPI communicator handle (integer)>",
      "localpet": "<rank of this process within the component>",
      "petcount": "<total number of PETs in the component>"
    },
    "channels": {
      "<direction>": {
        "<compname>": {
          "data": {
            "dimension": {
              "n_node":           "<number of mesh nodes>",
              "n_face":           "<number of mesh faces (elements)>",
              "n_max_face_nodes": "<maximum nodes per face>"
            },
            "coords": {
              "values": {
                "face_lon": "<element-center longitudes, 1-D array, size n_face>",
                "face_lat": "<element-center latitudes,  1-D array, size n_face>",
                "node_lon": "<mesh vertex longitudes, 1-D array, size n_node>",
                "node_lat": "<mesh vertex latitudes,  1-D array, size n_node>"
              }
            },
            "topologies": {
              "mesh": {
                "elements": {
                  "n_nodes_per_face":       "<nodes-per-element count array>",
                  "face_node_connectivity": "<face-to-node index array>"
                }
              }
            },
            "mask": {
              "values": {
                "face_mask": "<element mask (0=unmasked, 1=masked), size n_face>",
                "node_mask": "<node mask   (0=unmasked, 1=masked), size n_node>"
              }
            },
            "fields": {
              "<fieldname>": {
                "values":      "<1-D float64 array, size n_face or n_node>",
                "association": "<'face' if size == n_face, 'node' if size == n_node>"
              }
            }
          }
        }
      }
    }
  }

The ``<direction>`` key in ``channels`` takes one of the following values:

- ``import`` — fields flowing into the component (e.g., ocean fields received by ATM).
- ``import_on_export_grid`` — the same import fields remapped onto the export mesh. This channel is only present when ``ImportOnExportMesh: .true.`` is set.
- ``export`` — fields produced by this component.

The ``association`` tag on each field indicates where it is defined on the mesh:

- ``"face"`` — the field is defined at element centers; the values array has ``n_face`` elements. Most CMEPS standard fields use this association.
- ``"node"`` — the field is defined at mesh vertices; the values array has ``n_node`` elements.

.. note::
  For some mesh types (e.g., a regular 721×1440 latitude–longitude grid), ``node_lon`` / ``node_lat`` contain an extra south-pole row and have size ``n_node = 722 × 1440``, while field arrays have size ``n_face = 721 × 1440``. When computing per-rank element counts for MPI gather/scatter operations, always derive counts from an actual field array—never from coordinate arrays—to avoid off-by-one errors.

Export: Data produced by Python
-------------------------------

The Conduit node named `my_node_return` can be accessed from Python to provide data to GeoGate and update the fields in its export state. To access a specific field in the GeoGate export state, the following example statement ``my_node_return['data/fields/fieldA/values']`` can be used.

.. note::
  The name of the fields used in the ``my_node_return['data/fields/FIELD_NAME/values']`` statement needs to match with the field names given in the ``ExportFields`` runtime configuration option.

Script Caching and Performance
-------------------------------

GeoGate maintains a persistent Python interpreter for the lifetime of the model run. Two features reduce the per-timestep overhead of executing Python scripts significantly.

**Script compilation cache**

The first time a script is executed, GeoGate reads the file from disk and compiles it to a Python code object using ``Py_CompileString()``. The compiled object is stored in an in-memory cache keyed by the script file path. On every subsequent coupling timestep, GeoGate retrieves the cached code object and calls ``PyEval_EvalCode()`` directly, skipping both the file read and the compilation step entirely. The cache is released when the interpreter shuts down at the end of the run.

This means that adding ``import`` statements inside the script body carries zero compilation overhead after the first call, but the ``import`` overhead itself is still incurred on every call unless the module is already in ``sys.modules``. Use ``PreloadPythonModules`` to front-load expensive imports.

**Global dictionary persistence**

The Python interpreter's global namespace (the ``__main__`` module dictionary) persists across all coupling timestep calls. Any variable, function, or object assigned at module level in a script—for example a loaded model object stored in ``globals()``—is still present when the script executes again on the next timestep. This is the mechanism that makes the persistent-server pattern work: a server process imports torch and loads model weights once, then handles requests in a loop without reloading.

Scripts should guard one-time initialization with an explicit flag:

.. code-block:: python

  if 'aurora_model' not in globals():
      import torch
      from aurora import AuroraPretrained
      aurora_model = AuroraPretrained(...)
      aurora_model.load_checkpoint_local('weights.pt', strict=False)
      aurora_model.eval()

===========
Limitations
===========

Running Python scripts in parallel can be challenging. The simplest approach is to allocate a single core to the GeoGate component (``petList: 0`` in ``esmxRun.yaml``), which runs the script on one process with full ownership of all field data.

MPI-parallel execution
-----------------------

GeoGate exposes the component's MPI communicator through ``my_node`` so that Python scripts can participate in MPI collectives:

.. code-block:: python

  from mpi4py import MPI

  comm    = MPI.Comm.f2py(int(my_node["mpi/comm"]))
  rank    = comm.Get_rank()
  size    = comm.Get_size()

**ESMF Mesh and 1-D field arrays**

GeoGate uses an ESMF Mesh object internally to represent the grid geometry and topology of each component. Because ESMF fields defined on unstructured meshes are stored in a flat 1-D array (one value per mesh element or mesh node), all field arrays exposed to Python through the Conduit node are **always one-dimensional**, regardless of the logical shape of the underlying grid. Reshaping to a 2-D or 3-D array for further processing must be done explicitly in the Python script once the global domain is assembled.

Each rank's script invocation receives only the local domain slice of each field. A common pattern is to designate rank 0 as the coordinator: it gathers field data from all ranks via ``Gatherv``, performs the computation (or delegates it to a persistent background server over a Unix socket), and then distributes the results back to all ranks via ``Scatterv``.

**Building the scatter layout: field_counts and field_displs**

Before any collective operation, every rank must know how many elements each rank owns. The ``field_counts`` array holds the local element count for each rank and ``field_displs`` holds the displacement (starting offset) of each rank's data in the global flat buffer. These are computed with a single ``Allgather`` call using an actual field array as the reference — never from coordinate arrays, which may contain extra rows (see the note above on south-pole vertices):

.. code-block:: python

  import numpy as np

  # Read any field to determine the local element count for this rank.
  local_field = np.asarray(my_channel['data/fields/fieldA/values'])
  local_n     = np.array([len(local_field)], dtype=np.int32)

  field_counts = np.empty(size, dtype=np.int32)
  comm.Allgather(local_n, field_counts)

  # field_displs[i] is the start index of rank i's data in the global buffer.
  field_displs = np.concatenate([[0], np.cumsum(field_counts[:-1])]).astype(np.int32)
  total_n      = int(np.sum(field_counts))

**Gathering a field from all ranks to root (Gatherv)**

Once ``field_counts`` and ``field_displs`` are known, use ``Gatherv`` to assemble the full global field on rank 0:

.. code-block:: python

  local_data  = np.ascontiguousarray(local_field, dtype=np.float64)
  global_data = np.empty(total_n, dtype=np.float64) if rank == 0 else None

  comm.Gatherv(
      local_data,
      [global_data, field_counts, field_displs, MPI.DOUBLE],
      root=0,
  )

  # Rank 0 now holds the full 1-D global array.  Reshape as needed, e.g.:
  if rank == 0:
      global_2d = global_data.reshape((ny, nx))

**Scattering a result field from root to all ranks (Scatterv)**

After processing on rank 0, distribute the result back to each rank's local slice:

.. code-block:: python

  local_result = np.empty(int(field_counts[rank]), dtype=np.float64)

  comm.Scatterv(
      [np.ascontiguousarray(global_result, dtype=np.float64),
       field_counts, field_displs, MPI.DOUBLE] if rank == 0 else None,
      local_result,
      root=0,
  )

  # Each rank now holds its local slice of the result field.
  my_node_return['data/fields/fieldA/values'] = local_result

.. warning::
  The code snippets above illustrate a general gather/scatter pattern and are
  provided as a starting point only. The exact implementation — how
  ``field_counts`` and ``field_displs`` are computed, how the global array is
  reordered before scatter, and which fields are gathered or scattered — is
  **application-specific** and depends on the mesh type, the MPI decomposition
  used by the model, and the requirements of the processing step. These
  examples must be carefully adapted to each use case and should not be used
  verbatim without verifying that the assumptions hold for your configuration.

When the ATM component runs on multiple PETs and needs to access ocean fields that are natively on the OCN mesh, set ``ImportOnExportMesh: .true.`` to have CMEPS remap the ocean fields onto the ATM export mesh before the Python script runs. This guarantees that import and export fields share the same MPI decomposition, so the same ``field_counts`` and ``field_displs`` arrays can be reused for both the gather (ocean → script) and scatter (script → ATM) steps.

Persistent server pattern
--------------------------

For workloads that require heavy Python dependencies (e.g., PyTorch-based AI models), the recommended approach is a **persistent server**:

1. Start a single-process Python server **before** the ESMX/ESMF job that loads all heavy modules and model weights once.
2. The GeoGate Python script (the client) connects to the server over a node-local Unix socket (in ``/tmp``, not on Lustre) on each coupling timestep, sends a lightweight request, and receives the result.
3. The server is shut down after the ESMX job completes.

This pattern avoids both the Lustre metadata overhead of Python module imports (which can issue thousands of ``stat()`` calls per ``import`` statement) and the GPU model-load cost on every coupling step. The Unix socket path should be set via an environment variable in the job script and read by both the server and client scripts.

======================
Example Python Scripts
======================

To save Conduit nodes provided by the GeoGate, the following simple Python script can be used:

.. code-block:: python

  import conduit
  from conduit import Node

  # Arguments
  channel = "atm"
  debug = True

  # Access to channel data
  my_channel = my_node["channels/{}".format(channel)]

  # Save the data in the channel
  if debug:
      my_channel.save('my_channel')

.. note:
  In this case, the script will just save the data found in the ``atm`` channel. To save data in all the channels, the user can write the ``channels`` node rather than ``channels/atm``.

The following Python code can be used to read node data from a file:

.. code-block:: python

  from conduit import Node

  # Arguments
  channel = "atm"
  data_dir = './data'

  my_channel = Node()
  my_channel.load(os.path.join(data_dir, 'my_channel_{}".format(channel)))

The following example creates plots using data provided by the GeoGate:

.. code-block:: python

  import os
  import conduit
  from conduit import Node
  import xarray as xr
  import cartopy.crs as ccrs
  import matplotlib as mpl
  import matplotlib.pyplot as plt

  # Arguments
  channel = "ocn"
  debug = True
  nx_ocn = 1440
  ny_ocn = 721

  # Access to channel data
  my_channel = my_node["channels/{}".format(channel)]

  ds = xr.Dataset(
      data_vars = {
          "mask":  (["lat", "lon"], my_channel['data/mask/values/face_mask'].reshape((ny_ocn,nx_ocn))),
          "So_t":  (["lat", "lon"], my_channel['data/fields/So_t/values'].reshape((ny_ocn,nx_ocn)))
      },
      coords = {
          "lon": (["lat", "lon"], my_channel['data/coords/values/face_lon'].reshape((ny_ocn,nx_ocn))),
          "lat": (["lat", "lon"], my_channel['data/coords/values/face_lat'].reshape((ny_ocn,nx_ocn))),
      }
  )

  fig, axis = plt.subplots(1, 1, subplot_kw=dict(projection=ccrs.PlateCarree(central_longitude=0.0, globe=None)))

  ds["So_t"].where(ds.mask == 0).plot(
      ax=axis,
      transform=ccrs.PlateCarree(),
      cbar_kwargs={"orientation": "horizontal", "shrink": 0.7},
      robust=True,
  )

  axis.coastlines()

  fig, axis = plt.subplots(1, 1, subplot_kw=dict(projection=ccrs.Orthographic(-90, 30)))

  ds["So_t"].where(ds.mask == 0).plot(
      ax=axis,
      transform=ccrs.PlateCarree(),
      cbar_kwargs={"orientation": "horizontal", "shrink": 0.7},
      robust=True,
  )

  axis.coastlines()

.. note:
  The GeoGate component utilizes a generic ESMF mesh representation to define its geometry and topology. As a result, the import and export fields within the component are stored in a one-dimensional array, or a two-dimensional array if dealing with three-dimensional fields. The variables ``nx_ocn`` and ``ny_ocn`` defined in the Python script are employed to convert the one-dimensional data provided by the GeoGate into their two-dimensional representation.
