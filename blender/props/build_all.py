"""Build + export every SKYRUSH prop (unit: props).

    tools/blender.sh run blender/props/build_all.py              # everything
    tools/blender.sh run blender/props/build_all.py -- lamps     # one group

Outputs: game/assets/props/street/<name>.glb and game/assets/props/sites/<name>.glb
The texture atlases are written once into game/assets/props/_tex/ and the glbs
keep them external, so Godot imports every atlas a single time.

Only files whose bytes changed are written, and unchanged files keep their
mtime: Godot re-imports a file when its mtime moves, and the import is the
team-wide bottleneck (lead note: IMPORT-CHURN).
"""
import hashlib
import os
import shutil
import sys

import bpy

ROOT = os.path.expanduser("~/m/skyrush")
sys.path.insert(0, os.path.join(ROOT, "blender"))

from lib import common  # noqa: E402

# The scene is reset once, before the prop modules are imported: the modules hold
# module-level material references and a factory reset would invalidate them.
common.reset()

from props import materials as M  # noqa: E402
from props import build as B  # noqa: E402
from props import godot_assets  # noqa: E402
from props import pack_glb  # noqa: E402

OUT_STREET = os.path.join(ROOT, "game", "assets", "props", "street")
OUT_SITES = os.path.join(ROOT, "game", "assets", "props", "sites")
OUT_TEX = os.path.join(ROOT, "game", "assets", "props", "_tex")


def _stamp(path):
    """(hash, mtime) of a file, or (None, None) when it does not exist."""
    if not os.path.exists(path):
        return (None, None)
    digest = hashlib.sha1()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return (digest.hexdigest(), os.stat(path).st_mtime)


def _keep_mtime(before, path):
    """Restore the old mtime when the file's bytes did not change."""
    old_hash, old_mtime = before
    if old_hash is None or old_mtime is None:
        return
    new_hash, _ = _stamp(path)
    if new_hash == old_hash:
        os.utime(path, (old_mtime, old_mtime))


def _keep_geometry(old_path, path):
    """Keep the old .glb when the new one differs only in float noise.

    The exporter's tangents are not bit-exact between runs, so a byte
    comparison would make Godot re-import every prop on every build.
    """
    if not os.path.exists(old_path) or not os.path.exists(path):
        return
    with open(old_path, "rb") as fh:
        old = fh.read()
    with open(path, "rb") as fh:
        new = fh.read()
    if old == new:
        return
    if pack_glb.geometry_equal(old, new):
        with open(path, "wb") as fh:
            fh.write(old)
        os.utime(path, (os.stat(old_path).st_atime, os.stat(old_path).st_mtime))


def export_all(group=None):
    """Build every prop; `group` limits the run to one module name."""
    os.makedirs(OUT_STREET, exist_ok=True)
    os.makedirs(OUT_SITES, exist_ok=True)
    os.makedirs(OUT_TEX, exist_ok=True)
    built = []
    stats = []
    for name, builder, folder in B.all_props():
        if group and group not in name:
            continue
        prop = builder()
        path = os.path.join(folder, "%s.glb" % name)
        tex_before = {f: _stamp(os.path.join(OUT_TEX, f))
                      for f in os.listdir(OUT_TEX)}
        glb_before = _stamp(path)
        keep = os.path.join(ROOT, "tmp", "props", "keep")
        os.makedirs(keep, exist_ok=True)
        old_copy = os.path.join(keep, "%s.glb" % name)
        if os.path.exists(path):
            shutil.copyfile(path, old_copy)
        prop.finish(path, shared_textures=True)
        for f in tex_before:
            _keep_mtime(tex_before[f], os.path.join(OUT_TEX, f))
        _keep_mtime(glb_before, path)
        _keep_geometry(old_copy, path)
        tris = sum(common.tri_count(o) for o in prop.parts if o.type == "MESH")
        meshes = len([o for o in prop.parts if o.type == "MESH"])
        print("BUILT %-26s %6d tris %4d meshes  %s" % (name, tris, meshes, path))
        stats.append("%s\t%d\t%d" % (name, tris, meshes))
        built.append(name)
        for obj in prop.parts:          # keep node names unique for the next prop
            bpy.data.objects.remove(obj, do_unlink=True)
    scratch = os.path.join(ROOT, "tmp", "props")
    os.makedirs(scratch, exist_ok=True)
    with open(os.path.join(scratch, "prop_stats.tsv"), "w") as fh:
        fh.write("name\ttris\tmeshes\n" + "\n".join(stats) + "\n")
    _clean_shared_tex()
    # the shared Godot materials and the importer override (the family
    # materials are external, so every prop uses the same .tres)
    godot_assets.write_materials()
    godot_assets.patch_imports()
    return built


def _clean_shared_tex():
    """Drop the copies of the core's CC0 sets: the props point at the originals."""
    from props import pack_glb
    for name in os.listdir(OUT_TEX):
        if pack_glb._core_uri(name):
            os.remove(os.path.join(OUT_TEX, name))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    group = argv[0] if argv else None
    names = export_all(group)
    print("PROPS BUILT %d" % len(names))
