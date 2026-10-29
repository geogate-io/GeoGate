#!/usr/bin/env python3
"""
Same source as plot_export_map.py (the hydro plugin's export-side Mesh VTK
output), but loops over every timestamp available for a field instead of
just one, draws one frame per timestamp, and combines them into an
animated GIF -- useful for watching an export_element_map_file run's
mapped values evolve over the simulation instead of looking at a single
snapshot.

Usage:
  python3 plot_export_animation.py --vtk-dir /path/to/run --output export_map.gif
  python3 plot_export_animation.py --vtk-dir . --field Fall_roff --fps 4 \\
      --mapping-file mapping/mapping.txt --keep-frames frames/
"""

import argparse
import math
import os
import shutil
import tempfile

import numpy as np

from plot_export_map import discover_files, collect_elements, marker_size, load_mesh_segments, segments_bbox


def draw_frame(ax, scatter_holder, rows, field, timestamp):
    import cartopy.crs as ccrs

    if scatter_holder[0] is not None:
        scatter_holder[0].remove()

    lons = np.array([r[1] for r in rows])
    lats = np.array([r[2] for r in rows])
    vals = np.array([r[3] for r in rows])

    scatter_holder[0] = ax.scatter(lons, lats, s=marker_size(vals), c="#2060c0", alpha=0.7,
                                    edgecolor="black", linewidth=0.3,
                                    transform=ccrs.PlateCarree(), zorder=5)
    ax.set_title(f"{len(rows)} mapped elements based on NWM v3.0\n({field}, {timestamp})",
                 fontweight="bold")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--vtk-dir", default=".", help="directory containing the *.vtk files")
    parser.add_argument("--field", help="field name to plot (default: the only one found)")
    parser.add_argument("--mapping-file", help="export_element_map_file to cross-check each "
                         "frame's non-fill element count against (optional)")
    parser.add_argument("--output", default="export_map.gif", help="output animated GIF path")
    parser.add_argument("--fps", type=float, default=2.0, help="animation playback speed")
    parser.add_argument("--dpi", type=int, default=120, help="frame resolution")
    parser.add_argument("--keep-frames", help="also save the individual PNG frames into this "
                         "directory (default: a temporary directory, cleaned up afterward)")
    parser.add_argument("--no-mesh", action="store_true", help="don't draw the mesh outline backdrop")
    args = parser.parse_args()

    groups = discover_files(args.vtk_dir)
    if not groups:
        raise SystemExit(f"no *_<timestamp>_<field>.<npet>.<pet>.vtk files found under {args.vtk_dir}")

    fields = sorted({k[1] for k in groups})
    if args.field:
        field = args.field
    elif len(fields) == 1:
        field = fields[0]
    else:
        raise SystemExit(f"multiple fields present ({fields}); pass --field to pick one")

    timestamps = sorted(ts for ts, f in groups if f == field)
    if not timestamps:
        raise SystemExit(f"no timestamps found for field={field}; available fields: {fields}")

    frames = []
    duplicate_warnings = []
    for ts in timestamps:
        rows, report = collect_elements(groups[(ts, field)], field)
        frames.append((ts, rows))
        if report["duplicate_elems"]:
            duplicate_warnings.append(ts)

    print(f"Correctness check: {len(frames)} timestamps, field={field}")
    if duplicate_warnings:
        print(f"  WARNING: duplicate-ownership elements found at: {duplicate_warnings}")
    else:
        print("  no duplicate-ownership elements in any frame - OK")

    if args.mapping_file:
        unique_elems = set()
        with open(args.mapping_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                unique_elems.add(int(line.split()[1]))
        mismatches = [ts for ts, rows in frames if len(rows) != len(unique_elems)]
        print(f"  {args.mapping_file} has {len(unique_elems)} unique elements; "
              f"{len(frames) - len(mismatches)}/{len(frames)} frames match"
              + (f", MISMATCH at: {mismatches}" if mismatches else " - OK"))

    all_lons = np.concatenate([[r[1] for r in rows] for _, rows in frames if rows])
    all_lats = np.concatenate([[r[2] for r in rows] for _, rows in frames if rows])
    if all_lons.size == 0:
        raise SystemExit("no non-fill elements found in any frame -- nothing to animate")

    mesh_segments = None
    if not args.no_mesh:
        # The mesh is static across the whole animation, so it's drawn once
        # here rather than per frame. Every PET file for the timestamp holds
        # only its own partition of the mesh (see load_mesh_segments), so
        # all of them are combined to get the whole thing.
        mesh_paths = sorted(groups[(timestamps[0], field)])
        mesh_segments = load_mesh_segments(mesh_paths)

    pad = 0.3
    lon_min, lon_max, lat_min, lat_max = all_lons.min(), all_lons.max(), all_lats.min(), all_lats.max()
    if mesh_segments:
        mlon_min, mlon_max, mlat_min, mlat_max = segments_bbox(mesh_segments)
        lon_min, lon_max = min(lon_min, mlon_min), max(lon_max, mlon_max)
        lat_min, lat_max = min(lat_min, mlat_min), max(lat_max, mlat_max)
    extent = [lon_min - pad, lon_max + pad, lat_min - pad, lat_max + pad]

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import cartopy.crs as ccrs
    import cartopy.feature as cfeature
    from matplotlib.collections import LineCollection

    fig = plt.figure(figsize=(8, 8))
    ax = plt.axes(projection=ccrs.PlateCarree())
    ax.set_extent(extent, crs=ccrs.PlateCarree())
    ax.add_feature(cfeature.LAND.with_scale("10m"), facecolor="#f0ead6")
    ax.add_feature(cfeature.OCEAN.with_scale("10m"), facecolor="#d9e9f5")
    ax.add_feature(cfeature.COASTLINE.with_scale("10m"), linewidth=0.8)
    ax.add_feature(cfeature.STATES.with_scale("10m"), linewidth=0.5, edgecolor="gray")
    ax.add_feature(cfeature.RIVERS.with_scale("10m"), linewidth=0.5, edgecolor="steelblue", alpha=0.6)
    gl = ax.gridlines(draw_labels=True, linewidth=0.3, alpha=0.4)
    gl.top_labels = False
    gl.right_labels = False

    if mesh_segments:
        ax.add_collection(LineCollection(mesh_segments, colors="grey", linewidths=0.3, alpha=0.35,
                                          transform=ccrs.PlateCarree(), zorder=2))

    for mag in (1, 10, 100):
        ax.scatter([], [], s=marker_size(mag), c="#2060c0", alpha=0.7,
                   edgecolor="black", linewidth=0.3, label=f"$10^{{{int(math.log10(mag))}}}$")
    ax.legend(title=f"{field} magnitude", loc="upper right", frameon=True)
    fig.tight_layout()

    frame_dir = args.keep_frames or tempfile.mkdtemp(prefix="plot_export_animation_")
    os.makedirs(frame_dir, exist_ok=True)

    scatter_holder = [None]
    frame_paths = []
    for i, (ts, rows) in enumerate(frames):
        if not rows:
            print(f"  skipping {ts}: no non-fill elements")
            continue
        draw_frame(ax, scatter_holder, rows, field, ts)
        frame_path = os.path.join(frame_dir, f"frame_{i:04d}_{ts.replace(':', '-')}.png")
        fig.savefig(frame_path, dpi=args.dpi)
        frame_paths.append(frame_path)

    plt.close(fig)

    if not frame_paths:
        raise SystemExit("no frames were produced -- nothing to animate")

    from PIL import Image
    images = [Image.open(p).convert("RGB") for p in frame_paths]
    duration_ms = int(round(1000.0 / args.fps))
    images[0].save(args.output, save_all=True, append_images=images[1:],
                    duration=duration_ms, loop=0)
    print(f"Wrote {len(frame_paths)}-frame animation to {args.output}")

    if not args.keep_frames:
        shutil.rmtree(frame_dir, ignore_errors=True)
    else:
        print(f"Kept individual frames in {frame_dir}")


if __name__ == "__main__":
    main()
