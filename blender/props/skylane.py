"""Sky-lane pieces (unit: props): the launch ramp, the hologram ring gate and the
overhead sign gantry.

Gameplay dossier §5.6: a 30 m launch ramp with animated chevrons, hologram ring
gates of 14 m diameter, and an overhead sign 300 m before the pad.

The chevrons are real chevron geometry (not rectangles) and each row has its own
material, so the world unit can animate them row by row.
"""
import math

import bmesh

from . import atlas, kit, materials as M

RAMP_LEN = 30.0
RAMP_W = 12.0
RAMP_RISE = 3.0
GATE_D = 14.0
GANTRY_W = 18.0
CLEAR_Z = 6.40
CHEVRON_ROWS = 6
CYAN = (0.0, 0.90, 1.0)
MAGENTA = (1.0, 0.17, 0.84)


def _ramp_height(t):
    """Launch ramp profile: a smooth curve from flat to 3 m over 30 m."""
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return RAMP_RISE
    return RAMP_RISE * (t * t * (3.0 - 2.0 * t))


def _ramp_slope(t):
    """The ramp gradient (radians) at parameter t."""
    return math.atan(6.0 * t * (1.0 - t) * RAMP_RISE / RAMP_LEN)


def _arm_box(bm, mid, size, rot):
    """One bar of a chevron, added to a bmesh with its own rotation."""
    from mathutils import Euler, Matrix, Vector
    res = bmesh.ops.create_cube(bm, size=1.0)
    m = (Matrix.Translation(Vector(mid)) @ Euler(rot, "XYZ").to_matrix().to_4x4())
    for v in res["verts"]:
        v.co = m @ Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))


def _chevron_arms(p, name, centre, mat, half=1.5, length=3.2, width=0.5, thick=0.07,
                  tilt=0.0):
    """Two bars forming a '>' that points along +Y (the travel direction).

    Both arms live in one node, so the row can be animated as a unit.
    """
    cx, cy, cz = centre
    arm_len = math.hypot(half, length)
    bm = bmesh.new()
    for sx in (-1, 1):
        dx, dy = sx * half, -length
        norm = math.hypot(dx, dy)
        ang = math.atan2(dy / norm, dx / norm)
        mid = (cx + dx * 0.5, cy + dy * 0.5, cz)
        _arm_box(bm, mid, (arm_len, width, thick), (tilt, 0.0, ang))
    p.mesh(name, bm, mat, box_map=True)


def sky_lane_pad():
    """The 30 m launch ramp with animated chevrons (`Chevron_<n>`).

    The ramp is a real structure: a 0.4 m deck with side skirts, a steel
    substructure of portal bents, LED edge strips and the painted 飞行航道
    SKY LANE marking on an anti-slip deck.
    """
    p = kit.Prop("SkyLanePad")
    p.box("Apron", (0.0, 0.0, -0.05), (RAMP_W + 16.0, RAMP_LEN + 30.0, 0.10),
          M.surface(), surface="asphalt")
    bm = bmesh.new()
    steps = 20
    rings = []
    for i in range(steps + 1):
        t = i / float(steps)
        y = t * RAMP_LEN
        z = _ramp_height(t)
        rings.append([bm.verts.new(pp) for pp in
                      ((-RAMP_W * 0.5, y, z), (RAMP_W * 0.5, y, z),
                       (RAMP_W * 0.5, y, z - 0.40), (-RAMP_W * 0.5, y, z - 0.40))])
    for ra, rb in zip(rings, rings[1:]):
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((ra[k], ra[k2], rb[k2], rb[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    p.mesh("Deck", bm, M.surface(), surface="asphalt")
    # the side skirts: a steel plate along each edge of the deck
    for sx in (-1, 1):
        skirt = bmesh.new()
        for i in range(steps + 1):
            t = i / float(steps)
            y = t * RAMP_LEN
            z = _ramp_height(t)
            skirt.verts.new((sx * (RAMP_W * 0.5 + 0.04), y, z + 0.10))
            skirt.verts.new((sx * (RAMP_W * 0.5 + 0.04), y, z - 0.40))
        skirt.verts.ensure_lookup_table()
        for i in range(steps):
            a = 2 * i
            b = 2 * (i + 1)
            skirt.faces.new((skirt.verts[a], skirt.verts[b], skirt.verts[b + 1],
                             skirt.verts[a + 1]))
        bmesh.ops.recalc_face_normals(skirt, faces=skirt.faces[:])
        p.mesh("Skirt_%d" % sx, skirt, M.surface(), surface="silver")
    # the steel substructure: five portal bents under the deck
    for i in range(1, 6):
        t = i / 6.0
        y = t * RAMP_LEN
        z = _ramp_height(t)
        for sx in (-1, 1):
            p.box("Post_%d_%d" % (i, sx), (sx * (RAMP_W * 0.5 - 0.4), y, z * 0.5),
                  (0.30, 0.30, max(z, 0.2)), M.surface(), surface="galv")
        p.box("Cross_%d" % i, (0.0, y, z - 0.55), (RAMP_W - 0.6, 0.24, 0.24),
              M.surface(), surface="galv")
    # the LED edge strips along both sides of the deck
    for sx in (-1, 1):
        p.quad("EdgeLed_%d" % sx, RAMP_LEN - 1.0, 0.18, M.sign_lit(True),
               (sx * (RAMP_W * 0.5 - 0.25), RAMP_LEN * 0.5, _ramp_height(0.5) + 0.03),
               rot=(-math.pi / 2.0 + _ramp_slope(0.5), 0.0, 0.0), board="billboard_cyan")
    for i in range(CHEVRON_ROWS):
        t = (i + 0.5) / CHEVRON_ROWS
        y = t * RAMP_LEN
        z = _ramp_height(t) + 0.02
        tilt = -_ramp_slope(t)
        _chevron_arms(p, "Chevron_%d" % (i + 1), (0.0, y, z), M.chevron(i + 1, CYAN),
                      half=1.6, length=3.4, width=0.55, tilt=tilt)
    # the painted 飞行航道 SKY LANE marking on the deck
    t = 0.30
    p.quad("DeckText", 8.0, 4.0, M.deck_text(),
           (0.0, t * RAMP_LEN, _ramp_height(t) + 0.03),
           rot=(-math.pi / 2.0 + _ramp_slope(t), 0.0, math.pi))
    # the painted launch arrows in front of the ramp
    arrows = bmesh.new()
    for k in range(3):
        kit.add_quad(arrows, 4.0, 1.4, (0.0, -12.0 - k * 8.0, 0.02),
                     (-math.pi / 2.0, 0.0, math.pi / 2.0), atlas.ARROW_UV)
    p.mesh("PadArrows", arrows, M.road_marks(), box_map=False)
    p.empty("Light", (0.0, RAMP_LEN * 0.5, RAMP_RISE + 1.0), direction=(0.0, 0.0, -1.0),
            size=0.8)
    return p.finalize("SkyLanePad")


def sky_lane_gate():
    """A 14 m hologram ring gate: cyan hologram ring with magenta chevrons."""
    p = kit.Prop("SkyLaneGate")
    p.ring("Ring", (0.0, 0.0, 0.0), GATE_D * 0.5, 0.30, 0.30, M.hologram(),
           segments=64, axis="Y")
    p.ring("InnerRing", (0.0, 0.0, 0.0), GATE_D * 0.5 - 0.55, 0.10, 0.10, M.hologram(),
           segments=64, axis="Y")
    for i in range(8):
        a = math.tau * i / 8.0
        r = GATE_D * 0.5
        tx, tz = -math.sin(a), math.cos(a)          # the tangent of the ring
        tip = (math.cos(a) * r + tx * 0.55, 0.0, math.sin(a) * r + tz * 0.55)
        bm = bmesh.new()
        for sx in (-1, 1):
            ang = math.radians(26.0) * sx
            dx = tx * math.cos(ang) - tz * math.sin(ang)
            dz = tx * math.sin(ang) + tz * math.cos(ang)
            arm_len = 0.95
            mid = (tip[0] - dx * arm_len * 0.5, 0.0, tip[2] - dz * arm_len * 0.5)
            _arm_box(bm, mid, (arm_len, 0.10, 0.24), (0.0, -math.atan2(dz, dx), 0.0))
        p.mesh("Chevron_%d" % (i + 1), bm, M.chevron(i + 1, MAGENTA), box_map=False)
    p.empty("Light", (0.0, 0.0, 0.0), direction=(0.0, 1.0, 0.0), size=1.5)
    return p.finalize("SkyLaneGate")


def _truss(p, half):
    """A 0.9 m box truss over the carriageway (like the guide gantries)."""
    r = 0.055
    hz = hw = 0.45
    z = CLEAR_Z
    for sz in (-hz, hz):
        for sy in (-hw, hw):
            p.tube("TrussChord", (-half, sy, z + sz), (half, sy, z + sz), r,
                   M.surface(), segments=4, surface="galv", cap=False)
    panels = 6
    step = (2 * half) / panels
    for i in range(panels + 1):
        x = -half + i * step
        for sy in (-hw, hw):
            p.tube("TrussVert%d" % i, (x, sy, z - hz), (x, sy, z + hz), r * 0.8,
                   M.surface(), segments=4, surface="galv", cap=False)
        p.tube("TrussTop%d" % i, (x, -hw, z + hz), (x, hw, z + hz), r * 0.8,
               M.surface(), segments=4, surface="galv", cap=False)
    for i in range(panels):
        xa = -half + i * step
        xb = xa + step
        for sy in (-hw, hw):
            p.tube("TrussDiag%d" % i, (xa, sy, z - hz), (xb, sy, z + hz), r * 0.75,
                   M.surface(), segments=4, surface="galv", cap=False)
        p.tube("TrussDiagT%d" % i, (xa, -hw, z + hz), (xb, hw, z + hz), r * 0.7,
               M.surface(), segments=4, surface="galv", cap=False)


def sky_lane_gantry():
    """An overhead gantry sign: 飞行航道 SKY LANE ▲ 300 m."""
    p = kit.Prop("SkyLaneGantry")
    half = GANTRY_W * 0.5
    clear = CLEAR_Z
    for sx in (-half, half):
        p.box("Post", (sx, 0.0, clear * 0.5), (0.36, 0.36, clear), M.surface(), bevel=0.03,
              surface="galv")
        p.box("Foot", (sx, 0.0, 0.12), (0.80, 0.80, 0.24), M.surface(),
              surface="concrete")
    _truss(p, half)
    p.sign("SignFace", (0.0, -0.62, clear + 0.32), 6.0, 1.8, M.sign_lit(True),
           M.surface(), board="skylane_gantry_sign", frame=0.08, depth=0.12)
    p.empty("Light", (0.0, 0.0, clear - 0.3), direction=(0.0, 0.0, -1.0), size=0.5)
    return p.finalize("SkyLaneGantry")


BUILDERS = {
    "sky_lane_pad": sky_lane_pad,
    "sky_lane_gate": sky_lane_gate,
    "sky_lane_gantry": sky_lane_gantry,
}
