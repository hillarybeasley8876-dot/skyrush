import json, sys, os, re, urllib.request, urllib.parse, time, subprocess
# usage: python3 -I commons_get.py <outdir> <slug>=<File:Title> ...   (downloads <=1600px JPEG + appends meta to outdir/_meta.jsonl)
UA = "SkyrushRefBot/0.1 (research; https://github.com/hillarybeasley8876-dot/skyrush)"
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
def api(title):
    p = {"action": "query", "format": "json", "titles": title, "prop": "imageinfo",
         "iiprop": "url|size|extmetadata", "iiurlwidth": "1600"}
    u = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(p)
    with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=40) as r:
        return list(json.load(r)["query"]["pages"].values())[0]
for arg in sys.argv[2:]:
    slug, title = arg.split("=", 1)
    try:
        pg = api(title); ii = pg["imageinfo"][0]; em = ii.get("extmetadata", {})
        src = ii.get("thumburl") or ii["url"]
        raw = os.path.join(out, slug + ".dl")
        req = urllib.request.Request(src, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=90) as r, open(raw, "wb") as f: f.write(r.read())
        jpg = os.path.join(out, slug + ".jpg")
        subprocess.run(["sips", "-Z", "1600", "-s", "format", "jpeg", "-s", "formatOptions", "80", raw, "--out", jpg],
                       check=True, capture_output=True)
        os.remove(raw)
        meta = {"file": slug + ".jpg", "title": title, "page": ii.get("descriptionurl"),
                "license": em.get("LicenseShortName", {}).get("value"),
                "author": re.sub("<[^>]+>", "", em.get("Artist", {}).get("value", ""))[:80],
                "date": em.get("DateTimeOriginal", {}).get("value", "")[:20],
                "orig_size": f"{ii.get('width')}x{ii.get('height')}"}
        with open(os.path.join(out, "_meta.jsonl"), "a", encoding="utf-8") as f: f.write(json.dumps(meta, ensure_ascii=False) + "\n")
        print("OK", slug, meta["license"], meta["orig_size"])
    except Exception as e:
        print("FAIL", slug, title, e)
    time.sleep(1.5)
