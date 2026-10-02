.. _io:

**
IO
**

===========================================
Plugin Specific Third-party Dependencies
===========================================

None beyond ESMF/NUOPC themselves.

===========================================
Building GeoGate with IO Plugin Support
===========================================

The IO plugin is always built in — unlike the Hydro, Python, and Catalyst
plugins, there is no ``GEOGATE_USE_IO`` CMake option to toggle it off.

=============================
Runtime Configuration Options
=============================

None. The IO plugin has no plugin-specific YAML configuration file or
NUOPC component attributes of its own — it simply writes out whatever
fields the component has received as imports from its connected provider
component(s) (``is_local%wrap%FBImp(:)``, one ``ESMF_FieldBundle`` per
nested provider state, built by ``geogate_share``: ``FB_init_pointer``
during ``RealizeAccepted``/``DataInitialize`` — see the
:doc:`GeoGate Overview <overview>` for how import FieldBundles get built
in the first place).

======================
Writing Import Fields
======================

Every call to ``geogate_phases_io_run`` loops over each provider's import
``ESMF_FieldBundle`` and, for each one, queries its **first** field's
``geomtype`` to decide how to write the whole bundle — every field in a
bundle built by ``FB_init_pointer`` is assumed to share the same geometry,
so this single check is sufficient (and matches ``FB_init_pointer``'s own
per-bundle geomtype assumption):

- **ESMF_GEOMTYPE_MESH** / **ESMF_GEOMTYPE_GRID** → ``FBWriteVTK``: writes
  each field with
  `ESMF_FieldWriteVTK <https://earthsystemmodeling.org/docs/release/latest/ESMF_refdoc/node5.html>`_,
  one VTK file per field per call, named
  ``<compName>_import_<ISO currTime>_<fieldName>`` (ESMF handles the
  per-PET decomposition internally).
- **ESMF_GEOMTYPE_LOCSTREAM** → ``FBWriteCSV``: ``ESMF_FieldWriteVTK``
  does not support ``ESMF_LocStream``-based fields, so these are instead
  written as a plain per-PET CSV file, one row per locally-owned point:

  .. code-block:: text

    lat,lon,Fall_roff,Fall_soff
    31.086876,-94.640541,.200000,.080000
    46.022163,-67.986412,.000000,.010000
    ...

  ``lat``/``lon`` come from the LocStream's own ``ESMF:Lat``/``ESMF:Lon``
  keys; each subsequent column is one field's ``farrayptr``, in the order
  the field bundle reports them. The file is named
  ``<compName>_import_<ISO currTime>_PET<nnnn>.csv`` — one file per PET
  per call, so (unlike an accumulating log) each coupling timestep is a
  separate, self-contained file that can be compared directly against
  whatever real data file corresponds to that same date.

``<compName>`` is the lowercased NUOPC namespace of the provider component
(e.g. a component named ``ROF`` in ``ufs.configure`` is written as
``rof``), and the ISO timestamp is the model clock's current time at that
call (``timeStringISOFrac``), not necessarily the provider field's own
valid time — the same ``curr_time`` vs. ``valid_time`` distinction
documented for the :doc:`Hydro plugin <hydro>`.

===========
Example
===========

Chaining a producer and a consumer to exercise the IO plugin against a
LocStream-based export (as used to validate the Hydro plugin's
``ExportType: locstream`` support end-to-end) — note the two components
can run on a different number of PETs; see the
:doc:`GeoGate Overview <overview>` for how the receiving side's
decomposition gets rebalanced to match:

.. code-block:: text

  EARTH_component_list: ROF OCN

  ROF_model:              geogate
  ROF_petlist_bounds:     0 3
  ROF_attributes::
    HydroConfigFile = hydro_config.yaml
    ExportType = 'locstream'
    ExportMeshFile = nwm_ESMF.nc
    ExportFields = Fall_roff:Fall_soff
  ::

  OCN_model:              geogate
  OCN_petlist_bounds:     4 7
  OCN_attributes::
  ::

  runSeq::
  @3600
    ROF geogate_phases_hydro
    ROF -> OCN :remapMethod=redist
    OCN geogate_phases_io
  @
  ::

Here ``ROF`` (the Hydro plugin) is the producer, exporting
``Fall_roff``/``Fall_soff`` on a LocStream built from ``nwm_ESMF.nc``;
``OCN`` (the IO plugin) is the consumer, receiving those same fields on
its own, potentially differently-decomposed copy of that LocStream, and
writing them out as CSV every coupling step.

===========
Limitations
===========

- A field bundle is assumed to be geometrically uniform (every field
  sharing one Mesh/Grid/LocStream); a bundle mixing geomtypes across its
  own fields is not detected or supported (this would require one
  provider component to export fields on more than one kind of geometry
  at once, which does not happen in the current Hydro/Python/Catalyst
  plugins).
- ``FBWriteCSV``'s per-PET files are a verification aid, not intended as
  a permanent, scalable output format for large production runs.
