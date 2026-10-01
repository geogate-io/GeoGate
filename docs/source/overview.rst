.. _overview:

****************
GeoGate Overview
****************

This page describes GeoGate's own generic architecture — the parts shared
by every plugin — before the per-plugin documentation that follows. It
assumes you've already built GeoGate per the
:doc:`Quick Start Guide <quick_start>`.

=====================
One Cap, Many Plugins
=====================

GeoGate is a single, generic ESMF/NUOPC component. Every GeoGate instance
in a coupled run — however many there are, and whatever role each plays —
uses exactly the same "cap" (``geogate_nuopc.F90``) code; what differs
between instances is only their own runtime configuration (NUOPC
component attributes, and in some cases a plugin-specific YAML file) and
which plugin's RUN phase the run sequence actually invokes for them.

A "plugin" is just a RUN-phase entry point — e.g.
``geogate_phases_hydro_run``, ``geogate_phases_io_run`` — registered in
``SetServices`` via ``NUOPC_CompSetEntryPoint``/``NUOPC_CompSpecialize``
under its own phase label (``geogate_phases_hydro``,
``geogate_phases_io``, ...). Which phase actually runs for a given
GeoGate instance is selected entirely by the run sequence, e.g.:

.. code-block:: text

  ROF_model:              geogate
  OCN_model:              geogate

  runSeq::
  @3600
    ROF geogate_phases_hydro
    ROF -> OCN :remapMethod=redist
    OCN geogate_phases_io
  @
  ::

Here both ``ROF`` and ``OCN`` are GeoGate instances, but ``ROF`` runs the
Hydro plugin's phase and ``OCN`` runs the IO plugin's phase — one
producing data, the other consuming and writing out whatever it
received. A single GeoGate instance can equally be a producer, a
consumer, or both, including relative to multiple other instances at
once; nothing in the cap itself assumes a particular role.

==========================
Generic Runtime Attributes
==========================

These NUOPC component attributes are read by the cap itself
(``geogate_nuopc.F90``), not by any particular plugin, so they apply to
any GeoGate instance regardless of which plugin's phase it runs:

- **Verbosity**: generic logging verbosity (currently read but not yet
  acted on beyond being logged).
- **DebugMode** (``.true.``/``true``/``T``): enables additional
  diagnostic logging; read once during ``DataInitialize`` and exposed to
  plugins via ``geogate_share``: ``debugMode``.
- **ScalarFieldName**, **KeepFieldList**, **RemoveFieldList**: control
  which *imported* fields are actually kept, applied during
  ``ModifyAdvertised`` (see "Import Side" below).
  ``KeepFieldList``/``RemoveFieldList`` are read as a single
  colon-separated string and split internally (e.g. ``"So_t:So_omask"``);
  if ``KeepFieldList`` is given, ``RemoveFieldList`` is ignored.
- **ExportType** (``none`` / ``mesh`` / ``locstream``),
  **ExportMeshFile**, **ExportFields**: control what geometry and fields
  get built on the *export* side (see "Export Side" below).
  ``ExportFields`` is read through NUOPC's own multi-value attribute API
  rather than split internally like the two attributes above — when
  using ESMX this means it must be given as a YAML list (``[fieldA,
  fieldB]``); a colon-separated string arrives as a single list item and
  fails with ``is not a StandardName in the NUOPC_FieldDictionary!``.

A plugin may additionally read its own attributes and/or its own YAML
configuration file — e.g. the Hydro plugin's ``HydroConfigFile`` —
documented on that plugin's own page.

===========
Import Side
===========

Any other component connected to a GeoGate instance's import state
arrives as a *nested* ESMF_State, one per provider, under a namespace
attribute. ``geogate_internalstate``: ``InternalStateInit`` discovers
these nested states once (at ``AcceptTransfer`` time) and builds the
parallel ``compName(:)``/``NStateImp(:)`` arrays every later step indexes
by.

From there, the generic import pipeline is:

1. **ModifyAdvertised**: if ``KeepFieldList``/``RemoveFieldList``/
   ``ScalarFieldName`` are set, removes whichever advertised import
   fields they say to drop, per nested provider state.
2. **AcceptTransfer** → **ModifyDecomp**: handles the case where the
   importing instance's own PET count/decomposition differs from the
   provider's. For each accepted field's geometry type:

   - **Grid**: rebuilds a rebalanced ``ESMF_DistGrid`` (handling both
     regular and NUOPC's "arbitrary"/``ArbDimCount`` decompositions) and
     a matching new ``ESMF_Grid``.
   - **Mesh**: rebuilds via
     ``ESMF_MeshEmptyCreate(elementDistGrid=newdistgrid, ...)`` — a
     *bare* geometry shell from just the new, rebalanced distgrid. It
     never tries to copy or redistribute the old mesh's own data.
   - **LocStream**: rebuilds via ``ESMF_LocStreamCreate(distgrid=
     newdistgrid, coordSys=..., rc=rc)`` (the
     ``ESMF_LocStreamCreateFromDG`` overload) — the true LocStream
     analog of the Mesh branch above: a bare shell from just the new
     distgrid, not ``ESMF_LocStreamCreate(locstream, newdistgrid,
     rc=rc)`` (the ``ESMF_LocStreamCreateFromNewDG`` overload), which
     instead tries to redistribute the *source* LocStream's own key
     arrays (e.g. ``ESMF:Lat``/``ESMF:Lon``) onto the new decomposition.
     At this point in the Advertise → AcceptTransfer → ModifyDecomp
     sequence, the LocStream mirrored onto the importing side has only
     the bare geometry — the provider's own keys aren't carried over yet
     — so that redistributing constructor fails with an ESMF error about
     the source array bundle containing no arrays. Using the bare-shell
     constructor instead sidesteps that entirely while still genuinely
     rebalancing the decomposition to match however many PETs the
     *importing* instance actually has.

   In every case the new geometry is attached to every field still in
   ``ESMF_FIELDSTATUS_EMPTY``/``ESMF_FIELDSTATUS_GRIDSET`` via
   ``ESMF_FieldEmptySet``.
3. **RealizeAccepted** → **GridToMesh**: before the final realize, any
   field still on a **Grid** is converted to a **Mesh**
   (``ESMF_MeshCreate(grid, rc=rc)``), and the field is re-realized onto
   that mesh instead. This is a deliberate design choice, not an
   incidental side effect: to keep GeoGate itself as generic as
   possible, it standardizes on Mesh as its common internal geometry
   representation for anything that isn't already a LocStream — Mesh can
   represent both structured and unstructured geometry, whereas Grid
   cannot, so converting up front means the rest of GeoGate (and every
   plugin) only ever has to handle Mesh or LocStream on the import side,
   never Grid. A field that's already a Mesh instead has its
   ungridded-dimension/``GridToFieldMap`` attributes reapplied if needed;
   a LocStream field passes through this step unchanged, since it's
   already GeoGate's other first-class, generic representation.
4. **RealizeAccepted**: realizes each accepted field by name only
   (``NUOPC_Realize(state, fieldName=..., rc=rc)`` — no explicit geometry
   given, since that was already attached above), then builds
   ``FBImp(n)`` — one ``ESMF_FieldBundle`` per provider, via
   ``geogate_share``: ``FB_init_pointer`` — for convenient, direct access
   to every imported field's own data.

A plugin that needs to *consume* imported data (e.g. the IO plugin) reads
directly from ``is_local%wrap%FBImp(:)``/``compName(:)``; it never needs
to deal with the nested-state/geometry-rebalancing machinery above
itself.

===========
Export Side
===========

1. **Advertise**: reads ``ExportFields`` and advertises each name on the
   export state with ``TransferOfferGeomObject='will provide'``.
2. **RealizeProvided**: if ``ExportType`` is ``mesh`` or ``locstream``
   (``none`` skips this entirely), reads ``ExportMeshFile`` and builds
   the corresponding shared geometry —
   ``ESMF_MeshCreate(mesh_file, fileformat=ESMF_FILEFORMAT_ESMFMESH,
   rc=rc)`` or ``ESMF_LocStreamCreate(mesh_file,
   fileformat=ESMF_FILEFORMAT_ESMFMESH, centerflag=.false., rc=rc)`` —
   then creates one field per ``ExportFields`` entry on it, fills each
   with GeoGate's fill sentinel (``geogate_share``: ``fillValue``,
   ``1.0d20``) as a placeholder, and Realizes it into the export state.

A plugin that needs to *produce* export data (e.g. the Hydro plugin) does
not create its own fields for this purpose — it instead queries the
export state directly for fields matching whichever of its own
configured variables it's been told to export, and writes real data
straight into each matched field's own memory. See the
:doc:`Hydro plugin <hydro>` page for exactly how that matching and the
actual data read happen.

``geogate_share``: ``FB_init_pointer`` can also build an ``FBExp``
FieldBundle from the export state the same way ``FBImp`` is built on the
import side, for plugins (e.g. the Python plugin) that want convenient
direct access to export fields too, rather than going through
``ESMF_StateGet`` by name each time.

=================================
Where Plugin-specific Docs Differ
=================================

Everything above is identical regardless of which plugin is in use. What
each plugin's own page actually documents is: what it reads from the
export/import state in the manner described here, where its own data
actually comes from or goes to, and any plugin-specific runtime
configuration on top of the generic attributes listed above. Start with
:doc:`Plugins <plugins>` for the list.
