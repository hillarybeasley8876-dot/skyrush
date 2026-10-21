"""Tile output: the metadata sidecar, the glTF export and the clean-up.

The sidecar records the sha1 of the city file the tile was built from, so a stale
tile (built from an older map) is detected instead of silently used.

The tiles are written as `<tile>.gltf + <tile>.bin` with the images in the shared
folder game/assets/city/_tex/ (one imported copy of each texture for the whole city,
not one per tile).  The export goes to a temporary name and is swapped in atomically:
the game must never see a half-written tile.
"""
import hashlib
import json
import os

TILE_M = 512.0
SHARED_TEX_DIR = "../_tex"
TEX_DIR = os.path.expanduser("~/m/skyrush/game/assets/city/_tex")
TILE_SUFFIXES = (".glb", ".gltf", ".bin", ".json", ".import")


def city_digest(path):
    """The sha256 of a city file (the sidecar records which map a tile came from).

    sha256 because Godot's HashingContext can compute it in the unit test, so the
    game side can check the tiles against the map too.
    """
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def write_sidecar(path, tx, tz, records, stats, origin, digest, near_flags,
                  block_stats=None):
    """Per-building metadata for the world unit (seeds, styles, footprints, occluders)."""
    from . import occluders
    buildings = []
    occluder_list = []
    for rec in records:
        from .nights import params_for
        night = params_for(rec.get("style", "midrise"), rec.get("seed", 0))
        buildings.append({
            "id": rec.get("id"),
            "style": rec.get("style"),
            "seed": rec.get("seed"),
            "building_seed": night["building_seed"],
            "lit_ratio": night["lit_ratio"],
            "band_ratio": night["band_ratio"],
            "cool_mix": night["cool_mix"],
            "height": rec.get("height"),
            "floors": rec.get("floors"),
            "poly": rec.get("poly"),
            "near_road": bool(near_flags.get(rec.get("id"), False)),
            "ground": bool(rec.get("ground", False)),
        })
        if rec.get("style") in ("park", "plaza"):
            continue
        poly = rec.get("poly") or []
        if len(poly) < 3:
            continue
        cx, cz, w, d = occluders.inscribed_box([(p[0], p[1]) for p in poly])
        occluder_list.append([round(cx - origin[0], 2), round(cz - origin[1], 2),
                               round(w, 2), round(d, 2),
                               round(float(rec.get("height", 10.0)), 2)])
    data = {"tile": [tx, tz], "origin": [origin[0], origin[1]], "size_m": TILE_M,
            "city_sha256": digest, "buildings": buildings, "occluders": occluder_list,
            "stats": stats, "blocks": block_stats or []}
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1)
    return data


def snapshot_textures():
    """The bytes and the timestamp of every shared texture."""
    out = {}
    if not os.path.isdir(TEX_DIR):
        return out
    for name in sorted(os.listdir(TEX_DIR)):
        path = os.path.join(TEX_DIR, name)
        if not os.path.isfile(path) or name.endswith(".import"):
            continue
        with open(path, "rb") as fh:
            out[name] = (fh.read(), os.path.getmtime(path))
    return out


def restore_textures(before):
    """Put the generator's bytes and timestamps back after the export.

    The glTF exporter re-encodes a couple of the ORM maps while it writes the tile.
    Godot would re-import them on every build, and the importer is the team
    bottleneck, so the bytes and the timestamps are restored.
    """
    fixed = 0
    for name, (data, mtime) in before.items():
        path = os.path.join(TEX_DIR, name)
        if not os.path.exists(path):
            continue
        with open(path, "rb") as fh:
            current = fh.read()
        if current != data:
            with open(path, "wb") as fh:
                fh.write(data)
            fixed += 1
        os.utime(path, (mtime, mtime))
    return fixed


def export_tile(path, objects):
    """Export the objects of a tile: a .gltf + .bin with the shared textures.

    The export is written to a temporary name and swapped in, so the game never
    sees a half-written tile (the lead's rule).

    The settings are the ones of lib/export.py (CONTRACTS.md 2) with one change: no
    tangents.  A tangent is 16 of the 48 bytes of a vertex, and Godot regenerates
    them at import time (meshes/ensure_tangents=true in the .import file), so
    writing them would make the tiles a third bigger for nothing.
    """
    import bpy
    if not os.path.isabs(path):
        path = os.path.join(os.path.expanduser("~/m/skyrush/game"), path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    tmp = os.path.splitext(path)[0] + ".tmp.gltf"
    bpy.ops.export_scene.gltf(
        filepath=tmp, export_format="GLTF_SEPARATE", use_selection=True,
        export_apply=True, export_yup=True, export_tangents=False,
        export_cameras=False, export_lights=False, export_extras=True,
        export_image_format="AUTO", export_jpeg_quality=90, export_texcoords=True,
        export_normals=True, export_materials="EXPORT", export_unused_images=False,
        export_texture_dir=SHARED_TEX_DIR, export_keep_originals=True)
    final = os.path.splitext(path)[0] + ".gltf"
    bin_tmp = os.path.splitext(tmp)[0] + ".bin"
    bin_final = os.path.splitext(path)[0] + ".bin"
    if os.path.exists(bin_tmp):
        # the .gltf names the .bin after its own file name, so the temporary name
        # has to be replaced before the swap - otherwise the tile points at a .bin
        # that does not exist
        _rename_buffer(tmp, os.path.basename(bin_tmp), os.path.basename(bin_final))
        os.replace(bin_tmp, bin_final)
    os.replace(tmp, final)
    print("EXPORT %s (%d objects)" % (final, len(objects)))
    return final


def _rename_buffer(gltf_path, old_name, new_name):
    """Point the buffer URI of a .gltf at another .bin file name."""
    with open(gltf_path, "r") as fh:
        data = fh.read()
    if old_name not in data:
        return
    with open(gltf_path, "w") as fh:
        fh.write(data.replace('"%s"' % old_name, '"%s"' % new_name))


def clean_output(out_dir, keep):
    """Remove every previous tile file (the build rewrites the ones it needs).

    Keeping stale files around is worse than losing them: a leftover tile from another
    city would still be loaded by the game and by the footprint checker.  `keep` holds
    the names of the files that must survive (a partial build).
    """
    if not os.path.isdir(out_dir):
        return
    for name in os.listdir(out_dir):
        if not name.startswith("blocks_"):
            continue
        if not name.endswith(TILE_SUFFIXES):
            continue
        if name in keep:
            continue
        try:
            os.remove(os.path.join(out_dir, name))
        except OSError:
            pass
