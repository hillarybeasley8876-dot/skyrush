"""The tile builder: the blocks of one 512 m tile, one block at a time.

`build_city.py` drives the build (the tiles, the far LOD, the export); this
module turns the blocks of a tile into buildings: every block is planned into
parcels, every parcel into a building of the style of its block, and the ground
of the block is paved around them.
"""
import os
import random

from . import citydata, ground, kit, parcels, plan, shapes
from .ctx import Ctx
from .styles import heritage, industrial, midrise, neon
from .styles import office, park, residential, shikumen

# The dossier's Nanjing Rd pedestrian street (D2).  The map now has neon_street
# blocks, but the D2 rectangle still gets a neon frontage on the road-facing edge.
D2_RECT = (-900.0, -170.0, -560.0, -520.0)
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


def build_tile(city, tx, tz, materials, blocks, segments, grid, detail_map=None):
    """Build one tile; returns (bag, records, stats, block_stats).

    `detail_map` says how much decoration every building may keep (the tile is
    over its triangle budget); a building that is not in the map keeps it all.
    """
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
        ctx.detail_map = detail_map or {}
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
    rectangle that fitted inside it, which almost never happens on a staircase, so
    a fifth of the blocks stayed empty.  The polygon is cut into rectangles now, and
    every rectangle is planned with a frontage on the edge that faces a road.
    """
    from .variety import NeighbourGuard
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
