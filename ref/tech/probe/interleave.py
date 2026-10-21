#!/usr/bin/env python3
"""Parse RESULT lines of an interleaved run (base,X,base,Y,...,base) and print per-view deltas.
usage: python3 interleave.py out/file.txt [baseline_name]"""
import re, sys
BASE = sys.argv[2] if len(sys.argv) > 2 else "base"
rows = []
for line in open(sys.argv[1]):
    m = re.search(r"RESULT views=(\d+) (\S+)\s+ms=\s*([\d.]+)", line)
    if m:
        rows.append((int(m.group(1)), m.group(2), float(m.group(3))))
for i, (views, name, ms) in enumerate(rows):
    if name == BASE:
        continue
    prev = next((r[2] for r in reversed(rows[:i]) if r[1] == BASE), None)
    nxt = next((r[2] for r in rows[i + 1:] if r[1] == BASE), None)
    bases = [b for b in (prev, nxt) if b is not None]
    base = sum(bases) / len(bases)
    print(f"{name:32s} frame_ms={ms:6.2f} base_ms={base:6.2f} delta_per_view_ms={(ms - base) / views:+6.3f} base_per_view_ms={base / views:5.2f}")
