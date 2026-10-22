"""city_rules_index — the spatial index of the deck clearance rule.

The clearance rule asks, for every 2 m sample of every road, how high the
*other* roads are under it.  The old code listed every point of every
neighbouring road for each sample (the 120 m `PolyIndex` cells) and then
walked the whole point list of the neighbour again for its height.

This module keeps the raw points of all the roads in one grid, so a sample
only looks at the points near it, and it gives the same answers:

  * a road qualifies when one of its points is within
    `width/2 + other_width/2` of the sample (the old within-list test);
  * the height there is the height of the *closest* point of the road, the
    first one on a tie (the old `_height_at`);
  * the roads come in the order of the old point list, so the printed
    failures do not move.
"""
import math

CELL = 16.0        # the cell of the point grid (m)
ROAD_CELL = 120.0  # the cell of the old point list (m)
EPS = 1e-12        # the slack of the squared distance test


class PointGrid:
    """The raw points of all the roads in one grid."""

    def __init__(self, roads, widths):
        self.half = [w * 0.5 for w in widths]
        self.max_half = max(self.half) if self.half else 0.0
        self.acc = [None] * len(roads)
        self.cells = {}
        for ri, road in enumerate(roads):
            for pi, pt in enumerate(road["points"]):
                x, y, z = pt[0], pt[1], pt[2]
                key = (int(x // CELL), int(z // CELL))
                self.cells.setdefault(key, []).append(
                    (x, z, y, ri, pi,
                     int(x // ROAD_CELL), int(z // ROAD_CELL)))

    def near(self, x, z, hw, radius, own):
        """The roads that come within the clearance bound of (x, z).

        Returns (candidates, own height): the candidates are the roads
        that qualify, as (road index, height), in the order of the old
        point list; the height is the height of the closest point of the
        road `own` (the old `_height_at`).
        """
        acc = self.acc
        half = self.half
        cells = self.cells
        touched = []
        span = int((hw + self.max_half) // CELL) + 1
        cx = int(x // CELL)
        cz = int(z // CELL)
        for i in range(cx - span, cx + span + 1):
            for j in range(cz - span, cz + span + 1):
                for (px, pz, py, ri, pi, bx, bz) in cells.get((i, j), ()):
                    dx = px - x
                    dz = pz - z
                    d2 = (dx ** 2) + (dz ** 2)
                    b = hw + half[ri]
                    b2 = b * b
                    if d2 > b2 * (1.0 + EPS):
                        continue
                    e = acc[ri]
                    if e is None:
                        e = [d2, pi, py, None, None, False]
                        acc[ri] = e
                        touched.append(ri)
                    elif d2 < e[0] or (d2 == e[0] and pi < e[1]):
                        e[0] = d2
                        e[1] = pi
                        e[2] = py
                    h = math.hypot(dx, dz)
                    if h > b or h > radius:
                        continue
                    e[5] = True
                    if e[3] is None or bx < e[3] or (bx == e[3] and bz < e[4]):
                        e[3] = bx
                        e[4] = bz
        own_y = None
        out = []
        for ri in touched:
            e = acc[ri]
            acc[ri] = None
            if ri == own:
                own_y = e[2]
            if e[5]:
                out.append((e[3], e[4], ri, e[2]))
        out.sort()
        return [(ri, y) for _bx, _bz, ri, y in out], own_y


def junction_pairs(city):
    """The junctions of every pair of roads (cached per city).

    The clearance rule asks for the junctions of one pair of roads at a
    time; this index keeps them ready instead of walking the 743 junctions
    of the city for every sample that fails.
    """
    pairs = city.get("_junction_pairs")
    if pairs is None:
        pairs = {}
        for j in city["junctions"]:
            roads = j["roads"]
            for i, a in enumerate(roads):
                for b in roads[i + 1:]:
                    pairs.setdefault((a, b) if a < b else (b, a),
                                     []).append(j)
        city["_junction_pairs"] = pairs
    return pairs


def attach_anchors(city, point_at):
    """The anchor of the attach point of every road (cached per city).

    `point_at` walks the whole point list of the parent, so the anchor is
    found once per road and not once per sample.
    """
    anchors = city.get("_attach_anchors")
    if anchors is None:
        by_id = {r["id"]: r for r in city["roads"]}
        anchors = {}
        for road in city["roads"]:
            got = {}
            for key in ("attach_start", "attach_end"):
                att = road.get(key)
                if not att:
                    continue
                parent = by_id.get(att["road"])
                if parent is None:
                    continue
                point, _tan = point_at(parent, att["at"])
                if point:
                    got[key] = (point[0], point[1])
            anchors[road["id"]] = got
        city["_attach_anchors"] = anchors
    return anchors
