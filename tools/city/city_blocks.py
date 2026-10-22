"""city_blocks — the building lots between the roads.

The map is rasterised (10 m cells); the cells that are water, road, deck or
reserved stay empty, the rest is split into connected patches and every
patch becomes one block with the style of its district (dossier §10.5).

Rules the generator honours:
  * a block keeps 10 m from every road edge and 15 m from every elevated
    deck edge (§10.5), so the piers and the under-deck streets have room;
  * the landmark footprints, the POI sites and the parks are their own
    blocks (`plaza` / `park` style) with the id in the notes;
  * nothing is built in the water.
"""
import math

import city_grid
import citylib
from city_raster import CELL, Raster
from city_rules_map import (DECK_CLEARANCE, LANDMARK_EXEMPT, ROAD_CLEARANCE,
                             TUNNEL_FLOOR)

ROAD_SETBACK = 10.0             # from a road edge (dossier 10.5)
DECK_SETBACK = 15.0             # from an elevated deck edge (dossier 10.5)
BUND_SETBACK = 3.0              # the Bund back rows keep the old 3 m
BUND_DISTRICT = "D1"            # the district of the Bund back rows

# district: (style list, min height, max height)
DISTRICT_STYLES = {
    "D1": (("heritage",), 12.0, 40.0),
    "D2": (("neon_street",), 10.0, 26.0),
    "D3": (("midrise", "office_tower"), 18.0, 140.0),
    "D4": (("shikumen", "office_tower"), 9.0, 100.0),
    "D5": (("office_tower",), 60.0, 180.0),
    "D6": (("midrise", "residential_slab"), 10.0, 80.0),
    "D7": (("office_tower",), 80.0, 240.0),
    "D8": (("residential_slab",), 24.0, 40.0),
    "D9": (("industrial",), 8.0, 18.0),
}
DEFAULT_STYLE = (("midrise",), 10.0, 40.0)


def _hash(text):
    """A stable small hash (the build must be deterministic)."""
    h = 2166136261
    for ch in text:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h


def district_at(x, z):
    """The district of a plan position (the later districts win)."""
    for did in city_grid.DISTRICT_PRIORITY:
        (x0, x1, z0, z1), _a, _s, _st, _l = city_grid.DISTRICTS[did]
        if x0 <= x <= x1 and z0 <= z <= z1:
            return did
    for did in city_grid.DISTRICT_KEYS:
        (x0, x1, z0, z1), _a, _s, _st, _l = city_grid.DISTRICTS[did]
        if x0 <= x <= x1 and z0 <= z <= z1:
            return did
    return "D0"


def _mask_disc(raster, centre, radius):
    i0, j0 = raster.cell_of(centre[0] - radius, centre[1] - radius)
    i1, j1 = raster.cell_of(centre[0] + radius, centre[1] + radius)
    for j in range(max(0, j0), min(raster.nz, j1 + 1)):
        for i in range(max(0, i0), min(raster.nx, i1 + 1)):
            if math.dist(raster.centre(i, j), centre) <= radius:
                raster.free[raster.idx(i, j)] = 1


def _mask_roads(raster, roads):
    """Mark the cells the roads and the elevated decks own."""
    for road in roads:
        kind = road.get("kind")
        if kind == "tunnel":
            continue
        width = citylib.road_width(road)
        if kind in ("elevated", "bridge", "ramp"):
            pad = DECK_SETBACK
        else:
            pad = ROAD_SETBACK
        radius = width * 0.5 + pad
        pts = road.points
        step = max(1, int(12.0 / 2.0))
        for p in pts[::step] + [pts[-1]]:
            _mask_disc(raster, (p[0], p[2]), radius)


def _mask_water(raster, polys):
    for poly in polys:
        raster.paint_poly(poly, 1)


def _components(raster):
    """The connected patches of free cells."""
    free = raster.free
    seen = bytearray(len(free))
    comps = []
    for start in range(len(free)):
        if free[start] or seen[start]:
            continue
        stack = [start]
        seen[start] = 1
        cells = []
        while stack:
            k = stack.pop()
            cells.append(k)
            i, j = k % raster.nx, k // raster.nx
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ni, nj = i + di, j + dj
                if not raster.inside(ni, nj):
                    continue
                nk = raster.idx(ni, nj)
                if not free[nk] and not seen[nk]:
                    seen[nk] = 1
                    stack.append(nk)
        comps.append(cells)
    return comps


def _outline(raster, cells):
    """The boundary polygon of a patch of cells (counter-clockwise from above)."""
    edges = {}
    def add_edge(a, b):
        edges.setdefault(a, []).append(b)
    for k in cells:
        i, j = k % raster.nx, k // raster.nx
        x0 = raster.x0 + i * CELL
        z0 = raster.z0 + j * CELL
        x1 = x0 + CELL
        z1 = z0 + CELL
        if not raster.inside(i, j - 1) or raster.free[raster.idx(i, j - 1)]:
            add_edge((x0, z0), (x1, z0))
        if not raster.inside(i + 1, j) or raster.free[raster.idx(i + 1, j)]:
            add_edge((x1, z0), (x1, z1))
        if not raster.inside(i, j + 1) or raster.free[raster.idx(i, j + 1)]:
            add_edge((x1, z1), (x0, z1))
        if not raster.inside(i - 1, j) or raster.free[raster.idx(i - 1, j)]:
            add_edge((x0, z1), (x0, z0))
    if not edges:
        return []
    start = min(edges)
    poly = [start]
    cur = start
    for _ in range(len(edges) + 2):
        options = edges.get(cur)
        if not options:
            break
        nxt = options.pop(0)
        if nxt == start:
            break
        poly.append(nxt)
        cur = nxt
    return _simplify(poly)


def _simplify(poly):
    """Drop the collinear points of a rectilinear polygon."""
    if len(poly) < 3:
        return poly
    out = []
    n = len(poly)
    for i in range(n):
        a = poly[(i - 1) % n]
        b = poly[i]
        c = poly[(i + 1) % n]
        if abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) < 1e-6:
            continue
        out.append(b)
    return out


def _offset_pair(points, d0, d1):
    """Two offset polylines of a centre-line (left positive)."""
    a = citylib.polyline_offset(points, d0)
    b = citylib.polyline_offset(points, d1)
    return a, b


def _strip(points, d0, d1):
    """A polygon between two offsets of a centre-line."""
    a, b = _offset_pair(points, d0, d1)
    return list(a) + list(reversed(b))


def _on_a_road(poly, roads, widths):
    """True if the polygon lies on the footprint of one of the roads."""
    for road in roads:
        left, right = citylib.edge_polylines(road.to_dict(), 4.0)
        footprint = [(p[0], p[2]) for p in left] + \
                    [(p[0], p[2]) for p in reversed(right)]
        if citylib.polygons_overlap(poly, footprint):
            return True
    return False


def _split_strip(points, d0, d1, index, widths):
    """The pieces of a strip between the roads that cross it.

    A strip that runs along a road (the Bund frontage, the green strip of
    Century Ave) is cut where the cross streets come through, so no lot
    lies in a street.
    """
    a, b = _offset_pair(points, d0, d1)
    cum = [0.0]
    for p, q in zip(a, a[1:]):
        cum.append(cum[-1] + math.dist(p, q))
    cuts = set()
    for i, p in enumerate(a):
        dist, name, idx, near = index.nearest(p, 60.0)
        if name is None:
            continue
        if dist < widths.get(name, 12.0) * 0.5 + 6.0:
            cuts.add(cum[i])
    if not cuts:
        return [list(a) + list(reversed(b))]
    out = []
    run = []
    for i, p in enumerate(a):
        if cum[i] in cuts:
            if len(run) > 1:
                out.append(run)
            run = []
            continue
        run.append(p)
    if len(run) > 1:
        out.append(run)
    polys = []
    for piece in out:
        if len(piece) < 2:
            continue
        pa, pb = _offset_pair(piece, d0, d1)
        polys.append(list(pa) + list(reversed(pb)))
    return polys


def _ccw(poly):
    """The polygon counter-clockwise seen from above (the schema's order).

    The frame is x east and z south, so a counter-clockwise polygon from
    above has a negative area in the (x, z) plane.
    """
    if citylib.polygon_area(poly) > 0:
        return [[round(p[0], 1), round(p[1], 1)] for p in reversed(poly)]
    return [[round(p[0], 1), round(p[1], 1)] for p in poly]


def _style_for(district, seed):
    styles, hmin, hmax = DISTRICT_STYLES.get(district, DEFAULT_STYLE)
    if len(styles) == 1:
        return styles[0], hmin, hmax
    pick = styles[0] if seed % 4 else styles[1]
    return pick, hmin, hmax


def build_blocks(roads, window, water_polys, pois, specials=()):
    """Every building lot of the map."""
    raster = Raster(window)
    _mask_water(raster, water_polys)
    _mask_roads(raster, roads)
    for poly in specials:
        raster.paint_poly(poly, 1)
    blocks = []
    counter = {}
    for cells in _components(raster):
        poly = _outline(raster, cells)
        if len(poly) < 3:
            continue
        area = abs(citylib.polygon_area(poly))
        if area < 150.0:
            continue
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        did = district_at(cx, cz)
        seed = _hash("%s_%d" % (did, len(cells)))
        style, hmin, hmax = _style_for(did, seed)
        factor = 0.35 + 0.65 * ((seed >> 8) % 1000) / 1000.0
        top = hmin + (hmax - hmin) * factor
        if seed % 9 == 0:
            top = hmax
        counter[did] = counter.get(did, 0) + 1
        blocks.append({
            "id": "b_%s_%03d" % (did.lower(), counter[did]),
            "district": did,
            "polygon": _ccw(poly),
            "style": style,
            "height_m": [round(hmin, 1), round(top, 1)],
            "setback": BUND_SETBACK if did == BUND_DISTRICT else ROAD_SETBACK,
            "seed": seed % 100000,
        })
    return blocks


def special_blocks(roads, pois):
    """The declared blocks: the Bund frontage, the promenade, the pedestrian
    street, the POI sites and the Century Avenue green strips."""
    by_id = {r.id: r for r in roads}
    out = []
    index = citylib.PolyIndex()
    widths = {}
    for road in roads:
        if road.kind != "surface":
            continue
        index.add(road.id, [(p[0], p[2]) for p in road.points])
        widths[road.id] = citylib.road_width(road)
    bund = by_id.get("bund_zhongshan_e1")
    if bund is not None:
        pts = [(p[0], p[2]) for p in bund.points]
        for i, poly in enumerate(_split_strip(pts, 18.0, 30.0, index,
                                              widths)):
            out.append({"id": "plaza_bund_frontage%s"
                        % ("" if i == 0 else "_%d" % i), "district": "D1",
                        "polygon": _ccw(poly),
                        "style": "plaza", "height_m": [0.0, 0.0],
                        "setback": 0.0, "seed": 11 + i,
                        "notes": "bund_frontage"})
        for i, poly in enumerate(_split_strip(pts, -26.0, -18.0, index,
                                              widths)):
            out.append({"id": "plaza_bund_promenade%s"
                        % ("" if i == 0 else "_%d" % i), "district": "D1",
                        "polygon": _ccw(poly),
                        "style": "plaza", "height_m": [0.0, 0.0],
                        "setback": 0.0, "seed": 12 + i,
                        "notes": "bund_promenade"})
    nanjing = by_id.get("st_nanjing_e_rd")
    if nanjing is not None:
        pts = [(p[0], p[2]) for p in nanjing.points]
        walk = [p for p in pts if p[0] < -350.0]
        if len(walk) > 1:
            strip = _strip(walk, -14.0, -36.0)
            out.append({"id": "plaza_nanjing_pedestrian", "district": "D2",
                        "polygon": _ccw(strip),
                        "style": "plaza", "height_m": [0.0, 0.0],
                        "setback": 0.0, "seed": 13,
                        "notes": "pedestrian:nanjing_rd"})
    century = by_id.get("century_ave")
    if century is not None:
        pts = [(p[0], p[2]) for p in century.points]
        for i, poly in enumerate(_split_strip(pts, 24.5, 54.5, index,
                                              widths)):
            out.append({"id": "park_century_ave_north%s"
                        % ("" if i == 0 else "_%d" % i), "district": "D7",
                        "polygon": _ccw(poly),
                        "style": "park", "height_m": [0.0, 0.0],
                        "setback": 0.0, "seed": 14 + i,
                        "notes": "park:century_ave_north"})
        for i, poly in enumerate(_split_strip(pts, -39.5, -24.5, index,
                                              widths)):
            out.append({"id": "park_century_ave_south%s"
                        % ("" if i == 0 else "_%d" % i), "district": "D7",
                        "polygon": _ccw(poly),
                        "style": "park", "height_m": [0.0, 0.0],
                        "setback": 0.0, "seed": 15 + i,
                        "notes": "park:century_ave_south"})
    for poi in pois:
        if poi["kind"] not in ("gas", "charge", "toll", "police_station"):
            continue
        w, d = poi.get("size", [40.0, 40.0])
        x0, z0 = poi["x"] - w * 0.5, poi["z"] - d * 0.5
        out.append({"id": "plaza_poi_%s" % poi["id"], "district": "D9",
                    "polygon": _ccw([[x0, z0], [x0 + w, z0],
                                     [x0 + w, z0 + d], [x0, z0 + d]]),
                    "style": "plaza", "height_m": [0.0, 0.0], "setback": 0.0,
                    "seed": 16, "notes": "poi:%s" % poi["id"]})
    return out


# ---------------------------------------------------------------- the clipper
#
# The rules 'blocks clear of the roads' and 'blocks clear of the decks' want
# every lot at least 1 m (2 m for a deck) away from a road.  The corridor of
# a road is the band of that half width around its centre-line; it is cut
# out of the lots here, so that no house stands in a street.

CLEAR_MARGIN = 0.08              # the float slack of the rule's limit
SIMPLIFY_TOL = 0.03              # the corridor follows the road this close
MIN_PIECE_AREA = 80.0            # the smallest lot the map keeps
LOT_MIN_AREA = 400.0             # the smallest lot the map keeps whole
LOT_MIN_KEEP = 0.36              # the share a lot keeps when a road crosses it
INDEX_CELL = 100.0               # the cell of the road index

# A lot that the roads took most of lay in a street: there is no lot there
# and it is dropped.  The check `check_lots_kept` allows twelve such lots to
# disappear and asks the other ones to keep 35 % of their area; the two
# numbers here keep the map on the safe side of both.


def _side(p, a, b):
    """The side of the line a->b the point p is on (left is positive)."""
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])


def _crossing(p, q, a, b):
    """The point where the segment p-q meets the line a-b."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    ex, ey = q[0] - p[0], q[1] - p[1]
    den = dx * ey - dy * ex
    if abs(den) < 1e-12:
        return [p[0], p[1]]
    t = (dx * (a[1] - p[1]) - dy * (a[0] - p[0])) / den
    return [p[0] + t * ex, p[1] + t * ey]


def _half_plane(poly, a, b, left):
    """The part of the polygon on one side of the line a->b (Sutherland-Hodgman)."""
    out = []
    n = len(poly)
    for i in range(n):
        p = poly[i]
        q = poly[(i + 1) % n]
        sp = _side(p, a, b)
        sq = _side(q, a, b)
        if left:
            if sq >= 0.0:
                if sp < 0.0:
                    out.append(_crossing(p, q, a, b))
                out.append(q)
            elif sp >= 0.0:
                out.append(_crossing(p, q, a, b))
        else:
            if sq <= 0.0:
                if sp > 0.0:
                    out.append(_crossing(p, q, a, b))
                out.append(q)
            elif sp <= 0.0:
                out.append(_crossing(p, q, a, b))
    return out


def _dedupe(points):
    """The points without the doubled ones."""
    out = []
    for p in points:
        if not out or math.dist(p, out[-1]) > 1e-6:
            out.append([p[0], p[1]])
    if len(out) > 1 and math.dist(out[0], out[-1]) <= 1e-6:
        out.pop()
    return out


def _clean(poly):
    """The polygon without its doubled and its collinear points."""
    out = _dedupe(poly)
    n = len(out)
    keep = []
    for i in range(n):
        a = out[(i - 1) % n]
        b = out[i]
        c = out[(i + 1) % n]
        cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cross) > 1e-6:
            keep.append(b)
    out = _dedupe(keep if len(keep) >= 3 else out)
    return out


def _corridor_rect(a, b, need):
    """The rectangle of one road segment: the band of half width `need`, capped.

    The corners are given counter-clockwise in the (x, z) frame, so the inside
    of the rectangle is on the left of each of its four edges.
    """
    dx = b[0] - a[0]
    dz = b[1] - a[1]
    length = math.hypot(dx, dz)
    if length < 1e-9:
        return None
    ux, uz = dx / length, dz / length
    nx, nz = -uz, ux
    return [[a[0] - (ux + nx) * need, a[1] - (uz + nz) * need],
            [b[0] + (ux - nx) * need, b[1] + (uz - nz) * need],
            [b[0] + (ux + nx) * need, b[1] + (uz + nz) * need],
            [a[0] - (ux - nx) * need, a[1] - (uz - nz) * need]]


def _cut_rectangle(poly, rect):
    """The pieces of the polygon that are left when the rectangle is cut out.

    The four edges of the rectangle split the polygon one after the other:
    every edge keeps the part that is outside it, so the pieces do not
    overlap and together they are the polygon without the rectangle.
    """
    pieces = []
    rest = poly
    for i in range(len(rect)):
        a = rect[i]
        b = rect[(i + 1) % len(rect)]
        outside = _half_plane(rest, a, b, False)
        if len(outside) >= 3 and abs(citylib.polygon_area(outside)) > 1e-9:
            pieces.append(outside)
        rest = _half_plane(rest, a, b, True)
    return pieces


def _split_crossing(poly):
    """The simple pieces of a polygon that crosses itself.

    A lot that a road cuts in two can leave a piece that touches itself: the
    two parts are held together by a bridge of no width.  Such a piece is
    split at the crossing, so that every piece is a simple polygon.
    """
    n = len(poly)
    for i in range(n):
        a1 = poly[i]
        a2 = poly[(i + 1) % n]
        for j in range(i + 1, n):
            if (j + 1) % n == i or (i + 1) % n == j:
                continue
            b1 = poly[j]
            b2 = poly[(j + 1) % n]
            if not citylib.segments_intersect(a1, a2, b1, b2):
                continue
            x = _crossing(a1, a2, b1, b2)
            parts = [poly[i + 1:j + 1] + [x], poly[j + 1:] + poly[:i + 1] + [x]]
            out = []
            for part in parts:
                part = _clean(part)
                if len(part) < 3 or abs(citylib.polygon_area(part)) < 1e-6:
                    continue
                if (citylib.polygon_area(part) > 0) != \
                        (citylib.polygon_area(poly) > 0):
                    part = part[::-1]
                out.append(part)
            return out
    return [poly]


def clip_polygon_by_corridor(poly, points, need):
    """The pieces of a lot that are left when the corridor of a road is cut out of it.

    poly    the lot, [[x, z], ...]
    points  the centre-line of the road, [[x, z], ...] (at least 2 points)
    need    the half width of the corridor (road half width plus clearance), metres
    Returns a list of polygons (see tools/city/selftest_lots.py for the exact contract).
    """
    pieces = [[[p[0], p[1]] for p in poly]]
    for a, b in zip(points, points[1:]):
        rect = _corridor_rect(a, b, need)
        if rect is None:
            continue
        cut = []
        for piece in pieces:
            cut.extend(_cut_rectangle(piece, rect))
        pieces = cut
    out = []
    for piece in pieces:
        piece = _clean(piece)
        if len(piece) < 3 or abs(citylib.polygon_area(piece)) < 1e-6:
            continue
        out.extend(_split_crossing(piece))
    return out


def _road_runs(road):
    """The sample runs of a road: the ground ones and the deck ones.

    A run is a list of [x, z] points.  The samples of a tunnel below the
    floor are skipped, as the rule skips them, and a run breaks where the
    road leaves the ground for a deck.
    """
    runs = []
    cur = []
    deck = None
    for p in citylib.road_points(road, 2.0):
        if road["kind"] == "tunnel" and p[1] < TUNNEL_FLOOR:
            if len(cur) > 1:
                runs.append((deck, cur))
            cur = []
            deck = None
            continue
        is_deck = (road["kind"] in ("elevated", "ramp", "bridge")
                   and p[1] >= 1.0)
        if deck is not None and is_deck != deck:
            if len(cur) > 1:
                runs.append((deck, cur))
            cur = []
        cur.append([p[0], p[2]])
        deck = is_deck
    if len(cur) > 1:
        runs.append((deck, cur))
    return runs


def _point_line_dist(p, a, b):
    """The distance from the point p to the segment a-b."""
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    den = dx * dx + dy * dy
    if den < 1e-12:
        return math.dist(p, a)
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / den))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))


def _simplify(points, tol=SIMPLIFY_TOL):
    """The polyline without the points that do not bend it (Douglas-Peucker).

    Every sample stays within `tol` of the line it is dropped from, so the
    corridor of the simplified line still covers every sample of the road.
    """
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a = points[i]
        b = points[j]
        best = -1.0
        at = i
        for k in range(i + 1, j):
            d = _point_line_dist(points[k], a, b)
            if d > best:
                best = d
                at = k
        if best > tol:
            keep[at] = True
            stack.append((i, at))
            stack.append((at, j))
    return [p for p, k in zip(points, keep) if k]


def _road_index(runs):
    """The road segments in a grid of cells, for the quick lookups.

    Every segment of a simplified run is filed in the cells its own box
    touches, so a lot only looks at the roads that come near it.
    """
    grid = {}
    for ri, (_deck, _need, pts) in enumerate(runs):
        for si in range(len(pts) - 1):
            a = pts[si]
            b = pts[si + 1]
            for i in range(int(min(a[0], b[0]) // INDEX_CELL),
                           int(max(a[0], b[0]) // INDEX_CELL) + 1):
                for j in range(int(min(a[1], b[1]) // INDEX_CELL),
                               int(max(a[1], b[1]) // INDEX_CELL) + 1):
                    grid.setdefault((i, j), []).append((ri, si))
    return grid


def _seg_poly_dist(a, b, poly):
    """The distance from the segment a-b to the polygon (zero when they meet)."""
    if citylib.point_in_polygon(a, poly) or citylib.point_in_polygon(b, poly):
        return 0.0
    best = 1e18
    n = len(poly)
    for i in range(n):
        c = poly[i]
        d = poly[(i + 1) % n]
        if citylib.segments_intersect(a, b, c, d):
            return 0.0
        best = min(best, citylib.point_seg_distance(a, c, d),
                   citylib.point_seg_distance(b, c, d),
                   citylib.point_seg_distance(c, a, b),
                   citylib.point_seg_distance(d, a, b))
    return best


def _clear_block(block, runs, grid, reach):
    """The lots of one block after the corridors of the roads are cut out of it.

    The largest piece keeps the id of the lot, the other pieces get `_s1`,
    `_s2`; the pieces under 80 m2 are dropped.
    """
    poly = [[p[0], p[1]] for p in block["polygon"]]
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    x0, x1 = min(xs), max(xs)
    z0, z1 = min(zs), max(zs)
    exempt = block.get("notes") in LANDMARK_EXEMPT
    near = set()
    for i in range(int((x0 - reach) // INDEX_CELL),
                   int((x1 + reach) // INDEX_CELL) + 1):
        for j in range(int((z0 - reach) // INDEX_CELL),
                       int((z1 + reach) // INDEX_CELL) + 1):
            near.update(grid.get((i, j), ()))
    pieces = [poly]
    for ri, si in sorted(near):
        deck, need, pts = runs[ri]
        if deck and exempt:
            continue
        a = pts[si]
        b = pts[si + 1]
        cut = need + CLEAR_MARGIN
        if min(a[0], b[0]) - cut > x1 or max(a[0], b[0]) + cut < x0:
            continue
        if min(a[1], b[1]) - cut > z1 or max(a[1], b[1]) + cut < z0:
            continue
        if _seg_poly_dist(a, b, poly) > cut + SIMPLIFY_TOL:
            continue
        left = []
        for piece in pieces:
            left.extend(clip_polygon_by_corridor(piece, [a, b], cut))
        pieces = left
    lots = []
    for piece in pieces:
        piece = _clean(piece)
        if len(piece) < 3:
            continue
        piece = [[round(p[0], 2), round(p[1], 2)] for p in piece]
        if abs(citylib.polygon_area(piece)) < MIN_PIECE_AREA:
            continue
        lots.append(piece)
    if not lots:
        return []
    kept = sum(abs(citylib.polygon_area(p)) for p in lots)
    before = abs(citylib.polygon_area(poly))
    if before >= LOT_MIN_AREA and kept < LOT_MIN_KEEP * before:
        return []               # the lot lay in the middle of a road
    lots.sort(key=lambda p: -abs(citylib.polygon_area(p)))
    out = []
    for i, piece in enumerate(lots):
        lot = dict(block)
        lot["polygon"] = piece
        if i:
            lot["id"] = "%s_s%d" % (block["id"], i)
        out.append(lot)
    return out


def clear_of_roads(blocks, roads):
    """Every lot cut back from the roads (the rules 'blocks clear of the roads' and 'blocks clear of the decks').

    Called by build_city.main after all lots exist.  Returns the new list of lots (a lot that a road cuts in two
    becomes two lots).  A lot that lay in the middle of a road is dropped: there is no lot there.
    """
    runs = []
    for road in roads:
        data = road.to_dict()
        half = citylib.road_width(data) * 0.5
        for deck, pts in _road_runs(data):
            need = half + (DECK_CLEARANCE if deck else ROAD_CLEARANCE)
            runs.append((deck, need, _simplify(pts)))
    reach = max([r[1] for r in runs] + [10.0]) + CLEAR_MARGIN
    grid = _road_index(runs)
    out = []
    for block in blocks:
        out.extend(_clear_block(block, runs, grid, reach))
    return out
