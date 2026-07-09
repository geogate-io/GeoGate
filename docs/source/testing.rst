.. _testing:

*******************************
Automated Testing
*******************************

GeoGate uses `GitHub Actions <https://docs.github.com/en/actions>`_ to build the Catalyst and Python plugins from scratch against a `Spack <https://spack.io>`_-managed toolchain, run a small ESMX-driven coupled case (DATM + DOCN + GeoGate), and upload the run's logs/output as artifacts. The workflow definitions live under ``.github/workflows``, with the composite build/run steps factored out into ``.github/actions``.

=========================================
GitHub Actions Workflows
=========================================

- **test_catalyst_osmesa.yaml** / **test_catalyst_egl.yaml**: build GeoGate with the :doc:`Catalyst <catalyst>` plugin, one per headless GL backend. Both run the same ``config/catalyst/esmxRun.yaml``, which visualizes DATM/DOCN fields with the Catalyst scripts in that directory.

- **test_python.yaml**: builds GeoGate with the :doc:`Python <python>` plugin instead, and runs ``config/python/esmxRun.yaml``: a two-instance GeoGate pipeline (``COP1 -> COP2``) that exercises multiple incoming connections, a two-way Python script with an MPI-aware spatial reduction, and a one-way Python script, all in one case.

=========================================
Composite Actions Pipeline
=========================================

The workflows share four composite actions under ``.github/actions``, run in this order:

1. ``create_env``: builds/caches the Spack environment (ESMF, Conduit, libcatalyst, ParaView, all with ``+python``). Workflows that use the same versions and GL backend share the same cache.

2. ``install_geogate``: configures and builds GeoGate itself, with ``use_python``/``use_catalyst`` toggling which plugin(s) get compiled in.

3. ``install_cdeps``: builds the DATM/DOCN data components GeoGate couples against.

4. ``case_run``: assembles the ESMX executable, links the config's ``esmxRun.yaml``, and runs it with ``mpirun``. Takes ``config_dir`` (required) to pick which ``config/<config_dir>/`` to use, and ``esmx_np`` (default ``6``) for the PET count.

.. note::
  ``test_python.yaml`` adds one extra step between ``install_geogate`` and ``install_cdeps`` to install ``matplotlib``/``mpi4py`` into the same Spack-provided Python that GeoGate's embedded interpreter loads. After activating the Spack environment, the first ``python3`` on ``PATH`` is Spack's own internal bootstrap interpreter, not that Python, so its install prefix is resolved explicitly instead.

=========================================
Configuration Layout
=========================================

.. code-block:: text

  config/
  ├── shared/     # DATM/DOCN runtime config used by every test
  ├── catalyst/   # esmxRun.yaml + pv_*.py for the two Catalyst workflows
  └── python/     # esmxRun.yaml + geogate_modify.py/geogate_plot.py for the Python workflow

``case_run``'s ``config_dir`` input picks the test-specific directory; ``shared/`` files are always symlinked in regardless of which test is running. Every ``esmxRun.yaml`` is named the same across directories -- the directory is what disambiguates them, not the filename.
