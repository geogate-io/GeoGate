# Example GeoGate Python plugin script - two-way interaction (COP1).
#
# Reads Sa_u10m/Sa_v10m provided by DATM through the "atm" import channel,
# scales them by FACTOR, and returns the result to GeoGate so it can be
# exported and consumed downstream by another GeoGate instance
# (see geogate_plot.py / esmxRun_python.yaml).
#
# GeoGate exposes two Conduit nodes as Python globals for each script:
#   my_node        - hierarchical view of import/export data
#   my_node_return - node this script must populate to send data back
# See docs/source/python.rst for the full node layout.

from conduit import Node

FACTOR = 2.0
SCALE_FIELDS = ["Sa_u10m", "Sa_v10m"]


def find_import_channel(node, comp_name):
    for candidate in (comp_name, comp_name.upper(), comp_name.lower()):
        path = "channels/import/{}".format(candidate)
        if node.has_path(path):
            return node[path]
    raise KeyError("no import channel found for component '{}'".format(comp_name))


atm_fields = find_import_channel(my_node, "atm")["data/fields"]

my_node_return = Node()
for name in SCALE_FIELDS:
    my_node_return["data/fields/{}_x2/values".format(name)] = atm_fields[name]["values"] * FACTOR

print("[geogate_modify] pet {}/{}: scaled {} by {}".format(
    my_node["mpi/localpet"], my_node["mpi/petcount"], SCALE_FIELDS, FACTOR), flush=True)
