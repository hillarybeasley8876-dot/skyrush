"""Tile the city into 512 m tiles and export one .gltf per tile.

The tiles are written as .gltf + .bin with the images in the shared city
texture folder (game/assets/city/_tex), so the whole city needs one imported
copy of every texture instead of one per tile (the lead's TILE-TEX note).

A tile is only written when its bytes really change: Godot re-imports a file
whose timestamp moved, and the import of the city is the team's bottleneck.
"""
import json
import math
import os

from lib import common, export

from city.roads import materials, meshkit

TILE = 512.0
ASSETS = os.path.expanduser("~/m/skyrush/game/assets/city/roads")
SHARED_TEX = os.path.expanduser("~/m/skyrush/game/assets/city/_tex")
SCRATCH = os.path.expanduser("~/m/skyrush/tmp/roads/export")
MAX_TRIS = 400000
MAX_EDGE = 60.0        # no triangle edge may be longer than this
TILE_MARGIN = 64.0     # a vertex may be this far outside its tile


def tile_of(p):
    """Tile key (tx, tz) of a Blender-space point."""
    return (int(math.floor(p.x / TILE)), int(math.floor(-p.y / TILE)))


def split_runs(indices, excluded):
    """Split a list of path indices into contiguous runs, dropping excluded ones."""
    runs = []
    cur = []
    for i in indices:
        if i in excluded:
            if len(cur) > 1:
                runs.append(cur)
            cur = []
        else:
            cur.append(i)
    if len(cur) > 1:
        runs.append(cur)
    return runs


def tile_runs(road):
    """Split a road's path into (tile, indices) runs.

    Each run starts one sample before its tile so the quads that straddle a tile
    border are built exactly once: without it every tile boundary leaves a 4 m
    hole in the road surface, the kerb and the deck.
    """
    runs = []
    cur = []
    key = None
    for i, p in enumerate(road.path):
        k = tile_of(p)
        if k != key:
            if cur:
                runs.append((key, cur))
            cur = []
            key = k
        cur.append(i)
    if cur:
        runs.append((key, cur))
    out = []
    for n, (k, idx) in enumerate(runs):
        if n > 0 and idx:
            idx = [runs[n - 1][1][-1]] + idx
        out.append((k, idx))
    return out


class TileSet:
    """One geometry builder per 512 m tile."""

    def __init__(self):
        self.builders = {}

    def builder_at(self, p):
        key = tile_of(p)
        return self.builder(key)

    def builder(self, key):
        if key not in self.builders:
            self.builders[key] = meshkit.Builder()
            self.builders[key].tile = key
        return self.builders[key]

    def keys(self):
        return sorted(self.builders.keys())


def _same_bytes(a, b):
    """True when two files hold the same bytes."""
    if not os.path.exists(b) or not os.path.exists(a):
        return False
    if os.path.getsize(a) != os.path.getsize(b):
        return False
    with open(a, "rb") as fa, open(b, "rb") as fb:
        while True:
            ca = fa.read(1 << 20)
            cb = fb.read(1 << 20)
            if ca != cb:
                return False
            if not ca:
                return True


def _copy_if_changed(src, dst):
    """Copy a file only when its bytes changed; returns True when it did."""
    if _same_bytes(src, dst):
        return False
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src, "rb") as fh:
        data = fh.read()
    tmp = dst + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, dst)
    return True


def patch_gltf(path):
    """Put the real colours into the exported materials.

    The glTF exporter takes the base colour factor from the node graph, and a
    material whose colour comes from a multiply node is exported with a white
    factor. The factor is written here instead, so a white pot is white because
    the file says so.
    """
    with open(path) as fh:
        data = json.load(fh)
    changed = False
    for mat in data.get("materials", []):
        name = mat.get("name", "")
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        factor = materials.FACTORS.get(name)
        if factor is not None and pbr.get("baseColorFactor") != list(factor):
            pbr["baseColorFactor"] = [round(v, 4) for v in factor]
            changed = True
        if pbr.get("metallicRoughnessTexture") is not None:
            # the ORM map carries the absolute roughness and metallic
            if pbr.get("roughnessFactor") != 1.0:
                pbr["roughnessFactor"] = 1.0
                changed = True
            if pbr.get("metallicFactor") != 1.0:
                pbr["metallicFactor"] = 1.0
                changed = True
        if name in materials.ALPHA_MATERIALS:
            if mat.get("alphaMode") != "MASK" or mat.get("alphaCutoff") != 0.35:
                mat["alphaMode"] = "MASK"
                mat["alphaCutoff"] = 0.35
                changed = True
    if changed:
        with open(path, "w") as fh:
            json.dump(data, fh, indent=1)
    return changed


def export_tiles(tileset, only=None, out_dir=None):
    """Export every tile to <out_dir>/roads_<tx>_<tz>.gltf; returns a stats list."""
    out_dir = os.path.abspath(out_dir or ASSETS)
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(SCRATCH, exist_ok=True)
    stats = []
    written = set()
    for key in tileset.keys():
        if only is not None and key != only:
            continue
        builder = tileset.builders[key]
        if not builder.groups and not builder.named and not builder.objects:
            continue
        col = common.collection("tile_%d_%d" % key)
        for gname, group in builder.groups.items():
            if len(group.verts) == 0:
                continue
            xs = [v.co.x for v in group.verts]
            if key == (-3, 1) and (min(xs) < key[0] * TILE - 64 or max(xs) > (key[0] + 1) * TILE + 64):
                print("GROUP OUT %d_%d %-30s x %.0f..%.0f" % (
                    key[0], key[1], gname, min(xs), max(xs)))
        objs = builder.finish(col, prefix="roads_%d_%d" % key)
        name = "roads_%d_%d" % key
        scratch = os.path.join(SCRATCH, name + ".gltf")
        export.export_glb(scratch, objects=objs, shared_texture_dir="../_tex")
        patch_gltf(scratch)
        changed = _copy_if_changed(scratch, os.path.join(out_dir, name + ".gltf"))
        bin_path = os.path.join(SCRATCH, name + ".bin")
        if os.path.exists(bin_path):
            changed = _copy_if_changed(bin_path, os.path.join(out_dir, name + ".bin")) or changed
        written.add(name)
        tris, breakdown = _stats(objs)
        for (obj_name, minx, maxx, minz, maxz) in check_bounds(key, objs):
            print("TILE %d_%d OUT %-40s x %.0f..%.0f z %.0f..%.0f"
                  % (key[0], key[1], obj_name, minx, maxx, minz, maxz))
        stats.append({"tile": "%d_%d" % key, "tris": tris, "objects": len(objs),
                      "breakdown": breakdown, "written": changed})
        print("TILE %d_%d  %d objects  %d tris%s" %
              (key[0], key[1], len(objs), tris, "" if changed else "  (unchanged)"))
        if tris > 300000:
            for mat, n in sorted(breakdown.items(), key=lambda kv: -kv[1]):
                print("   %-32s %d" % (mat, n))
    if only is None:
        prune(out_dir, written)
    copy_shared_textures()
    return stats


def _stats(objs):
    """The triangle count of a tile and its breakdown per material."""
    tris = 0
    breakdown = {}
    for o in objs:
        if o.type != "MESH":
            continue
        n = common.tri_count(o)
        tris += n
        mat = o.data.materials[0].name if o.data.materials else o.name
        breakdown[mat] = breakdown.get(mat, 0) + n
    return tris, breakdown


def check_bounds(key, objs, margin=TILE_MARGIN):
    """The build assertion: a tile only holds geometry of its own square.

    A piece of road in the wrong tile is hidden by the tile's visibility range
    and drawn twice, so every object of a tile has to lie inside the tile (plus
    the margin of the samples that straddle the border).
    """
    from mathutils import Vector
    tx, tz = key
    out = []
    for o in objs:
        if o.type != "MESH":
            continue
        corners = [o.matrix_world @ Vector(c) for c in o.bound_box]
        if not corners:
            continue
        minx = min(c.x for c in corners)
        maxx = max(c.x for c in corners)
        minz = min(-c.y for c in corners)
        maxz = max(-c.y for c in corners)
        if (minx < tx * TILE - margin or maxx > (tx + 1) * TILE + margin
                or minz < tz * TILE - margin or maxz > (tz + 1) * TILE + margin):
            out.append((o.name, minx, maxx, minz, maxz))
    return out


def prune(out_dir, written):
    """Delete the tiles of an older build that this build did not write."""
    removed = 0
    for name in sorted(os.listdir(out_dir)):
        base = name.split(".")[0]
        if not name.startswith("roads_") or base in written:
            continue
        for suffix in (".glb", ".gltf", ".bin"):
            if name.endswith(suffix):
                path = os.path.join(out_dir, name)
                if os.path.exists(path):
                    os.remove(path)
                    removed += 1
        imp = os.path.join(out_dir, name + ".import")
        if os.path.exists(imp):
            os.remove(imp)
    if removed:
        print("PRUNED %d stale tile files" % removed)
    return removed


def copy_shared_textures():
    """Copy the exported images into the shared city texture folder.

    Only the files whose bytes changed are written, so an unchanged texture
    keeps its timestamp and Godot does not re-import it.
    """
    src_dir = os.path.join(os.path.dirname(SCRATCH), "_tex")
    if not os.path.isdir(src_dir):
        return 0
    count = 0
    for name in sorted(os.listdir(src_dir)):
        if name.endswith(".import"):
            continue
        if _copy_if_changed(os.path.join(src_dir, name), os.path.join(SHARED_TEX, name)):
            count += 1
    if count:
        print("TEXTURES %d new or changed" % count)
    return count
