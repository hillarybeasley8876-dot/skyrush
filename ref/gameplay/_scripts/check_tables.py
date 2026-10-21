"""Report markdown table rows whose column count differs from their header. Usage: check_tables.py file.md"""
import sys

def cols(line):
    inner = line.strip()
    if inner.startswith("|"):
        inner = inner[1:]
    if inner.endswith("|"):
        inner = inner[:-1]
    return len(inner.split("|"))

lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
in_code = False
header = None
bad = 0
for i, ln in enumerate(lines, 1):
    if ln.startswith("```"):
        in_code = not in_code
        continue
    if in_code:
        continue
    if ln.startswith("|"):
        if header is None:
            header = cols(ln)
        elif cols(ln) != header:
            bad += 1
            print(f"{i}: expected {header} got {cols(ln)}: {ln[:110]}")
    else:
        header = None
print("bad rows:", bad)
