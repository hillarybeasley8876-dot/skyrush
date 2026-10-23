"""city_grid — the surface street network of every district (dossier §10.5).

Each district has its own grain: D1 and D2 follow the Bund, D3 and D4 are
tilted 10-12 deg, D5 has its own angle, D6 follows Zhongshan E-2, D7 follows
Century Ave and the Lujiazui ring, D8 the Pudong grain.  The named Puxi
streets (Sichuan, Henan, Fujian, Xizang, Chongqing, Guangdong, Fuzhou,
Jiujiang, Nanjing E, Beijing E) keep their real positions.

Every street is clipped against the Huangpu and Suzhou Creek, and its ends
are snapped to the nearest crossing road, so the network has no dead ends
except at the map window edge (those are listed in the `dead_ends` note).
"""
import math
import os

import city_blocks
import city_corridor
import city_junctions
import city_landmarks
import city_marks
import city_rules
import city_snap
import city_trim
import citylib
from city_road import Road
from city_water import (CREEK, HUANGPU, _clip_rect, _creek_polygon,
                        _split_by_water, _water_polygon, is_water, on_land)

_LAYOUT = citylib.load_json(os.path.join(
    os.path.dirname(__file__), "..", "..", "ref", "shanghai", "build",
    "map_layout_v1.json"))
_LAYOUT_RIVER = _LAYOUT["river"]

WINDOW = {"x_min": -2200.0, "x_max": 1800.0, "z_min": -1200.0, "z_max": 1800.0}

REPAIR_ROUNDS = 4         # how often the repair pass looks for dead ends

# the named Puxi streets: (id, position, name, name_en)
NS_NAMED = [
    ("sichuan_rd", -255.0, "四川路", "Sichuan Rd"),
    ("henan_rd", -408.0, "河南路", "Henan Rd"),
    ("fujian_rd", -535.0, "福建路", "Fujian Rd"),
    ("xizang_rd", -720.0, "西藏路", "Xizang Rd"),
    ("chongqing_rd", -1080.0, "重庆路", "Chongqing Rd"),
]
EW_NAMED = [
    ("guangdong_rd", -110.0, "广东路", "Guangdong Rd"),
    ("fuzhou_rd", -230.0, "福州路", "Fuzhou Rd"),
    ("hankou_rd", -330.0, "汉口路", "Hankou Rd"),
    ("jiujiang_rd", -430.0, "九江路", "Jiujiang Rd"),
    ("nanjing_e_rd", -540.0, "南京东路", "Nanjing East Rd"),
    ("beijing_e_rd", -703.0, "北京东路", "Beijing East Rd"),
]

# district: rect, rotation (deg), spacing (m), style, lanes
# the rectangles tile the map window; where they overlap the district that
# comes first in DISTRICT_PRIORITY wins.
DISTRICTS = {
    "D1": ((-420.0, -170.0, -1200.0, 0.0), -26.0, 150.0, "heritage", 2),
    "D2": ((-900.0, -170.0, -580.0, -500.0), -26.0, 120.0, "neon_street", 2),
    "D3": ((-1150.0, -420.0, -1200.0, 100.0), 10.0, 165.0, "midrise", 2),
    "D4": ((-1150.0, -170.0, 250.0, 1150.0), -12.0, 120.0, "shikumen", 2),
    "D5": ((-2200.0, -1650.0, -1200.0, 400.0), 22.0, 190.0, "office_tower", 2),
    "D6": ((-170.0, 850.0, 0.0, 1800.0), 38.0, 155.0, "midrise", 2),
    "D7": ((500.0, 1800.0, -1200.0, 150.0), 113.0, 180.0, "office_tower", 2),
    "D8": ((1500.0, 1800.0, 150.0, 1800.0), 15.0, 165.0, "residential_slab", 2),
    "D9": ((-2200.0, -1650.0, 400.0, 1800.0), 0.0, 220.0, "industrial", 2),
    "D0": ((-170.0, 500.0, -1200.0, 0.0), -26.0, 200.0, "plaza", 1),
    "D3b": ((-1650.0, -1150.0, -1200.0, 1800.0), 6.0, 175.0, "midrise", 2),
    "D6b": ((-1150.0, -420.0, 100.0, 250.0), -6.0, 170.0, "midrise", 2),
    "D6c": ((-1150.0, -170.0, 1150.0, 1800.0), 8.0, 170.0, "midrise", 2),
    "D7b": ((850.0, 1500.0, 150.0, 1800.0), -12.0, 175.0, "office_tower", 2),
}
DISTRICT_KEYS = ["D1", "D2", "D3", "D3b", "D4", "D5", "D6", "D6b", "D6c",
                 "D7", "D7b", "D8", "D9", "D0"]
# the order in which the districts win where they overlap
DISTRICT_PRIORITY = ["D9", "D5", "D3b", "D2", "D1", "D3", "D4", "D6b", "D6",
                     "D6c", "D7", "D7b", "D8", "D0"]


def _lattice(lo, hi, spacing):
    """Line positions between lo and hi, `spacing` metres apart."""
    n = max(1, int(math.ceil((hi - lo) / spacing)))
    return [lo + (hi - lo) * i / n for i in range(n + 1)]


def _street(rid, name, name_en, plan, lanes=2, sidewalk=3.5, speed=40,
            style=None, kind="surface"):
    """One street from a plan (a list of points)."""
    if math.dist(plan[0], plan[-1]) < 25.0:
        return None
    return Road(rid, name, name_en, kind, [list(p) for p in plan],
                [("start", 0.0, 0.0), ("end", 0.0, 0.0)],
                lanes_fwd=lanes, lanes_back=lanes, lane_width=3.5, median=0.0,
                shoulder=0.5, sidewalk=sidewalk, speed_kmh=speed,
                style=style or {"parapet": "none", "lamps": "side",
                                "trees": "plane"})


def _bund_anchor(bund, z):
    """The point on the Bund's centre-line at the height `z` and the local
    tangent there (dossier 10.5: the D1 cross streets meet the Bund at a
    right angle and run to its centre-line)."""
    best, best_t = 1e18, None
    for a, b in zip(bund, bund[1:]):
        dx, dz = b[0] - a[0], b[1] - a[1]
        den = dx * dx + dz * dz
        if den < 1e-9:
            continue
        t = max(0.0, min(1.0, ((z - a[1]) * dz) / den))
        p = (a[0] + t * dx, a[1] + t * dz)
        d = abs(p[1] - z)
        if d < best:
            best, best_t = d, (p, (dx / den ** 0.5, dz / den ** 0.5))
    return best_t


# ---------------------------------------------------------------- the grid

def _named_ns_streets(counters, add, yanan):
    """The N-S streets: from the Yan'an Rd north to Suzhou Creek."""
    for name, x, cn, en in NS_NAMED:
        south = (x, _yanan_z(yanan, x))
        creek_z = _creek_z(x)
        north = (x, creek_z)
        runs = []
        for run in _split_by_water(south, north):
            if len(run) < 2:
                continue
            runs.append(run)
            add(name, cn, en, run[0], run[-1], 2, 3.5, 40)
        # the creek bridge: it joins the two parts of the street end to end
        for first, second in zip(runs, runs[1:]):
            add(name + "_bridge", cn + "桥", en + " Bridge",
                first[-1], second[0], 2, 0.0, 40, kind="bridge")


def _yanan_z(yanan, x):
    """The height of the Yan'an Rd surface at the position x."""
    if yanan is None:
        return 150.0
    best, best_z = 1e18, 150.0
    for p in yanan.points:
        d = abs(p[0] - x)
        if d < best:
            best, best_z = d, p[2]
    return best_z


def _creek_z(x):
    """The z of the Suzhou Creek centre-line at the position x."""
    line = [tuple(p) for p in _LAYOUT_RIVER["suzhou_creek_centerline"]]
    best, best_z = 1e18, None
    for a, b in zip(line, line[1:]):
        dx, dz = b[0] - a[0], b[1] - a[1]
        den = dx * dx + dz * dz
        if den < 1e-9:
            continue
        t = max(0.0, min(1.0, ((x - a[0]) * dx) / den))
        p = (a[0] + t * dx, a[1] + t * dz)
        d = abs(p[0] - x)
        if d < best:
            best, best_z = d, p[1]
    return best_z


def _named_ew_streets(bund, add):
    """The E-W streets: they meet the Bund at a right angle (dossier 10.5)."""
    for name, z, cn, en in EW_NAMED:
        anchor = _bund_anchor(bund, z)
        if anchor is None:
            continue
        p, tan = anchor
        head = math.degrees(math.atan2(tan[0], -tan[1]))
        west = (head - 90.0) % 360.0
        d = (math.sin(math.radians(west)), -math.cos(math.radians(west)))
        limit = -350.0 if name == "nanjing_e_rd" else -900.0
        length = (limit - p[0]) / d[0] if d[0] < -1e-6 else 900.0
        end = (p[0] + d[0] * length, p[1] + d[1] * length)
        add(name, cn, en, p, end, 2, 3.5 if name != "nanjing_e_rd" else 4.0, 30,
            style={"parapet": "none", "lamps": "magnolia", "trees": "plane"})


def _split_by_rects(p0, p1, rects):
    """The parts of a segment that are outside every rectangle."""
    parts = [(p0, p1)]
    for rect in rects:
        out = []
        for a, b in parts:
            clipped = _clip_rect(a, b, rect)
            if clipped is None:
                out.append((a, b))
                continue
            if math.dist(a, clipped[0]) > 0.5:
                out.append((a, clipped[0]))
            if math.dist(clipped[1], b) > 0.5:
                out.append((clipped[1], b))
        parts = out
    return parts


def _corridors(roads, streets):
    """The corridors of the arterial roads: the streets may not run in them."""
    out = []
    for road in roads:
        if road.kind != "surface":
            continue
        out.append({"id": road.id, "points": [(p[0], p[2]) for p in road.points],
                    "half": city_corridor.corridor_half(road.to_dict())})
    for street in streets:
        out.append({"id": street.id, "points": [(p[0], p[2]) for p in street.points],
                    "half": city_corridor.corridor_half(street.to_dict())})
    return out


def _district_lattice(counters, add, corridors):
    """The generated lattice of every district, in the district's own grain."""
    for rank, did in enumerate(DISTRICT_PRIORITY):
        (x0, x1, z0, z1), angle, spacing, style, lanes = DISTRICTS[did]
        blocked = [DISTRICTS[d][0] for d in DISTRICT_PRIORITY[:rank]]
        a = math.radians(angle)
        ux, uz = math.cos(a), math.sin(a)
        vx, vz = -math.sin(a), math.cos(a)
        cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
        corners = [(x0 - cx, z0 - cz), (x1 - cx, z0 - cz),
                   (x1 - cx, z1 - cz), (x0 - cx, z1 - cz)]
        us = [p[0] * ux + p[1] * uz for p in corners]
        vs = [p[0] * vx + p[1] * vz for p in corners]
        reach = math.hypot(x1 - x0, z1 - z0)
        axes = ((ux, uz, vx, vz, min(us), max(us), "ns"),
                (vx, vz, ux, uz, min(vs), max(vs), "ew"))
        for ux2, uz2, vx2, vz2, lo, hi, tag in axes:
            for pos in _lattice(lo, hi, spacing):
                origin = (cx + ux2 * pos, cz + uz2 * pos)
                p0 = (origin[0] - vx2 * reach, origin[1] - vz2 * reach)
                p1 = (origin[0] + vx2 * reach, origin[1] + vz2 * reach)
                clipped = _clip_rect(p0, p1, (x0, x1, z0, z1))
                if not clipped:
                    continue
                for seg in _split_by_rects(clipped[0], clipped[1], blocked):
                    for run in _split_by_water(seg[0], seg[1]):
                        for piece in _cut(run, corridors):
                            if math.dist(piece[0], piece[-1]) < 40.0:
                                continue
                            add("%s_%s" % (did.lower(), tag), "%s 街" % did,
                                "%s street" % did, piece, None, 1, 3.0, 30)


def _cut(run, corridors):
    """The pieces of a lattice line that lie outside the arterial corridors.

    The ends of the pieces are bent so that they meet the arterial at a
    right angle instead of following it.
    """
    if not corridors:
        return [run]
    out = []
    for piece in city_corridor.trim(run, corridors):
        piece = city_corridor.dogleg(piece, corridors, at_end=True)
        piece = city_corridor.dogleg(piece, corridors, at_end=False)
        if len(piece) > 1:
            out.append(piece)
    return out


def build_streets(main_roads):
    """The surface street network: the named streets plus the lattices."""
    streets = []
    counters = {}

    def add(name, cn, en, p0, p1=None, lanes=2, sidewalk=3.5, speed=40,
            style=None, kind="surface"):
        plan = [p0, p1] if p1 is not None else p0
        st = _street("", cn, en, plan, lanes, sidewalk, speed, style, kind)
        if st is None:
            return None
        counters[name] = counters.get(name, 0) + 1
        st.id = "st_%s" % name if counters[name] == 1 \
            else "st_%s_%d" % (name, counters[name])
        st.name = cn
        st.name_en = en
        streets.append(st)
        return st

    bund = None
    yanan = None
    for road in main_roads:
        if road.id == "bund_zhongshan_e1":
            bund = [(p[0], p[2]) for p in road.points]
        if road.id == "yanan_rd_surface":
            yanan = road
    if bund is None:
        bund = [(4.2, -10.2), (-111.3, -245.7), (-145.3, -524.4)]
    _named_ns_streets(counters, add, yanan)
    _named_ew_streets(bund, add)
    # the named streets are built first: the corridors of the lattice are
    # measured on them
    for st in streets:
        st.build()
    _district_lattice(counters, add, _corridors(main_roads, streets))
    # the streets are built before the snapping, so the search knows where
    # every road really runs
    for st in streets:
        st.build()
    streets, dead_ends = _snap_ends(streets, main_roads)
    for st in streets:
        st.build()
    dead_ends = _repair_ends(streets, main_roads, add)
    for st in streets:
        st.build()
    # the streets that run under a low ramp are cut: the ramp can neither
    # be raised nor the street lowered, so the street gives way.  The cut
    # has to come after the snapping and the repair, or the snapper joins
    # the cut ends back across the ramp.
    streets = city_trim.trim_under_decks(
        streets, main_roads,
        only_decks=("nanpu_spiral_lower", "nanpu_pudong_loop"))
    return streets, dead_ends


def _repair_ends(streets, main_roads, add):
    """Every road end the rule calls a dead end gets a road to meet.

    The lattice is cut by the district borders and by the corridors of
    the arterials, so a street often stops where the neighbouring
    district has no street of its own.  Such an end is joined to the
    nearest road by a short link, or extended along its own line to the
    next road, or - when it is only a short stub - cut back to the
    last junction it had.  A main road is never moved: it gets a link.

    The link comes first: it adds a street, while the extension moves
    a street that is already there, and the landmark lots stand clear
    of the roads, so moving one of them moves the lots as well.
    """
    attached = _attached_ends(main_roads + streets)
    main_ids = set(road.id for road in main_roads)
    number = _link_number(streets)
    for _ in range(REPAIR_ROUNDS):
        net = city_snap.Net(main_roads + streets)
        junctions = city_junctions.build_junctions(net.roads)
        broken = _broken_ends(net, junctions, attached)
        if not broken:
            return []
        lots = _landmark_lots(net.roads)
        off_limits = city_snap.route_roads(net.roads, junctions)
        fixed = 0
        for road, end in broken:
            number += 1
            name = "link_%d" % number
            if city_snap.fix_end(net, road, end, junctions, add, name,
                                 road.id not in main_ids, lots, off_limits):
                fixed += 1
                if len(road.plan) < 2:
                    # the stub carried nothing: the street is dropped
                    streets.remove(road)
        if not fixed:
            break
    net = city_snap.Net(main_roads + streets)
    junctions = city_junctions.build_junctions(net.roads)
    out = []
    for road, end in _broken_ends(net, junctions, attached):
        point = net.end_point(road, end)
        out.append((road.id, round(point[0], 1), round(point[1], 1)))
    return out


def _link_number(streets):
    """The first free number of a link street."""
    used = [int(st.id[len("st_link_"):]) for st in streets
            if st.id.startswith("st_link_") and st.id[len("st_link_"):].isdigit()]
    return max(used) if used else 0


def _landmark_lots(roads):
    """The lots of the map that a street may not cut.

    The landmarks and the parks stand where the dossier puts them, and
    the frontage of the Bund, the pedestrian street and the green
    strips of Century Avenue run along their roads.  A new street has
    to miss them all.
    """
    surface = [road for road in roads if road.kind == "surface"]
    pois = city_marks.build_pois({road.id: road for road in surface})
    lots = city_landmarks.landmark_blocks(surface)
    lots += city_landmarks.park_blocks(surface)
    lots += city_blocks.special_blocks(surface, pois)
    return [block["polygon"] for block in lots]


def _attached_ends(roads):
    """The road ends that the assembly attaches to a parent road.

    The assembly (build_city) sets the attaches after the streets are
    built, so the repair pass asks it which ends it will take.  The
    import is late on purpose: build_city imports this module.
    """
    import build_city
    known = set(road.id for road in roads)
    out = {}
    for child_id, child_key, parent_id, parent_key, _target in \
            build_city.CONNECTIONS:
        if child_key and child_id in known:
            out[(child_id, 0 if child_key == "attach_start" else 1)] = parent_id
        if parent_key and parent_id in known:
            out[(parent_id, 0 if parent_key == "attach_start" else 1)] = child_id
    return out


def _broken_ends(net, junctions, attached):
    """The road ends the rule calls a dead end."""
    roads = []
    for road in net.roads:
        data = road.to_dict()
        for key, end in (("attach_start", 0), ("attach_end", 1)):
            parent = attached.get((road.id, end))
            if parent:
                data[key] = {"road": parent, "at": 0.0, "side": "right"}
        roads.append(data)
    city = {"roads": roads, "junctions": junctions, "window": WINDOW}
    out = []
    for message in city_rules.check_dead_ends(city):
        words = message.split()
        road = net.by_id.get(words[0])
        if road is None:
            continue
        out.append((road, 0 if words[1] == "start" else 1))
    return out


def _snap_ends(streets, main_roads, reach=400.0):
    """Extend every street end to the road it meets.

    The end walks along the street's own line until it reaches a road: the
    end of a street that crosses a road stops on the road's centre-line, the
    end of a street that runs along a road stops at the road's edge.  The
    ends that find no road are listed as the dead ends of the map.
    """
    polys = {}
    widths = {}
    for road in main_roads:
        polys[road.id] = [(p[0], p[2]) for p in road.points]
        widths[road.id] = citylib.road_width(road)
    for st in streets:
        polys[st.id] = [(p[0], p[2]) for p in st.points]
        widths[st.id] = citylib.road_width(st)
    index = city_snap.coarse_index(polys, widths)
    dead = []
    loose = []
    for st in streets:
        for end in (0, 1):
            point = (st.plan[end][0], st.plan[end][1])
            snapped, road_id = city_snap.snap_end(st.plan, end, index, polys,
                                                  widths, st.id, WINDOW)
            if snapped is None or not on_land(point, snapped):
                loose.append((st, end))
                continue
            if math.dist(snapped, point) > 0.5:
                st.plan[end] = [snapped[0], snapped[1]]
    # a street that finds no road is joined to the nearest one by a link
    links = _link_ends(loose, polys, widths, index)
    # the links are roads now: a second pass catches the ends they reach
    still = []
    for st, end in loose:
        point = (st.plan[end][0], st.plan[end][1])
        if _linked(point, links):
            continue
        snapped, road_id = city_snap.snap_end(st.plan, end, index, polys,
                                              widths, st.id, WINDOW)
        if snapped is None or not on_land(point, snapped):
            still.append((st, end))
            continue
        if math.dist(snapped, point) > 0.5:
            st.plan[end] = [snapped[0], snapped[1]]
    for st, end in still:
        point = (st.plan[end][0], st.plan[end][1])
        dead.append((st.id, round(point[0], 1), round(point[1], 1)))
    streets.extend(links)
    # a street that collapsed into a stub carries nothing
    for st in list(streets):
        if math.dist(st.plan[0], st.plan[-1]) < 25.0:
            streets.remove(st)
    return streets, dead


def _linked(point, links):
    """True if a link road starts at the point."""
    for link in links:
        if math.dist((link.plan[0][0], link.plan[0][1]), point) < 1.0:
            return True
    return False


def _link_ends(loose, polys, widths, index):
    """A short link road from every street end that finds no other road."""
    links = []
    for i, (st, end) in enumerate(loose):
        point = (st.plan[end][0], st.plan[end][1])
        head = city_snap.direction(st.plan, end)
        cands = []
        for name, _idx, _near in index.within(point, 320.0):
            if name == st.id:
                continue
            poly = polys[name]
            dist, near = city_snap.closest_point(poly, point)
            if dist < 25.0 or dist > 320.0:
                continue
            # the link must meet the road it joins at a real angle
            link_dir = ((near[0] - point[0]) / dist,
                        (near[1] - point[1]) / dist)
            angle = city_snap.angle_between(
                link_dir, city_snap.poly_direction(poly, 0))
            if angle < 20.0:
                continue
            cands.append((dist, near))
        cands.sort()
        near = None
        for _dist, point_on_road in cands:
            if on_land(point, point_on_road):
                near = point_on_road
                break
        if near is None:
            continue
        link = _street("st_link_%d" % (i + 1), st.name, st.name_en,
                       [point, near], 1, 3.0, 30, st.style)
        if link is None:
            continue
        links.append(link)
        polys[link.id] = [(point[0], point[1]), (near[0], near[1])]
        widths[link.id] = citylib.road_width(link)
        index.add(link.id, [(point[0], point[1]), (near[0], near[1])])
    return links
