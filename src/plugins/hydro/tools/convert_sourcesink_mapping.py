#!/usr/bin/env python3
"""
SCHISM/pySCHISM-specific: converts the sources.json/sinks.json files
produced by pySCHISM's own NWM source/sink generation (element_id ->
[flow_id, ...]) into the hydro plugin's generic export_element_map_file
format (flow_id element_index weight, one entry per line). The plugin's
own export_element_map_file format is not SCHISM-specific -- this is just
a convenience for pySCHISM's particular input shape; a different
unstructured-grid model's own source/sink mapping would need its own
converter (or could be hand-written directly in this plain format).

The mapping is treated as many-to-many:
  - If an element appears with more than one flow id (across either file,
    or both combined), each contributes a separate entry targeting that
    element -- the plugin sums their values there.
  - If a flow id appears against more than one distinct element (across
    either file, or both combined -- e.g. the same NWM reach acting as a
    source into one element and a sink from another), its value is split
    evenly: weight = 1/N, N = the number of distinct elements that flow id
    maps to. A flow id appearing only once gets weight 1.0.
  - sources.json and sinks.json are merged before any of the above is
    computed, de-duplicated on the exact (flow_id, element_id) pair (not
    on either column alone) -- so the same pair listed in both files
    collapses to one entry, not two.

Usage:
  python3 convert_sourcesink_mapping.py \\
      --sources mapping/sources.json --sinks mapping/sinks.json \\
      --output mapping/export_element_map.txt
"""

import argparse
import json
from collections import defaultdict


def load_pairs(path):
    if path is None:
        return set()
    with open(path) as f:
        data = json.load(f)
    pairs = set()
    for element_id, flow_ids in data.items():
        for flow_id in flow_ids:
            pairs.add((int(flow_id), int(element_id)))
    return pairs


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sources", help="path to sources.json")
    parser.add_argument("--sinks", help="path to sinks.json")
    parser.add_argument("--output", required=True, help="export_element_map_file to write")
    args = parser.parse_args()

    if not args.sources and not args.sinks:
        raise SystemExit("give at least one of --sources/--sinks")

    pairs = load_pairs(args.sources) | load_pairs(args.sinks)
    if not pairs:
        raise SystemExit("no (flow_id, element_id) pairs found in the input file(s)")

    elements_per_flow = defaultdict(set)
    for flow_id, element_id in pairs:
        elements_per_flow[flow_id].add(element_id)

    rows = []
    for flow_id, element_id in sorted(pairs):
        n = len(elements_per_flow[flow_id])
        weight = 1.0 / n
        rows.append((flow_id, element_id, weight))

    with open(args.output, "w") as f:
        f.write("# flow_id  element_index  weight\n")
        for flow_id, element_id, weight in rows:
            f.write(f"{flow_id}  {element_id}  {weight:.10g}\n")

    split_count = sum(1 for fid, elems in elements_per_flow.items() if len(elems) > 1)
    elements_per_entry = defaultdict(int)
    for _, element_id in pairs:
        elements_per_entry[element_id] += 1
    sum_count = sum(1 for e, n in elements_per_entry.items() if n > 1)

    print(f"Wrote {len(rows)} entries to {args.output}")
    print(f"  {len(elements_per_flow)} distinct flow ids, {len(elements_per_entry)} distinct elements")
    print(f"  {split_count} flow id(s) split across multiple elements (weight < 1.0)")
    print(f"  {sum_count} element(s) fed by multiple flow ids (summed)")


if __name__ == "__main__":
    main()
