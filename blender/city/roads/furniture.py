"""Road furniture placement: lamps, gantries, signs, trees, bus stops, cable anchors.

The props unit models the objects; the world unit places them from
game/world/data/road_furniture.json. Coordinates are Godot space (x east, y up,
z south), heading 0 = north.

Every prop stands on the surface of the road it belongs to: a traffic light of
an elevated road stands on the deck, not on the street below it, and a prop
that would grow through a deck is dropped.

A prop of a street stands on the sidewalk of its own side: the edge of the
carriageway of that side, the kerb, and then a little way into the sidewalk.
"""
import math

from mathutils import Vector

DECK_LAMP_SPACING = 32.0
SURFACE_LAMP_SPACING = 22.0
GANTRY_SPACING = 500.0
VMS_SPACING = 800.0
TREE_SPACING = 5.25
BUS_STOP_SPACING = 320.0
CABLE_SPACING = 9.6
TUNNEL_LIGHT_SPACING = 12.0
EXIT_ADVANCE = (500.0, 300.0, 100.0)   # the exit advance signs, in metres
CLEARANCE = 0.5                  # the gap a prop must keep from a road surface above
GIRDER_DEPTH = 2.0                # the deck structure under an elevated road
LAMP_HEIGHT = 9.0
TREE_HEIGHT = 14.0
NOISE_WALL_HEIGHT = 3.5
DIVERGE_ANGLE = 30.0             # a ramp that leaves the road at this angle is an off-ramp
TREE_DEPTH = 1.2                 # m into the sidewalk of the road
LAMP_DEPTH = 0.6                 # m into the sidewalk of the road

def godot(p):
    """Blender (x, y, z) -> Godot (x, y, z) with y up."""
    return (round(p.x, 2), round(p.z, 2), round(-p.y, 2))

def _heading(tangent):
    """Heading in degrees, 0 = north (-Z in Godot, +Y in Blender), 90 = east.

    The tangent is a Blender vector (x east, y north). The first version used -y as
    the north and so gave 180 degrees minus the heading: right on a road that runs
    east or west, upside down on a road that runs north or south and a mirror image
    on every diagonal one. The world unit also rotates the bus shelters and the
    noise walls by the lanes next to them, see world/build/furniture_builder.gd.
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

def _clearance_ok(city, point, height, road=None, carriageway=False):
    """False when a road surface runs over the prop, or when the prop stands on
    the carriageway of another road: a street that crosses the road of the prop,
    or that runs beside it, has its own lanes there.
    """
    for other in city.roads:
        if road is not None and other.id == road.id:
            continue
        dist, idx = other.nearest(point)
        if dist > 60.0:
            continue
        other_z = other.path[idx].z - (GIRDER_DEPTH if other.elevated else 0.0)
        if other_z > point.z + 0.2:
            if other_z < point.z + height + CLEARANCE:
                return False        # a road surface runs over the prop
        elif carriageway and other_z > point.z - 0.5:
            half = (other.lanes_fwd + other.lanes_back) * other.lane_width * 0.5 \
                + other.median * 0.5 + other.shoulder
            if dist < half + 0.5:
                return False        # the prop stands on the carriageway of another road
    return True

def _edge(road, side):
    """The distance from the centre line of the road to the kerb of that side (m).
    The two sides of a road are not the same: a road with three lanes one way
    and two the other way has a wide carriageway on one side only.
    """
    from city.roads import profiles
    lay = profiles.layout(road)
    return lay["asphalt_fwd"] if side > 0 else -lay["asphalt_back"]

def _sidewalk_offset(road, side, depth):
    """The offset from the centre line of a prop that stands `depth` m into the
    sidewalk of that side; None when the road has no sidewalk.
    """
    if road.sidewalk <= 0.0:
        return None
    from city.roads import profiles
    return side * (_edge(road, side) + profiles.KERB_W + depth)

def _cut(city, road, wide=False):
    """The path samples of the road that a junction takes: the kerb and the
    sidewalk of the road stop there, and the fill of the junction takes over.
    With `wide` the kerb return takes a sidewalk width more.
    """
    from city.roads import junction_holes
    out = set()
    for hole in junction_holes.road_holes(city, road).values():
        out |= hole
    if not wide:
        return out
    return out | set(i + d for i in out for d in (-1, 1))

def _walk(city, road, items, kind, spacing, depth, height, extra, start, wide=True):
    """The props of a road on the sidewalks of its two sides, one every `spacing` m.
    The sides alternate, so the props of a street stand in two rows.  A prop of
    the cut of a junction is left out: the sidewalk does not reach into it.
    """
    cut = _cut(city, road, wide)
    s = start
    side = 1
    while s < road.length:
        p, t, r, u, i = road.at(s)
        off = _sidewalk_offset(road, side, depth)
        if off is not None and i not in cut:
            pos = p + r * off
            if _clearance_ok(city, pos, height, road, True):
                items.append(_item(kind, road, pos, t, extra))
        side = -side
        s += spacing

def lamps(city, road, items):
    """Street and deck lamps along a road (a tunnel has its own lighting): a lamp
    of a street stands on the sidewalk of its side, a lamp of a viaduct in its
    median.
    """
    style = road.style.get("lamps", "none")
    if style == "none" or road.kind == "tunnel":
        return
    kind = _lamp_style(road, style)
    spacing = DECK_LAMP_SPACING if road.elevated else SURFACE_LAMP_SPACING
    height = 11.0 if road.elevated else (9.0 if style == "magnolia" else LAMP_HEIGHT)
    if road.elevated:
        # a road with a median has its lamps in the median, a one-way deck on
        # the barrier
        median = road.median > 0.0 and road.lanes_back > 0
        s = spacing * 0.5
        side = 1
        while s < road.length:
            p, t, r, u, _ = road.at(s)
            pos = p if median else p + r * (side * (_edge(road, side) + 0.3))
            extra = {"arms": 2 if median else 1, "height_m": height,
                     "mount": "median" if median else "barrier"}
            if _clearance_ok(city, pos, height, road):
                items.append(_item(kind, road, pos, t, extra))
            side = -side
            s += spacing
        return
    _walk(city, road, items, kind, spacing, LAMP_DEPTH, height,
          {"arms": 1, "height_m": height, "mount": "sidewalk"}, spacing * 0.5)

def tunnel_lights(city, road, items):
    """The ceiling lights of a tunnel: one record every 12 m per bore.  They
    only exist where the ground covers the tunnel.
    """
    if road.kind != "tunnel":
        return
    from city.roads import profiles, tunnel
    lay = profiles.layout(road)
    s = 6.0
    while s < road.length:
        i = road.index_at(s)
        covered = tunnel.kind_at(road, i, 0.2) == "COVERED"
        p, t, r, u, _ = road.at(s)
        if covered:
            for index, offset in enumerate(tunnel.bore_offsets(lay)):
                pos = p + r * offset + u * (tunnel.CLEARANCE - 0.2)
                items.append(_item("tunnel_light", road, pos, t, {
                    "bore": index, "height_m": tunnel.CLEARANCE - 0.2,
                    "energy": 2.4, "distance_m": round(s, 1)}))
        s += TUNNEL_LIGHT_SPACING

def _exits(city, road):
    """The off-ramps that leave this road: (distance, destination road).  A ramp
    that climbs onto the road is an on-ramp and gets no exit sign.
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
        dest = city.by_id.get(end.get("road"))
        if dest is None or not _leaves(other, road, start):
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
                return sorted(out, key=lambda o: o[2])
    return sorted(out, key=lambda o: o[2])

def _arrow(angle):
    """The arrow of a guide sign for a turn of this angle (radians)."""
    if angle > math.radians(20.0):
        return "→"
    return "←" if angle < -math.radians(20.0) else "↑"

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
        text = "  ".join("%s %s" % (_arrow(a), n[0]) for n in names) if names             else clean_name(road.name)
        text_en = "  ".join("%s %s" % (_arrow(a), n[1]) for n in names) if names             else clean_name(road.name_en or road.name)
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
    """Plane trees along a surface road, on the sidewalk of their side."""
    if road.style.get("trees", "none") != "plane":
        return
    _walk(city, road, items, "tree", TREE_SPACING, TREE_DEPTH, TREE_HEIGHT,
          {"height_m": TREE_HEIGHT}, 3.0)

def bus_stops(city, road, items):
    """Bus shelters along a surface street, in the middle of the sidewalk."""
    if road.elevated:
        return
    _walk(city, road, items, "bus_stop", BUS_STOP_SPACING, road.sidewalk * 0.5, 3.0,
          {"length_m": 8.0}, 20.0, wide=False)

def noise_walls(city, road, items):
    """Noise wall runs declared in the road style: a wall of a deck stands on the
    deck, the world moves it to the parapet (the deck of the Yan'an Elevated runs
    above the surface road, so the parapet belongs to that junction).
    """
    for (a, b, side) in road.style.get("noise_walls", []) or []:
        s = float(a)
        # a run that is declared longer than the road (road.at clamps to the end: 13 walls stood on the same spot at the end of the
        # Yan'an Elevated)
        while s < min(float(b), road.length):
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
        r, u = road.frames[j][1], road.frames[j][2]
        for sign, tag in ((1.0, "R"), (-1.0, "L")):
            items.append(_item("cable_anchor", road, p + r * (sign * offset) + u * 0.35,
                               u, {"side": "right" if sign > 0 else "left",
                                   "distance_m": round(s, 1),
                                   "name": "CableAnchor_%s_%d_%s" % (road.id, int(s), tag)}))
        s += CABLE_SPACING

def junction_furniture(city, junction, items):
    """Traffic lights and road-name signs around a junction: they stand on the
    kerb of their arm, outside the lanes.  The mast of a traffic light reaches
    over the lanes of its own road, and the name of the road is on a plate at
    the kerb, facing the traffic that comes from the arm.
    """
    from city.roads import junctions as jn
    from city.roads import profiles
    arms, centre = jn.arm_geometry(city, junction)
    if len(arms) < 2:
        return
    for a in arms:
        road = a["road"]
        radius = jn.road_radius(arms, road.id)
        if radius <= 0.0:
            continue
        # the first station of the arm where the kerb of the road stands again:
        # the fill of the junction takes the road up to the kerb return, and a
        # junction next door may cut it further
        at = a["s0"] + a["sign"] * (radius + 6.0)
        j = road.first_beyond(at) if a["sign"] > 0.0 else road.last_before(at)
        cut = _cut(city, road)
        step = 1 if a["sign"] > 0.0 else -1
        while 0 <= j < len(road.path) and j in cut and abs(road.dist[j] - at) < 40.0:
            j += step
        j = max(0, min(len(road.path) - 1, j))
        p, t, r, u, i = road.at(road.dist[j])
        for side in (-1.0, 1.0):
            edge = _edge(road, side)
            head = p + r * (side * (edge + profiles.KERB_W + 0.5))
            if bool(junction.get("signals", True)) and _clearance_ok(city, head, 7.0, road):
                # the arm of the mast reaches over the lanes of its own road
                items.append(_item("traffic_light", road, head, r * (-side), {
                    "junction": junction["id"], "height_m": 7.0, "lanes": 2,
                    "mount": "mast_arm"}))
        # the name of the road, on a plate at the kerb of the approach
        side = 1.0 if a["sign"] > 0.0 else -1.0
        edge = _edge(road, side)
        plate = p + r * (side * (edge + profiles.KERB_W + 1.7))
        if _clearance_ok(city, plate, 2.6, road):
            items.append(_item("sign", road, plate, a["dir"], {
                "junction": junction["id"], "name": clean_name(road.name),
                "name_en": clean_name(road.name_en or road.name),
                "height_m": 2.6}))

def build(city):
    """Every road furniture item in the city: (props, cable anchors)."""
    items = []
    anchors = []
    for road in city.roads:
        for place in (lamps, gantries, trees, bus_stops, noise_walls, tunnel_lights):
            place(city, road, items)
        cable_anchors(road, anchors)
    for junction in city.junctions:
        junction_furniture(city, junction, items)
    return items, anchors
