# Hydro Plugin Tools

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
