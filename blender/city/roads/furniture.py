"""Road furniture placement: lamps, gantries, signs, trees, bus stops, cable anchors.

The props unit models the objects; the world unit places them from
game/world/data/road_furniture.json. Coordinates are Godot space (x east, y up,
z south), heading 0 = north.

Every prop stands on the surface of the road it belongs to: a traffic light of
an elevated road stands on the deck, not on the street below it, and a prop
that would grow through a deck is dropped.
"""
import math

from mathutils import Vector

DECK_LAMP_SPACING = 32.0
SURFACE_LAMP_SPACING = 30.0
GANTRY_SPACING = 500.0
VMS_SPACING = 800.0
TREE_SPACING = 7.0
BUS_STOP_SPACING = 400.0
CABLE_SPACING = 9.6
TUNNEL_LIGHT_SPACING = 12.0
EXIT_ADVANCE = (500.0, 300.0, 100.0)   # the exit advance signs, in metres
CLEARANCE = 0.5                  # the gap a prop must keep from a road surface above
GIRDER_DEPTH = 2.0                # the deck structure under an elevated road
LAMP_HEIGHT = 9.0
TREE_HEIGHT = 14.0
NOISE_WALL_HEIGHT = 3.5
DIVERGE_ANGLE = 30.0             # a ramp that leaves the road at this angle is an off-ramp

SIGN_TEXTS = [
    "延安高架路 Yan'an Elevated Rd",
    "南北高架路 N-S Elevated Rd",
    "外滩 The Bund",
    "陆家嘴 Lujiazui",
    "出口 EXIT",
    "西藏中路 出口 500m",
    "内环高架 Inner Ring",
    "南浦大桥 Nanpu Bridge",
    "延安东路隧道 Yan'an E. Rd Tunnel",
    "外滩隧道 Bund Tunnel",
    "虹桥机场 Hongqiao Airport",
]


def godot(p):
    """Blender (x, y, z) -> Godot (x, y, z) with y up."""
    return (round(p.x, 2), round(p.z, 2), round(-p.y, 2))


def _heading(tangent):
    """Heading in degrees, 0 = north (-Z in Godot, +Y in Blender), 90 = east.

    The tangent is a Blender vector (x east, y north). The first version used -y as the north
    and so gave 180 degrees minus the heading: right on a road that runs east or west, upside
    down on a road that runs north or south and a mirror image on every diagonal one (the
    lamp arms, the signs and the traffic lights of the diagonal roads were turned by the
    difference). The world unit also rotates the bus shelters and the noise walls by the lanes
    next to them (they do not trust this heading), see world/build/furniture_builder.gd.
    """
    return round(math.degrees(math.atan2(tangent.x, tangent.y)) % 360.0, 1)


def _item(kind, road, p, tangent, extra=None):
    x, y, z = godot(p)
    out = {"kind": kind, "road": road.id, "x": x, "y": y, "z": z,
           "heading_deg": _heading(tangent)}
    if extra:
        out.update(extra)
    return out


def clean_name(name):
    """Drop a parenthesised qualifier: 'Yan'an Rd (surface)' -> 'Yan'an Rd'."""
    out = name.split("(")[0].strip()
    return out if out else name


def _lamp_style(road, style):
    """Prop type for a road's lamp style (matches the world's prop library)."""
    if style == "heritage":
        return "lamp_heritage"
    return "lamp"


def _clearance_ok(city, point, height, ignore_road=None):
    """False when a road surface passes within CLEARANCE above the prop."""
    for road in city.roads:
        if ignore_road is not None and road.id == ignore_road.id:
            continue
        dist, idx = road.nearest(point)
        if dist > 60.0:
            continue
        other_z = road.path[idx].z - (GIRDER_DEPTH if road.elevated else 0.0)
        if other_z <= point.z + 0.2:
            continue          # the road runs below the prop
        if other_z >= point.z + height + CLEARANCE:
            continue          # the road runs well above the prop
        return False
    return True


def lamps(city, road, items):
    """Street and deck lamps along a road (a tunnel has its own lighting)."""
    style = road.style.get("lamps", "none")
    if style == "none" or road.kind == "tunnel":
        return
    kind = _lamp_style(road, style)
    spacing = DECK_LAMP_SPACING if road.elevated else SURFACE_LAMP_SPACING
    height = 11.0 if road.elevated else (9.0 if style == "magnolia" else LAMP_HEIGHT)
    s = spacing * 0.5
    side = 1
    while s < road.length:
        p, t, r, u, _ = road.at(s)
        if road.elevated:
            pos = p
            extra = {"arms": 2, "height_m": height, "mount": "median"}
        else:
            off = road.lanes_fwd * road.lane_width * 0.5 + road.median * 0.5 + 2.0
            pos = p + r * (side * off)
            extra = {"arms": 1, "height_m": height, "mount": "sidewalk"}
        if _clearance_ok(city, pos, height, road):
            items.append(_item(kind, road, pos, t, extra))
        side = -side
        s += spacing


def tunnel_lights(city, road, items):
    """The ceiling lights of a tunnel: one record every 12 m per bore.

    The world unit puts them in its light pool: a tunnel without them is a
    black hole in the night city.
    """
    if road.kind != "tunnel":
        return
    from city.roads import profiles, tunnel
    lay = profiles.layout(road)
    s = 6.0
    while s < road.length:
        p, t, r, u, _ = road.at(s)
        for index, offset in enumerate(tunnel.bore_offsets(lay)):
            pos = p + r * offset + u * (tunnel.CLEARANCE - 0.2)
            items.append(_item("tunnel_light", road, pos, t, {
                "bore": index, "height_m": tunnel.CLEARANCE - 0.2,
                "energy": 2.4, "distance_m": round(s, 1)}))
        s += TUNNEL_LIGHT_SPACING


def _exits(city, road):
    """The off-ramps that leave this road: (distance, destination road).

    An off-ramp starts on the road it leaves and ends lower down (or on
    another road of the same level). A ramp that climbs onto the road is an
    on-ramp and gets no exit sign.
    """
    out = []
    for other in city.roads:
        if other.kind != "ramp" or other.id == road.id:
            continue
        start = other.data.get("attach_start")
        end = other.data.get("attach_end")
        if not start or start.get("road") != road.id:
            continue
        if not end or end.get("road") == road.id:
            continue
        if not _leaves(other, road, start):
            continue
        dest = city.by_id.get(end.get("road"))
        if dest is None:
            continue
        out.append((float(start["at"]), dest))
    return out


def _leaves(ramp, parent, attach):
    """True when the ramp leaves the parent road instead of climbing onto it."""
    start_z = ramp.path[0].z
    end_z = ramp.path[-1].z
    pidx = parent.index_at(float(attach["at"]))
    parent_z = parent.path[pidx].z
    if end_z > parent_z + 0.5:
        return False       # the ramp climbs onto the parent: an on-ramp
    if end_z < start_z - 0.5:
        return True        # the ramp descends from the parent: an off-ramp
    # the same level: it is a left turn ramp when it leaves at an angle
    t_ramp = ramp.frames[0][0]
    t_parent = parent.frames[pidx][0]
    return t_ramp.dot(t_parent) < math.cos(math.radians(DIVERGE_ANGLE))


def _destinations_ahead(city, road, s, count):
    """The roads met by the next junctions ahead of `s`: [(name, name_en, angle)]."""
    out = []
    for junction in city.junctions_of(road):
        dist, idx = road.nearest(city.junction_centre(junction))
        if dist <= s:
            continue
        for rid in junction.get("roads", []):
            other = city.by_id.get(rid)
            if other is None or other.id == road.id:
                continue
            if any(o[0] == clean_name(other.name) for o in out):
                continue
            _d, oidx = other.nearest(city.junction_centre(junction))
            turn = road.frames[idx][0].angle(other.frames[oidx][0])
            if turn > math.pi:
                turn -= 2.0 * math.pi
            out.append((clean_name(other.name), clean_name(other.name_en or other.name), turn))
            if len(out) >= count:
                out.sort(key=lambda o: o[2])
                return out
    out.sort(key=lambda o: o[2])
    return out


def _arrow(angle):
    """The arrow of a guide sign for a turn of this angle (radians)."""
    if angle > math.radians(20.0):
        return "→"
    if angle < -math.radians(20.0):
        return "←"
    return "↑"


def gantries(city, road, items):
    """Guide gantries: a direction sign every 500 m and the exit advance signs."""
    if not road.elevated:
        return
    s = GANTRY_SPACING
    while s < road.length:
        p, t, r, u, _ = road.at(s)
        if not _clearance_ok(city, p, 6.0, road):
            s += GANTRY_SPACING
            continue
        names = _destinations_ahead(city, road, s, 2)
        if names:
            text = "  ".join("%s %s" % (_arrow(a), n[0]) for n in names)
            text_en = "  ".join("%s %s" % (_arrow(a), n[1]) for n in names)
        else:
            text = clean_name(road.name)
            text_en = clean_name(road.name_en or road.name)
        items.append(_item("gantry", road, p, t, {
            "clearance_m": 5.5, "text": text, "text_en": text_en,
            "kind_text": "direction"}))
        s += GANTRY_SPACING
    for (at, dest) in _exits(city, road):
        for d in EXIT_ADVANCE:
            s = at - d
            if s < 5.0 or s > road.length:
                continue
            p, t, r, u, _ = road.at(s)
            if not _clearance_ok(city, p, 6.0, road):
                continue
            items.append(_item("gantry", road, p, t, {
                "clearance_m": 5.5, "text": "%s 出口 %dm" % (clean_name(dest.name), int(d)),
                "text_en": "%s Exit %d m" % (clean_name(dest.name_en or dest.name), int(d)),
                "kind_text": "exit"}))
    s = VMS_SPACING
    while s < road.length:
        p, t, r, u, _ = road.at(s)
        if _clearance_ok(city, p, 2.5, road):
            items.append(_item("vms", road, p, t, {"width_m": 8.0, "height_m": 2.5}))
        s += VMS_SPACING


def trees(city, road, items):
    """Plane trees along a surface road."""
    if road.style.get("trees", "none") != "plane" or road.sidewalk <= 0.0:
        return
    s = 3.0
    side = 1
    while s < road.length:
        p, t, r, u, _ = road.at(s)
        off = road.lanes_fwd * road.lane_width * 0.5 + road.median * 0.5 + 1.6
        pos = p + r * (side * off)
        if _clearance_ok(city, pos, TREE_HEIGHT, road):
            items.append(_item("tree", road, pos, t, {"height_m": TREE_HEIGHT}))
        side = -side
        s += TREE_SPACING


def bus_stops(city, road, items):
    """Bus shelters along a surface street."""
    if road.elevated or road.sidewalk <= 0.0:
        return
    s = 60.0
    side = 1
    while s < road.length:
        p, t, r, u, _ = road.at(s)
        off = road.lanes_fwd * road.lane_width * 0.5 + road.median * 0.5 + 2.4
        pos = p + r * (side * off)
        if _clearance_ok(city, pos, 3.0, road):
            items.append(_item("bus_stop", road, pos, t, {"length_m": 8.0}))
        side = -side
        s += BUS_STOP_SPACING


def noise_walls(city, road, items):
    """Noise wall runs declared in the road style."""
    for (a, b, side) in road.style.get("noise_walls", []) or []:
        s = float(a)
        while s < float(b):
            p, t, r, u, _ = road.at(s)
            sign = 1.0 if side in ("left", "both") else -1.0
            if side == "both":
                sign = 1.0 if (int(s / 30) % 2 == 0) else -1.0
            off = road.lanes_fwd * road.lane_width * 0.5 + road.median * 0.5 + 1.0
            pos = p + r * (sign * off)
            if not _clearance_ok(city, pos, NOISE_WALL_HEIGHT, road):
                s += 30.0
                continue
            items.append(_item("noise_wall", road, pos, t, {"length_m": 30.0}))
            s += 30.0


def cable_anchors(road, items):
    """Cable anchor sockets on a cable-stayed bridge deck."""
    if not road.bridge:
        return
    offset = road.lanes_fwd * road.lane_width * 0.5 + road.median * 0.5 + 1.0
    s = 0.0
    while s <= road.length:
        j = road.index_at(s)
        p = road.path[j]
        r = road.frames[j][1]
        u = road.frames[j][2]
        for sign, tag in ((1.0, "R"), (-1.0, "L")):
            items.append(_item("cable_anchor", road, p + r * (sign * offset) + u * 0.35,
                               u, {"side": "right" if sign > 0 else "left",
                                   "distance_m": round(s, 1),
                                   "name": "CableAnchor_%s_%d_%s" % (road.id, int(s), tag)}))
        s += CABLE_SPACING


def junction_furniture(city, junction, items):
    """Traffic lights and road-name signs around a junction.

    The props stand on the road of the arm they belong to: a traffic light of
    an elevated road is on the deck, at the height of that road, and not on the
    street that passes underneath.
    """
    from city.roads import junctions as jn
    from city.roads import levels
    arms, centre = jn.arm_geometry(city, junction)
    for a in arms:
        road = a["road"]
        t = a["dir"]
        r = Vector((-t.y, t.x, 0.0))
        reach = a["half"] + jn.END_CAP + 3.0
        # the height of the road where the prop stands
        z = levels.z_at(road, a["s0"] + a["sign"] * reach)
        stop = centre + t * reach + Vector((0.0, 0.0, z))
        if bool(junction.get("signals", True)):
            for side in (-1.0, 1.0):
                head = stop + r * (side * (a["half"] - 1.5)) - t * 3.0
                head.z = z
                if _clearance_ok(city, head, 7.0, road):
                    items.append(_item("traffic_light", road, head, t, {
                        "junction": junction["id"], "height_m": 7.0, "lanes": 2,
                        "mount": "mast_arm"}))
        for side in (-1.0, 1.0):
            sign = stop + r * (side * (a["half"] + 1.0))
            sign.z = z
            if _clearance_ok(city, sign, 2.6, road):
                items.append(_item("sign", road, sign, t, {
                    "junction": junction["id"], "name": clean_name(road.name),
                    "name_en": clean_name(road.name_en or road.name),
                    "height_m": 2.6}))


def build(city):
    """Every road furniture item in the city: (props, cable anchors)."""
    items = []
    anchors = []
    for road in city.roads:
        lamps(city, road, items)
        gantries(city, road, items)
        trees(city, road, items)
        bus_stops(city, road, items)
        noise_walls(city, road, items)
        tunnel_lights(city, road, items)
        cable_anchors(road, anchors)
    for junction in city.junctions:
        junction_furniture(city, junction, items)
    return items, anchors
