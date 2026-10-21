#!/usr/bin/env python3
"""Import doctor (core-owned): heals Godot import metadata before every `godot --import`.

    python3 tools/import_doctor.py ~/m/skyrush/game

Godot marks an asset `valid=false` when it scans the file while another process is still writing it
(Blender exports, PIL saves) and then never retries it, so the asset silently fails to load in game.
This script, run under the import lock by tools/godot_import.sh:
  * resets every `valid=false` import whose source is complete (unchanged for SETTLE_S seconds):
    deletes the .import file and its .godot/imported/<name>-<md5(res path)>.* artefacts, so the
    following import treats it as a new file;
  * deletes orphan .import files whose source is gone (e.g. `*.tmp.glb.import` left by atomic saves).
"""
import hashlib
import sys
import time
from pathlib import Path

SETTLE_S = 5.0


def res_path(proj: Path, source: Path) -> str:
    return "res://" + source.relative_to(proj).as_posix()


def reset(proj: Path, imp: Path, source: Path) -> None:
    digest = hashlib.md5(res_path(proj, source).encode("utf-8")).hexdigest()
    for art in (proj / ".godot" / "imported").glob("%s-%s.*" % (source.name, digest)):
        art.unlink()
    imp.unlink()


def main() -> int:
    proj = Path(sys.argv[1]).expanduser().resolve()
    now = time.time()
    resets, orphans = [], []
    for imp in proj.rglob("*.import"):
        if ".godot" in imp.parts:
            continue
        source = imp.with_suffix("")
        if not source.exists():
            imp.unlink()
            orphans.append(imp)
            continue
        if "\nvalid=false" in imp.read_text(errors="replace") and now - source.stat().st_mtime > SETTLE_S:
            reset(proj, imp, source)
            resets.append(source)
    for s in resets[:12]:
        print("[import-doctor] reset invalid import:", res_path(proj, s))
    print("[import-doctor] %d invalid imports reset, %d orphan .import files removed" % (len(resets), len(orphans)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
