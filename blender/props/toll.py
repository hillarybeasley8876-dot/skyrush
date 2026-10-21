"""The expressway toll plaza (unit: props).

Dossier §7.2: a 110 x 20 m canopy with a bull-nose fascia, per-lane signal boxes,
islands with crash cushions, booths, breakable barrier arms, an ETC gantry per
carriageway and four 30 m high-mast lights.

Node contract: `LaneSignal_<n>_Red` / `_Green` (both states, so the world unit can
switch a lane), `Barrier_<n>` (its origin is on the hinge), `Light_<n>` and the
`-convcolonly` collision proxies.

The plaza carries two carriageways of ten lanes: the south one is eastbound
(+X), the north one is westbound (-X).  The island of a lane is always on the
DRIVER'S LEFT, so the booth is in front of the driver and the barrier arm
covers the lane it belongs to.
"""
import math

import bmesh

from lib import geo

from . import kit, materials as M
from . import toll_parts as TP

# ----------------------------------------------------------------- dimensions
LANE_W = 3.20
ISLAND_W = 2.20
LANES = 10                 # per carriageway
CLEAR = 5.50               # canopy underside clearance
FASCIA_H = 3.40
BULL_NOSE = 1.20           # the radius of the rounded canopy front
CANOPY_DEPTH = 20.0
CANOPY_Y = 56.0            # half span across the plaza (112 m total)
KERB_H = 0.25
CARRIAGEWAY_N = 2
MEDIAN_Y = 2.0             # half width of the median strip
PLAZA_X0 = -53.9
PLAZA_X1 = -2.1
ETC_X = -40.0              # the ETC gantry stands 30 m before the canopy front
ETC_POST_Y = 56.0
CANOPY_FRONT_X = -CANOPY_DEPTH * 0.5
BOOTH_W = 1.80
BOOTH_D = 3.00
BOOTH_H = 2.80
ARM_LEN = 3.00
ARM_HINGE_Z = 0.95
POST_OFFSET = LANE_W * 0.5 + 0.35   # the post stands on the island edge
BOOTH_X = 0.0              # the booth stands in the middle of the canopy
POST_X = 2.40              # the barrier post is DOWNSTREAM of the booth window

SILVER = "silver"
WHITE = "white_paint"
DARK = "steel_dark"
GALV = "galv"
RED = "red_paint"
YELLOW = "yellow"


def _lanes():
    """(lane_y, island_y, side, direction) for every lane.

    The south carriageway (lanes 1-10) runs eastbound (+X), the north one
    (lanes 11-20) westbound (-X).  `side` is where the island of the lane is:
    the island is always on the DRIVER'S LEFT: the right of an eastbound
    driver is Godot +Z (Blender -Y) and the right of a westbound driver is
    Godot -Z (Blender +Y), so the island is at +Y for the eastbound lanes
    and at -Y for the westbound ones.
    """
    out = []
    for carriage in range(CARRIAGEWAY_N):
        east = carriage == 0
        for i in range(LANES):
            off = MEDIAN_Y + LANE_W * 0.5 + i * (LANE_W + ISLAND_W)
            lane = -off if east else off
            side = 1.0 if east else -1.0
            out.append((lane, lane + side * (LANE_W * 0.5 + ISLAND_W * 0.5), side,
                        1.0 if east else -1.0))
    return out


def _island_ys():
    """The y of every island (one per lane)."""
    return [island for _lane, island, _side, _dir in _lanes()]


def _pavement(p):
    """The concrete plaza with its joint grid, the polished lanes and the paint."""
    TP.pavement(p, CANOPY_DEPTH, CANOPY_Y, _lanes())


def _canopy(p):
    """The 112 x 20 m canopy with its bull-nose fascia and white soffit."""
    front = CANOPY_FRONT_X
    profile = [(front, CLEAR), (front, CLEAR + FASCIA_H - BULL_NOSE)]
    cz = CLEAR + FASCIA_H - BULL_NOSE
    for deg in (180, 162, 144, 126, 108, 90):
        a = math.radians(deg)
        profile.append((front + BULL_NOSE + BULL_NOSE * math.cos(a),
                        cz + BULL_NOSE * math.sin(a)))
    profile.append((CANOPY_DEPTH * 0.5, CLEAR + FASCIA_H))
    profile.append((CANOPY_DEPTH * 0.5, CLEAR))
    bm = bmesh.new()
    from mathutils import Vector
    geo.sweep(profile, [Vector((0.0, -CANOPY_Y, 0.0)), Vector((0.0, CANOPY_Y, 0.0))],
              closed_profile=True)
    p.mesh("TollRoof", bm, M.surface(), surface="silver")
    p.box("Soffit", (0.1, 0.0, CLEAR - 0.03), (CANOPY_DEPTH - 1.2, 2 * CANOPY_Y - 1.2, 0.07),
          M.soffit(), surface="soffit")
    _collider(p, "Canopy", (0.0, 0.0, CLEAR + FASCIA_H * 0.5),
              (CANOPY_DEPTH, 2 * CANOPY_Y, FASCIA_H + 1.4))
    # the name panel: 21 m wide, INSIDE the flat band of the fascia, so it
    # never rises above the roof line
    p.quad("FasciaSign", 21.0, 2.10, M.sign_lit(),
           (front - 0.06, 0.0, CLEAR + 1.15), rot=(0.0, 0.0, -math.pi / 2.0),
           board="toll_fascia")
    p.box("FasciaSignBack", (front - 0.02, 0.0, CLEAR + 1.15), (0.06, 21.4, 2.50),
          M.surface(), surface="silver")
    # the green ETC LED strips, four across the fascia
    for sy in (-38.0, -22.0, 22.0, 38.0):
        p.quad("EtcStrip_%d" % int(sy), 3.0, 0.5, M.sign_lit(True),
               (front - 0.06, sy, CLEAR + 1.15), rot=(0.0, 0.0, -math.pi / 2.0),
               board="toll_etc_strip")
        p.box("EtcStripBack_%d" % int(sy), (front - 0.02, sy, CLEAR + 1.15),
              (0.06, 3.3, 0.8), M.surface(), surface="silver")
    # the lit accent along the lower edge of the bull-nose: the grey fascia
    # would be invisible against the night sky without it
    p.quad("FasciaAccent", 2 * CANOPY_Y - 2.0, 0.25, M.sign_lit(True),
           (front - 0.05, 0.0, CLEAR + FASCIA_H - BULL_NOSE - 0.30),
           rot=(0.0, 0.0, -math.pi / 2.0), board="billboard_led")


def _collider(p, name, center, size):
    bm = bmesh.new()
    geo.box(bm, center, size)
    return p.mesh(name + "-convcolonly", bm, None, box_map=True)


def _soffit_lights(p):
    """The troffers under the canopy: a lit panel every 6 m."""
    lamps = []
    for x in (-7.0, -2.0, 3.0, 8.0):
        for i in range(19):
            lamps.append((2.6, 0.7, (x, -54.0 + i * 6.0, CLEAR - 0.075)))
    p.quads("SoffitLights", lamps, M.sign_lit(True), board="billboard_led")


def _canopy_lights(p):
    """One `Light_<n>` marker every two lanes under the canopy front.

    The world unit turns them into real spot lights (ART.md §4): without them
    the forecourt of the plaza is black under a bright ceiling.
    """
    n = 0
    for i, (lane_y, _island, _side, _dir) in enumerate(_lanes()):
        if i % 2:
            continue
        n += 1
        # the light stands over the booth, so the cabin and the columns are
        # lit from the front and not only from the edge of the canopy
        p.empty("Light_%d" % n, (BOOTH_X - 1.0, lane_y, CLEAR - 0.20),
                direction=(0.0, 0.0, -1.0), size=0.6)


def _islands(p):
    """Kerbed islands with a column each and a crash cushion on the nose."""
    for i, iy in enumerate(_island_ys()):
        n = i + 1
        p.box("Island_%d" % n, (0.0, iy, KERB_H * 0.5), (30.0, ISLAND_W, KERB_H),
              M.surface(), surface="concrete")
        _collider(p, "Island_%d" % n, (0.0, iy, KERB_H * 0.5), (30.0, ISLAND_W, KERB_H))
        p.cyl("Column_%d" % n, (0.0, iy, KERB_H + (CLEAR - KERB_H) * 0.5), 0.40,
              CLEAR - KERB_H, M.surface(), segments=14, surface=SILVER)
        p.wear_band("ColumnWear_%d" % n, (0.0, iy, KERB_H), 0.40)
        _collider(p, "Column_%d" % n, (0.0, iy, KERB_H + (CLEAR - KERB_H) * 0.5),
                  (0.8, 0.8, CLEAR - KERB_H))
        TP.cushion(p, n, iy)


def _booth(p, n, by, direction):
    """A toll booth: a white cabin glazed on all four sides (toll_parts)."""
    TP.booth(p, n, by, direction)
    _collider(p, "Booth_%d" % n, (BOOTH_X, by, 1.40), (BOOTH_D, BOOTH_W, BOOTH_H))


def _barrier_arm(p, n, lane_y, side, direction):
    """A 3 m barrier arm: the post stands on the island edge DOWNSTREAM of the
    booth, and the arm swings across the lane about the traffic axis.

    The arm is built towards the lane, so with the rotation reset it covers
    its own lane and not the island (the review of the toll layout).
    """
    post_y = lane_y + side * POST_OFFSET
    post_x = POST_X * direction
    p.box("BarrierPost_%d" % n, (post_x, post_y, 0.55), (0.44, 0.44, 1.10), M.surface(),
          bevel=0.02, surface=GALV)
    p.box("BarrierMotor_%d" % n, (post_x, post_y, 1.20), (0.50, 0.50, 0.24), M.surface(),
          surface=DARK)
    # The arm points along the local -Y, so the Godot local +Z is the length of
    # the arm: the world unit lifts it with a rotation about X (it expects the
    # arm to lie along +Z).  The lanes that need the other direction get a
    # mirror of pi about Z.
    bm = bmesh.new()
    geo.box(bm, (0.0, -ARM_LEN * 0.5, 0.0), (0.13, ARM_LEN, 0.15))
    arm = p.mesh("Barrier_%d" % n, bm, M.sign_lit(), loc=(post_x, post_y, ARM_HINGE_Z),
                 rot=(0.0, 0.0, math.pi if side < 0.0 else 0.0), box_map=False)
    kit.map_strip_uv(arm, ARM_LEN, "barrier_arm")
    # the lane and the island the arm belongs to (the test checks the pose)
    arm["lane_y"] = lane_y
    arm["island_y"] = lane_y + side * (LANE_W * 0.5 + ISLAND_W * 0.5)
    return arm


def _lane_signals(p, n, lane_y, direction):
    """The lane control light: both states ship so the world unit can switch."""
    # the eastbound signals stand at the front of the canopy (-X) and the
    # westbound ones at its back (+X): both face the approaching traffic
    sx = CANOPY_FRONT_X + 0.10 if direction > 0.0 else CANOPY_DEPTH * 0.5 + 0.05
    face = -direction            # the signal faces the approaching driver
    p.box("SignalBox_%d" % n, (sx, lane_y, CLEAR - 0.60), (0.30, 0.84, 0.84), M.surface(),
          bevel=0.02, surface=DARK)
    # the two states sit 2 cm apart, so the world unit shows one by hiding the
    # other (they must not z-fight)
    p.quad("LaneSignal_%d_Red" % n, 0.76, 0.76, M.sign_lit(),
           (sx - 0.18 * direction, lane_y, CLEAR - 0.60),
           rot=(0.0, 0.0, -math.pi / 2.0 * direction), board="toll_signal_red")
    p.quad("LaneSignal_%d_Green" % n, 0.76, 0.76, M.sign_lit(),
           (sx - 0.15 * direction, lane_y, CLEAR - 0.60),
           rot=(0.0, 0.0, -math.pi / 2.0 * direction), board="toll_signal_green")
    label = "toll_lane_etc" if (n % 3) != 0 else "toll_lane_mixed"
    p.quad("LaneLabel_%d" % n, 1.60, 0.50, M.sign_lit(),
           (sx - 0.17 * direction, lane_y, CLEAR - 1.30),
           rot=(0.0, 0.0, -math.pi / 2.0 * direction), board=label)


def _etc_gantry(p, index, x, y0, y1, lanes):
    """The ETC gantry of one carriageway: a 0.9 x 0.9 m box truss with a camera
    and an antenna over every lane."""
    gz = 6.60
    half = 0.45
    for sz in (-half, half):
        for sy in (-half, half):
            p.tube("EtcChord%d" % index, (x, y0 + sy, gz + sz), (x, y1 + sy, gz + sz),
                   0.055, M.surface(), segments=4, surface=GALV, cap=False)
    span = y1 - y0
    panels = max(2, int(round(span / 6.0)))
    step = span / panels
    for i in range(panels + 1):
        yy = y0 + i * step
        for sy in (-half, half):
            p.tube("EtcVert%d_%d" % (index, i), (x, yy + sy, gz - half),
                   (x, yy + sy, gz + half), 0.045, M.surface(), segments=4,
                   surface=GALV, cap=False)
        p.tube("EtcTop%d_%d" % (index, i), (x, yy - half, gz + half),
               (x, yy + half, gz + half), 0.045, M.surface(), segments=4, surface=GALV,
               cap=False)
    for i in range(panels):
        ya, yb = y0 + i * step, y0 + (i + 1) * step
        for sy in (-half, half):
            p.tube("EtcDiag%d_%d" % (index, i), (x, ya + sy, gz - half),
                   (x, yb + sy, gz + half), 0.040, M.surface(), segments=4, surface=GALV,
                   cap=False)
    for sy in (y0, y1):
        p.box("EtcPost%d_%d" % (index, int(sy > 0)), (x, sy, gz * 0.5), (0.40, 0.40, gz),
              M.surface(), bevel=0.03, surface=GALV)
        p.box("EtcPostFoot%d_%d" % (index, int(sy > 0)), (x, sy, 0.10), (0.80, 0.80, 0.20),
              M.surface(), surface="concrete")
    for i, (lane_y, _island, _side, _dir) in enumerate(lanes):
        p.box("EtcCamera_%d_%d" % (index, i + 1), (x - 0.28, lane_y, gz - 1.10),
              (0.26, 0.22, 0.20), M.surface(), surface=DARK)
        p.cyl("EtcAntenna_%d_%d" % (index, i + 1), (x, lane_y, gz + 0.30), 0.03, 0.60,
              M.surface(), segments=6, surface=DARK)


def _high_mast(p, index, x, y):
    """A 30 m high-mast light with six heads and a `Light_<n>` marker."""
    p.cyl("Mast_%d" % index, (x, y, 15.0), 0.28, 30.0, M.surface(), segments=12, r2=0.16,
          surface=GALV)
    p.box("MastBase_%d" % index, (x, y, 0.35), (1.30, 1.30, 0.70), M.surface(),
          surface="concrete")
    p.cyl("Ring_%d" % index, (x, y, 30.2), 1.30, 0.30, M.surface(), segments=14,
          surface=GALV)
    for k in range(6):
        a = math.tau * k / 6.0
        hx, hy = x + math.cos(a) * 1.10, y + math.sin(a) * 1.10
        p.box("Head_%d_%d" % (index, k), (hx, hy, 30.0), (0.70, 0.50, 0.22), M.surface(),
              bevel=0.02, surface="alu", rot=(0.0, 0.0, a))
        p.quad("Lamp_%d_%d" % (index, k), 0.58, 0.40, M.sign_lit(), (hx, hy, 29.86),
               board="billboard_led")
    p.empty("Light_%d" % index, (x, y, 29.6), direction=(0.0, 0.0, -1.0), size=0.8)


def toll_plaza():
    """The whole toll plaza as one glb."""
    p = kit.Prop("TollPlaza")
    lanes = _lanes()
    _pavement(p)
    _canopy(p)
    _soffit_lights(p)
    _islands(p)
    for i, (lane_y, island_y, side, direction) in enumerate(lanes):
        n = i + 1
        _booth(p, n, island_y, direction)
        _lane_signals(p, n, lane_y, direction)
        _barrier_arm(p, n, lane_y, side, direction)
    _canopy_lights(p)
    _etc_gantry(p, 1, ETC_X, -CANOPY_Y, -MEDIAN_Y, lanes[:LANES])
    _etc_gantry(p, 2, -ETC_X, MEDIAN_Y, CANOPY_Y, lanes[LANES:])
    for i, (mx, my) in enumerate(((-26.0, -64.0), (26.0, -64.0), (-26.0, 64.0),
                                  (26.0, 64.0))):
        _high_mast(p, LANES * 2 + i + 1, mx, my)
    return p.finalize("TollPlaza")


BUILDERS = {"toll_plaza": toll_plaza}
