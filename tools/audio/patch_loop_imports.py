"""Sets `loop=true` in the Godot .import files of the seamless loop files.

Godot 4.7's OGG importer defaults to `loop=false`; the loop region itself comes from the
LOOPSTART/LOOPEND vorbis comments written by tools/audio/common.py :: to_ogg.

Run after `tools/godot.sh import` (the .import files must exist first):
  python3 tools/audio/patch_loop_imports.py && tools/godot.sh import
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
GAME = os.path.join(ROOT, "game", "audio")

LOOP_SFX = [
    "scrape_loop", "boost_roar_loop", "thruster_hiss_loop", "siren_wail", "siren_yelp",
    "traffic_ev_hum", "tyre_squeal", "city_ambience", "rain_layer", "river_ambience",
    "road_roll", "wind_rush",
]
LOOP_MUSIC = ["cruise", "pursuit", "race"]


def wanted(path: str) -> bool:
    base = os.path.basename(path)
    for sub in ("sfx", "music"):
        if os.sep + sub + os.sep in path:
            name = base[:-len(".ogg.import")] if base.endswith(".ogg.import") else ""
            if sub == "music":
                return name in LOOP_MUSIC
            return name in LOOP_SFX
    return False


def patch(path: str) -> bool:
    """Sets loop=true. An import that was interrupted leaves valid=false — delete those so the
    next import rebuilds them."""
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    if "valid=false" in text:
        os.remove(path)
        return True
    new = re.sub(r"^loop=false$", "loop=true", text, flags=re.M)
    if new == text:
        return False
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(new)
    return True


def main() -> int:
    changed = []
    for sub in ("sfx", "music", "voice"):
        folder = os.path.join(GAME, sub)
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".ogg.import"):
                continue
            path = os.path.join(folder, name)
            if not wanted(path):
                continue
            if patch(path):
                changed.append(os.path.join(sub, name))
    for c in changed:
        print("loop=true", c)
    print("patched %d import files" % len(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
