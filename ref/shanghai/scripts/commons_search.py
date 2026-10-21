import json, sys, urllib.request, urllib.parse, time
# usage: python3 -I commons_search.py "<query>" [limit]  -> prints candidate files (title, size, license, author)
UA = "SkyrushRefBot/0.1 (research; https://github.com/hillarybeasley8876-dot/skyrush)"
q, lim = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 15
params = {"action": "query", "format": "json", "generator": "search", "gsrnamespace": "6",
          "gsrsearch": q, "gsrlimit": str(lim), "prop": "imageinfo",
          "iiprop": "url|size|extmetadata|mime", "iiurlwidth": "1600"}
url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
for attempt in range(3):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=40) as r:
            d = json.load(r); break
    except Exception as e:
        print("retry", e); time.sleep(5)
else:
    sys.exit(1)
pages = sorted(d.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 0))
for p in pages:
    ii = (p.get("imageinfo") or [{}])[0]; em = ii.get("extmetadata", {})
    lic = em.get("LicenseShortName", {}).get("value", "?")
    art = em.get("Artist", {}).get("value", "?")
    import re; art = re.sub("<[^>]+>", "", art)[:40]
    date = em.get("DateTimeOriginal", {}).get("value", "")[:10]
    print(f"{ii.get('width')}x{ii.get('height')} | {lic} | {date} | {art} | {p['title']}")
