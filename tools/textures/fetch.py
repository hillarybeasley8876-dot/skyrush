#!/usr/bin/env python3
"""Fetch CC0 PBR textures into the shared library game/assets/textures/<id>/.

  fetch.py polyhaven <id> [--res 2k]       Poly Haven texture (diff, nor_gl, rough, ao, disp, arm)
  fetch.py ambientcg <id> [--res 2K]       ambientCG material (zip -> Color/NormalGL/Roughness/AO/...)
  fetch.py hdri <polyhaven_id> [--res 2k]  Poly Haven HDRI -> game/assets/hdri/<id>.hdr
  fetch.py list                            show the library manifest

Output names: <id>_diff.jpg, <id>_nor_gl.jpg, <id>_rough.jpg, <id>_ao.jpg, <id>_disp.jpg,
<id>_metal.jpg, <id>_opacity.jpg (whatever the source provides). Updates manifest.json
(id -> {source, licence, maps, res}). Downloads are staged in tmp/dl/<id>/ (untrusted data: only
image files are extracted; zip paths are flattened). Network errors retry 3x with backoff.
"""
import json
import os
import shutil
import sys
import time
import urllib.request
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIB = os.path.join(ROOT, "game", "assets", "textures")
HDRI = os.path.join(ROOT, "game", "assets", "hdri")
STAGE = os.path.join(ROOT, "tmp", "dl")
MANIFEST = os.path.join(LIB, "manifest.json")
UA = {"User-Agent": "skyrush-texture-fetch/1.0"}
PH_MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough", "AO": "ao",
           "Displacement": "disp", "arm": "arm", "Metal": "metal", "Opacity": "opacity"}
ACG_MAPS = {"Color": "diff", "NormalGL": "nor_gl", "Roughness": "rough", "AmbientOcclusion": "ao",
            "Displacement": "disp", "Metalness": "metal", "Opacity": "opacity"}


def get(url, dest=None, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            if dest:
                with open(dest, "wb") as f:
                    f.write(data)
            return data
        except Exception as exc:  # network boundary: retry, then surface the error
            if i == tries - 1:
                raise RuntimeError("download failed after %d tries: %s (%s)" % (tries, url, exc))
            time.sleep(3 * (i + 1))


def manifest():
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            return json.load(f)
    return {}


def save_manifest(m):
    os.makedirs(LIB, exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(m, f, indent=1, sort_keys=True)


def fetch_polyhaven(tid, res):
    files = json.loads(get("https://api.polyhaven.com/files/%s" % tid))
    info = json.loads(get("https://api.polyhaven.com/info/%s" % tid))
    out = os.path.join(LIB, tid)
    os.makedirs(out, exist_ok=True)
    maps = []
    for key, short in PH_MAPS.items():
        entry = files.get(key, {}).get(res, {})
        fmt = "jpg" if "jpg" in entry else ("png" if "png" in entry else None)
        if not fmt:
            continue
        get(entry[fmt]["url"], os.path.join(out, "%s_%s.%s" % (tid, short, fmt)))
        maps.append(short)
    dims = info.get("dimensions") or []
    return {"source": "polyhaven", "licence": "CC0", "maps": maps, "res": res,
            "size_m": [d / 1000.0 for d in dims] if dims else None, "name": info.get("name")}


def fetch_ambientcg(tid, res):
    meta = json.loads(get("https://ambientcg.com/api/v2/full_json?id=%s&include=downloadData" % tid))
    assets = meta.get("foundAssets") or []
    if not assets:
        raise RuntimeError("ambientCG: no asset %s" % tid)
    want = "%s-JPG" % res.upper()
    link = None
    for folder in assets[0]["downloadFolders"].values():
        for cat in folder["downloadFiletypeCategories"].values():
            for d in cat["downloads"]:
                if d.get("attribute") == want:
                    link = d["downloadLink"]
    if not link:
        raise RuntimeError("ambientCG: %s has no %s download" % (tid, want))
    stage = os.path.join(STAGE, tid)
    shutil.rmtree(stage, ignore_errors=True)
    os.makedirs(stage)
    zpath = os.path.join(stage, "pack.zip")
    get(link, zpath)
    out = os.path.join(LIB, tid)
    os.makedirs(out, exist_ok=True)
    maps = []
    with zipfile.ZipFile(zpath) as z:
        for name in z.namelist():
            base = os.path.basename(name)
            stem, ext = os.path.splitext(base)
            if ext.lower() not in (".jpg", ".png"):
                continue
            suffix = stem.split("_")[-1]
            short = ACG_MAPS.get(suffix)
            if not short:
                continue
            with z.open(name) as src, open(os.path.join(out, "%s_%s%s" % (tid, short, ext.lower())), "wb") as dst:
                shutil.copyfileobj(src, dst)
            maps.append(short)
    shutil.rmtree(stage, ignore_errors=True)
    return {"source": "ambientcg", "licence": "CC0", "maps": sorted(maps), "res": res,
            "name": assets[0].get("displayName")}


def fetch_hdri(tid, res):
    files = json.loads(get("https://api.polyhaven.com/files/%s" % tid))
    url = files["hdri"][res]["hdr"]["url"]
    os.makedirs(HDRI, exist_ok=True)
    get(url, os.path.join(HDRI, "%s.hdr" % tid))
    return {"source": "polyhaven-hdri", "licence": "CC0", "maps": ["hdr"], "res": res}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("polyhaven", "ambientcg", "hdri", "list"):
        sys.exit(__doc__)
    m = manifest()
    if sys.argv[1] == "list":
        for k in sorted(m):
            print(k, m[k].get("source"), ",".join(m[k].get("maps", [])), m[k].get("size_m") or "")
        return
    tid = sys.argv[2]
    res = sys.argv[sys.argv.index("--res") + 1] if "--res" in sys.argv else "2k"
    fn = {"polyhaven": fetch_polyhaven, "ambientcg": fetch_ambientcg, "hdri": fetch_hdri}[sys.argv[1]]
    entry = fn(tid, res)
    key = ("hdri:" + tid) if sys.argv[1] == "hdri" else tid
    m[key] = entry
    save_manifest(m)
    print(json.dumps({key: entry}))


if __name__ == "__main__":
    main()
