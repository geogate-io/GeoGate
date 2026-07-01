.. _ftorch:

******
FTorch
******

`FTorch <https://github.com/Cambridge-ICCS/FTorch>`_ provides Fortran bindings for `PyTorch <https://pytorch.org>`_, allowing pre-trained TorchScript models to be loaded and run for inference directly from Fortran without going through an embedded Python interpreter. The generic FTorch plugin is designed to provide machine-learning model inference capability to the fully coupled Earth system modeling applications or individual model components that use `ESMF (Earth System Modeling Framework) <https://earthsystemmodeling.org/doc/>`_ and `NUOPC (National Unified Operational Prediction Capability) Layer <https://earthsystemmodeling.org/nuopc/>`_.

========================================
Plugin Specific Third-party Dependencies
========================================

The FTorch plugin requires the following third-party libraries/tools to function:

- `FTorch <https://github.com/Cambridge-ICCS/FTorch>`_
- `LibTorch (PyTorch C++ distribution) <https://pytorch.org/get-started/locally/>`_, which is a dependency of FTorch

.. note::
  All dependencies can be installed using a combination of `Spack <https://spack.io>`_ and Python (i.e., `pip <https://pip.pypa.io/en/stable/#>`_, `Conda <https://conda-forge.org>`_) package managers. FTorch can also be built directly from source, following the instructions in its `documentation <https://cambridge-iccs.github.io/FTorch/>`_.

============================================
Building GeoGate with FTorch Plugin Support
============================================

To build the FTorch plugin, the user needs to provide the ``-DGEOGATE_USE_FTORCH=ON`` CMake option at build time, together with a discoverable FTorch installation (e.g. by setting ``CMAKE_PREFIX_PATH`` or ``FTorch_DIR`` to the FTorch install location). Otherwise, GeoGate will not build with FTorch plugin support.

=============================
Runtime Configuration Options
=============================

In GeoGate, each specific plugin comes with its own set of runtime configuration options. For the FTorch plugin, users can specify the following options:

- **FtorchModelFile:** Path to the TorchScript model file (i.e. a model exported with ``torch.jit.script`` or ``torch.jit.trace``) that will be loaded and used for inference.

- **FtorchDevice:** The device used to run the model, either ``cpu`` or ``cuda``. This option is optional and defaults to ``cpu``.

- **FtorchDeviceIndex:** The device index used when ``FtorchDevice`` is set to ``cuda``. This option is optional and defaults to ``0``.

- **FtorchInputFields:** The list of import field names that are passed to the model as input tensors, in the exact order expected by the model. The list can be provided as a double-column-separated list like ``"fieldA:fieldB"``. Each name needs to match a field found in one of the field bundles received from a connected component.

- **FtorchOutputFields:** The list of export field names that are filled with the tensors produced by the model, in the exact order returned by the model. The list can be provided as a double-column-separated list like ``"fieldC:fieldD"``. Each name needs to match an entry already created in the GeoGate export state, as described below.

The GeoGate can create its own export state, which is the basic data object utilized by the ESMF library for exchanging data among model components. Since the FTorch plugin writes its output directly into the export state, users must provide the following additional run-time configuration options.

.. note::
  More information about the ESMF State class can be found in the `ESMF reference manual <https://earthsystemmodeling.org/docs/nightly/develop/ESMF_refdoc/node4.html#SECTION04070000000000000000>`_.

- ExportMeshFile: This refers to the ESMF mesh file that will be utilized to create the underlying mesh for the ESMF fields attached to the ESMF export state.

- ExportFields: This refers to the list of export fields that will be created on the GeoGate export state, and needs to include all the field names listed in ``FtorchOutputFields``. You can provide the list in one of two formats: as a double-column-separated list (e.g., "fieldA:fieldB") or as a YAML-formatted list (e.g., [fieldA, fieldB]), which is applicable if you are using ESMX as a driver component.

=======================
Interacting with FTorch
=======================

Unlike the Python plugin, the FTorch plugin does not require an intermediate data description layer (e.g. Conduit) since FTorch provides a direct Fortran interface to LibTorch. For each connected component, the import fields are one-dimensional, double-precision arrays defined on the GeoGate mesh. The plugin builds one input tensor per entry in ``FtorchInputFields`` by wrapping the underlying ESMF field data array, without copying it, and feeds these tensors to the loaded TorchScript model. The tensors returned by the model are written into the export field arrays named in ``FtorchOutputFields`` so that other connected components can use the values through the GeoGate export state.

.. note::
  Because tensors are built directly on top of the underlying field memory, the order and shape of ``FtorchInputFields``/``FtorchOutputFields`` need to be consistent with what the TorchScript model expects. Any reshaping, normalization, or unit conversion needs to be incorporated into the exported TorchScript model itself, or applied to the field data beforehand using another GeoGate plugin or model component.

===========
Limitations
===========

The FTorch plugin currently loads a single TorchScript model and assumes a single forward pass per call, with one tensor per input/output field. Running multiple models, or models that require batching, looping, or auxiliary scalar inputs (e.g., time), is not yet supported and would require extending the plugin.

Multi-GPU configurations are supported by FTorch itself, but the GeoGate FTorch plugin currently only exposes a single device type and device index per component instance.
