#!/usr/bin/env python3
"""
Reads the ASCII VTK files the hydro plugin writes for its export-side Mesh
field (ESMF_FieldWriteVTK, one file per PET per output timestamp, named
"<fieldprefix>_<timestamp>_<field>.<npet>.<pet>.vtk") and plots the
non-fill (actually mapped) element locations and values on a map -- useful
for sanity-checking an export_element_map_file run (e.g. the SCHISM
source/sink mapping built by convert_sourcesink_mapping.py), similar in
spirit to the per-element source/sink maps pySCHISM itself plots, but as a
single combined panel since the plugin's own mapping is one unified list,
not separate source/sink lists.

Each PET's file holds the full mesh connectivity but only fills in values
for the elements that PET owns; every other element's value is the fill
sentinel (1e20, written as "1e+20"). Combining all PET files for one
timestamp and keeping only non-fill elements recovers every mapped
element exactly once (each is owned by exactly one PET). Element
coordinates in the VTK are 3D Cartesian points on the unit sphere (ESMF's
internal representation), not lon/lat directly, so each element's
centroid is converted back via lon = atan2(y, x), lat = asin(z / r).

Usage:
  python3 plot_export_map.py --vtk-dir /path/to/run --output export_map.png
  python3 plot_export_map.py --vtk-dir . --timestamp 2021-06-01T02:48:00 \\
      --field Fall_roff --mapping-file mapping/mapping.txt
"""

import argparse
import glob
import math
import os
import re
import sys

import numpy as np

FILL_VALUE = 1.0e20
VTK_NAME_RE = re.compile(
    r"^(?P<prefix>.+)_(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})_"
    r"(?P<field>.+)\.(?P<npet>\d+)\.(?P<pet>\d+)\.vtk$"
)


def discover_files(vtk_dir):
    """Group *.vtk files in vtk_dir by (timestamp, field) -> list of paths."""
    groups = {}
    for path in glob.glob(os.path.join(vtk_dir, "*.vtk")):
        m = VTK_NAME_RE.match(os.path.basename(path))
        if not m:
            continue
        key = (m.group("timestamp"), m.group("field"))
        groups.setdefault(key, []).append(path)
    return groups


def parse_vtk(path):
    """Parse one ESMF ASCII VTK file into points, cell node-index lists,
    per-cell _ELEM_NUM, and per-cell field values (field name auto-detected
    from the "elemArray1_<field>" SCALARS block)."""
    with open(path) as f:
        lines = f.read().split("\n")

    npts = ncells = None
    points = None
    cell_nodes = None
    elem_num = None
    field_name = None
    field_vals = None

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith("POINTS"):
            npts = int(line.split()[1])
            flat = []
            i += 1
            while len(flat) < npts * 3:
                flat.extend(float(x) for x in lines[i].split())
                i += 1
            points = np.array(flat, dtype=float).reshape(npts, 3)
            continue
        if line.startswith("CELLS"):
            parts = line.split()
            ncells = int(parts[1])
            nnums = int(parts[2])
            flat = []
            i += 1
            while len(flat) < nnums:
                flat.extend(int(x) for x in lines[i].split())
                i += 1
            cell_nodes = []
            pos = 0
            for _ in range(ncells):
                cnt = flat[pos]
                cell_nodes.append(flat[pos + 1 : pos + 1 + cnt])
                pos += 1 + cnt
            continue
        if line.startswith("SCALARS _ELEM_NUM"):
            i += 2  # skip the LOOKUP_TABLE line
            flat = []
            while len(flat) < ncells:
                flat.extend(int(x) for x in lines[i].split())
                i += 1
            elem_num = np.array(flat, dtype=int)
            continue
        if line.startswith("SCALARS elemArray1_"):
            field_name = line.split()[1][len("elemArray1_"):]
            i += 2
            flat = []
            while len(flat) < ncells:
                flat.extend(float(x) for x in lines[i].split())
                i += 1
            field_vals = np.array(flat, dtype=float)
            continue
        if line.startswith("POINT_DATA"):
            break
        i += 1

    if points is None or cell_nodes is None or elem_num is None or field_vals is None:
        raise ValueError(f"{path}: missing POINTS/CELLS/_ELEM_NUM/elemArray1_* section")
    return points, cell_nodes, elem_num, field_name, field_vals


def xyz_to_lonlat(xyz):
    x, y, z = xyz[..., 0], xyz[..., 1], xyz[..., 2]
    r = np.sqrt(x * x + y * y + z * z)
    lon = np.degrees(np.arctan2(y, x))
    lat = np.degrees(np.arcsin(np.clip(z / r, -1.0, 1.0)))
    return lon, lat


def collect_elements(paths, field):
    """Combine all PET files for one timestamp into one array of
    (elem_num, lon, lat, value) for non-fill elements, plus a correctness
    report dict."""
    report = {"n_pet_files": len(paths), "ncells_per_pet": [], "npts_per_pet": [],
              "duplicate_elems": [], "n_nonfill": 0}
    seen = {}
    rows = []
    for path in sorted(paths):
        points, cell_nodes, elem_num, fname, field_vals = parse_vtk(path)
        if field is not None and fname != field:
            continue
        report["ncells_per_pet"].append(len(cell_nodes))
        report["npts_per_pet"].append(points.shape[0])
        nonfill = np.where(field_vals != FILL_VALUE)[0]
        for idx in nonfill:
            e = int(elem_num[idx])
            nodes = np.array(cell_nodes[idx])
            centroid = points[nodes].mean(axis=0)
            lon, lat = xyz_to_lonlat(centroid)
            value = float(field_vals[idx])
            if e in seen:
                report["duplicate_elems"].append(e)
            else:
                seen[e] = True
                rows.append((e, float(lon), float(lat), value))
    report["n_nonfill"] = len(rows)
    return rows, report


def print_report(report, mapping_file):
    print("VTK correctness check:")
    print(f"  PET files combined        : {report['n_pet_files']}")
    print(f"  cells per PET file        : {sorted(set(report['ncells_per_pet']))}")
    print(f"  points per PET file       : {report['npts_per_pet']}")
    print(f"  non-fill elements found   : {report['n_nonfill']}")
    if report["duplicate_elems"]:
        print(f"  WARNING: {len(report['duplicate_elems'])} element id(s) appeared as "
              f"non-fill in more than one PET file: {sorted(set(report['duplicate_elems']))[:10]}...")
    else:
        print("  each non-fill element owned by exactly one PET (no duplicates) - OK")
    if len(set(report["ncells_per_pet"])) > 1:
        print("  WARNING: PET files disagree on total cell count -- not all from the same mesh/run?")
    if mapping_file:
        unique_elems = set()
        with open(mapping_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                unique_elems.add(int(line.split()[1]))
        print(f"  unique elements in {mapping_file}: {len(unique_elems)}")
        if len(unique_elems) == report["n_nonfill"]:
            print("  matches non-fill element count - OK")
        else:
            print("  MISMATCH vs non-fill element count -- check mapping/export config")


def marker_size(value, floor=1.0, min_size=10.0, size_per_decade=90.0):
    """Area (points^2), one `size_per_decade` step per order of magnitude
    above `floor` -- so a 10x jump in value always reads as the same,
    clearly visible size jump, matching the exponential 10^0/10^1/10^2
    legend rather than compressing it toward a near-linear look. Values
    at or below `floor` (including a legitimate zero) get the smallest
    marker, `min_size`, instead of vanishing or being clipped negative."""
    v = np.clip(np.asarray(value, dtype=float), floor, None)
    return min_size + size_per_decade * np.log10(v / floor)


def make_plot(rows, timestamp, field, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import cartopy.crs as ccrs
    import cartopy.feature as cfeature

    lons = np.array([r[1] for r in rows])
    lats = np.array([r[2] for r in rows])
    vals = np.array([r[3] for r in rows])

    pad = 0.3
    extent = [lons.min() - pad, lons.max() + pad, lats.min() - pad, lats.max() + pad]

    fig = plt.figure(figsize=(8, 8))
    ax = plt.axes(projection=ccrs.PlateCarree())
    ax.set_extent(extent, crs=ccrs.PlateCarree())
    ax.add_feature(cfeature.LAND, facecolor="#f0ead6")
    ax.add_feature(cfeature.OCEAN, facecolor="#d9e9f5")
    ax.add_feature(cfeature.COASTLINE, linewidth=0.8)
    ax.add_feature(cfeature.STATES.with_scale("10m"), linewidth=0.5, edgecolor="gray")
    ax.add_feature(cfeature.RIVERS.with_scale("10m"), linewidth=0.5, edgecolor="steelblue", alpha=0.6)
    gl = ax.gridlines(draw_labels=True, linewidth=0.3, alpha=0.4)
    gl.top_labels = False
    gl.right_labels = False

    ax.scatter(lons, lats, s=marker_size(vals), c="#2060c0", alpha=0.7,
               edgecolor="black", linewidth=0.3, transform=ccrs.PlateCarree(), zorder=5)

    for mag in (1, 10, 100):
        ax.scatter([], [], s=marker_size(mag), c="#2060c0", alpha=0.7,
                   edgecolor="black", linewidth=0.3, label=f"$10^{{{int(math.log10(mag))}}}$")
    ax.legend(title=f"{field} magnitude", loc="upper right", frameon=True)

    ax.set_title(f"{len(rows)} mapped elements based on NWM v3.0\n({field}, {timestamp})",
                 fontweight="bold")

    fig.tight_layout()
    fig.savefig(output, dpi=150)
    print(f"Wrote {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--vtk-dir", default=".", help="directory containing the *.vtk files")
    parser.add_argument("--timestamp", help="ISO timestamp to plot (default: the latest found)")
    parser.add_argument("--field", help="field name to plot (default: the only one found)")
    parser.add_argument("--mapping-file", help="export_element_map_file to cross-check the "
                         "non-fill element count against (optional)")
    parser.add_argument("--output", default="export_map.png", help="output image path")
    args = parser.parse_args()

    groups = discover_files(args.vtk_dir)
    if not groups:
        raise SystemExit(f"no *_<timestamp>_<field>.<npet>.<pet>.vtk files found under {args.vtk_dir}")

    timestamps = sorted({k[0] for k in groups})
    fields = sorted({k[1] for k in groups})
    timestamp = args.timestamp or timestamps[-1]
    if args.field:
        field = args.field
    elif len(fields) == 1:
        field = fields[0]
    else:
        raise SystemExit(f"multiple fields present ({fields}); pass --field to pick one")

    key = (timestamp, field)
    if key not in groups:
        raise SystemExit(f"no files for timestamp={timestamp} field={field}; "
                          f"available timestamps: {timestamps}")

    rows, report = collect_elements(groups[key], field)
    print_report(report, args.mapping_file)
    if not rows:
        raise SystemExit("no non-fill elements found -- nothing to plot")

    make_plot(rows, timestamp, field, args.output)


if __name__ == "__main__":
    main()
