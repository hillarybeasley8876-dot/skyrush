"""Build the city blocks: one .glb per 512 m tile, plus a far LOD and a metadata sidecar.

    tools/blender.sh run blender/city/buildings/build_city.py -- --city data/city/test_city.json

Every tile is emitted as merged meshes, one object per material and 128 m cell, so the
world unit gets a handful of draw calls per tile; the per-building metadata (seed,
style, footprint, height) goes into blocks_<tx>_<tz>.json next to the glb.
"""
import hashlib
import json
import math
import os
import sys
import time

import bmesh
import bpy

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

from lib import common  # noqa: E402

from city.buildings import cells, citydata, colliders, detail, far, far_budget  # noqa: E402
from city.buildings import kit, plan, roadgrid, tile_io  # noqa: E402
from city.buildings.tile import build_tile, nearby_segments  # noqa: E402

TILE_M = 512.0
# the triangle budgets of a tile (game/assets/city/blocks/tests/test_blocks.gd)
NEAR_BUDGET = 600000
FAR_BUDGET = 40000
OUT_DIR = os.path.expanduser("~/m/skyrush/game/assets/city/blocks")
FAR_MATERIALS = {
    "wall_office": "window_far_office",
    "wall_resi": "window_far_resi",
    "roof": "roof",
    "emissive_cyan": "emissive_cyan",
    "emissive_magenta": "emissive_magenta",
    "emissive_warm": "emissive_warm",
    "beacon": "beacon",
    "emissive_white": "emissive_white",
    "led": "led",
}


def parse_args(argv):
    """--city <path> --out <dir> --tile <tx,tz> --only <tx,tz;tx,tz]
    --near <tris> --far <tris> override the triangle budgets."""
    opts = {"city": citydata.default_city_path(), "out": OUT_DIR, "tile": None, "only": None,
            "near": NEAR_BUDGET, "far": FAR_BUDGET}
    i = 0
    while i < len(argv):
        key = argv[i]
        if key == "--city":
            opts["city"] = argv[i + 1]
            i += 2
        elif key == "--out":
            opts["out"] = argv[i + 1]
            i += 2
        elif key == "--tile":
            opts["tile"] = argv[i + 1]
            i += 2
        elif key == "--only":
            opts["only"] = argv[i + 1]
            i += 2
        elif key == "--near":
            opts["near"] = int(argv[i + 1])
            i += 2
        elif key == "--far":
            opts["far"] = int(argv[i + 1])
            i += 2
        else:
            i += 1
    return opts


def parse_tiles(text):
    """A list of (tx, tz) from "1,2;3,4"."""
    out = []
    for part in text.split(";"):
        part = part.strip()
        if not part:
            continue
        tx, tz = part.split(",")
        out.append((int(tx), int(tz)))
    return out


def keep_names(out_dir, keep_tiles):
    """The file names the kept tiles must have on disk.

    Everything else that starts with "blocks_" is removed by the clean-up: the old
    .glb tiles of a previous format, their .import files and the tiles of a city
    that has shrunk.
    """
    keep = set()
    for (tx, tz) in keep_tiles:
        base = "blocks_%d_%d" % (tx, tz)
        for stem in (base, base + "_far"):
            for suffix in (".gltf", ".bin", ".json", ".gltf.import"):
                keep.add(stem + suffix)
    return keep


def tile_range(city):
    """The tile indices covering the city window."""
    win = city.get("window", {})
    x0 = int(math.floor(win.get("x_min", 0) / TILE_M))
    x1 = int(math.floor(win.get("x_max", 0) / TILE_M))
    z0 = int(math.floor(win.get("z_min", 0) / TILE_M))
    z1 = int(math.floor(win.get("z_max", 0) / TILE_M))
    return x0, x1, z0, z1


def split_all_blocks(city):
    """Split every block into tile-sized pieces and group them by tile."""
    out = {}
    for block in city.get("blocks", []):
        for piece in _split_block(block):
            cx, cz = citydata.polygon_centroid(piece["polygon"])
            key = (int(cx // TILE_M), int(cz // TILE_M))
            out.setdefault(key, []).append(piece)
    return out


def _split_block(block, limit=400.0):
    """Split a block that is bigger than a tile into pieces that fit one cell.

    The map still contains a few long "fill" strips (up to 1 km); building them whole
    would put their geometry in the wrong tile and leave holes in the neighbours.
    """
    frame = plan.Frame(block["polygon"])
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    if (s1 - s0) <= limit and (t1 - t0) <= limit:
        return [block]
    out = []
    n_s = max(1, int(math.ceil((s1 - s0) / limit)))
    n_t = max(1, int(math.ceil((t1 - t0) / limit)))
    for i in range(n_s):
        for j in range(n_t):
            sa = s0 + (s1 - s0) * i / n_s
            sb = s0 + (s1 - s0) * (i + 1) / n_s
            ta = t0 + (t1 - t0) * j / n_t
            tb = t0 + (t1 - t0) * (j + 1) / n_t
            poly = plan.rectangle(frame, sa, ta, sb, tb)
            if not all(frame.contains(x, z) for x, z in poly):
                continue
            sub = dict(block)
            sub["polygon"] = [list(p) for p in poly]
            sub["id"] = "%s_%d_%d" % (block["id"], i, j)
            sub["seed"] = int(block.get("seed", 0)) + i * 31 + j * 7
            out.append(sub)
    return out


def _tile_rect(blocks):
    """The rectangle of the blocks of a tile (in city space)."""
    xs = [p[0] for b in blocks for p in b["polygon"]]
    zs = [p[1] for b in blocks for p in b["polygon"]]
    if not xs:
        return [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    x0, x1 = min(xs), max(xs)
    z0, z1 = min(zs), max(zs)
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def build_tile_within_budget(city, tx, tz, materials, blocks, segments, grid, budget):
    """Build a tile and keep it inside its near triangle budget.

    A tile that fits keeps every building as it is.  A tile over the budget is
    built again with the decoration of its least important buildings taken away
    (the ones farthest from the road and the smallest ones): the plan says which
    building loses which decoration, and the plan is corrected from what the
    last build really saved until the tile fits.
    """
    bag, records, stats, block_stats = build_tile(city, tx, tz, materials, blocks,
                                                  segments, grid)
    if stats["tris"] <= budget:
        return bag, records, stats, block_stats
    base = stats["tris"]
    counts = dict(bag.building_tris)
    near = nearby_segments(segments, _tile_rect(blocks), 120.0)
    need = (base - budget) * 0.5
    for attempt in range(4):
        plan, promised = detail.make_plan(records, counts, near, need)
        bag, records, stats, block_stats = build_tile(city, tx, tz, materials, blocks,
                                                      segments, grid, plan)
        tris = stats["tris"]
        saved = base - tris
        print("  tile %d,%d: %d tris, asked for %d (the plan promised %d), saved %d"
              % (tx, tz, tris, int(need), int(promised), saved))
        if tris <= budget:
            if tris >= 0.62 * base:
                break
            need = max(1.0, need * 0.5)     # too much came off: ask for less
            continue
        # not enough: the plan saved `saved` triangles for a request of `need`,
        # so ask for the share of the deficit that this rate implies
        rate = saved / float(need) if need > 0 else 1.0
        need = (base - 0.99 * budget) / max(rate, 0.05)
    if stats["tris"] > budget:
        print("WARN near budget: tile %d,%d has %d triangles over %d" % (tx, tz, stats["tris"], budget))
    return bag, records, stats, block_stats


def _far_buckets():
    """The empty far-LOD buckets of one cell."""
    return {"wall_office": bmesh.new(), "wall_resi": bmesh.new(), "roof": bmesh.new()}


def _far_records(records):
    """The records that get a far-LOD mass (a park has none)."""
    out = []
    for rec in records:
        if rec.get("style") in ("park", "plaza"):
            continue
        poly = rec.get("poly") or []
        if len(poly) < 3:
            continue
        out.append(rec)
    return out


def far_objects(records, col, materials, budget=FAR_BUDGET):
    """The far LOD: one merged mass per facade preset and cell, plus the crowns.

    The detail of every building is picked so that the tile fits its far
    triangle budget (`far.far_levels`): a tile that fits keeps the committed
    look, a tile over the budget drops the tiny detail of its least important
    buildings first.
    """
    useable = _far_records(records)
    levels = far_budget.far_levels(useable, budget)
    planned = sum(far_budget.far_cost(rec, lvl) for rec, lvl in zip(useable, levels))
    per_cell = {}
    for rec, level in zip(useable, levels):
        poly = rec.get("poly") or []
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        cell = cells.cell_of(cx, cz)
        buckets = per_cell.setdefault(cell, _far_buckets())
        far.add_far_from_record(buckets, rec, level)
    out = []
    tris = 0
    for cell, buckets in sorted(per_cell.items()):
        centre = cells.cell_centre_blender(cell[0], cell[1])
        for key, bm in sorted(buckets.items()):
            if len(bm.faces) == 0:
                bm.free()
                continue
            tris += _bm_tris(bm)
            name = "blocks_far_%s_c%d_%d" % (key, cell[0], cell[1])
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me)
            bm.free()
            for v in me.vertices:
                v.co -= centre
            obj = bpy.data.objects.new(name, me)
            obj.location = centre
            col.objects.link(obj)
            me.materials.append(materials[FAR_MATERIALS[key]])
            out.append(obj)
    if tris != planned:
        print("WARN far cost model: %d triangles built, %d planned" % (tris, planned))
    if tris > budget:
        print("WARN far budget: %d triangles over %d" % (tris, budget))
    return out, tris


def _bm_tris(bm):
    """The triangles of a bmesh (a quad counts as two)."""
    bm.faces.ensure_lookup_table()
    return sum(len(f.verts) - 2 for f in bm.faces)


def main(argv):
    opts = parse_args(argv)
    common.reset()
    # the city file is read once: the tiles and the digest in the sidecars must
    # describe the SAME map, even if city_layout rewrites it while we build
    with open(opts["city"], "rb") as fh:
        raw = fh.read()
    city = json.loads(raw.decode("utf-8"))
    materials = kit.build_materials()
    os.makedirs(opts["out"], exist_ok=True)
    x0, x1, z0, z1 = tile_range(city)
    tiles = []
    if opts["tile"]:
        tx, tz = [int(v) for v in opts["tile"].split(",")]
        tiles = [(tx, tz)]
    elif opts["only"]:
        tiles = parse_tiles(opts["only"])
    else:
        for tx in range(x0, x1 + 1):
            for tz in range(z0, z1 + 1):
                tiles.append((tx, tz))
    tile_blocks = split_all_blocks(city)
    # the clean-up runs AFTER the build: the game must never be left without its
    # tiles while the new ones are written
    all_tiles = set()
    for tx in range(x0, x1 + 1):
        for tz in range(z0, z1 + 1):
            all_tiles.add((tx, tz))
    # the tiles that must survive the clean-up: the ones this build wrote and, for
    # a partial build, the ones it did not touch
    keep_tiles = set(tiles) | (all_tiles - set(tiles)) if opts["only"] else set(tiles)
    # the at-grade ramps are obstacles like the surface roads: a ramp that has
    # not climbed yet stands on the ground
    segments = (citydata.road_segments(city)
                + citydata.at_grade_elevated_segments(city))
    grid = roadgrid.RoadGrid(segments)
    digest = hashlib.sha256(raw).hexdigest()
    tex_before = tile_io.snapshot_textures()
    total_tris = 0
    for (tx, tz) in tiles:
        started = time.time()
        col = common.collection("tile_%d_%d" % (tx, tz))
        bag, records, stats, block_stats = build_tile_within_budget(
            city, tx, tz, materials, tile_blocks.get((tx, tz), []), segments, grid,
            opts["near"])
        origin = (tx * TILE_M, tz * TILE_M)
        objs = bag.emit(col, "blocks_%d_%d" % (tx, tz))
        cols, near_flags = colliders.collider_objects(records, grid, col)
        far_objs, far_tris = far_objects(records, col, materials, opts["far"])
        all_objs = objs + cols
        if not all_objs:
            print("tile %d,%d: empty" % (tx, tz))
            continue
        name = "blocks_%d_%d" % (tx, tz)
        tile_io.export_tile(os.path.join(opts["out"], name + ".gltf"), all_objs)
        if far_objs:
            tile_io.export_tile(os.path.join(opts["out"], name + "_far.gltf"), far_objs)
        tile_io.write_sidecar(os.path.join(opts["out"], name + ".json"), tx, tz, records,
                              stats, origin, digest, near_flags, block_stats)
        tris = sum(common.tri_count(o) for o in all_objs)
        total_tris += tris
        print("tile %d,%d: %d blocks, %d buildings, %d tris, %d objects, %d colliders, "
              "far %d tris, %.1f s"
              % (tx, tz, stats["blocks"], len(records), tris, len(all_objs), len(cols),
                 far_tris, time.time() - started))
        if stats["empty_blocks"]:
            print("  blocks without building: %s" % stats["empty_blocks"])
    if not opts["tile"]:
        tile_io.clean_output(opts["out"], keep_names(opts["out"], keep_tiles))
    fixed = tile_io.restore_textures(tex_before)
    print("TOTAL tris %d (%d texture files restored after the export)" % (total_tris, fixed))
    from city.buildings.variety import NeighbourGuard
    print("neighbour guard: %d re-rolls" % NeighbourGuard.REROLLS)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
