# Example GeoGate Python plugin script - two-way interaction (COP1).
# Scales Sa_u10m/Sa_v10m from DATM and returns them for export to COP2.
# See docs/source/python.rst for the my_node / my_node_return layout.

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

# Same names on the way out: ExportFields must match a StandardName known
# to the NUOPC field dictionary, and import/export are separate states.
my_node_return = Node()
for name in SCALE_FIELDS:
    my_node_return["data/fields/{}/values".format(name)] = atm_fields[name]["values"] * FACTOR

print("[geogate_modify] pet {}/{}: scaled {} by {}".format(
    my_node["mpi/localpet"], my_node["mpi/petcount"], SCALE_FIELDS, FACTOR), flush=True)
