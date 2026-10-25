"""The toll plaza that fits a 3+3 lane expressway (unit: props).

The plaza of `toll.py` is the dossier's (§7.2): ten lanes a way, 2.2 m islands
between them, 112 m wide. The G50 that carries the toll of the map is a 3+3
lane road 25.5 m wide that does not widen, so that plaza stood across it
turned by 90 degrees with its booths in one lane. This plaza is built on the
lanes of the road: its lanes lie on the lane centres of the road (3.75 m
apart, a 2 m median), so the traffic drives through it in its own lanes.

    lane 1 (the inner lane, by the median): the ETC lane, its arm lifts itself;
              its booth stands on the median island
    lanes 2, 3: closed lanes (red) with an arm on a slim island on the lane
              line to the driver's left

Node contract (as `toll.py`): `LaneSignal_<n>_Red` / `_Green`, `Barrier_<n>`
(its origin on the hinge, the arm along the Godot local +Z; extras `lane_y`
and `etc`), `Light_<n>`, the `-convcolonly` collision proxies. Lanes 1-3 run
eastbound (+X, the Blender -Y side), lanes 4-6 westbound.
"""
import math

import bmesh

from lib import geo

from . import kit, materials as M
from . import toll_parts as TP

# ----------------------------------------------------------------- the road
LANES = 3                  # per carriageway
PITCH = 3.75               # the lane width of the road (the lanes of the plaza lie on its centres)
MEDIAN_Y = 1.0             # half the median of the road
SHOULDER = 0.5
EDGE_Y = MEDIAN_Y + LANES * PITCH + SHOULDER      # 12.75: the edge of the carriageway
# ----------------------------------------------------------------- the plaza
SLIM_W = 0.60              # the islands on the lane lines carry the barrier posts
ISLAND_LEN = 24.0
KERB_H = 0.25
MEDIAN_ISLAND_LEN = 30.0
OUTER_ISLAND_W = 2.6       # the island beyond the outer lane, with a booth and the columns
CLEAR = 5.30               # the underside of the canopy
FASCIA_H = 2.10            # the canopy top is at 7.4 m: a Big Hop clears it (apex 7.8 m)
BULL_NOSE = 1.0
CANOPY_DEPTH = 20.0
CANOPY_FRONT_X = -CANOPY_DEPTH * 0.5
CANOPY_Y = EDGE_Y + OUTER_ISLAND_W + 0.8           # 16.15 half span
ETC_X = -40.0              # the ETC gantry: 30 m before the canopy front
ARM_LEN = 3.00
ARM_HINGE_Z = 0.95
POST_X = 2.40              # the barrier post: downstream of the middle of the canopy
BOOTH_STAGGER = 4.0        # the two median booths stand apart along the road
GALV = "galv"
DARK = "steel_dark"
SILVER = "silver"


def lanes():
    """(lane_y, post_y, direction, etc) for every lane: eastbound 1-3 (-Y), westbound 4-6 (+Y).

    The post of the arm stands on the island to the DRIVER'S LEFT: the median
    island for lane 1, the slim island on the lane line for lanes 2 and 3.
    """
    out = []
    for carriage in range(2):
        east = carriage == 0
        sign = -1.0 if east else 1.0
        for i in range(LANES):
            lane_y = sign * (MEDIAN_Y + PITCH * (i + 0.5))
            if i == 0:
                post_y = sign * (MEDIAN_Y - 0.30)
            else:
                post_y = sign * (MEDIAN_Y + PITCH * i)
            out.append((lane_y, post_y, 1.0 if east else -1.0, i == 0))
    return out


def _collider(p, name, center, size):
    bm = bmesh.new()
    geo.box(bm, center, size)
    return p.mesh(name + "-convcolonly", bm, None, box_map=True)


def _canopy(p):
    """The canopy over the road with its bull-nose fascia, the name and the ETC strips."""
    front = CANOPY_FRONT_X
    cz = CLEAR + FASCIA_H - BULL_NOSE
    profile = [(front, CLEAR), (front, cz)]
    for deg in (180, 162, 144, 126, 108, 90):
        a = math.radians(deg)
        profile.append((front + BULL_NOSE + BULL_NOSE * math.cos(a), cz + BULL_NOSE * math.sin(a)))
    profile.append((CANOPY_DEPTH * 0.5, CLEAR + FASCIA_H))
    profile.append((CANOPY_DEPTH * 0.5, CLEAR))
    from mathutils import Vector
    bm = bmesh.new()
    geo.sweep(profile, [Vector((0.0, -CANOPY_Y, 0.0)), Vector((0.0, CANOPY_Y, 0.0))], closed_profile=True)
    p.mesh("TollRoof", bm, M.surface(), surface=SILVER)
    p.box("Soffit", (0.1, 0.0, CLEAR - 0.03), (CANOPY_DEPTH - 1.2, 2 * CANOPY_Y - 1.2, 0.07), M.soffit(),
          surface="soffit")
    _collider(p, "Canopy", (0.0, 0.0, CLEAR + FASCIA_H * 0.5), (CANOPY_DEPTH, 2 * CANOPY_Y, FASCIA_H + 0.2))
    # the name over the eastbound and the westbound traffic
    for face, x in ((-1.0, front - 0.06), (1.0, CANOPY_DEPTH * 0.5 + 0.06)):
        rot = (0.0, 0.0, -math.pi / 2.0 * (1.0 if face < 0 else -1.0))
        p.quad("FasciaSign_%d" % int(face > 0), 14.0, 1.50, M.sign_lit(), (x, 0.0, CLEAR + 0.95), rot=rot,
               board="toll_fascia")
        p.box("FasciaSignBack_%d" % int(face > 0), (x + face * 0.04, 0.0, CLEAR + 0.95), (0.06, 14.4, 1.80),
              M.surface(), surface=SILVER)
    # the green ETC strips over the ETC lanes, and the lit accent of the bull-nose
    for lane_y, _post, direction, etc in lanes():
        if not etc:
            continue
        x = front - 0.06 if direction > 0 else CANOPY_DEPTH * 0.5 + 0.06
        rot = (0.0, 0.0, -math.pi / 2.0 * direction)
        p.quad("EtcStrip_%d" % int(lane_y), 3.0, 0.45, M.sign_lit(True), (x, lane_y, CLEAR + 0.30), rot=rot,
               board="toll_etc_strip")
    p.quad("FasciaAccent", 2 * CANOPY_Y - 2.0, 0.22, M.sign_lit(True),
           (front - 0.05, 0.0, CLEAR + FASCIA_H - BULL_NOSE - 0.25), rot=(0.0, 0.0, -math.pi / 2.0),
           board="billboard_led")


def _soffit_lights(p):
    lamps = []
    for x in (-7.0, -2.0, 3.0, 8.0):
        for i in range(6):
            lamps.append((2.6, 0.7, (x, -CANOPY_Y + 3.0 + i * (2 * CANOPY_Y - 6.0) / 5.0, CLEAR - 0.075)))
    p.quads("SoffitLights", lamps, M.sign_lit(True), board="billboard_led")


def _islands(p):
    """The median island with its booths and columns, the slim islands on the lane lines, the outer islands."""
    # the median: one booth per carriageway (for the ETC lane, it is a control booth), two columns
    p.box("MedianIsland", (0.0, 0.0, KERB_H * 0.5), (MEDIAN_ISLAND_LEN, 2 * MEDIAN_Y - 0.1, KERB_H), M.surface(),
          surface="concrete")
    _collider(p, "MedianIsland", (0.0, 0.0, KERB_H * 0.5), (MEDIAN_ISLAND_LEN, 2 * MEDIAN_Y - 0.1, KERB_H))
    for n, (bx, direction) in enumerate(((-BOOTH_STAGGER, 1.0), (BOOTH_STAGGER, -1.0))):
        _booth(p, n + 1, bx, 0.0, direction)
    for n, cx in enumerate((-8.5, 8.5)):
        _column(p, "MedianColumn_%d" % (n + 1), cx, 0.0)
    # the slim islands on the lane lines: a kerb and a crash cushion on the nose that meets the traffic
    k = 0
    for lane_y, post_y, direction, etc in lanes():
        if etc:
            continue
        k += 1
        p.box("Island_%d" % k, (0.0, post_y, KERB_H * 0.5), (ISLAND_LEN, SLIM_W, KERB_H), M.surface(),
              surface="concrete")
        _collider(p, "Island_%d" % k, (0.0, post_y, KERB_H * 0.5), (ISLAND_LEN, SLIM_W, KERB_H))
        _slim_cushion(p, k, post_y, direction)
    # the outer islands, beyond the shoulders: a booth each and the columns of the canopy edge
    for n, side in enumerate((-1.0, 1.0)):
        oy = side * (EDGE_Y + OUTER_ISLAND_W * 0.5)
        p.box("OuterIsland_%d" % (n + 1), (0.0, oy, KERB_H * 0.5), (MEDIAN_ISLAND_LEN, OUTER_ISLAND_W, KERB_H),
              M.surface(), surface="concrete")
        _collider(p, "OuterIsland_%d" % (n + 1), (0.0, oy, KERB_H * 0.5), (MEDIAN_ISLAND_LEN, OUTER_ISLAND_W, KERB_H))
        _booth(p, 3 + n, 0.0, oy, -side)
        for m, cx in enumerate((-8.5, 8.5)):
            _column(p, "EdgeColumn_%d_%d" % (n + 1, m + 1), cx, oy)


def _booth(p, n, bx, by, direction):
    """A toll booth (toll_parts) at (bx, by), its window towards the traffic of `direction`."""
    saved = TP.BOOTH_X
    TP.BOOTH_X = bx
    try:
        TP.booth(p, n, by, direction)
    finally:
        TP.BOOTH_X = saved
    _collider(p, "Booth_%d" % n, (bx, by, 1.40), (TP.BOOTH_D, TP.BOOTH_W, TP.BOOTH_H))


def _column(p, name, cx, cy):
    p.cyl(name, (cx, cy, KERB_H + (CLEAR - KERB_H) * 0.5), 0.36, CLEAR - KERB_H, M.surface(), segments=14,
          surface=SILVER)
    _collider(p, name, (cx, cy, KERB_H + (CLEAR - KERB_H) * 0.5), (0.72, 0.72, CLEAR - KERB_H))


def _slim_cushion(p, n, iy, direction):
    """A slim crash cushion on the upstream nose of a lane line island."""
    nose = -direction * (ISLAND_LEN * 0.5 + 1.0)
    yellow = bmesh.new()
    geo.box(yellow, (nose, iy, 0.30 + 0.35), (2.0, SLIM_W - 0.05, 0.70))
    p.mesh("SlimCushion_%d" % n, yellow, M.surface(), surface="yellow")
    _collider(p, "SlimCushion_%d" % n, (nose, iy, 0.30 + 0.35), (2.0, SLIM_W - 0.05, 0.70))


def _barrier(p, n, lane_y, post_y, direction, etc):
    """The barrier arm of a lane: the post on the island to the driver's left, the arm across the lane."""
    side = 1.0 if lane_y > post_y else -1.0         # the arm points from the post into its lane
    post_x = POST_X * direction
    p.box("BarrierPost_%d" % n, (post_x, post_y, 0.55), (0.40, 0.40, 1.10), M.surface(), bevel=0.02, surface=GALV)
    p.box("BarrierMotor_%d" % n, (post_x, post_y, 1.20), (0.46, 0.46, 0.24), M.surface(), surface=DARK)
    _collider(p, "BarrierPost_%d" % n, (post_x, post_y, 0.65), (0.46, 0.46, 1.30))
    bm = bmesh.new()
    geo.box(bm, (0.0, -ARM_LEN * 0.5, 0.0), (0.13, ARM_LEN, 0.15))
    # the arm is built along -Y (the Godot local +Z): towards -Y it needs no turn, towards +Y half a turn
    arm = p.mesh("Barrier_%d" % n, bm, M.sign_lit(), loc=(post_x, post_y, ARM_HINGE_Z),
                 rot=(0.0, 0.0, 0.0 if side < 0.0 else math.pi), box_map=False)
    kit.map_strip_uv(arm, ARM_LEN, "barrier_arm")
    arm["lane_y"] = lane_y
    arm["etc"] = 1 if etc else 0


def _signals(p, n, lane_y, direction, etc):
    """The lane control light at the canopy edge that meets the traffic: both states ship."""
    sx = CANOPY_FRONT_X + 0.10 if direction > 0.0 else CANOPY_DEPTH * 0.5 - 0.10
    p.box("SignalBox_%d" % n, (sx, lane_y, CLEAR - 0.55), (0.30, 0.84, 0.84), M.surface(), bevel=0.02, surface=DARK)
    for state, dx in (("Red", 0.18), ("Green", 0.15)):
        p.quad("LaneSignal_%d_%s" % (n, state), 0.76, 0.76, M.sign_lit(),
               (sx - dx * direction, lane_y, CLEAR - 0.55), rot=(0.0, 0.0, -math.pi / 2.0 * direction),
               board="toll_signal_red" if state == "Red" else "toll_signal_green")
    p.quad("LaneLabel_%d" % n, 1.60, 0.50, M.sign_lit(), (sx - 0.17 * direction, lane_y, CLEAR - 1.25),
           rot=(0.0, 0.0, -math.pi / 2.0 * direction), board="toll_lane_etc" if etc else "toll_lane_mixed")


def _etc_gantry(p, index, x, y0, y1, lane_list):
    """The ETC gantry of one carriageway: a box truss with a camera and an antenna over every lane."""
    gz = 6.40
    half = 0.40
    for sz in (-half, half):
        for sy in (-half, half):
            p.tube("EtcChord%d" % index, (x, y0 + sy, gz + sz), (x, y1 + sy, gz + sz), 0.05, M.surface(),
                   segments=4, surface=GALV, cap=False)
    panels = max(2, int(round(abs(y1 - y0) / 4.0)))
    step = (y1 - y0) / panels
    for i in range(panels + 1):
        yy = y0 + i * step
        for sy in (-half, half):
            p.tube("EtcVert%d_%d" % (index, i), (x, yy + sy, gz - half), (x, yy + sy, gz + half), 0.04, M.surface(),
                   segments=4, surface=GALV, cap=False)
    for sy in (y0, y1):
        p.box("EtcPost%d_%d" % (index, int(sy > 0)), (x, sy, gz * 0.5), (0.40, 0.40, gz), M.surface(), bevel=0.03,
              surface=GALV)
        _collider(p, "EtcPost%d_%d" % (index, int(sy > 0)), (x, sy, gz * 0.5), (0.40, 0.40, gz))
    for i, (lane_y, _post, _dir, _etc) in enumerate(lane_list):
        p.box("EtcCamera_%d_%d" % (index, i + 1), (x - 0.25, lane_y, gz - 1.0), (0.26, 0.22, 0.20), M.surface(),
              surface=DARK)
        p.cyl("EtcAntenna_%d_%d" % (index, i + 1), (x, lane_y, gz + 0.28), 0.03, 0.55, M.surface(), segments=6,
              surface=DARK)


def _high_mast(p, index, x, y):
    p.cyl("Mast_%d" % index, (x, y, 12.0), 0.24, 24.0, M.surface(), segments=12, r2=0.14, surface=GALV)
    p.box("MastBase_%d" % index, (x, y, 0.35), (1.1, 1.1, 0.70), M.surface(), surface="concrete")
    for k in range(4):
        a = math.tau * k / 4.0
        hx, hy = x + math.cos(a) * 0.9, y + math.sin(a) * 0.9
        p.box("Head_%d_%d" % (index, k), (hx, hy, 24.0), (0.6, 0.45, 0.2), M.surface(), bevel=0.02, surface="alu",
              rot=(0.0, 0.0, a))
        p.quad("Lamp_%d_%d" % (index, k), 0.5, 0.36, M.sign_lit(), (hx, hy, 23.88), board="billboard_led")
    p.empty("Light_%d" % index, (x, y, 23.6), direction=(0.0, 0.0, -1.0), size=0.8)


def toll_plaza_road():
    """The 3+3 lane toll plaza as one glb."""
    p = kit.Prop("TollPlazaRoad")
    lane_list = lanes()
    _canopy(p)
    _soffit_lights(p)
    _islands(p)
    for i, (lane_y, post_y, direction, etc) in enumerate(lane_list):
        n = i + 1
        _signals(p, n, lane_y, direction, etc)
        _barrier(p, n, lane_y, post_y, direction, etc)
        p.empty("Light_%d" % n, (0.0, lane_y, CLEAR - 0.20), direction=(0.0, 0.0, -1.0), size=0.6)
    _etc_gantry(p, 1, ETC_X, -MEDIAN_Y - 0.3, -EDGE_Y - 0.6, lane_list[:LANES])
    _etc_gantry(p, 2, -ETC_X, MEDIAN_Y + 0.3, EDGE_Y + 0.6, lane_list[LANES:])
    _high_mast(p, 2 * LANES + 1, 0.0, -(CANOPY_Y + 4.0))
    _high_mast(p, 2 * LANES + 2, 0.0, CANOPY_Y + 4.0)
    return p.finalize("TollPlazaRoad")


BUILDERS = {"toll_plaza_road": toll_plaza_road}
