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
- **export_ids** / **export_ids_file** (optional): export only a subset of flow ids rather than every point. Mutually exclusive with each other and with ``export_element_map_file``. See "Export Side" below.
- **export_element_map_file** (optional): export onto a different mesh entirely (e.g. an ocean model's grid), filling only explicitly mapped elements. Mutually exclusive with ``export_ids``/``export_ids_file``. See "Export Side" below.

=====================
Export Side
=====================

Setting the generic ``ExportType``/``ExportMeshFile``/``ExportFields`` NUOPC component attributes (see the :doc:`GeoGate Overview <overview>`) causes ``geogate_nuopc.F90`` to build a shared geometry (``mesh`` or ``locstream``) from ``ExportMeshFile`` and create one field per ``ExportFields`` entry on it, filled with GeoGate's fill sentinel as a placeholder. The Hydro plugin does not create these fields itself — instead, once per run (``ResolveExportFields``, called once at startup), it looks up each configured variable's ``exportName`` (the ``dataVarName:exportName`` mapping above) against the fields actually present in the export state, then fills them every call according to one of three modes:

Mode 1: export every point
--------------------------

**Every point in** ``coord_file`` **is exported, unchanged.** The default, with none of the options below set. Requires ``ExportMeshFile`` to describe the *same* points, in the *same* order, as ``coord_file`` — e.g. for the NWM RouteLink case, a LocStream mesh file built with the same ``ascendingIndex`` order as ``order_variable`` above (see ``hydro/tools/mesh_nwm.py``, which builds exactly this kind of file).

.. code-block:: yaml

  hydro:
    coord_file: "v3.0_par/RouteLink_CONUS.nc"
    id_variable: "link"
    lat_variable: "lat"
    lon_variable: "lon"
    order_variable: "ascendingIndex"
    data_files:
      - "nwm.t00z.medium_range.channel_rt_1.f001.conus.nc"
    time_variable: "time"
    time_selection: linear
    variables:
      - streamflow:Fall_roff
      - velocity:Fall_soff

Paired with, in ``ufs.configure``:

.. code-block:: text

  ExportType = 'locstream'
  ExportMeshFile = nwm_ESMF.nc
  ExportFields = Fall_roff:Fall_soff

- A variable whose ``exportName`` isn't present in the export state, or whose matched field isn't on a LocStream, is skipped with a warning — it's still read from ``data_files`` and available for ``FBExp``-style internal access, just not exported.
- A variable whose ``exportName`` **is** found gets ``varData(n)%p`` pointed directly at that field's own memory (``ESMF_FieldGet(..., farrayptr=...)``) — every later read/blend step (see "Data Ingest" below) writes straight into the export field, with no separate copy.
- If a matched field's local size doesn't match the Hydro plugin's own decomposition, this is a hard configuration error (``rc=ESMF_FAILURE``), not a silent skip — writing a differently-sized buffer into the wrong-sized field's memory would otherwise silently corrupt it.

Mode 2: export a subset of points
----------------------------------

**Only a chosen subset of flow ids is exported; every other point is left at the fill sentinel.** Set ``export_ids`` (inline YAML list) or ``export_ids_file`` (external file, one flow id per line — blank lines and ``#`` comments are skipped; mutually exclusive with ``export_ids``), still onto the *same* full LocStream as mode 1 (``ExportMeshFile`` does **not** need to be a separate, smaller file — the full NWM LocStream can still be used; it's only worth building a smaller file if the receiving component's own memory/I/O footprint needs to shrink too):

.. code-block:: yaml

  hydro:
    coord_file: "v3.0_par/RouteLink_CONUS.nc"
    id_variable: "link"
    lat_variable: "lat"
    lon_variable: "lon"
    order_variable: "ascendingIndex"
    data_files:
      - "nwm.t00z.medium_range.channel_rt_1.f001.conus.nc"
    time_variable: "time"
    time_selection: linear
    variables:
      - streamflow:Fall_roff
      - velocity:Fall_soff
    export_ids: [6635572, 166764152, 15569905]
    # or: export_ids_file: "export_ids.txt"

Paired with the same ``ufs.configure`` as mode 1 (``ExportType = 'locstream'``, ``ExportMeshFile = nwm_ESMF.nc`` — unchanged, since the export geometry is still the full LocStream).

Implementation: since the export geometry is required to be identical to hydro's own decomposition already (mode 1's own requirement), this needs no data redistribution at all — just a local, per-PET boolean mask (``isExportSelected(:)``, built once from ``pointIdLocal(:)`` + ``config%exportIds`` via a sort and binary search). ``BlendAndFillFields`` leaves every non-selected point at the fill sentinel, the same way it already handles a genuinely missing/fill source value.

Mode 3: map flow ids onto an external mesh
--------------------------------------------

**Export onto a completely different mesh** — e.g. an ocean model's own grid — **filling only explicitly mapped elements**, with every other element left at the fill sentinel. Set ``export_element_map_file`` (external file, two or three whitespace-separated columns per line — ``flow_id element_index [weight]``, ``#`` comments skipped; mutually exclusive with ``export_ids``/``export_ids_file``):

.. code-block:: yaml

  hydro:
    coord_file: "v3.0_par/RouteLink_CONUS.nc"
    id_variable: "link"
    lat_variable: "lat"
    lon_variable: "lon"
    order_variable: "ascendingIndex"
    data_files:
      - "nwm.t00z.medium_range.channel_rt_1.f001.conus.nc"
    time_variable: "time"
    time_selection: linear
    variables:
      - streamflow:Fall_roff
      - velocity:Fall_soff
    export_element_map_file: "export_element_map.txt"

``export_element_map_file`` content (this is also exactly the file used to validate this mode, mapping 4 real NWM flow ids to 4 element indices spanning each of 4 PETs' ranges in a 165,132-element test mesh):

.. code-block:: text

  # flow_id  ocean_element_index
  166764152  1000
  13196034   50000
  15569905   100000
  15569903   150000

The mapping is **many-to-many**, not strictly one-to-one:

- **More than one flow id targeting the same element** (e.g. two separate reaches both feeding one coastal node) is summed: both rows' values are added together at that element.
- **The same flow id targeting more than one element** (e.g. one NWM reach acting as a source into one element and a sink out of another — this happens in practice; see ``hydro/tools/convert_sourcesink_mapping.py`` below) needs the optional third column, ``weight``, so the flow's total discharge isn't counted in full at every element it touches:

  .. code-block:: text

    # flow_id  element_index  weight
    15569903   3000           0.5
    15569903   4000           0.5

  ``weight`` multiplies that row's value before it's summed into its target element; a row with no third column defaults to ``weight = 1.0`` (today's plain one-to-one behavior, unaffected). A flow id's weights are checked at config-read time and must not sum to more than ``1.0`` (a small floating-point tolerance is allowed, e.g. for an exact ``1/3`` split) — this is a hard configuration error, not a warning, since it would otherwise manufacture discharge that doesn't exist. Only an *exact* duplicate ``(flow_id, element_index)`` pair is rejected as a mistake; a repeated id or a repeated element alone is the expected, supported shape of this mapping.

``hydro/tools/convert_sourcesink_mapping.py`` converts pySCHISM-style ``sources.json``/``sinks.json`` (``{element_id: [flow_id, ...]}``) directly into this format, merging both files and computing the even-split ``weight`` automatically for any flow id that ends up targeting more than one element.

Paired with, in ``ufs.configure`` (note ``ExportType`` is ``'mesh'`` here, not ``'locstream'``, and ``ExportMeshFile`` is the target mesh itself — e.g. an ocean model's grid, not anything built from ``coord_file``):

.. code-block:: text

  ExportType = 'mesh'
  ExportMeshFile = hgrid_ESMF.nc
  ExportFields = Fall_roff:Fall_soff

The IO plugin consuming this needs no changes, since it already geomtype-dispatches to ``FBWriteVTK`` for Mesh fields (see :doc:`IO plugin <io>`).

.. important::
  **How the two ids in the mapping are defined is worth being precise about, since they come from two different sources with two different meanings:**

  - The **flow id** (left column) is the exact, real-world id from ``id_variable`` (e.g. RouteLink's ``link``, equal to ``channel_rt``'s ``feature_id``) — the same value used everywhere else in this plugin (``pointIdLocal``, ``export_ids``, etc.), matched directly against the data files' own ids.
  - The **ocean element index** (right column) is **not** a semantic id the ocean model assigns internally — it's the element's 1-based row position in the target mesh file's own on-disk ``elementConn``/``numElementConn`` arrays. This was confirmed empirically (standalone test, ``/glade/derecho/scratch/turuncu/test_mesh_seqindex/``): a file-loaded ``ESMF_Mesh``'s element ``DistGrid`` sequence index is exactly that on-disk row position, split into contiguous per-PET blocks — and an ESMFMESH file has no separate element-id field at all, so row position is the *only* identity it has to give.

  In other words, "element 1000" means "the 1000th element as written into the mesh file," not necessarily any number the ocean model itself uses to refer to that element elsewhere. This is workable as long as whatever generates the ocean mesh file preserves a known, stable element ordering — but it is a positional handle, not a semantic one, and is worth revisiting if a more robust way to identify target elements (e.g. the ocean model's own native element ids, if its mesh-generation tooling can emit or cross-reference them) becomes available.

Implementation: since the target mesh is a genuinely different geometry/decomposition than hydro's own, a flow id's value may need to move to a different PET than the one that computed it. Rather than ``ESMF_FieldRedistStore``/``ESMF_FieldRedist``, this uses a lighter mechanism suited to the typically-small mapped set: every PET contributes its own locally-owned values (zero everywhere else) into a small per-map-entry buffer, ``ESMF_VMAllReduce(reduceflag=ESMF_REDUCE_SUM)`` combines them across this component's own PETs, and each PET then resets every locally-owned, targeted element to zero and accumulates each entry's ``weight``-scaled contribution into it (so an element fed by several flow ids ends up with their sum). The per-entry reduce is exact, not approximate, regardless of how many map entries share a flow id or an element: exactly one PET owns a given flow id, so every non-owner's zero contribution cannot corrupt that entry's own sum (including when the real value is itself a legitimate zero).

Verified end-to-end against a real ocean mesh (``hgrid_ESMF.nc``, 165,132 elements): mapping 4 real flow ids (with known non-fill streamflow) to 4 element indices spanning each of 4 PETs' ranges reproduced the correct value at exactly those 4 elements (confirmed via the VTK output's own ``_ELEM_NUM`` ground-truth labeling) across every coupling step of a 3-hour run, matching an independently-recomputed ``linear`` time interpolation from the real NWM data files.

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

**Multiple time records per file.** A data variable's on-disk rank determines whether a time record needs to be explicitly selected: if it has only the point dimension (``ndims == 1``, e.g. NWM's own per-hour ``channel_rt`` files, where ``streamflow(feature_id)`` carries no time dimension at all — each file holds exactly one implicit record), the read proceeds as a plain decomposed read, same as coordinates. If it has more than one dimension (``ndims > 1``, e.g. ``streamflow(time, feature_id)``), ``PIO_setframe`` selects the correct time record before the decomposed read. This is why the read is skipped for ``ndims == 1``: calling ``PIO_setframe`` on a variable with no record dimension at all is not something the reviewed PIO source documents cleanly one way or the other, so it's avoided instead of assumed safe.

A single ``data_files`` entry spanning many time records (``ndims > 1``) works exactly like many single-record files — ``data_files`` can hold just one combined file instead of one entry per timestep, and ``time_variable`` then needs just one CF ``units`` attribute covering every record in it. Verified directly: merging NWM's 24 separate hourly ``channel_rt`` files into one file (``streamflow(time, feature_id)``, 24 time records) and reconfiguring ``data_files`` to point at it alone, with ``time_selection: linear``, reproduced byte-identical output against the original 24-separate-file configuration (319,324,870 values checked across every PET and every coupling step).

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
- For export modes 1/2 (full or subset export, no ``export_element_map_file``), ``ExportMeshFile`` must describe the same points, in the same order, as ``coord_file`` (see "Export Side" above) — a mismatched point count is caught as a hard error, but a mismatched *order* with the same count is not currently detected and would silently export values against the wrong points.
- For export mode 3 (``export_element_map_file``), the ocean element index is a positional handle (the target mesh's own on-disk element row), not a semantic id — see the note in "Export Side" above. A duplicate flow id or element index in the map is caught as a hard error, but nothing currently detects a flow id or element index that simply doesn't exist in ``coord_file``/``ExportMeshFile`` (it's silently never matched, leaving that map entry's target element at the fill sentinel forever).
- ``linear`` does not extrapolate past either end of the configured records, the same as ``lower``/``upper``.
- ``time_variable``'s calendar is hardcoded to Gregorian (``ESMF_CALKIND_GREGORIAN``) when parsing its CF ``units`` attribute — a data file's own CF ``calendar`` attribute (e.g. ``noleap``, ``360_day``, ``proleptic_gregorian``) is never read or honored. Fine for NWM's real-world files (standard Gregorian), but a data source using a non-Gregorian calendar would get incorrect dates. Only elapsed-time units (``seconds``/``minutes``/``hours``/``days``) are accepted in the first place — the genuinely calendar-ambiguous CF units ``months since``/``years since`` are rejected as an error, so leap years and month lengths are handled correctly for every *supported* case by ESMF's own calendar-aware ``ESMF_Time`` arithmetic, not by any custom logic in this plugin.
- ``coord_file``'s ``lat_variable``/``lon_variable`` are assumed on-disk 4-byte floats, and ``id_variable`` a default (4-byte) integer, with **no runtime type check or dispatch** (``geogate_hydro_pio``: ``PioReadCoords`` hardcodes ``PIO_real``/``PIO_int`` unconditionally). This differs from ``data_files``' own variables, which *are* type-checked and dispatched at runtime (``NF90_SHORT``/``NF90_INT``/``NF90_FLOAT``/``NF90_DOUBLE``, via ``HydroReadVarMeta``'s ``xtype``; a short-typed variable is read through the same path as an int-typed one, since netCDF widens short to int losslessly on read) — see "Packed/scaled variables" above. A coordinate file whose lat/lon are stored as doubles, or whose id variable is a different integer width, would be silently misread rather than erroring. Not yet hit in practice (NWM's RouteLink file matches these assumptions), but worth generalizing to match ``PioReadVariable``'s own dispatch pattern if a future data source needs it.
- ``geogate_hydro_pio``'s PIO options are hardcoded, not read from ``hydro_config.yaml``: ``num_iotasks=1`` (a single PET does all the actual file I/O for every read — see "Parallel Decomposition Implementation" above), ``num_aggregator=0``, ``stride=1``, ``rearr=PIO_rearr_subset``, and the file type itself (``PIO_iotype_netcdf``, i.e. serial NetCDF-3/classic via PIO rather than ``pnetcdf``/``netcdf4p``/``netcdf4c``). Fine at NWM CONUS scale, but a larger domain or a different filesystem/PIO tuning need would require exposing these as plugin options rather than editing the source.
