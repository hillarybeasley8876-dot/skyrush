import json, sys, urllib.request, urllib.parse, re, time
# usage: python3 -I commons_cat.py "Category:Name" [limit]  -> list files + subcats in a Commons category
UA = "SkyrushRefBot/0.1 (research; https://github.com/hillarybeasley8876-dot/skyrush)"
cat, lim = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "40"
def call(p):
    u = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(p)
    with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=40) as r:
        return json.load(r)
sub = call({"action": "query", "format": "json", "list": "categorymembers", "cmtitle": cat, "cmtype": "subcat", "cmlimit": "50"})
print("SUBCATS:", [m["title"] for m in sub["query"]["categorymembers"]])
d = call({"action": "query", "format": "json", "generator": "categorymembers", "gcmtitle": cat, "gcmtype": "file",
          "gcmlimit": lim, "prop": "imageinfo", "iiprop": "size|extmetadata"})
for p in d.get("query", {}).get("pages", {}).values():
    ii = (p.get("imageinfo") or [{}])[0]; em = ii.get("extmetadata", {})
    print(f"{ii.get('width')}x{ii.get('height')} | {em.get('LicenseShortName',{}).get('value','?')} | {em.get('DateTimeOriginal',{}).get('value','')[:10]} | {p['title']}")
