.. _hydro:

*****
Hydro
*****

The Hydro plugin ingests point coordinates from a configured NetCDF file and builds a parallel-decomposed ``ESMF_LocStream`` from it, with one ``ESMF_Field`` per configured name on that LocStream. The coordinate file's id/lat/lon (and optional point-reordering) variable names all come from the plugin's YAML config, so the plugin itself is data-source agnostic; the examples below use the National Water Model (NWM) ``RouteLink`` file as one concrete data source, but any similarly-shaped NetCDF file (a 1-D id variable plus 1-D lat/lon variables sharing the same dimension) can be configured instead.

.. note::
  The plugin ingests real, time-varying data (see "Data Ingest" below) and can export it to another component by matching each configured variable against a field already present in the export state (``ExportType``/``ExportMeshFile``/``ExportFields``, read generically by ``geogate_nuopc.F90`` — see the :doc:`GeoGate Overview <overview>`). All four ``time_selection`` modes (``nearest``/``lower``/``upper``/``linear``) are implemented.

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

The plugin reads a small YAML configuration file (default path ``hydro_config.yaml``, overridable via the NUOPC component attribute ``HydroConfigFile``) via ``ESMF_HConfig``. Example, using the NWM RouteLink file as the data source and exporting two of its variables under different NUOPC standard names:

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
    time_selection: linear   # optional, default "nearest"; or "lower", "upper", "linear"
    variables:
      - streamflow:Fall_roff
      - velocity:Fall_soff

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
  - ``linear``: interpolates between the record at-or-before the current time (the ``lower`` bracket) and the one at-or-after it (the ``upper`` bracket), weighted by the current time's fractional position between the two records' own valid times. A point is left at GeoGate's fill sentinel if **either** bracket endpoint is itself a fill value at that point, not only when both are — blending a real value against the fill sentinel would otherwise produce a physically meaningless result. Whenever the current time exactly matches a record's own valid time (including, trivially, every call when the coupling interval matches the data's own time spacing), the ``lower`` and ``upper`` brackets resolve to that same record and the weight is exactly zero, so ``linear`` degenerates to the same result as ``nearest``/``lower``/``upper`` with no special-casing needed. Like ``lower``/``upper``, it does not extrapolate past either end of the configured records.
- **variables**: list of variable names to create on the hydro LocStream and read from ``data_files``. Each entry may optionally map a data-file variable name to a different export-state field name as ``dataVarName:exportName`` (a coupled system's own field-dictionary naming convention does not always match the data file's variable names, e.g. NUOPC's ``Fall_roff``/``Fall_soff`` standard names above vs. NWM's own ``streamflow``/``velocity``). A bare name with no colon exports under that same name. See "Export Side" below for how each name is actually matched against the export state.

=====================
Export Side
=====================

Setting the generic ``ExportType``/``ExportMeshFile``/``ExportFields`` NUOPC component attributes (see the :doc:`GeoGate Overview <overview>`) causes ``geogate_nuopc.F90`` to build a shared geometry (``mesh`` or ``locstream``) from ``ExportMeshFile`` and create one field per ``ExportFields`` entry on it, filled with GeoGate's fill sentinel as a placeholder. The Hydro plugin does not create these fields itself — instead, once per run (``ResolveExportFields``, called once at startup), it looks up each configured variable's ``exportName`` (the ``dataVarName:exportName`` mapping above) against the fields actually present in the export state:

- A variable whose ``exportName`` isn't present in the export state, or whose matched field isn't on a LocStream, is skipped with a warning — it's still read from ``data_files`` and available for ``FBExp``-style internal access, just not exported.
- A variable whose ``exportName`` **is** found gets ``varData(n)%p`` pointed directly at that field's own memory (``ESMF_FieldGet(..., farrayptr=...)``) — every later read/blend step (see "Data Ingest" below) writes straight into the export field, with no separate copy.
- If a matched field's local size doesn't match the Hydro plugin's own decomposition (e.g. ``ExportMeshFile`` has a different point count or order than ``coord_file``), this is a hard configuration error (``rc=ESMF_FAILURE``), not a silent skip — writing a differently-sized buffer into the wrong-sized field's memory would otherwise silently corrupt it.

This requires ``ExportMeshFile`` to describe the *same* points, in the *same* order, as ``coord_file`` — e.g. for the NWM RouteLink case, a LocStream mesh file built with the same ``ascendingIndex`` order as ``order_variable`` above (see ``hydro/tools/mesh_nwm.py``, which builds exactly this kind of file).

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

1. Reads the model clock's current time (``NUOPC_ModelGet`` + ``ESMF_ClockGet``). This is **not** necessarily the same as the selected record's own valid time below — reconciling that difference via the configured ``time_selection`` mode is exactly the behavior ``FindNearestTime``/``FindLowerTime``/``FindUpperTime``/the ``linear`` blend implement.
2. Scans the flat list of every ``data_files`` entry's valid time(s) (built once at init, via ``geogate_hydro_time``: ``HydroReadFileTimes``, one entry per time record — so a file with multiple time records contributes multiple entries) and picks a lower/upper bracket per the configured ``time_selection`` (``FindNearestTime``/``FindLowerTime``/``FindUpperTime`` in ``geogate_phases_hydro.F90``; see "Runtime Configuration Options" above for what each does). For ``nearest``/``lower``/``upper`` the bracket's two ends are always the same record; for ``linear`` they generally differ.
3. Only if that bracket changed since the last call, re-reads every configured variable's raw (pre-unpack) data for both bracket ends (``ReadBracketData``, via ``geogate_hydro_pio``: ``PioReadVariable``) — this avoids redundant re-reads when the coupling interval is finer than the data's own time spacing, and (for ``linear``) avoids re-reading the upper end a second time once it becomes the new lower end.
4. Every call, regardless of whether the bracket changed, re-blends the cached bracket data and refills the fields (``BlendAndFillFields``) — this is cheap (in-memory only) and necessary because ``linear``'s blend weight keeps changing continuously even while the bracket itself stays the same.

.. tip::
  The current time is logged on every call, regardless of whether the selection changes, so the run phase's actual calling cadence can be checked against the configured coupling interval, e.g. via ``grep 'geogate_phases_hydro_run) currTime=' PET0000.ESMF_LogFile``.

**Multiple time records per file.** A data variable's on-disk rank determines whether a time record needs to be explicitly selected: if it has only the point dimension (``ndims == 1``, e.g. today's NWM ``channel_rt`` files, where ``streamflow(feature_id)`` carries no time dimension at all — each file holds exactly one implicit record), the read proceeds as a plain decomposed read, same as coordinates. If it has more than one dimension (``ndims > 1``, e.g. a hypothetical ``streamflow(time, feature_id)``), ``PIO_setframe`` selects the correct time record before the decomposed read. This is why the read is skipped for ``ndims == 1``: calling ``PIO_setframe`` on a variable with no record dimension at all is not something the reviewed PIO source documents cleanly one way or the other, so it's avoided instead of assumed safe.

**Packed/scaled variables.** Each configured variable's on-disk type, rank, and CF packing attributes (``scale_factor``, ``add_offset``, ``_FillValue``/``missing_value``) are read once (``geogate_hydro_io``: ``HydroReadVarMeta``, from ``data_files(1)`` only) and assumed identical across all ``data_files`` — consistent with the "multiple files following each other" use case, but a data source whose packing changes file-to-file isn't supported. Raw values are unpacked as ``value = raw*scale_factor + add_offset``, with fill/missing cells mapped to GeoGate's own fill sentinel (``geogate_share::fillValue``, ``1.0d20``).

===============
Build Gotchas
===============

**Real-kind promotion (-real-size 64).** This project's build adds ``-real-size 64`` to ``CMAKE_Fortran_FLAGS`` globally (see ``ufs-weather-model/cmake/Intel.cmake``), which silently promotes any bare, unspecified-kind ``real`` declaration to 8 bytes everywhere, including inside GeoGate's own subdirectory. Coordinate lat/lon variables are typically on-disk 4-byte ``float``, and ``geogate_hydro_pio.F90`` tells PIO's ``io_desc_t`` to expect 4-byte elements (``basepiotype=PIO_real``); a bare ``real`` read buffer under that flag is actually 8-byte, so the compiler binds ``PIO_read_darray``'s generic to its double-precision specific while the ``io_desc_t`` still expects 4-byte elements, corrupting every value read. The fix is declaring those buffers with an explicit ``real(kind=4)`` (immune to ``-real-size``, since that flag only affects the *default* kind), which is what the current code does. If new real-valued PIO/NetCDF reads are added, give their raw on-disk-matching buffers an explicit kind too rather than bare ``real``.

**ESMF_HConfig is function-based.** ``ESMF_HConfigAsString``/``AsLogical``/``GetSize``/``IsDefined``/``CreateAt`` are all *functions* — their result is the return value, not a ``value=`` dummy argument (there is no such argument on any of them). This was confirmed directly against the compiled ``esmf_hconfigmod.mod`` for the ESMF releases in use here (8.8.0 and 8.9.1); if building against a different ESMF release, re-check with e.g. ``strings <path-to>/esmf_hconfigmod.mod | grep '^ESMF_HCONFIGASSTRING%'``. ``ESMF_HConfigAsStringSeq`` is avoided entirely (its ``stringLen`` argument's optionality wasn't confirmed); YAML sequences are instead read element-by-element via ``ESMF_HConfigAsString(..., index=n, rc=rc)``.

===========
Limitations
===========

- Data files are assumed to already share the coordinate file's point ordering (no reordering is applied to them), and to share identical variable packing/type/rank across all configured ``data_files``.
- ``ExportMeshFile`` must describe the same points, in the same order, as ``coord_file`` (see "Export Side" above) — a mismatched point count is caught as a hard error, but a mismatched *order* with the same count is not currently detected and would silently export values against the wrong points.
- ``linear`` does not extrapolate past either end of the configured records, the same as ``lower``/``upper``.
- ``time_variable``'s calendar is hardcoded to Gregorian (``ESMF_CALKIND_GREGORIAN``) when parsing its CF ``units`` attribute — a data file's own CF ``calendar`` attribute (e.g. ``noleap``, ``360_day``, ``proleptic_gregorian``) is never read or honored. Fine for NWM's real-world files (standard Gregorian), but a data source using a non-Gregorian calendar would get incorrect dates. Only elapsed-time units (``seconds``/``minutes``/``hours``/``days``) are accepted in the first place — the genuinely calendar-ambiguous CF units ``months since``/``years since`` are rejected as an error, so leap years and month lengths are handled correctly for every *supported* case by ESMF's own calendar-aware ``ESMF_Time`` arithmetic, not by any custom logic in this plugin.
- ``coord_file``'s ``lat_variable``/``lon_variable`` are assumed on-disk 4-byte floats, and ``id_variable`` a default (4-byte) integer, with **no runtime type check or dispatch** (``geogate_hydro_pio``: ``PioReadCoords`` hardcodes ``PIO_real``/``PIO_int`` unconditionally). This differs from ``data_files``' own variables, which *are* type-checked and dispatched at runtime (``NF90_INT``/``NF90_FLOAT``/``NF90_DOUBLE``, via ``HydroReadVarMeta``'s ``xtype``) — see "Packed/scaled variables" above. A coordinate file whose lat/lon are stored as doubles, or whose id variable is a different integer width, would be silently misread rather than erroring. Not yet hit in practice (NWM's RouteLink file matches these assumptions), but worth generalizing to match ``PioReadVariable``'s own dispatch pattern if a future data source needs it.
- ``geogate_hydro_pio``'s PIO options are hardcoded, not read from ``hydro_config.yaml``: ``num_iotasks=1`` (a single PET does all the actual file I/O for every read — see "Parallel Decomposition Implementation" above), ``num_aggregator=0``, ``stride=1``, ``rearr=PIO_rearr_subset``, and the file type itself (``PIO_iotype_netcdf``, i.e. serial NetCDF-3/classic via PIO rather than ``pnetcdf``/``netcdf4p``/``netcdf4c``). Fine at NWM CONUS scale, but a larger domain or a different filesystem/PIO tuning need would require exposing these as plugin options rather than editing the source.
