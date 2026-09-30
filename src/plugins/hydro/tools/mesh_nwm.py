#!/usr/bin/env python3
"""
Builds an ESMF unstructured-mesh netCDF file (nodeCoords/elementConn/
numElementConn, gridType="unstructured") from a coordinate file's lon/lat
variables, for use with ESMF_MeshCreate/ESMF_LocStreamCreate(fileformat=
ESMF_FILEFORMAT_ESMFMESH, ...).

Point data (e.g. RouteLink reaches) has no natural polygon/element
structure, so each point is written as its own degenerate, single-node
"element" (numElementConn=1) -- the standard workaround for representing a
point cloud in the element-based ESMF mesh file format.

Nodes are written in --order-variable order (default "ascendingIndex"), not
--coord-file's raw on-disk order: this variable is the same reordering the
hydro plugin's own PIO-based LocStream construction uses (see
geogate_hydro_io.F90's HydroReadReorderIndex), and it is what makes the
coordinate file's canonical order match the data files' own on-disk order
(e.g. RouteLink's link, sorted ascending, equals channel_rt's feature_id
order). Writing the mesh file in raw on-disk order instead would silently
decouple it from the data files' point order if this file were ever used to
build the LocStream that data gets read into -- pass --order-variable ""
only if you specifically want the file's own raw on-disk order instead.

Usage:
  python3 mesh_nwm.py \\
      --coord-file v3.0_par/RouteLink_CONUS.nc --output mesh_routelink.nc
"""

import argparse

import netCDF4
import numpy as np


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--coord-file", required=True,
                         help="NetCDF file supplying the point coordinates (e.g. RouteLink)")
    parser.add_argument("--lon-variable", default="lon")
    parser.add_argument("--lat-variable", default="lat")
    parser.add_argument("--order-variable", default="ascendingIndex",
                         help="0-based reorder index, applied so node order matches the data "
                              "files' own on-disk order; pass \"\" for --coord-file's raw order")
    parser.add_argument("--output", default="esmf_mesh.nc")
    args = parser.parse_args()

    with netCDF4.Dataset(args.coord_file) as src:
        lonRaw = src.variables[args.lon_variable][:]
        latRaw = src.variables[args.lat_variable][:]
        order = src.variables[args.order_variable][:] if args.order_variable else None

    if lonRaw.shape != latRaw.shape:
        raise SystemExit(f"'{args.lon_variable}' shape {lonRaw.shape} != "
                          f"'{args.lat_variable}' shape {latRaw.shape}")

    # netCDF4 auto-masks fill/missing cells; a point is valid only if
    # neither its lon nor its lat is masked.
    valid = ~(np.ma.getmaskarray(lonRaw) | np.ma.getmaskarray(latRaw))
    lon = np.ma.filled(lonRaw, 0.0).astype("float64")
    lat = np.ma.filled(latRaw, 0.0).astype("float64")

    if order is not None:
        order = np.asarray(order, dtype=np.int64)
        if order.shape != lon.shape:
            raise SystemExit(f"'{args.order_variable}' shape {order.shape} != "
                              f"'{args.lon_variable}' shape {lon.shape}")
        lon = lon[order]
        lat = lat[order]
        valid = valid[order]

    nodeCount = lon.size

    elementCount = nodeCount

    with netCDF4.Dataset(args.output, "w", format="NETCDF4") as dst:
        dst.createDimension("nodeCount", nodeCount)
        dst.createDimension("elementCount", elementCount)
        dst.createDimension("maxNodePElement", 1)
        dst.createDimension("coordDim", 2)

        nodeCoords = dst.createVariable("nodeCoords", "f8", ("nodeCount", "coordDim"))
        nodeCoords.units = "degrees"
        nodeCoords[:, 0] = lon
        nodeCoords[:, 1] = lat

        nodeMask = dst.createVariable("nodeMask", "i4", ("nodeCount",))
        nodeMask[:] = valid.astype("int32")

        # One degenerate, single-node element per point (1-based node index)
        elementConn = dst.createVariable("elementConn", "i4", ("elementCount", "maxNodePElement"))
        elementConn.long_name = "Node Indices that define the element connectivity"
        elementConn.polygon_break_value = np.int64(0)
        elementConn[:, 0] = np.arange(1, nodeCount + 1, dtype="int32")

        numElementConn = dst.createVariable("numElementConn", "i4", ("elementCount",))
        numElementConn.long_name = "Number of nodes per element"
        numElementConn[:] = np.ones(elementCount, dtype="int32")

        dst.gridType = "unstructured"
        dst.version = "0.9"

    orderNote = f"'{args.order_variable}' order" if args.order_variable else "raw on-disk order"
    print(f"Wrote {nodeCount} points ({int(valid.sum())} valid) in {orderNote} to {args.output}")


if __name__ == "__main__":
    main()
