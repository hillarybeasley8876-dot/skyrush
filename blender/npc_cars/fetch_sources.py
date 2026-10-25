"""Downloads the third-party car models of the fleet into the car cache and checks them.

    python blender/npc_cars/fetch_sources.py [ids] [--cache DIR]

        ids          the sources to fetch (default: every source of sources.json)
        --cache DIR  where the files go (default: SKYRUSH_CAR_CACHE, else <checkout>/../skyrush-out/cache/cars)

The list, the licences and the sha256 of every file are in blender/npc_cars/sources.json. A file that is already in the
cache with the right sha256 is not downloaded again; a download with another sha256 is refused (the source changed: look at
it before the converter uses it). A zip is unpacked into the folder its "unzip" entry names. The files are not committed:
blender/npc_cars/web/convert_real.py reads them from the same cache. Standard library only.
"""
import hashlib
import json
import os
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKOUT = os.path.dirname(os.path.dirname(HERE))
SOURCES = os.path.join(HERE, "sources.json")


def default_cache():
    """The cache of the car sources: SKYRUSH_CAR_CACHE, else skyrush-out/cache/cars next to the checkout."""
    env = os.environ.get("SKYRUSH_CAR_CACHE")
    if env:
        return env
    return os.path.join(os.path.dirname(CHECKOUT), "skyrush-out", "cache", "cars")


def load_sources():
    with open(SOURCES, encoding="utf-8") as f:
        return json.load(f)["sources"]


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url, path):
    request = urllib.request.Request(url, headers={"User-Agent": "skyrush-fetch/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, open(path, "wb") as out:
        while True:
            block = response.read(1 << 20)
            if not block:
                break
            out.write(block)


def fetch(source_id, entry, cache):
    """Makes sure the file of one source is in the cache with the right sha256 (and unpacked). Returns True when it is."""
    path = os.path.join(cache, entry["file"])
    if os.path.exists(path) and sha256(path) == entry["sha256"]:
        print("ok      %-13s %s" % (source_id, path))
    else:
        part = path + ".part"
        print("fetch   %-13s %s" % (source_id, entry["url"]))
        try:
            download(entry["url"], part)
        except OSError as error:
            print("FAILED  %-13s %s" % (source_id, error))
            return False
        got = sha256(part)
        if got != entry["sha256"]:
            print("FAILED  %-13s sha256 %s, sources.json says %s (kept as %s)" % (source_id, got, entry["sha256"], part))
            return False
        os.replace(part, path)
        print("ok      %-13s %s" % (source_id, path))
    folder = entry.get("unzip")
    if folder:
        target = os.path.join(cache, folder)
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if not all(os.path.exists(os.path.join(target, n)) for n in names):
                archive.extractall(target)
                print("unzip   %-13s %s (%d files)" % (source_id, target, len(names)))
    return True


def main(argv):
    cache = default_cache()
    ids = []
    i = 0
    while i < len(argv):
        if argv[i] == "--cache" and i + 1 < len(argv):
            cache = argv[i + 1]
            i += 2
        else:
            ids.append(argv[i])
            i += 1
    sources = load_sources()
    unknown = [s for s in ids if s not in sources]
    if unknown:
        print("unknown source(s): %s (known: %s)" % (", ".join(unknown), ", ".join(sources)))
        return 2
    os.makedirs(cache, exist_ok=True)
    ok = True
    for source_id in ids or list(sources):
        ok = fetch(source_id, sources[source_id], cache) and ok
    print("FETCH %s (%s)" % ("DONE" if ok else "FAILED", cache))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
