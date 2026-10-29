# Hydro Plugin Tools

## convert_sourcesink_mapping.py

**SCHISM/pySCHISM-specific.** Converts the `sources.json`/`sinks.json`
files produced by [pySCHISM](https://github.com/schism-dev/pyschism)'s own
NWM source/sink generation (`{element_id: [flow_id, ...]}`) into the
hydro plugin's generic `export_element_map_file` format (`flow_id
element_index weight`, one entry per line) -- for case 3 (map flow ids
onto an external mesh; see `docs/source/hydro.rst`: Export Side). The
plugin's own `export_element_map_file` format is not SCHISM-specific --
this converter is just a convenience for the one input shape pySCHISM
happens to produce; a different unstructured-grid model's own source/sink
mapping would need its own converter (or could be hand-written directly in
this plain `flow_id element_index [weight]` format).

The mapping is treated as many-to-many, merging both input files first and
de-duplicating on the exact `(flow_id, element_id)` pair (not on either
column alone):

- An element fed by more than one flow id gets one entry per flow id; the
  plugin sums their values at that element.
- A flow id that maps to more than one distinct element (e.g. the same NWM
  reach acting as a source into one element and a sink from another) gets
  its value split evenly across them: `weight = 1/N`. A flow id appearing
  only once gets `weight = 1.0`.

### Requirements

Python, standard library only.

### Usage

```
python3 convert_sourcesink_mapping.py \
    --sources mapping/sources.json --sinks mapping/sinks.json \
    --output mapping/export_element_map.txt
```

| Option | Default | Description |
| --- | --- | --- |
| `--sources` | (optional) | Path to `sources.json` -- give at least one of `--sources`/`--sinks` |
| `--sinks` | (optional) | Path to `sinks.json` |
| `--output` | (required) | `export_element_map_file` to write |

## download_nwm_retrospective.py

Downloads NWM Retrospective v3.0 `CHRTOUT` files (CONUS, hourly) from
NOAA's public S3 archive for a given date range, one file at a time --
useful for building a local `data_files:` set for the hydro plugin's
`hydro_config.yaml` without needing AWS credentials (the bucket is public;
anonymous HTTPS GET works directly). Verified against the live bucket:

```
https://noaa-nwm-retrospective-3-0-pds.s3.amazonaws.com/CONUS/netcdf/CHRTOUT/<YYYY>/<YYYYMMDDHHMM>.CHRTOUT_DOMAIN1
```

Re-running with the same arguments skips files already downloaded, so an
interrupted multi-day download can simply be re-run to resume.

### Requirements

Python with `requests` (present in NCAR's `npl` conda env: `module load
conda && conda activate npl`).

### Usage

```
python3 download_nwm_retrospective.py --start 2010-01-01 --end 2010-01-02 --outdir CHRTOUT
python3 download_nwm_retrospective.py --start 2010-01-01T06:00 --end 2010-01-01T12:00 --outdir CHRTOUT
```

| Option | Default | Description |
| --- | --- | --- |
| `--start` | (required) | Start date/time (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM`) |
| `--end` | (required) | End date/time, inclusive, same format as `--start` |
| `--outdir` | (required) | Directory to save files into |

This is the **Retrospective v3.0** archive (a multi-decade reanalysis-style
simulation), not the real-time operational forecast feed -- the latter
lives on a different bucket (`noaa-nwm-pds`) with a different layout and
would need a separate tool.

## plot_export_map.py

Reads the ASCII VTK files the hydro plugin writes for its export-side Mesh
field (`ESMF_FieldWriteVTK`, one file per PET per output timestamp) and
plots the non-fill (actually mapped) element locations on a map, sized by
value on a log scale -- a quick visual sanity check for an
`export_element_map_file` run (e.g. a SCHISM source/sink mapping built by
`convert_sourcesink_mapping.py`). Each PET's file holds the full mesh but
only fills in values for the elements it owns; combining all PET files for
one timestamp and keeping only non-fill elements recovers every mapped
element exactly once. It also prints a correctness report (PET file/cell
counts, duplicate-ownership check, and, with `--mapping-file`, a check that
the non-fill element count matches the mapping file's own unique-element
count).

### Requirements

Python with `numpy`, `matplotlib`, and `cartopy` (all present in NCAR's
`npl` conda env: `module load conda && conda activate npl`). `cartopy`
downloads Natural Earth coastline/states/rivers data on first use and
caches it afterward.

### Usage

```
python3 plot_export_map.py --vtk-dir /path/to/run \
    --mapping-file mapping/mapping.txt --output export_map.png
```

| Option | Default | Description |
| --- | --- | --- |
| `--vtk-dir` | `.` | Directory containing the `*.vtk` files |
| `--timestamp` | latest found | ISO timestamp to plot |
| `--field` | the only one found | Field name to plot, if more than one is present |
| `--mapping-file` | (optional) | `export_element_map_file` to cross-check the non-fill element count against |
| `--output` | `export_map.png` | Output image path |

## plot_export_animation.py

Same VTK source as `plot_export_map.py` above, but loops over every
timestamp available for a field, draws one frame per timestamp (same
coastline-map style, with the mapped-element count and timestamp in the
title), and combines them into an animated GIF -- useful for watching a
run's mapped values evolve instead of looking at a single snapshot. Runs
the same correctness checks (duplicate-ownership, optional
`--mapping-file` element-count cross-check) across every frame, not just
one.

### Requirements

Same as `plot_export_map.py` (`numpy`, `matplotlib`, `cartopy`), plus
`Pillow` for GIF assembly -- all present in NCAR's `npl` conda env. Must
be run from (or with) `plot_export_map.py` on the Python path, since it
imports its VTK-parsing and marker-sizing functions from it.

### Usage

```
python3 plot_export_animation.py --vtk-dir /path/to/run \
    --mapping-file mapping/mapping.txt --output export_map.gif
```

| Option | Default | Description |
| --- | --- | --- |
| `--vtk-dir` | `.` | Directory containing the `*.vtk` files |
| `--field` | the only one found | Field name to plot, if more than one is present |
| `--mapping-file` | (optional) | `export_element_map_file` to cross-check each frame's non-fill element count against |
| `--output` | `export_map.gif` | Output animated GIF path |
| `--fps` | `2.0` | Playback speed (frames per second) |
| `--dpi` | `120` | Frame resolution |
| `--keep-frames` | (optional) | Directory to also save the individual PNG frames into (default: a temporary directory, cleaned up afterward) |

## mesh_nwm.py

Builds an ESMF unstructured-mesh netCDF file from a coordinate file's
`lon`/`lat` variables (e.g. RouteLink), for use with `ESMF_MeshCreate` /
`ESMF_LocStreamCreate(fileformat=ESMF_FILEFORMAT_ESMFMESH, ...)`:

```
netcdf mesh_routelink {
dimensions:
        nodeCount = <npoints> ;
        elementCount = <npoints> ;
        maxNodePElement = 1 ;
        coordDim = 2 ;
variables:
        double nodeCoords(nodeCount, coordDim) ;
                nodeCoords:units = "degrees" ;
        int nodeMask(nodeCount) ;   // 1=valid, 0=masked (fill/missing lon or lat)
        int elementConn(elementCount, maxNodePElement) ;
                elementConn:long_name = "Node Indices that define the element connectivity" ;
                elementConn:polygon_break_value = 0LL ;
        int numElementConn(elementCount) ;
                numElementConn:long_name = "Number of nodes per element" ;

// global attributes:
                :gridType = "unstructured" ;
                :version = "0.9" ;
}
```

`nodeCoords(:,0)` is longitude, `nodeCoords(:,1)` is latitude. `nodeMask` is
derived from whichever lon/lat cells netCDF4 reports as masked (fill or
missing value) in the source file, not hardcoded to all-valid.

Point data (e.g. RouteLink reaches) has no natural polygon/element
structure, so `elementConn`/`numElementConn` describe one degenerate,
single-node "element" per point (`numElementConn(:) = 1`,
`elementConn(:,1) = <1-based node index>`) -- the standard workaround for
representing a point cloud in the element-based ESMF mesh file format.
(`ESMF_LocStreamCreateFromFile` also needs `centerflag=.false.` passed at
the call site, since these points are the mesh's actual nodes, not derived
element-center locations.)

### Node ordering

Nodes are written in `--order-variable` order (default `ascendingIndex`),
**not** `--coord-file`'s raw on-disk order.

**Background.** RouteLink's own on-disk order is a topological/network
order -- it is *not* sorted by reach id. The NWM channel_rt data files
(e.g. `nwm.t00z.medium_range.channel_rt_1.f001.conus.nc`), however, store
their `feature_id` dimension pre-sorted ascending, and this sorted-ascending
order was verified empirically (across all 2,776,734 CONUS points) to equal
RouteLink's `link` values sorted ascending. RouteLink's `ascendingIndex`
variable is exactly the 0-based permutation that reproduces that
sorted-ascending order from RouteLink's raw on-disk layout. The hydro
plugin's own PIO-based LocStream construction (`BuildLocStreamAndFields` in
`../geogate_phases_hydro.F90`) applies this same permutation when reading
RouteLink's coordinates (via `HydroReadReorderIndex` in
`../geogate_hydro_io.F90`), which is precisely what lets it reuse the same,
untranslated read map (`seqIndexList`) later when reading the data files
themselves (see `ReadAndFillFields`) -- coordinates and data end up
point-aligned *because* both ultimately follow that one sorted-ascending
order, not because they share RouteLink's native order.

This matters here because `mesh_nwm.py`'s job is to produce a file an
*independent* mechanism (`ESMF_LocStreamCreateFromFile`) can build a
LocStream from directly, with no reorder step of its own applied afterward.
If that file were written in RouteLink's raw on-disk order instead, the
resulting LocStream's canonical point order would silently diverge from
the data files' order -- every point would still exist, but coordinates
and data values would end up mismatched, pointing at the wrong location
entirely, with nothing in either read path to catch it. Applying
`--order-variable ascendingIndex` (the default) avoids this by construction,
rather than relying on some downstream consumer to re-apply the same
permutation correctly.

This was verified empirically, not just reasoned through: an isolated test
(`/glade/derecho/scratch/turuncu/test_locstream_compare/`) built a LocStream
directly from this mesh file and, separately, via the hydro plugin's own
PIO-based construction, then compared both. Before this ordering fix, the
two LocStreams' canonical (unsorted) point orders differed, though they
still contained the same *set* of points. After it, both the per-point set
and the position-by-position canonical order matched exactly (0 mismatches
across all 2,776,734 points), confirmed on both a serial run and a real
parallel 8-PET run.

Writing the mesh file in raw on-disk order instead (`--order-variable ""`)
would silently decouple its point order from the data files' order, if this
file were ever used to build the LocStream that data actually gets read
into.

### Requirements

Python with `netCDF4` and `numpy` (both present in NCAR's `npl` conda env:
`module load conda && conda activate npl`).

### Usage

```
python3 mesh_nwm.py \
    --coord-file v3.0_par/RouteLink_CONUS.nc \
    --output mesh_routelink.nc
```

### Example

Exact command used to (re)generate `/glade/derecho/scratch/turuncu/NWM/esmf_mesh.nc`,
the file the isolated LocStream comparison test in
`/glade/derecho/scratch/turuncu/test_locstream_compare/` builds against, run
from `/glade/derecho/scratch/turuncu/NWM`:

```
module load conda && conda activate npl

python3 ufs-weather-model/GeoGate/src/plugins/hydro/tools/mesh_nwm.py \
    --coord-file v3.0_par/RouteLink_CONUS.nc \
    --output esmf_mesh.nc
```

| Option | Default | Description |
| --- | --- | --- |
| `--coord-file` | (required) | Path to the NetCDF file supplying point coordinates (e.g. RouteLink) |
| `--lon-variable` | `lon` | Longitude variable name in `--coord-file` |
| `--lat-variable` | `lat` | Latitude variable name in `--coord-file` |
| `--order-variable` | `ascendingIndex` | 0-based reorder index; pass `""` for `--coord-file`'s raw on-disk order |
| `--output` | `mesh_routelink.nc` | Output mesh file path |
