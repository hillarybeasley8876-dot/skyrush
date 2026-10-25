"""city_charge — the 申城闪充 flash-charge gantries (dossier 8.2, gameplay 3.4).

The three charge stations of the map stood on the roads with their columns, posts and totem in the lanes (a car hit a
column at 100 km/h), the trigger of their bay floated over the Roadster (it never charged), and the nearest one was 910 m
away from the median lane point. A charger is a gantry over a main road now: its posts stand outside the carriageway (the
27 m guide gantry of the props unit on a road 20-26 m wide, the 19 m one on a street 13-17 m wide), a car that drives
under it at 60 km/h or more charges.

The gantries are spread over the map farthest-first: the next one goes to the eligible point nearest to the lane point
that is farthest from every charger so far. An eligible point is on a main road or a street of the right width, straight
for 25 m both ways, 50 m from every junction and 70 m from the ends of its road, 80 m from the other gantries, the sky
lane pads and the roadblock sites, and with no deck over it.
"""
import math

MAIN_ROADS = ("ns_elevated", "yanan_elevated", "lujiazui_ring_rd", "zhongshan_e2_s", "yanan_rd_surface",
              "pudong_south_rd", "bund_zhongshan_e1", "g50_west", "lujiazui_w_rd")
STREET_PREFIX = "st_"     # the streets of the districts: a 19 m gantry spans their 15 m
SPANS = ((13.0, 17.0, 19), (20.0, 26.0, 27))   # (the narrowest road, the widest, the span of the gantry)
STEP = 20.0               # m between the points of a road that are tried
JUNCTION_CLEAR = 50.0     # m from a junction (its gantries, its turning lanes)
END_CLEAR = 70.0          # m from the ends of the road
OTHER_CLEAR = 80.0        # m from the other gantries, the pads, the roadblock sites
STRAIGHT = 25.0           # m both ways that turn less than STRAIGHT_TURN
STRAIGHT_TURN = 4.0       # degrees
DECK_CLEAR = 9.0          # m: a road this much higher within DECK_REACH is a deck over the point
DECK_REACH = 16.0
COUNT = 12                # chargers on the map
DEPTH = 16.0              # m of road the charge area covers
DEMAND_STEP = 40.0        # m between the lane points the coverage is measured on


def _cum(points):
    out = [0.0]
    for a, b in zip(points, points[1:]):
        out.append(out[-1] + math.hypot(b[0] - a[0], b[2] - a[2]))
    return out


def _at(points, cum, s):
    """The point and the heading (degrees, 0 = north = -Z) at the distance s."""
    for i in range(1, len(points)):
        if cum[i] >= s or i == len(points) - 1:
            a, b = points[i - 1], points[i]
            seg = (cum[i] - cum[i - 1]) or 1.0
            t = max(0.0, min(1.0, (s - cum[i - 1]) / seg))
            p = [a[k] + (b[k] - a[k]) * t for k in range(3)]
            return p, math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0
    return list(points[-1]), 0.0


def _turn(a, b):
    return abs((b - a + 180.0) % 360.0 - 180.0)


def span_for(road):
    """The span of the gantry over a road (19 or 27 m), or 0 when no gantry fits it."""
    if road["id"] not in MAIN_ROADS and not road["id"].startswith(STREET_PREFIX):
        return 0
    if road["kind"] not in ("surface", "elevated"):
        return 0
    w = width_of(road)
    for lo, hi, span in SPANS:
        if lo <= w <= hi:
            return span
    return 0


def width_of(road):
    return ((road["lanes_fwd"] + road["lanes_back"]) * road["lane_width"] + road.get("median", 0.0)
            + 2.0 * road.get("shoulder", 0.0))


def _decks(roads):
    """Every point of every road, by 50 m cell: (x, y, z)."""
    cells = {}
    for r in roads:
        for p in r["points"][::2]:
            cells.setdefault((int(p[0] // 50), int(p[2] // 50)), []).append(p)
    return cells


def _under_deck(cells, p):
    for i in range(int(p[0] // 50) - 1, int(p[0] // 50) + 2):
        for j in range(int(p[2] // 50) - 1, int(p[2] // 50) + 2):
            for q in cells.get((i, j), ()):
                if q[1] - p[1] > DECK_CLEAR and math.hypot(q[0] - p[0], q[2] - p[2]) < DECK_REACH:
                    return True
    return False


def candidates(roads, junctions, avoid):
    """The eligible points: (x, y, z, heading, road id, road)."""
    cells = _decks(roads)
    out = []
    for r in roads:
        if span_for(r) == 0:
            continue
        pts = r["points"]
        cum = _cum(pts)
        s = END_CLEAR
        while s <= cum[-1] - END_CLEAR:
            p, h = _at(pts, cum, s)
            _b, h0 = _at(pts, cum, max(s - STRAIGHT, 0.0))
            _a, h1 = _at(pts, cum, min(s + STRAIGHT, cum[-1]))
            ok = _turn(h0, h) < STRAIGHT_TURN and _turn(h, h1) < STRAIGHT_TURN
            if ok:
                ok = all(math.hypot(j["x"] - p[0], j["z"] - p[2]) >= JUNCTION_CLEAR for j in junctions)
            if ok:
                ok = all(math.hypot(a[0] - p[0], a[1] - p[2]) >= OTHER_CLEAR for a in avoid)
            if ok:
                ok = not _under_deck(cells, p)
            if ok:
                out.append((p[0], p[1], p[2], h, r["id"], r))
            s += STEP
    return out


def demand(roads):
    """The lane points the coverage is measured on: every road but the tunnel, every DEMAND_STEP metres."""
    out = []
    for r in roads:
        if r["kind"] == "tunnel":
            continue
        pts = r["points"]
        cum = _cum(pts)
        s = 0.0
        while s <= cum[-1]:
            p, _h = _at(pts, cum, s)
            out.append((p[0], p[2]))
            s += DEMAND_STEP
    return out


def place(roads, junctions, avoid, count=COUNT):
    """The chargers, farthest-first, and the distances from the lane points to the nearest one."""
    cands = candidates(roads, junctions, avoid)
    points = demand(roads)
    if not cands or not points:
        return [], []
    nearest = [float("inf")] * len(points)
    chosen = []
    # the first one: the eligible point nearest to the middle of the lane points
    cx = sum(p[0] for p in points) / len(points)
    cz = sum(p[1] for p in points) / len(points)
    target = (cx, cz)
    for _ in range(count):
        best = None
        for c in cands:
            if any(math.hypot(c[0] - o[0], c[2] - o[2]) < OTHER_CLEAR * 4.0 for o in chosen):
                continue
            d = math.hypot(c[0] - target[0], c[2] - target[1])
            if best is None or d < best[0]:
                best = (d, c)
        if best is None:
            break
        c = best[1]
        chosen.append(c)
        for i, p in enumerate(points):
            nearest[i] = min(nearest[i], math.hypot(p[0] - c[0], p[1] - c[2]))
        far = max(range(len(points)), key=lambda i: nearest[i])
        target = points[far]
    return chosen, nearest


def charge_pois(roads, junctions, avoid, names, count=COUNT):
    """The POIs of the chargers ("kind": "charge", "style": "gantry") and a coverage report."""
    chosen, nearest = place(roads, junctions, avoid, count)
    out = []
    for i, c in enumerate(sorted(chosen, key=lambda c: (round(c[0]), round(c[2])))):
        road = c[5]
        out.append({"id": "charge_%s_%d" % (c[4], i + 1), "kind": "charge", "style": "gantry",
                    "x": round(c[0], 1), "y": round(c[1], 2), "z": round(c[2], 1),
                    "heading_deg": round(c[3], 1), "size": [round(width_of(road), 1), DEPTH],
                    "road": c[4], "label": "申城闪充·%s" % names.get(c[4], c[4]),
                    "asset": "guide_gantry_%d" % span_for(road), "span_m": span_for(road)})
    report = {}
    if nearest:
        s = sorted(nearest)
        report = {"count": len(out), "median_m": s[len(s) // 2], "p90_m": s[int(len(s) * 0.9)], "max_m": s[-1]}
    return out, report
