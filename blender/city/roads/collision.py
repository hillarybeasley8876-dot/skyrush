"""Collision meshes: simplified road surfaces and thick closed barriers.

Per tile the generator emits two extra objects whose names end in -colonly, so
Godot turns them into collision-only trimeshes (CONTRACTS §2). Road surfaces are
one-sided (fine, the car is always above them); parapets and barriers are closed
volumes at least 0.5 m thick so nothing tunnels through them at 100 m/s.
"""
import bmesh
import contextlib
import io

from mathutils import Vector

from city.roads import lanes as lane_graph, meshkit, profiles, tiles

ASPHALT = "SH_wet_asphalt"
SURFACE_NAME = "surface-colonly"
CONCRETE_NAME = "concrete-colonly"
STEEL_NAME = "steel-colonly"
SURFACE_DROP = 0.015     # the collider sits just under the visible asphalt
BARRIER_INSET = 0.04     # inset so the collider never z-fights the render mesh
RIBBON_SHIFT = 1.0       # the connector strip is a step ahead of its lane
CORRIDOR_MARGIN = 0.5    # a deck keeps its collider this far off the ramp's lane
LANE_CLEAR = 1.2         # a deck keeps this much room from the lane under it
CAR_HALF = 0.95          # the half width of the car that drives on the lane
ROOF_MIN = 0.05          # a step: a surface this far above a lane is in the way
ROOF_MAX = 1.3           # a roof: a surface higher than this is passed under
LEDGE_MIN = 0.25         # a surface this far above a lane stands in its way

_LANE_GRAPH = {}         # id(city) -> the lane graph of the city: built once
_LANE_INDEX = {}         # id(city) -> the lanes with their height and cells
_LANES = {}              # id(city) -> the lanes of the city in Blender space
_LANE_GRID = {}          # id(city) -> the lane points per grid cell
_GRIDS = {}              # id(road) -> the path samples per grid cell
_CELL = 32.0             # the grid of the lane index, in metres
_POINT_CELL = 16.0       # the grid of the lane points, in metres


def lane_graph_of(city):
    """The lane graph of the city: the connector lanes of the ramp attaches.

    The graph is built once: the lane builder prints a report and takes a
    while, and the attaches and the piers both need it.
    """
    data = _LANE_GRAPH.get(id(city))
    if data is not None:
        return data
    quiet = io.StringIO()
    with contextlib.redirect_stdout(quiet):
        data = lane_graph.build_lanes(city)
    _LANE_GRAPH[id(city)] = data
    return data


def build_surface(road, idx, builder, lay):
    """Coarse drivable surface: one strip across the carriageway."""
    path = [road.path[i] for i in idx]
    frames = [road.frames[i] for i in idx]
    if len(path) < 2:
        return
    tmpl = [(lay["asphalt_back"], 1.0, 1.0, 1.0), (lay["asphalt_fwd"], 1.0, 1.0, 1.0)]
    bm = bmesh.new()
    meshkit.strip(bm, path, frames, tmpl, z=-SURFACE_DROP)
    builder.add_named(SURFACE_NAME, bm, surface="asphalt")


def _inset(prof, amount, drop=0.0):
    """Shrink a closed profile towards its centre and push it down."""
    cx = sum(p[0] for p in prof) / len(prof)
    cz = sum(p[1] for p in prof) / len(prof)
    out = []
    for (x, z) in prof:
        dx, dz = x - cx, z - cz
        scale = 1.0 - amount / max(abs(dx), abs(dz), 0.001)
        out.append((cx + dx * scale, cz + dz * scale + drop))
    return out


def _cap_ends(bm):
    """Cap the open ends of a swept tube: the collider becomes a closed volume.

    A cut ends the sweep, and an open end is a hole a car can drive into: the
    cap closes the barrier at the cut, so the collider stays a solid.
    """
    along = bm.verts.layers.float.get("along")
    if along is None:
        return
    values = [v[along] for v in bm.verts]
    for target in (min(values), max(values)):
        ring = [v for v in bm.verts if abs(v[along] - target) < 1e-4]
        if len(ring) < 3:
            continue
        try:
            bm.faces.new(ring)
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def build_barriers(road, idx, builder, lay, side):
    """The closed collider of the parapet on one side of the deck.

    It follows the real profile, inset by 4 cm so the render mesh always wins the
    depth test, and reaches 0.6 m below the deck so a car can never tunnel through.
    """
    if not road.elevated or len(idx) < 2:
        return
    path = [road.path[i] for i in idx]
    mirror = side == "back"
    edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
    parapet = _inset(profiles.parapet_profile(), BARRIER_INSET, drop=-0.60)
    prof = [(edge - x if mirror else edge + x, z) for (x, z) in parapet]
    bm = meshkit.sweep(bmesh.new(), prof, path)
    _cap_ends(bm)
    builder.add_named(CONCRETE_NAME, bm)


def build_median_barrier(road, idx, builder, lay):
    """Collider for the median barrier of an elevated deck.

    The median stands in the middle of the deck, so only the traffic of a ramp
    attach that crosses it cuts it.
    """
    if not road.elevated or lay["median_half"] <= 0.0 or len(idx) < 2:
        return
    path = [road.path[i] for i in idx]
    median = _inset(profiles.median_barrier_profile(lay["median_half"]), BARRIER_INSET,
                    drop=-0.60)
    bm = meshkit.sweep(bmesh.new(), median, path)
    _cap_ends(bm)
    builder.add_named(CONCRETE_NAME, bm)


def build_median(road, idx, builder, lay):
    """Collider for the raised median island of a surface road."""
    if lay["median_half"] <= 0.0 or road.elevated or len(idx) < 2:
        return
    path = [road.path[i] for i in idx]
    prof = [(-lay["median_half"], -0.30), (lay["median_half"], -0.30),
            (lay["median_half"], profiles.KERB_H), (-lay["median_half"], profiles.KERB_H)]
    bm = meshkit.sweep(bmesh.new(), prof, path)
    _cap_ends(bm)
    builder.add_named(CONCRETE_NAME, bm)


def build_bridge(road, idx, builder, lay, side):
    """The steel collider of a cable-stayed bridge: the edge girders.

    A bridge deck has no parapet, so the girder is the wall that keeps a car on
    the deck.
    """
    if not road.bridge or len(idx) < 2:
        return
    path = [road.path[i] for i in idx]
    mirror = side == "back"
    edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
    out = -1.0 if mirror else 1.0
    prof = [(edge - out * 1.20, -2.50), (edge, -2.50),
            (edge, 0.15), (edge - out * 1.20, 0.15)]
    bm = meshkit.sweep(bmesh.new(), prof, path, closed_profile=True)
    _cap_ends(bm)
    builder.add_named(STEEL_NAME, bm, surface="steel")


def build(road, idx, builder, lay=None, excluded=None, gaps=None):
    """Collision geometry for a road segment.

    The drivable surface is never cut: a car must always find the road under
    its wheels, even where a junction's fill takes over the asphalt (the fill
    sits 1 cm lower, so the road's own surface still wins). The barriers are
    cut at the kerb returns: a parapet that runs straight through a junction
    would wall off the turning lanes. They are cut at the ramp attaches too, on
    the same gaps as the visible parapet: there the traffic of the attach
    crosses the deck edge, and a barrier that stands there is an invisible wall
    across the connector lane.
    """
    lay = lay or profiles.layout(road)
    excluded = excluded or set()
    gaps = gaps or {}
    build_surface(road, idx, builder, lay)
    for sub in _split(idx, excluded | _gap_indices(road, idx, gaps.get("median", ()))):
        build_median(road, sub, builder, lay)
    for side in ("fwd", "back"):
        cut = excluded | _gap_indices(road, idx, gaps.get(side, ()))
        for sub in _split(idx, cut):
            build_barriers(road, sub, builder, lay, side)
            build_bridge(road, sub, builder, lay, side)
        # The median barrier of the deck stands in the middle of the deck, so
        # only the traffic of an attach that crosses it cuts it.  It is swept
        # for each side of the deck, the way the build has always swept it.
        for sub in _split(idx, excluded | _gap_indices(road, idx, gaps.get("median", ()))):
            build_median_barrier(road, sub, builder, lay)


def _grid(road):
    """The path samples of a road per grid cell."""
    grid = _GRIDS.get(id(road))
    if grid is None:
        grid = {}
        for i, p in enumerate(road.path):
            grid.setdefault((int(p.x // _CELL), int(p.y // _CELL)), []).append(i)
        _GRIDS[id(road)] = grid
    return grid


def plan_offset(road, point):
    """(signed lateral offset, station, height) of a point in the plan of a road.

    The offset is measured from the centre line, so it says how far the point
    is outside the carriageway, and the height is the height of the road there.
    A point that is nowhere near the road gets a huge offset.
    """
    grid = _grid(road)
    cx = int(point.x // _CELL)
    cy = int(point.y // _CELL)
    best = (1e18, 0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for i in grid.get((cx + dx, cy + dy), ()):
                p = road.path[i]
                d = (p.x - point.x) ** 2 + (p.y - point.y) ** 2
                if d < best[0]:
                    best = (d, i)
    if best[0] > 40.0 * 40.0:
        return 1e6, 0.0, 0.0
    i = best[1]
    j = i + 1 if i + 1 < len(road.path) else i
    a = road.path[i]
    b = road.path[j]
    seg = b - a
    seg.z = 0.0
    l2 = seg.x * seg.x + seg.y * seg.y
    t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((point.x - a.x) * seg.x
                                                   + (point.y - a.y) * seg.y) / l2))
    right = Vector((seg.y, -seg.x, 0.0))
    if right.length < 1e-6:
        right = road.frames[i][1]
    else:
        right.normalize()
    station = road.dist[i] + t * (road.dist[j] - road.dist[i])
    height = a.z + (b.z - a.z) * t
    lateral = ((point.x - a.x - seg.x * t) * right.x
               + (point.y - a.y - seg.y * t) * right.y)
    return lateral, station, height


def lane_index(city):
    """The lanes of the city: their height and the cells they cross.

    The index is what the gap rules work on: a lane is the traffic, and the
    lanes of the city say where the traffic goes.
    """
    index = _LANE_INDEX.get(id(city))
    if index is not None:
        return index
    out = []
    for lane in lane_graph_of(city)["lanes"]:
        pts = lane["points"]
        zs = [p[1] for p in pts]
        cells = set((int(p[0] // _CELL), int(-p[2] // _CELL)) for p in pts)
        out.append((lane, min(zs), max(zs), cells))
    _LANE_INDEX[id(city)] = out
    return out


def lanes_of(city):
    """The lanes of the city in Blender space: [(road id, [points]), ...].

    The points of the lane graph are in the game's coordinates, so they are
    turned into the Blender frame here: every helper of this module works in
    Blender.
    """
    out = _LANES.get(id(city))
    if out is not None:
        return out
    out = []
    for lane in lane_graph_of(city)["lanes"]:
        pts = [Vector((p[0], -p[2], p[1])) for p in lane["points"]]
        if len(pts) > 1:
            out.append((lane.get("road", ""), pts))
    _LANES[id(city)] = out
    return out


def lane_grid(city):
    """The lane points of the city in a grid: {(cell): [(road id, point), ...]}.

    The city has hundreds of thousands of lane points, so a deck that stands
    over one of them is found through the grid and not by walking every lane.
    """
    grid = _LANE_GRID.get(id(city))
    if grid is not None:
        return grid
    grid = {}
    for (road, pts) in lanes_of(city):
        for p in pts:
            key = (int(p.x // _POINT_CELL), int(p.y // _POINT_CELL))
            grid.setdefault(key, []).append((road, p))
    _LANE_GRID[id(city)] = grid
    return grid


def _quad_points(quad, grid):
    """The lane points that can lie in the plan of a quad."""
    x0 = min(p.x for p in quad)
    x1 = max(p.x for p in quad)
    y0 = min(p.y for p in quad)
    y1 = max(p.y for p in quad)
    for cx in range(int(x0 // _POINT_CELL), int(x1 // _POINT_CELL) + 1):
        for cy in range(int(y0 // _POINT_CELL), int(y1 // _POINT_CELL) + 1):
            for item in grid.get((cx, cy), ()):
                yield item


def _in_quad(quad, p):
    """True when a point lies in the plan of a quad."""
    signs = [(quad[(i + 1) % 4].x - quad[i].x) * (p.y - quad[i].y)
             - (quad[(i + 1) % 4].y - quad[i].y) * (p.x - quad[i].x)
             for i in range(4)]
    return all(s >= -1e-6 for s in signs) or all(s <= 1e-6 for s in signs)


def roofs_lane(quad, grid):
    """True when a quad stands over a lane as a step.

    The top of the quad is more than LEDGE_MIN above a lane that runs under
    it: the car on that lane drives into the quad.  A quad that is more than
    ROOF_MAX above the lane is a roof the car passes under, so it keeps its
    collider.
    """
    top = max(p.z for p in quad)
    for _road, p in _quad_points(quad, grid):
        if top - p.z <= LEDGE_MIN:
            continue
        if _in_quad(quad, p):
            return True
    return False


def over_corridor(road, quad, clear):
    """True when a quad lies (partly) over a road's lane corridor.

    The corridor is the width of the carriageway plus a margin: a quad that
    reaches into it stands over the lane of that road.
    """
    for p in quad:
        d, i, t = road.closest(p)
        a, b = road.path[i], road.path[i + 1]
        dz = p.z - (a.z + (b.z - a.z) * t)
        if max(0.0, d * d - dz * dz) ** 0.5 < clear:
            return True
    return False


def pave(builder, pa, ra, rb, pb, collide=True):
    """The visible asphalt of a quad and the collision surface under it.

    The asphalt is always built: a quad that has no collider is still seen.
    The collider is dropped where the quad would roof a lane.
    """
    builder.add(ASPHALT, quad(pa, ra, rb, pb))
    if not collide:
        return
    builder.add_named(SURFACE_NAME, quad(pa, ra, rb, pb, drop=SURFACE_DROP),
                      surface="asphalt")


def roof_cut(city, ramp, parent, tileset, lay, near):
    """Narrow the carriageway collider where one deck roofs the other's lane.

    A deck that stands a step or a roof above the lane of the other road
    takes that lane away: the collider of its carriageway is pulled in to the
    room the lane needs, so the car on the lane finds its own road again.
    The road's own outer lane keeps the width a car needs, so the cut never
    reaches the traffic of the road itself.
    """
    for (r, l, other) in ((parent, profiles.layout(parent), ramp.id),
                          (ramp, lay, parent.id)):
        cuts = {}
        for (lroad, pts) in lanes_of(city):
            if lroad != other:
                continue
            for k, p in enumerate(pts):
                if (p - near).length > 250.0:
                    continue
                _d, i, _t = r.closest(p)
                off = (p - r.path[i]).dot(r.frames[i][1])
                if (abs(off) > max(l["asphalt_fwd"], -l["asphalt_back"]) + 2.0
                        or not ROOF_MIN < r.project(p)[1] - p.z < ROOF_MAX):
                    continue
                if abs(off) - LANE_CLEAR <= 0.5:
                    continue
                sign = 1.0 if off > 0.0 else -1.0
                side = "fwd" if sign > 0.0 else "back"
                # the room is measured across the lane, not across the road
                t = pts[min(k + 1, len(pts) - 1)] - p
                t.z = 0.0
                cos_t = max(0.3, abs(r.frames[i][1].cross(t).z) / max(0.1, t.length))
                cut = sign * min(abs(off) - LANE_CLEAR / cos_t, abs(l["asphalt_" + side]))
                ivs = [iv for group in l["lanes"].values() for iv in group
                       if sign * (iv[0] + iv[1]) * 0.5 > 0.0]
                if ivs:
                    # the road's own lane keeps the width a car needs: the
                    # lanes of a one-way road lie on the side of the centre
                    # line, so every lane is looked at, not only the ones of
                    # the side that is cut
                    lane = max(ivs, key=lambda x: abs((x[0] + x[1]) * 0.5))
                    if sign * cut < sign * (lane[0] + lane[1]) * 0.5 + CAR_HALF:
                        continue
                for j in (i - 3, i - 2, i - 1, i, i + 1, i + 2, i + 3):
                    if j not in cuts or abs(cuts[j]) > abs(cut):
                        cuts[j] = cut
        _apply_cuts(r, l, cuts, tileset)


def _apply_cuts(r, lay, cuts, tileset):
    """Move the edge of the carriageway collider of a road inwards."""
    down = Vector((0.0, 0.0, -SURFACE_DROP))
    for key, run in tiles.tile_runs(r):
        if not any(i in cuts for i in run):
            continue
        bm = tileset.builder(key).named.get(SURFACE_NAME)
        if bm is None:
            continue
        index = {}
        for v in bm.verts:
            index.setdefault((int(v.co.x * 10), int(v.co.y * 10), int(v.co.z * 10)),
                             []).append(v)
        for i in run:
            if i not in cuts:
                continue
            p = r.path[i]
            right = r.frames[i][1]
            edge = lay["asphalt_fwd" if cuts[i] > 0.0 else "asphalt_back"]
            old = p + right * edge + down
            want = p + right * cuts[i] + down
            for c in index.get((int(old.x * 10), int(old.y * 10), int(old.z * 10)), ()):
                if (c.co - old).length < 0.01:
                    c.co = want
                    break


def pier_column(builder, p, r, t, zg, portal, span=12.0, across=True):
    """A closed convex collider for a pier column, so cars cannot drive through it."""
    bm = bmesh.new()
    if portal:
        axis = r if across else t
        for s in (-1.0, 1.0):
            _box(bm, p + axis * (s * span * 0.5), r, t, 2.0, 3.0, 0.0, zg - 1.2)
    else:
        _box(bm, p, r, t, 2.0, 3.0, 0.0, zg - 2.0)
    builder.add_named(CONCRETE_NAME, bm)


def _box(bm, centre, right, tangent, across, along, z0, z1):
    """A closed box in the road frame."""
    hx, hy = along * 0.5, across * 0.5
    corners = []
    for a in (-hx, hx):
        for b in (-hy, hy):
            for c in (z0, z1):
                q = centre + tangent * a + right * b
                corners.append(Vector((q.x, q.y, c)))
    idxs = [bm.verts.new(c) for c in corners]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
             (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in faces:
        bm.faces.new([idxs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_connectors(city, road, tileset):
    """The collision surface under the connector lanes of the ramp's attaches.

    A connector lane is the curve the traffic takes from the parent to the
    ramp.  It crosses the wedge between the two decks, where there is no
    asphalt at all: without a surface of its own the car falls through the
    world at the joint.
    """
    for lane in lane_graph_of(city)["lanes"]:
        if lane.get("road") != road.id or not lane["id"].startswith("attach_"):
            continue
        _ribbon(tileset, lane)


def _ribbon(tileset, lane):
    """A collision strip under one connector lane."""
    pts = [Vector((p[0], -p[2], p[1])) for p in lane["points"]]
    if len(pts) < 2:
        return
    half = max(1.0, float(lane.get("width", 3.5)) * 0.5)
    stations = []
    for i, p in enumerate(pts):
        if i == 0:
            step = pts[1] - pts[0]
        elif i == len(pts) - 1:
            step = pts[-1] - pts[-2]
        else:
            step = pts[i + 1] - pts[i - 1]
        step.z = 0.0
        if step.length < 1e-6:
            step = Vector((1.0, 0.0, 0.0))
        step.normalize()
        stations.append(p + step * RIBBON_SHIFT)
    # the strip starts a step ahead of the lane, so every sample of the lane
    # lies inside the strip and not on the edge of one of its quads
    stations.insert(0, pts[0] - (stations[0] - pts[0]))
    for i in range(len(stations) - 1):
        a, b = stations[i], stations[i + 1]
        across = b - a
        across.z = 0.0
        if across.length < 1e-6:
            continue
        across.normalize()
        right = Vector((across.y, -across.x, 0.0))
        v0 = a + right * half
        v1 = a - right * half
        v2 = b - right * half
        v3 = b + right * half
        tileset.builder_at((a + b) * 0.5).add_named(
            SURFACE_NAME, quad(v0, v1, v2, v3, drop=SURFACE_DROP), surface="asphalt")


def quad(pa, ra, rb, pb, drop=0.0):
    """One flat quad with its normal pointing up: a collider is one sided."""
    bm = bmesh.new()
    verts = []
    for p in (pa, ra, rb, pb):
        v = bm.verts.new(p)
        v.co.z -= drop
        verts.append(v)
    face = bm.faces.new(verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if face.normal.z < 0.0:
        face.normal_flip()
    return bm


def _gap_indices(road, idx, gaps):
    """The path indices of `idx` that lie inside one of the gaps."""
    if not gaps:
        return set()
    return {i for i in idx if any(a <= road.dist[i] <= b for (a, b) in gaps)}


def _split(idx, excluded):
    """The path indices of `idx` with the excluded ones removed."""
    out = []
    cur = []
    for i in idx:
        if i in excluded:
            if len(cur) > 1:
                out.append(cur)
            cur = []
        else:
            cur.append(i)
    if len(cur) > 1:
        out.append(cur)
    return out
