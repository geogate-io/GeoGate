# Example GeoGate Python plugin script - one-way interaction (COP2).
# Plots the Sa_u10m/Sa_v10m/Sa_wspd10m/So_t fields COP1 exported (So_t is a
# spatial anomaly, not raw SST). One-way (no my_node_return), and pinned to
# a single PET since plotting needs the whole global field at once -- see
# "Limitations" in docs/source/python.rst.

import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from conduit import Node

NX_ATM = 1440
NY_ATM = 721
OUTPUT_DIR = "output"
FIELDS = ["Sa_u10m", "Sa_v10m", "Sa_wspd10m", "So_t"]


def find_import_channel(node, comp_name):
    for candidate in (comp_name, comp_name.upper(), comp_name.lower()):
        path = "channels/import/{}".format(candidate)
        if node.has_path(path):
            return node[path]
    raise KeyError("no import channel found for component '{}'".format(comp_name))


cop1_data = find_import_channel(my_node, "cop1")["data"]
lon = np.array(cop1_data["coords/values/face_lon"]).reshape((NY_ATM, NX_ATM))
lat = np.array(cop1_data["coords/values/face_lat"]).reshape((NY_ATM, NX_ATM))

time_str = my_node["state/time_str"]
os.makedirs(OUTPUT_DIR, exist_ok=True)

for name in FIELDS:
    values = np.array(cop1_data["fields/{}/values".format(name)]).reshape((NY_ATM, NX_ATM))

    fig, ax = plt.subplots(figsize=(8, 4))
    mesh = ax.pcolormesh(lon, lat, values, shading="auto")
    fig.colorbar(mesh, ax=ax, orientation="horizontal", shrink=0.7, label=name)
    ax.set_title("{} at {}".format(name, time_str))
    ax.set_xlabel("longitude")
    ax.set_ylabel("latitude")

    ofile = os.path.join(OUTPUT_DIR, "{}_{}.png".format(name, time_str.replace(":", "")))
    fig.savefig(ofile, dpi=120, bbox_inches="tight")
    plt.close(fig)
    print("[geogate_plot] wrote {}".format(ofile), flush=True)
