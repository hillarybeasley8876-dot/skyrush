"""Generate the building texture set (run with plain python3, no Blender needed).

    python3 blender/city/buildings/gen_textures.py

Writes the albedo / normal / ORM maps into game/assets/city/_tex/ (the folder every
city tile shares) and a manifest.json with the real-world size of every tile (for the
metres-per-UV mapping).  The atlases (neon, props, cloth, interiors) are written next
to them with their cell manifests.  All output is deterministic.

Two rules from the lead's import note:
  * a texture is only written when its bytes change, and an unchanged file keeps its
    timestamp - Godot re-imports a file whose mtime moved, and the importer is the
    team bottleneck;
  * only the hero surfaces (brick, granite, tile) are 2048 px; the props and the
    small surfaces are 1024 px and the cloth 512 px.
"""
import hashlib
import io
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from buildings.texgen import atlas_neon, brick, carvings, cloth, interiors, led  # noqa: E402
from buildings.texgen import metal  # noqa: E402
from buildings.texgen import misc, props, shops, signs, stone, tile  # noqa: E402
from buildings.texgen.height import normal_from_height, orm_pack  # noqa: E402
from buildings.texgen.noise import to_srgb_bytes  # noqa: E402

OUT = os.path.expanduser("~/m/skyrush/game/assets/city/_tex")

# id -> (generator, metres per tile, pixel size)
SURFACES = [
    ("brick_grey", brick.grey_brick, (brick.TILE_W, 1.30), (2048, 2048)),
    ("brick_red", brick.red_brick, (brick.TILE_W, 1.30), (2048, 2048)),
    ("stone_granite", stone.granite, stone.TILE_M, (2048, 2048)),
    ("stone_pale", stone.pale_stone, 1.20, (1024, 1024)),
    ("tile_white", tile.glazed_tile, tile.TILE_M, (2048, 2048)),
    ("render_grey", tile.render, tile.RENDER_M, (1024, 1024)),
    ("metal_corrugated", metal.corrugated, metal.TILE_M, (1024, 1024)),
    ("shutter_steel", metal.shutter_steel, metal.SHUTTER_M, (1024, 1024)),
    ("steel_powder", metal.steel_powder, metal.STEEL_M, (1024, 1024)),
    ("steel_galv", metal.steel_galv, metal.STEEL_M, (1024, 1024)),
    ("glass_dirty", misc.glass_dirty, misc.GLASS_M, (1024, 1024)),
    ("wood_lacquer", misc.wood_lacquer, misc.WOOD_M, (1024, 1024)),
    ("brass", misc.brass, misc.BRASS_M, (1024, 1024)),
    ("roof_tile", misc.roof_tile, misc.ROOF_M, (1024, 1024)),
    ("awning_canvas", misc.awning_canvas, misc.AWNING_M, (1024, 1024)),
    ("leaf_card", misc.leaf_card, misc.LEAF_M, (1024, 1024)),
    ("lawn", misc.lawn, misc.LAWN_M, (1024, 1024)),
    ("paving_stone", misc.paving_stone, misc.PAVING_M, (1024, 1024)),
]

# The albedos are PHYSICAL: a surface is painted with the colour it really has,
# and the night comes from the exposure and the lights of the environment.  The
# night value used to be baked into the texture, which made the paving linear
# 0.088 and the white tile 0.257 - a night city made of grey paint instead of
# a night city with lights in it.

EMISSIVE = [
    ("emissive_warm", (255, 176, 96)),
    ("emissive_cyan", (120, 236, 255)),
    ("emissive_magenta", (255, 90, 220)),
    ("emissive_red", (255, 64, 72)),
    ("emissive_white", (214, 228, 255)),
]


def _snapshot():
    """The (mtime, digest) of every file in the output folder, before the build."""
    out = {}
    if not os.path.isdir(OUT):
        return out
    for name in os.listdir(OUT):
        path = os.path.join(OUT, name)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as fh:
            data = fh.read()
        out[name] = (os.path.getmtime(path), hashlib.sha256(data).hexdigest())
    return out


def _restore_timestamps(before):
    """Give an unchanged file its old timestamp back (the import churn guard).

    Godot re-imports a texture whose mtime moved; the importer is the team
    bottleneck, so a texture that came out the same must not look new.
    """
    kept = 0
    for name, (mtime, digest) in before.items():
        path = os.path.join(OUT, name)
        if not os.path.exists(path):
            continue
        with open(path, "rb") as fh:
            data = fh.read()
        if hashlib.sha256(data).hexdigest() == digest:
            os.utime(path, (mtime, mtime))
            kept += 1
    return kept


def _write_if_changed(path, data):
    """Write the bytes only when they differ from what is on disk."""
    if os.path.exists(path):
        with open(path, "rb") as fh:
            if fh.read() == data:
                return False
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, path)
    return True


def _encode(img, fmt, quality=92):
    """The encoded bytes of a PIL image (JPEG or PNG)."""
    buf = io.BytesIO()
    if fmt == "JPEG":
        img.save(buf, format=fmt, quality=quality)
    else:
        img.save(buf, format=fmt)
    return buf.getvalue()



def _save_surface(name, fn, size_m, size=(1024, 1024)):
    albedo, height, rough, ao, metal = fn(size=size)
    # the ambient occlusion is baked into the albedo so it reaches the game even
    # without a glTF occlusionTexture (the ORM keeps the raw value in its red channel)
    albedo = np.clip(albedo * ao[..., None], 0.0, 1.6)
    _write_if_changed(os.path.join(OUT, name + "_diff.jpg"),
                      _encode(Image.fromarray(to_srgb_bytes(albedo)), "JPEG"))
    _write_if_changed(os.path.join(OUT, name + "_nor.png"),
                      _encode(Image.fromarray(to_srgb_bytes(normal_from_height(height, 2.0))),
                              "PNG"))
    _write_if_changed(os.path.join(OUT, name + "_orm.png"),
                      _encode(Image.fromarray(orm_pack(ao, rough, metal)), "PNG"))
    return {"size_m": size_m, "maps": ["diff", "nor", "orm"], "px": list(size)}


def _save_emissive(name, colour, size=256):
    """A soft glowing band: the crown strips and the aviation lights."""
    rgb = np.zeros((size, size, 3), dtype=np.float32)
    rgb[:] = np.array(colour, dtype=np.float32) / 255.0
    x = np.linspace(-1.0, 1.0, size, dtype=np.float32)[None, :]
    y = np.linspace(-1.0, 1.0, size, dtype=np.float32)[:, None]
    glow = np.exp(-(x * x * 1.4 + y * y * 6.0)) * 0.85 + 0.15
    _write_if_changed(os.path.join(OUT, name + "_diff.jpg"),
                      _encode(Image.fromarray(to_srgb_bytes(rgb * glow[..., None])), "JPEG"))
    return {"size_m": 1.0, "maps": ["diff"], "px": [size, size]}


def _save_atlas(name, img, entries, manifest):
    """Write an atlas image and add its cells to the shared slot manifest."""
    _write_if_changed(os.path.join(OUT, name + ".jpg"), _encode(img, "JPEG"))
    manifest.extend(entries)
    return {"size_m": 0.0, "maps": ["diff"], "atlas": True, "px": list(img.size)}


def main():
    os.makedirs(OUT, exist_ok=True)
    before = _snapshot()
    manifest = {}
    for name, fn, size_m, size in SURFACES:
        manifest[name] = _save_surface(name, fn, size_m, size)
        print("texture %s ok (%d px)" % (name, size[0]))
    for name, colour in EMISSIVE:
        manifest[name] = _save_emissive(name, colour)
        print("emissive %s ok" % name)
    # the far LOD window atlases (base colour + emission)
    from buildings.texgen import atlas_windows
    for preset, builder in (("office", atlas_windows.build_office),
                            ("resi", atlas_windows.build_resi)):
        img, _cell, _grid = builder()
        arr = np.asarray(img)
        _write_if_changed(os.path.join(OUT, "windows_far_%s_diff.jpg" % preset),
                          _encode(Image.fromarray(arr), "JPEG"))
        emit = atlas_windows.emission_from(arr)
        _write_if_changed(os.path.join(OUT, "windows_far_%s_emit.jpg" % preset),
                          _encode(Image.fromarray(emit), "JPEG"))
        manifest["windows_far_%s" % preset] = {"size_m": 0.0, "maps": ["diff", "emit"],
                                               "atlas": True, "px": list(arr.shape[1::-1])}
    # the atlases with their cell manifests
    entries = signs.write_atlases(OUT)
    entries.extend(led.build(OUT))
    for name, builder in (("cloth", cloth.build), ("interiors", interiors.build),
                          ("shop_interiors", shops.build)):
        img, cells = builder()
        manifest[name] = _save_atlas(name, img, cells, entries)
        print("atlas %s ok (%d cells)" % (name, len(cells)))
    # the prop sheet: the albedo plus a normal and an ORM map
    img, cells, normal, orm = props.build()
    manifest["props"] = _save_atlas("props", img, cells, entries)
    manifest["props"]["maps"] = ["diff", "nor", "orm"]
    _write_if_changed(os.path.join(OUT, "props_nor.png"),
                      _encode(Image.fromarray(to_srgb_bytes(normal)), "PNG"))
    _write_if_changed(os.path.join(OUT, "props_orm.png"),
                      _encode(Image.fromarray(orm), "PNG"))
    print("atlas props ok (%d cells)" % len(cells))
    # the carved stone reliefs (the shikumen pediment panels)
    img, cells, height = carvings.build()
    manifest["carvings"] = _save_atlas("carvings", img, cells, entries)
    manifest["carvings"]["maps"] = ["diff", "nor"]
    _write_if_changed(os.path.join(OUT, "carvings_nor.png"),
                      _encode(Image.fromarray(to_srgb_bytes(
                          normal_from_height(height, 3.0))), "PNG"))
    print("atlas carvings ok (%d cells)" % len(cells))
    signs.write_manifest(OUT, entries)
    manifest["signs"] = {"count": len(entries)}
    data = json.dumps(manifest, indent=1, sort_keys=True).encode("utf-8")
    _write_if_changed(os.path.join(OUT, "manifest.json"), data)
    kept = _restore_timestamps(before)
    total = 0
    count = 0
    for name in os.listdir(OUT):
        if name.endswith(".import"):
            continue
        total += os.path.getsize(os.path.join(OUT, name))
        count += 1
    print("wrote %d surfaces + %d atlas cells to %s" % (len(SURFACES), len(entries), OUT))
    print("%d texture files, %.1f MB, %d unchanged files kept their timestamp"
          % (count, total / 1e6, kept))


if __name__ == "__main__":
    main()
