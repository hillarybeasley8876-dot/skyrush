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


def clip_polygon_by_corridor(poly, points, need):
    """The pieces of a lot that are left when the corridor of a road is cut out of it.

    poly    the lot, [[x, z], ...]
    points  the centre-line of the road, [[x, z], ...] (at least 2 points)
    need    the half width of the corridor (road half width plus clearance), metres
    Returns a list of polygons (see tools/city/selftest_lots.py for the exact contract).
    """
    raise NotImplementedError("clip_polygon_by_corridor: written by the job city-lots-clear")


def clear_of_roads(blocks, roads):
    """Every lot cut back from the roads (the rules 'blocks clear of the roads' and 'blocks clear of the decks').

    Called by build_city.main after all lots exist.  Returns the new list of lots (a lot that a road cuts in two
    becomes two lots).  For now it returns the lots unchanged: written by the job city-lots-clear.
    """
    return blocks
