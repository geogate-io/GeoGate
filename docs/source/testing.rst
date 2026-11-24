.. _testing:

*******************************
Automated Testing
*******************************

GeoGate uses `GitHub Actions <https://docs.github.com/en/actions>`_ to build its plugins from scratch against a `Spack <https://spack.io>`_-managed toolchain, run a small ESMX-driven coupled case, and upload the run's logs/output as artifacts. The workflow definitions live under ``.github/workflows``, with the composite build/run steps factored out into ``.github/actions``.

=========================================
GitHub Actions Workflows
=========================================

- **test_catalyst_osmesa.yaml** / **test_catalyst_egl.yaml**: build GeoGate with the :doc:`Catalyst <catalyst>` plugin, one per headless GL backend. Both run the same ``config/catalyst/esmxRun.yaml``, which visualizes DATM/DOCN fields with the Catalyst scripts in that directory.

- **test_python.yaml**: builds GeoGate with the :doc:`Python <python>` plugin instead, and runs ``config/python/esmxRun.yaml``: a two-instance GeoGate pipeline (``COP1 -> COP2``) that exercises multiple incoming connections, a two-way Python script with an MPI-aware spatial reduction, and a one-way Python script, all in one case.

- **test_hydro.yaml**: builds GeoGate with the :doc:`Hydro <hydro>` plugin instead, and runs ``config/hydro/esmxRun.yaml``: a two-instance pipeline (``ROF -> OCN``) where ``ROF`` is a real Hydro plugin instance (reading 3 hours of real NWM Retrospective v3.0 ``CHRTOUT`` data, mapped onto a SCHISM mesh's elements via ``export_element_map_file`` -- see :doc:`Hydro: Mode 3 <hydro>`) and ``OCN`` is a plain :doc:`IO plugin <io>` consumer that writes the redistributed field to VTK from the import side. Unlike the other two workflows, it does **not** use ``install_cdeps``/``case_run`` (see below) and has its own data-fetching step, ``fetch_hydro_data``.

=========================================
Composite Actions Pipeline
=========================================

``test_catalyst_*``/``test_python`` share four composite actions under ``.github/actions``, run in this order:

1. ``create_env``: builds/caches the Spack environment (ESMF, Conduit, libcatalyst, ParaView, all with ``+python``, plus ``+external-parallelio`` for PIO). Workflows that use the same versions and GL backend share the same cache.

2. ``install_geogate``: configures and builds GeoGate itself, with ``use_python``/``use_catalyst``/``use_hydro`` toggling which plugin(s) get compiled in. ``use_hydro`` additionally loads the ``parallelio`` Spack module (built as an ``esmf +external-parallelio`` dependency) and points ``PIO_DIR`` at it, so the Hydro plugin's ``find_package(PIO REQUIRED COMPONENTS Fortran)`` succeeds -- confirmed working as of this writing, on the first try, with no further CMake hints needed.

3. ``install_cdeps``: builds the DATM/DOCN data components GeoGate couples against.

4. ``case_run``: assembles the ESMX executable, links the config's ``esmxRun.yaml``, and runs it with ``mpirun``. Takes ``config_dir`` (required) to pick which ``config/<config_dir>/`` to use, and ``esmx_np`` (default ``6``) for the PET count.

.. note::
  ``test_python.yaml`` adds one extra step between ``install_geogate`` and ``install_cdeps`` to install ``matplotlib``/``mpi4py`` into the same Spack-provided Python that GeoGate's embedded interpreter loads. After activating the Spack environment, the first ``python3`` on ``PATH`` is Spack's own internal bootstrap interpreter, not that Python, so its install prefix is resolved explicitly instead.

**test_hydro.yaml's own pipeline.** It reuses ``create_env`` and ``install_geogate`` (with ``use_python: OFF``, ``use_catalyst: OFF``, ``use_hydro: ON``) but skips ``install_cdeps`` entirely -- the Hydro plugin doesn't use CDEPS/DATM/DOCN -- and does not call ``case_run``, since that action's ``esmxBuild.yaml`` generation and "Prepare Run Directory" step hardcode DATM/DOCN component blocks the Hydro test has no use for. Instead it inlines the equivalent, DATM/DOCN-free steps directly:

1. ``fetch_hydro_data`` (new composite action): restores or downloads/caches the 4 ``CHRTOUT`` files (via ``hydro/tools/download_nwm_retrospective.py``) and ``RouteLink_CONUS.nc``. The latter is one member of a much larger (~4.7GB) tarball (`NOAA/NOHRSC's NWM parameter archive <https://www.nohrsc.noaa.gov/owp_files/nwm/nwm_parameters/NWM_parameter_files_v3.0.tar.gz>`_); rather than downloading the whole thing, ``curl ... | tar -xzf - v3.0_par/RouteLink_CONUS.nc`` streams and extracts just that one file (~90s), and only the extracted 269MB file is cached, never the tarball. Both caches use a fixed key (unrelated to the Spack dependency cache), so they persist independently of Spack/ESMF version bumps.
2. A trimmed ``ESMX_Builder``/``esmxBuild.yaml`` step with only the ``geogate`` component block (no ``datm``/``docn``).
3. Symlinking ``config/hydro/``'s ``hydro_config_ci.yaml``/``mapping.txt``/``hgrid_ESMF.nc`` directly into the run directory, then the same ``mpirun`` invocation as ``case_run``.
4. A plotting/validation step: ``hydro/tools/plot_export_map.py --mapping-file mapping.txt`` against ``OCN``'s VTK output -- this doubles as the plot-generation step and, since the script exits non-zero on a correctness mismatch (duplicate element ownership, or a mapping-file/non-fill-count mismatch) by default, as the test's actual pass/fail gate, not just "did the run crash."

.. important::
  **Artifact uploads and colons in filenames.** GeoGate's VTK/CSV writers (:doc:`IO plugin <io>`'s ``FBWriteVTK``/``FBWriteCSV``, and the Hydro plugin's own export-side dump) embed an ISO timestamp directly in the output filename (e.g. ``..._2021-06-01T00:00:00_...``). ``actions/upload-artifact`` rejects colons outright (an NTFS-safety restriction) and fails the *entire* upload step if even one matched file has one -- this can look exactly like a real test failure (no artifacts at all, including no logs to diagnose it) when it's actually just the upload step. ``test_hydro.yaml`` works around this with a "Sanitize Output Filenames for Upload" step (``tr ':' '-'``, ``if: always()``) placed after plotting (which needs the original colon-containing names to match its filename parser) but before ``upload-artifact``. Any future workflow that uploads this plugin's raw VTK/CSV output needs the same workaround.

=========================================
Configuration Layout
=========================================

.. code-block:: text

  config/
  ├── shared/     # DATM/DOCN runtime config used by the Catalyst/Python tests
  ├── catalyst/   # esmxRun.yaml + pv_*.py for the two Catalyst workflows
  ├── python/     # esmxRun.yaml + geogate_modify.py/geogate_plot.py for the Python workflow
  └── hydro/      # esmxRun.yaml + hydro_config_ci.yaml + mapping.txt + hgrid_ESMF.nc for the Hydro workflow

``case_run``'s ``config_dir`` input picks the test-specific directory for the Catalyst/Python tests; ``shared/`` files are always symlinked in regardless of which of those two is running. ``test_hydro.yaml`` symlinks its own ``config/hydro/`` files directly (see above) rather than going through ``case_run``. Every ``esmxRun.yaml`` is named the same across directories -- the directory is what disambiguates them, not the filename.
