import json, sys
# usage: python3 -I show_extract.py file.json [maxchars]
d = json.load(open(sys.argv[1], encoding="utf-8"))
mx = int(sys.argv[2]) if len(sys.argv) > 2 else 6000
for p in d.get("query", {}).get("pages", {}).values():
    print("==", p.get("title"))
    print((p.get("extract") or "MISSING")[:mx])
