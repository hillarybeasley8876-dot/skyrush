"""The far-LOD triangle budget: how much detail a building may keep.

The far city of a tile may not blow its triangle budget (40 000 triangles per
512 m tile).  `far.py` builds the far masses; this module says how much detail
each of them may carry: a cost model that counts the triangles of a building at
every level of the detail ladder of `far.LEVELS`, and the rule that picks the
level of every building of a tile so that the tile fits.

The model mirrors the geometry of `far.add_far_from_record`; the build compares
the planned and the built triangles of every tile and warns when they differ.
"""
import math

from . import far


def _edge_lengths(poly):
    """The length of every edge of a ring."""
    n = len(poly)
    out = []
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        out.append(math.hypot(b[0] - a[0], b[1] - a[1]))
    return out


def _box_tris(poly):
    """The triangles of one far box: the wall quads and the roof cap."""
    n = len(poly)
    walls = sum(1 for L in _edge_lengths(poly) if L >= 0.2)
    return 2 * walls + (n - 2)


def _crown_tris(poly):
    """The triangles of the lit crown around a ring."""
    return 12 * sum(1 for L in _edge_lengths(poly) if L >= 0.3)


def _mech_tris(poly, vent_step):
    """The triangles of the mechanical floor: the band and its lit vents."""
    total = 0
    for L in _edge_lengths(poly):
        if L < 0.3:
            continue
        total += 12 + 12 * max(1, int(L / vent_step))
    return total


def far_cost(rec, level):
    """The triangles the far mass of one building takes at one detail level.

    The model mirrors `far.add_far_from_record` exactly, so a tile can plan its
    detail before a single face is built.
    """
    p = far.LEVELS[level]
    poly = far.outline_of(rec, p)
    h = float(rec.get("height", 10.0))
    style = rec.get("style", "midrise")
    tris = 0
    merged = h < p.podium_merge_h
    if not merged:
        tris += _box_tris(far.shrink(poly, 1.12))
    tris += _box_tris(poly)
    top_poly = poly
    if h > p.setback_min_h:
        top_poly = far.shrink(poly, 0.78)
        tris += _box_tris(top_poly)
    if h > p.crown_min_h:
        tris += _crown_tris(top_poly)
    if p.edge_lines and far.is_white_crown(rec):
        tris += 12 * len(poly)
    if h > p.mech_min_h:
        tris += _mech_tris(top_poly, p.vent_step)
    if h > p.mast_min_h:
        tris += 24
    if h > far.AVIATION_MIN_H:
        tris += 12
    if p.billboard and h > far.BILLBOARD_MIN_H and style in far.BILLBOARD_STYLES:
        tris += 12
    return tris


def _importance(rec):
    """How much a building matters to the skyline: the tall ones, then the big ones."""
    poly = rec.get("poly") or []
    h = float(rec.get("height", 0.0))
    area = 0.0
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        area += a[0] * b[1] - b[0] * a[1]
    return (h, abs(area) * 0.5)


def far_levels(recs, budget):
    """The detail level of every building of a tile.

    A tile that fits its budget keeps every building at level 0 (the committed
    look).  A tile over the budget drops to the first level that fits and then
    hands the detail back to the most important buildings (the towers of the
    skyline) while the tile still fits: the short blocks lose their tiny detail
    first, the silhouette of the towers does not change.
    """
    if not recs:
        return []
    levels_of_far = far.LEVELS
    costs = [[far_cost(rec, l) for l in range(len(levels_of_far))] for rec in recs]
    if sum(c[0] for c in costs) <= budget:
        return [0] * len(recs)
    level = 1
    while level < far.MAX_LEVEL and sum(c[level] for c in costs) > budget:
        level += 1
    levels = [level] * len(recs)
    total = sum(c[level] for c in costs)
    full = sum(c[0] for c in costs)
    floor = 0.30 * full        # the far city must keep a third of its triangles
    order = sorted(range(len(recs)), key=lambda i: (-_importance(recs[i])[0], i))
    for i in order:
        while levels[i] > 0:
            # the triangles the building takes again when it gets its detail back
            back = costs[i][levels[i] - 1] - costs[i][levels[i]]
            if total + back > budget:
                break
            if back < 0 and total + back < floor:
                break           # the far city must not lose its last triangles
            total += back
            levels[i] -= 1
    return levels
