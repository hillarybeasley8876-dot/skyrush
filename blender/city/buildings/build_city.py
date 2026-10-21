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
import random
import sys
import time

import bmesh
import bpy

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))

from lib import common  # noqa: E402

from city.buildings import cells, citydata, colliders, far, ground, kit  # noqa: E402
from city.buildings import parcels  # noqa: E402
from city.buildings import plan, roadgrid, shapes, tile_io  # noqa: E402
from city.buildings.ctx import Ctx  # noqa: E402
from city.buildings.styles import heritage, industrial, midrise, neon  # noqa: E402
from city.buildings.styles import office, park, residential, shikumen  # noqa: E402

TILE_M = 512.0
# The dossier's Nanjing Rd pedestrian street (D2).  The map now has neon_street
# blocks, but the D2 rectangle still gets a neon frontage on the road-facing edge.
D2_RECT = (-900.0, -170.0, -560.0, -520.0)
OUT_DIR = os.path.expanduser("~/m/skyrush/game/assets/city/blocks")
# the building stands at the edge of the block polygon: the map already sets the blocks
# back from the sidewalk, and a second setback would open a 12-17 m band of paving
STREET_SETBACK = 0.8

STYLES = {
    "shikumen": shikumen,
    "midrise": midrise,
    "office_tower": office,
    "residential_slab": residential,
    "heritage": heritage,
    "neon_street": neon,
    "industrial": industrial,
    "park": park,
    "plaza": park,
}

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
    """--city <path> --out <dir> --tile <tx,tz> --only <tx,tz;tx,tz>"""
    opts = {"city": citydata.default_city_path(), "out": OUT_DIR, "tile": None, "only": None}
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


def build_tile(city, tx, tz, materials, blocks, segments, grid):
    """Build one tile; returns (bag, records, stats)."""
    bag = kit.Bag(materials)
    records = []
    block_stats = []
    water = citydata.water_polygons(city)
    empty = {}
    for block in blocks:
        style = block.get("style", "midrise")
        module = STYLES.get(style)
        if module is None:
            continue
        seed = int(block.get("seed", 0)) * 7919 + tx * 131 + tz * 17
        rng = random.Random(seed)
        ctx = Ctx(seed, bag, water)
        ctx.roads = nearby_segments(segments, block["polygon"], 40.0)
        ctx.reset_pool()
        frame = plan.Frame(block["polygon"])
        before = len(records)
        try:
            _block_ground(ctx, block, frame, grid)
            if style in ("park", "plaza"):
                module.generate(ctx, block, frame, rng, records)
            else:
                _generate_parcels(ctx, module, block, seed, grid, records)
            if style != "neon_street" and _in_d2(block["polygon"]):
                _add_d2_neon(ctx, block, records[before:], segments, rng)
        except Exception as exc:  # a bad block must not kill the whole city
            import traceback
            print("WARN block %s (%s): %s" % (block.get("id"), style, exc))
            traceback.print_exc()
        if len(records) == before and style not in ("park", "plaza"):
            empty[style] = empty.get(style, 0) + 1
            if os.environ.get("BLOCK_DEBUG"):
                plist = parcels.of_block(block["polygon"], grid)
                print("EMPTY %s %s parcels=%d %s" % (
                    block["id"], style, len(plist),
                    [(round(p.width), round(p.depth), p.front, p.street) for p in plist[:6]]))
        block_stats.append(_block_stat(block, style, records[before:]))
    stats = {"blocks": len(blocks), "buildings": len(records), "tris": bag.tris(),
             "empty_blocks": empty}
    return bag, records, stats, block_stats


def _block_stat(block, style, records):
    """The built coverage of one block: the footprint area over the block area."""
    area = abs(shapes.signed_area([(p[0], p[1]) for p in block["polygon"]]))
    built = 0.0
    for rec in records:
        poly = rec.get("poly") or []
        if len(poly) >= 3:
            built += abs(shapes.signed_area([(p[0], p[1]) for p in poly]))
    return {"id": block["id"], "style": style, "area": round(area, 1),
            "built": round(built, 1), "buildings": len(records),
            "coverage": round(built / area, 3) if area > 1.0 else 0.0}


def _generate_parcels(ctx, module, block, seed, grid, records):
    """Plan every parcel of a block on its own.

    The block polygon is a 10 m raster outline; the planner used to ask for ONE
    rectangle that fitted inside it, which almost never happens on a staircase, so a
    fifth of the blocks stayed empty.  The polygon is cut into rectangles now, and
    every rectangle is planned with a frontage on the edge that faces a road.
    """
    from city.buildings.variety import NeighbourGuard
    ctx.guard = NeighbourGuard()
    for pi, parcel in enumerate(parcels.of_block(block["polygon"], grid)):
        pframe = plan.Frame(parcel.corners(), front_edge=0)
        pblock = dict(block)
        pblock["id"] = "%s_p%d" % (block["id"], pi)
        pblock["setback"] = STREET_SETBACK if parcel.street else 0.0
        prng = random.Random((seed + pi * 7919) & 0x7FFFFFFF)
        module.generate(ctx, pblock, pframe, prng, records)


def _block_ground(ctx, block, frame, grid):
    """The ground cover of a block: the paving inside it and the strip to the kerb."""
    ctx.begin_building(block["polygon"])
    ground.block_paving(ctx, frame)
    ground.kerb_strip(ctx, frame, grid)
    ctx.end_building()


def _in_d2(poly):
    """True when a block polygon touches the dossier's Nanjing Rd rectangle."""
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    return not (max(xs) < D2_RECT[0] or min(xs) > D2_RECT[1]
                or max(zs) < D2_RECT[2] or min(zs) > D2_RECT[3])


def _add_d2_neon(ctx, block, records, segments, rng):
    """Give a D2 block the neon frontage on the edge that faces the road."""
    for rec in records:
        poly = [(p[0], p[1]) for p in rec.get("poly", [])]
        if len(poly) != 4:
            continue
        best = None
        for edge in range(4):
            fc = plan.facade(poly, edge)
            mid = (fc["a"][0] + fc["b"][0]) * 0.5, (fc["a"][1] + fc["b"][1]) * 0.5
            d = citydata.road_edge_distance(mid[0], mid[1], segments)
            if best is None or d < best[0]:
                best = (d, edge)
        if best is None or best[0] > 40.0:
            continue
        neon.add_frontage_neon(ctx, poly, best[1], int(rec.get("floors", 6)), rng)


def nearby_segments(segments, polygon, pad):
    """The road segments close to a block (a cheap spatial filter)."""
    xs = [p[0] for p in polygon]
    zs = [p[1] for p in polygon]
    x0, x1 = min(xs) - pad, max(xs) + pad
    z0, z1 = min(zs) - pad, max(zs) + pad
    out = []
    for (ax, az, bx, bz, hw) in segments:
        if max(ax, bx) < x0 or min(ax, bx) > x1:
            continue
        if max(az, bz) < z0 or min(az, bz) > z1:
            continue
        out.append((ax, az, bx, bz, hw))
    return out


def _far_buckets():
    """The empty far-LOD buckets of one cell."""
    return {"wall_office": bmesh.new(), "wall_resi": bmesh.new(), "roof": bmesh.new()}


def far_objects(records, col, materials):
    """The far LOD: one merged mass per facade preset and cell, plus the crowns."""
    per_cell = {}
    for rec in records:
        if rec.get("style") in ("park", "plaza"):
            continue
        poly = rec.get("poly") or []
        if len(poly) < 3:
            continue
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        cell = cells.cell_of(cx, cz)
        buckets = per_cell.setdefault(cell, _far_buckets())
        far.add_far_from_record(buckets, rec)
    out = []
    for cell, buckets in sorted(per_cell.items()):
        centre = cells.cell_centre_blender(cell[0], cell[1])
        for key, bm in sorted(buckets.items()):
            if len(bm.faces) == 0:
                bm.free()
                continue
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
    return out


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
        bag, records, stats, block_stats = build_tile(city, tx, tz, materials,
                                                      tile_blocks.get((tx, tz), []),
                                                      segments, grid)
        origin = (tx * TILE_M, tz * TILE_M)
        objs = bag.emit(col, "blocks_%d_%d" % (tx, tz))
        cols, near_flags = colliders.collider_objects(records, grid, col)
        far_objs = far_objects(records, col, materials)
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
        print("tile %d,%d: %d blocks, %d buildings, %d tris, %d objects, %d colliders, %.1f s"
              % (tx, tz, stats["blocks"], len(records), tris, len(all_objs), len(cols),
                 time.time() - started))
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
