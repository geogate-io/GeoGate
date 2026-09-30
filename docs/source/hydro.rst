.. _hydro:

*****
Hydro
*****

The Hydro plugin ingests point coordinates from a configured NetCDF file and builds a parallel-decomposed ``ESMF_LocStream`` from it, with one ``ESMF_Field`` per configured name on that LocStream. The coordinate file's id/lat/lon (and optional point-reordering) variable names all come from the plugin's YAML config, so the plugin itself is data-source agnostic; the examples below use the National Water Model (NWM) ``RouteLink`` file as one concrete data source, but any similarly-shaped NetCDF file (a 1-D id variable plus 1-D lat/lon variables sharing the same dimension) can be configured instead.

.. note::
  The plugin ingests real, time-varying data (see "Data Ingest" below), but there is no destination-Mesh regrid or NUOPC export-state realization yet — the LocStream and its fields are built and filled, but not yet connected to another component. Of the four ``time_selection`` modes, only ``linear`` is not yet implemented (see "Runtime Configuration Options" below).

========================================
Plugin Specific Third-party Dependencies
========================================

The Hydro plugin requires the following third-party libraries to function:

- `NetCDF-Fortran <https://docs.unidata.ucar.edu/netcdf-fortran/current/>`_
- `ParallelIO (PIO) <https://github.com/NCAR/ParallelIO>`_, version 2.6.x

.. note::
  Both are typically already available through a spack-stack environment on HPC systems that also build the wider UFS Weather Model.

==========================================
Building GeoGate with Hydro Plugin Support
==========================================

To build the Hydro plugin, provide the ``-DGEOGATE_USE_HYDRO=ON`` CMake option at build time. Otherwise, GeoGate builds a void phase that logs an error and returns a failure code if invoked, and neither NetCDF-Fortran nor PIO is required.

When built as part of a larger CMake project (e.g. as a subdirectory of ufs-weather-model) that already calls ``find_package(PIO)`` itself, the plugin reuses the resulting ``PIO::PIO_Fortran`` target rather than re-running ``FindPIO.cmake``, which would otherwise fail trying to recreate its ``ALIAS`` targets.

=============================
Runtime Configuration Options
=============================

The plugin reads a small YAML configuration file (default path ``hydro_config.yaml``, overridable via the NUOPC component attribute ``HydroConfigFile``) via ``ESMF_HConfig``. Example, using the NWM RouteLink file as the data source:

.. code-block:: yaml

  hydro:
    coord_file: "v3.0_par/RouteLink_CONUS.nc"
    id_variable: "link"
    lat_variable: "lat"
    lon_variable: "lon"
    order_variable: "ascendingIndex"   # optional
    data_files:
      - "nwm.t00z.medium_range.channel_rt_1.f001.conus.nc"
      - "nwm.t00z.medium_range.channel_rt_1.f002.conus.nc"
    time_variable: "time"
    time_selection: nearest  # optional, default "nearest"; or "lower", "upper", "linear" (not yet implemented)
    variables:
      - streamflow
      - velocity

- **coord_file**: path to the NetCDF file supplying point coordinates.
- **id_variable**: name of the 1-D variable giving each point's unique integer id.
- **lat_variable** / **lon_variable**: names of the 1-D latitude/longitude variables, sharing the same dimension as ``id_variable``.
- **order_variable** (optional): name of a variable giving, for each target-order point, its 0-based on-disk record in ``coord_file``. Omit this key entirely when the coordinate file's on-disk order should be used as the target order as-is (the common case for a new/generic data source); see "Parallel Decomposition Implementation" below for when this is actually needed.
- **data_files**: list of one or more data files to ingest, all sharing ``coord_file``'s point ordering and the same variable schema. A file may hold one or more time records.
- **time_variable**: name of the time coordinate variable present in each data file. Its CF ``units`` attribute (e.g. ``"hours since 2000-01-01 00:00:00"``) is parsed to get that file's actual valid time(s) — no fixed time resolution or reference epoch is assumed.
- **time_selection** (optional, default ``nearest``): how to pick a ``data_files`` value for the model's current time.

  - ``nearest``: the record closest in time to the model's current time. Switches at the midpoint between two records' valid times; an exact tie is broken in favor of the later record in ``data_files`` (round-half-up), so the switch lands exactly on the midpoint rather than one coupling step after it.
  - ``lower``: the most recent record at-or-before the current time. Holds it until the model clock actually reaches the next record's own valid time — never switches early, never extrapolates (errors if the current time precedes every configured record).
  - ``upper``: the nearest upcoming record at-or-after the current time — the mirror image of ``lower`` (errors if the current time is after every configured record).
  - ``linear``: interpolate between the ``lower`` and ``upper`` records. Accepted by the config schema but not yet implemented — the plugin errors out at startup if selected.
- **variables**: list of field names to create on the hydro LocStream and read from ``data_files``.

=====================================
Parallel Decomposition Implementation
=====================================

Some data sources' on-disk record order does not match the order the plugin ultimately wants to use as its "target" (decomposition) order — the NWM RouteLink file is a concrete example: its own on-disk order (sorted by its ``link`` variable) is a **different permutation** of the same points than the ascending/``feature_id`` order shared by every NWM forecast output (``channel_rt``) file (verified to match exactly for the CONUS domain: RouteLink ``link`` sorted ascending == ``channel_rt`` ``feature_id``, which is the order this plugin uses as its target when configured with ``order_variable: ascendingIndex``). When that happens, a given PET's contiguous block of the target order corresponds to scattered, non-contiguous positions in the file's on-disk order — not something a plain NetCDF hyperslab read can express. When a data source's on-disk order already *is* the desired target order, ``order_variable`` can simply be omitted and this reordering step becomes a no-op (identity mapping).

The plugin resolves this generically as follows:

1. Every PET reads the full, optional reorder-index variable (``geogate_hydro_io``: ``HydroReadReorderIndex``) if one is configured (small, one-time; e.g. ~11MB for CONUS RouteLink), or otherwise builds the identity mapping. ``reorderIndex(i)`` (0-based) gives the on-disk record for the *i*-th point in target order.
2. An ``ESMF_DistGrid`` sized to the true global point count is built, using ESMF's default decomposition across the component's PETs. Each PET queries its own local (target-order) global sequence indices from it.
3. Those local indices are translated through ``reorderIndex`` into the scattered on-disk positions PIO needs to fetch (a "compdof" array), and ParallelIO's explicit decomposition-map read (``geogate_hydro_pio``: ``PioReadCoords``) fetches just this PET's id/lat/lon values directly — only one PET actually touches the filesystem (``num_iotasks=1``); PIO's ``SUBSET`` rearranger ships each PET's slice to it over MPI. This avoids replicating the full (large) coordinate arrays on every PET.
4. The ``ESMF_LocStream`` is created directly from that same ``ESMF_DistGrid`` (``ESMF_LocStreamCreate(distgrid=...)``), so its decomposition matches PIO's read exactly.

`ESMF's own file I/O (ESMF_FieldRead) <https://earthsystemmodeling.org/docs/release/latest/ESMF_refdoc/node5.html>`_ was considered instead of PIO, but it aligns a Field's ``DistGrid`` index range directly against a file's on-disk variable layout and has no notion of a reorder-index permutation — it would face the same on-disk-order mismatch as a plain hyperslab read whenever ``order_variable`` is actually needed.

===========
Data Ingest
===========

Unlike the coordinate file, ``data_files`` entries are assumed to already be in the plugin's target order (no ``order_variable``-style reordering is applied to them) — this matches NWM ``channel_rt``'s on-disk ``feature_id`` order, which was verified to equal RouteLink ``link`` sorted ascending. A data source whose data files need their own reordering isn't supported yet.

``geogate_hydro_time``: ``HydroReadFileTimes`` gets each valid time from ``time_variable``'s own CF ``units`` attribute, of the form ``"<period> since <YYYY-MM-DD[ HH:MM:SS][Z|UTC]>"`` (a ``T`` ISO-8601 date/time separator is also accepted in place of a space). The period keyword (``seconds``/``minutes``/``hours``/``days``, including short forms like ``sec``/``hr``) and the reference date/time are both parsed from the attribute itself — nothing is hardcoded, so a data source using a different period or epoch than NWM's ``"minutes since 1970-01-01 00:00:00 UTC"`` needs no code changes.

Each call to ``geogate_phases_hydro_run``:

1. Reads the model clock's current time (``NUOPC_ModelGet`` + ``ESMF_ClockGet``).
2. Scans the flat list of every ``data_files`` entry's valid time(s) (built once at init, via ``geogate_hydro_time``: ``HydroReadFileTimes``, one entry per time record — so a file with multiple time records contributes multiple entries) and picks a single one per the configured ``time_selection`` (``FindNearestTime``/``FindLowerTime``/``FindUpperTime`` in ``geogate_phases_hydro.F90``; see "Runtime Configuration Options" above for what each does).
3. Only if that selection changed since the last call, re-reads every configured variable (``geogate_hydro_pio``: ``PioReadVariable``) from the selected file/record and refills the fields — this avoids redundant re-reads when the coupling interval is finer than the data's own time spacing.

**Multiple time records per file.** A data variable's on-disk rank determines whether a time record needs to be explicitly selected: if it has only the point dimension (``ndims == 1``, e.g. today's NWM ``channel_rt`` files, where ``streamflow(feature_id)`` carries no time dimension at all — each file holds exactly one implicit record), the read proceeds as a plain decomposed read, same as coordinates. If it has more than one dimension (``ndims > 1``, e.g. a hypothetical ``streamflow(time, feature_id)``), ``PIO_setframe`` selects the correct time record before the decomposed read. This is why the read is skipped for ``ndims == 1``: calling ``PIO_setframe`` on a variable with no record dimension at all is not something the reviewed PIO source documents cleanly one way or the other, so it's avoided instead of assumed safe.

**Packed/scaled variables.** Each configured variable's on-disk type, rank, and CF packing attributes (``scale_factor``, ``add_offset``, ``_FillValue``/``missing_value``) are read once (``geogate_hydro_io``: ``HydroReadVarMeta``, from ``data_files(1)`` only) and assumed identical across all ``data_files`` — consistent with the "multiple files following each other" use case, but a data source whose packing changes file-to-file isn't supported. Raw values are unpacked as ``value = raw*scale_factor + add_offset``, with fill/missing cells mapped to GeoGate's own fill sentinel (``geogate_share::fillValue``, ``1.0d20``).

===============
Build Gotchas
===============

**Real-kind promotion (-real-size 64).** This project's build adds ``-real-size 64`` to ``CMAKE_Fortran_FLAGS`` globally (see ``ufs-weather-model/cmake/Intel.cmake``), which silently promotes any bare, unspecified-kind ``real`` declaration to 8 bytes everywhere, including inside GeoGate's own subdirectory. Coordinate lat/lon variables are typically on-disk 4-byte ``float``, and ``geogate_hydro_pio.F90`` tells PIO's ``io_desc_t`` to expect 4-byte elements (``basepiotype=PIO_real``); a bare ``real`` read buffer under that flag is actually 8-byte, so the compiler binds ``PIO_read_darray``'s generic to its double-precision specific while the ``io_desc_t`` still expects 4-byte elements, corrupting every value read. The fix is declaring those buffers with an explicit ``real(kind=4)`` (immune to ``-real-size``, since that flag only affects the *default* kind), which is what the current code does. If new real-valued PIO/NetCDF reads are added, give their raw on-disk-matching buffers an explicit kind too rather than bare ``real``.

**ESMF_HConfig is function-based.** ``ESMF_HConfigAsString``/``AsLogical``/``GetSize``/``IsDefined``/``CreateAt`` are all *functions* — their result is the return value, not a ``value=`` dummy argument (there is no such argument on any of them). This was confirmed directly against the compiled ``esmf_hconfigmod.mod`` for the ESMF releases in use here (8.8.0 and 8.9.1); if building against a different ESMF release, re-check with e.g. ``strings <path-to>/esmf_hconfigmod.mod | grep '^ESMF_HCONFIGASSTRING%'``. ``ESMF_HConfigAsStringSeq`` is avoided entirely (its ``stringLen`` argument's optionality wasn't confirmed); YAML sequences are instead read element-by-element via ``ESMF_HConfigAsString(..., index=n, rc=rc)``.

============
Verification
============

``geogate_phases_hydro_run`` writes one ``hydro_locstream_check_PET<nnnn>.csv`` per PET (``id,lat,lon`` for each locally-owned point). A standalone script, ``verify_hydro_locstream.py`` (kept outside the GeoGate repository, alongside the run's working files; currently written against the NWM RouteLink case specifically), independently reads the coordinate file via ``ncdump`` and checks:

- every point id appears in **exactly one** PET's dump (catches gaps or overlaps in the decomposition itself, not just wrong values), and
- that dump's ``lat``/``lon`` match the source file's within a tight tolerance.

This has been run successfully end-to-end against the NWM RouteLink CONUS file (4 PETs, all 2,776,734 point ids accounted for exactly once).

``geogate_phases_hydro_run`` also **appends** a new block to ``hydro_data_check_PET<nnnn>.csv`` every time it selects a new data file/record (it does not overwrite the previous block), so one file accumulates the full history of every timestep ingested during a run. Each block starts with its own metadata lines before the ``id,<var1>,<var2>,...`` header:

.. code-block:: text

  # curr_time=2026-09-28T01:05:00
  # valid_time=2026-09-28T01:00:00
  # data_file=nwm.t00z.medium_range.channel_rt_1.f001.conus.nc
  # time_record=1
  id,streamflow,velocity
  101,0.200000,0.010000
  ...

Note that ``curr_time`` (the model clock's actual current time at that call) and ``valid_time`` (the *selected* file's own time) are recorded separately and are generally different — reconciling that difference via the configured ``time_selection`` mode is exactly the behavior being verified.

A second standalone script, ``verify_hydro_data.py``, reads every block across all PET dump files (merging each PET's own local id subset per timestep), and for **each** timestep independently checks two separate things — deliberately kept as two separate claims, since conflating them is exactly what made an earlier version of this script misleading:

1. **Selection correctness**: recomputes, from ``hydro_config.yaml`` and the data files themselves (via ``ncdump``, and a Python port of ``geogate_hydro_time.F90``'s CF ``units`` parsing), which file/record actually was nearest to that block's own recorded ``curr_time`` — and compares that against what GeoGate reported. Comparing GeoGate's output only against its own self-reported selection (as an earlier version of this script did) cannot catch a selection bug; it only confirms the read path is self-consistent with itself.
2. **Read/unpack correctness**: independently unpacks that block's ``data_file`` via ``ncdump`` and checks the dumped values against it.

This has been run successfully end-to-end against real NWM data, and deliberately exercised against a synthetic case with wrong values to confirm the read/unpack check actually fails when it should (it's easy to write a checker that always reports PASS by accident).

.. warning::
  While building this checker, a real bug was caught and is worth flagging for anyone extending either verification script: ``ncdump`` prints ``_`` (not a number) for any cell equal to a variable's ``_FillValue``/``missing_value``. A naive "extract every number with a regex" parse silently drops those tokens, which desyncs every later value from its id when zipped positionally against another variable read the same way — confirmed directly against the real ``streamflow`` variable (67,154 fill cells; the token count was off by exactly that many). Both scripts now tokenize by splitting on commas and explicitly handle ``_`` as a fill marker, preserving position.

===========
Limitations
===========

- Of the ``time_selection`` modes, only ``nearest``, ``lower``, and ``upper`` are implemented; ``linear`` is accepted by the config schema but errors out at startup.
- Data files are assumed to already share the coordinate file's point ordering (no reordering is applied to them), and to share identical variable packing/type/rank across all configured ``data_files``.
- No destination-Mesh regrid or NUOPC export-state realization — the LocStream and its fields are built and filled, but not yet connected to another component.
- The per-PET CSV dumps are verification aids, not permanent features.
