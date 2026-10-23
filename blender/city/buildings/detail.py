"""The near-LOD detail budget: the decoration a building keeps.

A tile may not blow its near triangle budget (600 000 triangles per 512 m tile).
The optional detail of a building - the ornament, the window frames, the signs,
the roof clutter - is decoration, and the decoration of the least important
buildings goes first: the ones farthest from the road and the smallest ones.

The budget of a building is a number:

  3  everything (the committed look)
  2  the tier-1 decoration is gone (the roof clutter, the AC units, the attic
     balustrade, the small ornaments)
  1  the tier-1 and the tier-2 decoration are gone (the window frames, the
     cornices, the balconies, the signs)
  0  only the mass of the building is left

The style modules know their own decoration; the share of a building's triangles
that each tier takes is measured per style (TIER_SHARE).  The plan then spreads
the reduction over the least important buildings until the tile fits its budget.
"""
from . import citydata

FULL = 3

# the share of a building's triangles that each decoration tier takes, per style.
# Measured on the trial build of the city (the script is in the job notes): the
# numbers are the share of a building's own triangles.
TIER_SHARE = {
    "heritage": (0.124, 0.529, 0.020),
    "midrise": (0.421, 0.239, 0.000),
    "neon_street": (0.237, 0.478, 0.000),
    "office_tower": (0.059, 0.564, 0.000),
    "shikumen": (0.290, 0.185, 0.000),
    "residential_slab": (0.250, 0.300, 0.000),
    "industrial": (0.200, 0.100, 0.000),
}
DEFAULT_SHARE = (0.250, 0.300, 0.000)


def poly_key(poly):
    """The key of a building footprint (two decimals, like the sidecar records)."""
    return tuple((round(float(p[0]), 2), round(float(p[1]), 2)) for p in poly)


def centroid(poly):
    """The centre of a footprint."""
    n = len(poly)
    if n == 0:
        return (0.0, 0.0)
    return (sum(p[0] for p in poly) / n, sum(p[1] for p in poly) / n)


def area(poly):
    """The area of a footprint."""
    total = 0.0
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        total += a[0] * b[1] - b[0] * a[1]
    return abs(total) * 0.5


def is_building(rec):
    """True for a record that carries a building (a park has no decoration)."""
    if rec.get("style") in ("park", "plaza") or rec.get("ground"):
        return False
    return len(rec.get("poly") or []) >= 3


def importance(rec, segments):
    """The sort key of a building: the farthest from the road first, the smallest first."""
    poly = rec.get("poly") or []
    cx, cz = centroid(poly)
    d = citydata.road_edge_distance(cx, cz, segments)
    return (-d, area(poly))


def make_plan(records, counts, segments, need):
    """The detail budget of every building of a tile: {footprint key: budget}.

    `need` is the number of triangles the tile has to lose.  The reduction is
    spread over the least important buildings: the first tier goes to the
    buildings that can lose the most for the least, and only the buildings that
    are left over lose their second tier.  A building never loses more than it
    has: the mass of a building is not decoration.  The second value is the
    saving the plan promises, so the caller can correct the plan.
    """
    usable = [rec for rec in records if is_building(rec)]
    usable.sort(key=lambda rec: importance(rec, segments))
    budgets = {}
    for rec in usable:
        budgets[poly_key(rec["poly"])] = FULL
    left = float(need)
    promised = 0.0
    for tier in range(len(DEFAULT_SHARE)):
        if left <= 0.0:
            break
        overspent = False
        for rec in usable:
            if left <= 0.0:
                break
            key = poly_key(rec["poly"])
            if budgets[key] <= FULL - tier - 1:
                continue          # this building already lost that tier
            share = TIER_SHARE.get(rec.get("style"), DEFAULT_SHARE)
            save = share[tier] * counts.get(key, 0)
            if save <= 0.0:
                continue
            if save > left and overspent:
                continue          # too big a step, and we already stretched once
            if save > left:
                overspent = True  # the tile must fit: this building pays the rest
            budgets[key] = FULL - tier - 1
            left -= save
            promised += save
    return budgets, promised
