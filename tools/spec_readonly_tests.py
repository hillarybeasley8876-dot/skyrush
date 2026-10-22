import glob
import json
import sys

spec = sys.argv[1]
folders = sys.argv[2:]
d = json.load(open(spec, encoding="utf-8"))
ro = []
for folder in folders:
    for f in sorted(glob.glob(folder + "/*")):
        if f.endswith((".gd", ".tscn")):
            ro.append(f.replace(chr(92), "/"))
d["readonly"] = ro
with open(spec, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
print(len(ro), "readonly test files in", spec)
