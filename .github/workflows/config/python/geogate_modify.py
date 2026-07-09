# Example GeoGate Python plugin script - two-way interaction (COP1).
# Derives Sa_wspd10m from Sa_u10m/Sa_v10m, and turns So_t into a spatial
# anomaly relative to the domain-wide mean. That mean is a reduction across
# COP1's whole domain, not a per-PET quantity, so it's computed with an
# MPI Allreduce over COP1's PETs (my_node["mpi/comm"] is the Fortran
# communicator handle for just this component, converted via
# MPI.Comm.f2py). See docs/source/python.rst for the my_node /
# my_node_return layout.

import numpy as np
from conduit import Node
from mpi4py import MPI


def find_import_channel(node, comp_name):
    for candidate in (comp_name, comp_name.upper(), comp_name.lower()):
        path = "channels/import/{}".format(candidate)
        if node.has_path(path):
            return node[path]
    raise KeyError("no import channel found for component '{}'".format(comp_name))


atm_fields = find_import_channel(my_node, "atm")["data/fields"]
ocn_fields = find_import_channel(my_node, "ocn")["data/fields"]

u10 = np.array(atm_fields["Sa_u10m"]["values"])
v10 = np.array(atm_fields["Sa_v10m"]["values"])
sst = np.array(ocn_fields["So_t"]["values"])

# DOCN fills land points with a large sentinel (> 1e20); exclude them from
# the spatial mean, or it gets dragged far from the true ocean average.
land = sst > 1.0e20
valid = ~land

comm = MPI.Comm.f2py(my_node["mpi/comm"])
global_sum = comm.allreduce(sst[valid].sum(), op=MPI.SUM)
global_count = comm.allreduce(int(valid.sum()), op=MPI.SUM)
global_mean = global_sum / global_count

so_t_anomaly = sst - global_mean
so_t_anomaly[land] = np.nan

# Same names on the way out except the new Sa_wspd10m: ExportFields must
# match a StandardName known to the NUOPC field dictionary, and import/
# export are separate states so reusing Sa_u10m/Sa_v10m/So_t is safe.
my_node_return = Node()
my_node_return["data/fields/Sa_u10m/values"] = u10
my_node_return["data/fields/Sa_v10m/values"] = v10
my_node_return["data/fields/Sa_wspd10m/values"] = np.sqrt(u10 ** 2 + v10 ** 2)
my_node_return["data/fields/So_t/values"] = so_t_anomaly

print("[geogate_modify] pet {}/{}: So_t global mean = {:.3f}".format(
    my_node["mpi/localpet"], my_node["mpi/petcount"], global_mean), flush=True)
