"""Regenerate every sign, foliage and surface texture for the props unit.

    /usr/bin/python3 tools/signs/build_all.py

The printed boards are rendered into a scratch folder and packed into the shared
sign atlas; only the four boards the city's lookdev uses as light-box art are
copied into the game folder, so Godot imports a handful of images instead of a
hundred (lead note: IMPORT-CHURN).  The shared atlases are copied into the game
folder by the Blender export (the .glb files reference them from there), so the
game holds one copy of each.

Only files whose bytes changed are written: Godot re-imports a file when its
mtime moves, and the import is the team-wide bottleneck (lead note).
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import families  # noqa: E402
import foliage  # noqa: E402
import guide_sign  # noqa: E402
import prop_atlas  # noqa: E402
import prop_maps  # noqa: E402
import site_signs  # noqa: E402
import surfaces  # noqa: E402
import town_signs  # noqa: E402

ROOT = os.path.expanduser("~/m/skyrush")
SCRATCH = os.path.join(ROOT, "tmp", "props", "tex")
GAME_TEX = os.path.join(ROOT, "game", "assets", "props", "textures")


def _publish_lookdev_boards():
    """Copy the four boards the lookdev uses into the game folder."""
    os.makedirs(GAME_TEX, exist_ok=True)
    out = []
    for name in surfaces.LOOKDEV_BOARDS:
        src = os.path.join(surfaces.TEX_DIR, "%s.png" % name)
        if not os.path.exists(src):
            continue
        dst = os.path.join(GAME_TEX, "%s.png" % name)
        if not os.path.exists(dst) or open(src, "rb").read() != open(dst, "rb").read():
            shutil.copyfile(src, dst)
        out.append(dst)
    return out


def main():
    written = []
    # the printed boards: they are the source of the sign atlas
    for module in (town_signs, guide_sign, site_signs):
        written += module.build_all()
        written += getattr(module, "build_all_extra", lambda: [])()
    written += getattr(site_signs, "build_all_bays", lambda: [])()
    written += getattr(site_signs, "build_all_extra2", lambda: [])()
    # the shared atlases: scratch first, the export copies them into the game
    written += families.build(SCRATCH)
    written.append(families.led_panel(SCRATCH, "chevron"))
    written += families.light_pool(SCRATCH, "gas", canopy_w=60.0, canopy_d=30.0,
                                   bays=(6, 3))
    written += families.light_pool(SCRATCH, "charge", canopy_w=70.0, canopy_d=24.0,
                                   bays=(7, 2))
    written += prop_maps.build_small(SCRATCH)
    written.append(foliage.build(SCRATCH))
    written.append(prop_atlas.build(SCRATCH))
    written += _publish_lookdev_boards()
    print("TEXTURES %d written" % len(written))
    for path in written:
        print("  %s" % os.path.basename(path))


if __name__ == "__main__":
    main()
