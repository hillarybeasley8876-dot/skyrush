"""Hero Roadster wheels: low-profile tyre, six-spoke star rim, carbon-ceramic brake.

The wheel is built in local coordinates (axis = X, origin at the hub, outboard =
+X) and then mirrored in X for the left-hand side, so both sides dish outwards.
The object origin stays on the wheel centre, so the wheel spins about its local X.

The rim follows photo 13: six white aero blades, each split into two prongs with
a brushed-gold channel in the slot between them, dark satin spokes behind and a
dark hexagonal centre cap with two engraved rings.
"""
import math

import bmesh
from mathutils import Matrix

from car import materials, paths, shapes, uv_car
from lib import common

SEG = 120          # segments around the tyre
TREAD_GROOVES = 2
M_TYRE, M_WHITE, M_DARK, M_GOLD = 0, 1, 2, 3
RIM_SLOTS = (M_WHITE, M_DARK, M_GOLD)

# the wheel face of photo 13 (review r3 #7)
SECTOR = math.pi / 6.0     # the face is six sectors, one per white blade
ARM_HALF_MM = 0.009        # the dark V-spoke's arm is 18 mm wide at every radius
GOLD_HUB, GOLD_RIM = 0.012, 0.070   # the gold vane's half angle (tapers to the cap)
CAP_R = 0.062              # the hex centre cap
ARM_DROP = 0.005           # the arms are 5 mm below the white face
GOLD_DROP = 0.011          # the gold vane is 6 mm below the arms
CHAMFER = 0.001            # the 1 mm chamfer along the blade's edges
BLADE_R_HUB = 0.058        # the blades start at the centre cap


def _profile(R, W, Rr):
    """Tyre cross-section as (radius, x, v) points, inner bead -> tread -> outer.

    v is the texture coordinate: 0.0 inner bead, 0.34 inboard shoulder, 0.40..0.72
    tread, 0.72..1.0 outboard sidewall (the lettering band).
    """
    hw = W / 2.0
    p = [(Rr, -hw, 0.00), (Rr + 0.030, -hw - 0.006, 0.06), (R - 0.055, -hw - 0.003, 0.20),
         (R - 0.016, -hw + 0.010, 0.31), (R - 0.001, -hw + 0.040, 0.40)]
    t0, t1 = -hw + 0.040, hw - 0.040
    for i in range(TREAD_GROOVES + 1):
        c = t0 + (t1 - t0) * i / TREAD_GROOVES
        p.append((R, c, 0.40 + 0.32 * i / TREAD_GROOVES))
    p += [(R, hw - 0.040, 0.72), (R - 0.016, hw - 0.010, 0.80), (R - 0.055, hw + 0.003, 0.90),
          (Rr + 0.030, hw + 0.006, 0.96), (Rr, hw, 1.00)]
    return p


def _tyre(bm, R, W, Rr, flip_u=False):
    """Revolve the tyre profile around the X axis; UVs run u=angle, v=profile.

    `flip_u` reverses the direction of u. The two sides are built by MIRRORING
    the left tyre, so the lettering would read backwards on the right hand
    side: the u of the right hand tyres is flipped (review r3 #6).
    """
    prof = _profile(R, W, Rr)
    n = len(prof)
    rings = []
    for i in range(SEG):
        a = 2.0 * math.pi * i / SEG
        c, s = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((x, r * c, r * s)) for r, x, _ in prof])
    uv = bm.loops.layers.uv.new("UVMap")
    for i in range(SEG):
        j = (i + 1) % SEG
        for k in range(n - 1):
            try:
                f = bm.faces.new((rings[i][k], rings[j][k], rings[j][k + 1], rings[i][k + 1]))
            except ValueError:
                continue
            f.material_index = M_TYRE
            u0, u1 = i / SEG, (i + 1) / SEG
            if flip_u:
                u0, u1 = 1.0 - u0, 1.0 - u1
            v0, v1 = prof[k][2], prof[k + 1][2]
            for loop, c in zip(f.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
                loop[uv].uv = c
    return bm


def _blade(bm, ac, edge0, edge1, mat, stations):
    """A blade between two angular edges; edge0/edge1 are f(r) -> angle offset.

    A station is (r, x) for a flat blade or (r, x0, x1) for a strip whose two
    edges sit at different depths (the chamfer along a blade's edge).
    """
    rows = []
    for st in stations:
        r = st[0]
        x0 = st[1]
        x1 = st[2] if len(st) > 2 else x0
        a0, a1 = ac + edge0(r), ac + edge1(r)
        rows.append((bm.verts.new((x0, r * math.cos(a0), r * math.sin(a0))),
                     bm.verts.new((x1, r * math.cos(a1), r * math.sin(a1)))))
    for i in range(len(rows) - 1):
        try:
            f = bm.faces.new((rows[i][0], rows[i + 1][0], rows[i + 1][1], rows[i][1]))
            f.material_index = mat
        except ValueError:
            pass


def _barrel(bm, r, x0, x1, mat, n=SEG):
    """Cylinder wall (open) between two X positions."""
    ring = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        ring.append((bm.verts.new((x0, r * math.cos(a), r * math.sin(a))),
                     bm.verts.new((x1, r * math.cos(a), r * math.sin(a)))))
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((ring[i][0], ring[j][0], ring[j][1], ring[i][1]))
        f.material_index = mat
    return ring


def _rim(bm, Rr, W):
    """The wheel face of photo 13.

    Six WIDE white aero blades fill the face. Between two blades runs a dark
    V-spoke: two arms of 18 mm, and the brushed gold vane recessed 6 mm below
    the arms, in the middle of the V. A dark hex centre cap with two engraved
    rings closes the hub.
    """
    hw = W / 2.0
    x_face = hw - 0.020
    prof = [(Rr, hw), (Rr, hw - 0.012), (Rr - 0.014, hw - 0.038), (Rr - 0.032, hw - 0.058),
            (Rr - 0.032, -hw + 0.070), (Rr - 0.014, -hw + 0.022), (Rr, -hw + 0.010)]
    shapes.revolve(bm, prof, seg=112, mat=[M_DARK] * len(prof), axis="X", close=True)
    r_hub, r_rim = BLADE_R_HUB, Rr + 0.001

    def face(r):
        """The depth of the white face: the hub is dished 22 mm."""
        t = (r - r_hub) / max(r_rim - r_hub, 1e-6)
        return x_face - 0.022 + 0.026 * t

    def gold_edge(r):
        """The half angle of the gold vane."""
        t = (r - r_hub) / max(r_rim - r_hub, 1e-6)
        return GOLD_HUB + (GOLD_RIM - GOLD_HUB) * t

    def arm_edge(r):
        """The half angle of the dark arm: 18 mm wide at every radius."""
        return ARM_HALF_MM / max(r, 1e-4)

    def blade_edge(r):
        """The half angle of the white blade: the sector minus the V-spoke."""
        return SECTOR - gold_edge(r) - arm_edge(r)

    stations = []
    steps = 9
    for i in range(steps):
        r = r_hub + (r_rim - r_hub) * i / float(steps - 1)
        stations.append((r, face(r)))
    for i in range(6):
        ac = 2.0 * math.pi * i / 6.0
        ag = ac + SECTOR                       # the V-spoke between two blades
        # the white aero blade: a wide wedge from the cap to the rim
        _blade(bm, ac, lambda r: -(blade_edge(r) - CHAMFER),
               lambda r: blade_edge(r) - CHAMFER, M_WHITE, stations)
        # the 1 mm chamfer that catches the light along both edges
        for s in (-1, 1):
            _blade(bm, ac, lambda r, s=s: s * (blade_edge(r) - CHAMFER),
                   lambda r, s=s: s * blade_edge(r), M_WHITE,
                   [(r, x - 0.0015, x - 0.0015) for r, x in stations])
        # the two dark arms of the V-spoke, 5 mm below the white face
        for s in (-1, 1):
            _blade(bm, ag, lambda r, s=s: s * gold_edge(r),
                   lambda r, s=s: s * (gold_edge(r) + arm_edge(r)), M_DARK,
                   [(r, x - ARM_DROP) for r, x in stations])
        # the brushed gold vane inside the V, 6 mm below the arms
        _blade(bm, ag, lambda r: -gold_edge(r), lambda r: gold_edge(r), M_GOLD,
               [(r, x - GOLD_DROP) for r, x in stations])
    # the dark pocket floor: nothing shows through the wheel
    _blade(bm, 0.0, lambda r: -math.pi, lambda r: math.pi, M_DARK,
           [(r_hub, face(r_hub) - 0.030), (r_rim, face(r_rim) - 0.030)])
    _hub(bm, x_face)


def _hub(bm, x_face):
    """Dark hub barrel and the hexagonal centre cap (engraved ring pattern)."""
    _barrel(bm, 0.058, x_face - 0.058, x_face - 0.020, M_DARK, 24)
    lo, hi = [], []
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0 + math.pi / 6.0
        lo.append(bm.verts.new((x_face - 0.014, CAP_R * math.cos(a), CAP_R * math.sin(a))))
        hi.append(bm.verts.new((x_face + 0.004, CAP_R * math.cos(a), CAP_R * math.sin(a))))
    f = bm.faces.new(hi)
    f.material_index = M_DARK
    for rr in (0.030, 0.044):        # engraved concentric rings on the centre cap
        inner, outer = [], []
        for i in range(24):
            a = 2.0 * math.pi * i / 24
            inner.append(bm.verts.new((x_face + 0.004, rr * math.cos(a), rr * math.sin(a))))
            outer.append(bm.verts.new((x_face + 0.005, (rr + 0.004) * math.cos(a),
                                        (rr + 0.004) * math.sin(a))))
        for i in range(24):
            j = (i + 1) % 24
            f = bm.faces.new((inner[i], outer[i], outer[j], inner[j]))
            f.material_index = M_DARK
    for i in range(6):
        j = (i + 1) % 6
        f = bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
        f.material_index = M_DARK


def _disc(bm, r_out, r_in, x, n=64):
    """Carbon-ceramic brake disc (the drilled ring comes from the map)."""
    ring = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        ring.append((bm.verts.new((x, r_in * math.cos(a), r_in * math.sin(a))),
                     bm.verts.new((x, r_out * math.cos(a), r_out * math.sin(a)))))
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((ring[i][0], ring[i][1], ring[j][1], ring[j][0]))
        f.material_index = 1        # the M_Disc slot of the caliper object
    return bm


def _caliper(bm, r, x, ang=math.pi / 2.0):
    """Bronze caliper straddling the disc (does not spin)."""
    w, h, d = 0.055, 0.13, 0.038
    c, s = math.cos(ang), math.sin(ang)
    pts = []
    for sy in (-w, w):
        for sz in (-h / 2, h / 2):
            for sx in (-d, d):
                pts.append(bm.verts.new((x + sx, r * c - sy * s, r * s + sy * c)))
    q = [pts[0], pts[1], pts[3], pts[2], pts[4], pts[5], pts[7], pts[6]]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    for f in faces:
        try:
            bm.faces.new([q[i] for i in f])
        except ValueError:
            pass
    for sy in (-0.028, 0.028):
        p0 = (x + 0.02, r * c - sy * s, r * s + sy * c)
        p1 = (x - 0.02, r * c - sy * s, r * s + sy * c)
        shapes.tube(bm, [p0, p1], 0.016, 10, 0)
    shapes.box(bm, (x, r * c, r * s), (0.030, 0.075, 0.075), 0)
    return bm


def build_wheels(col, root):
    """Four wheels (origin at the hub, spin about local X) and their calipers."""
    d = paths.loft()["wheels"]
    for key, tag in (("front", "F"), ("rear", "R")):
        w = d[key]
        cx, cy, cz = w["centre"]
        R = w["tyre_diameter"] / 2.0
        W = w["tyre_width"]
        Rr = w["rim_diameter"] / 2.0
        for side, sname in ((1, "R"), (-1, "L")):
            bm = bmesh.new()
            _rim(bm, Rr, W)
            if side < 0:
                bmesh.ops.transform(bm, matrix=Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)),
                                    verts=bm.verts)
                bmesh.ops.reverse_faces(bm, faces=bm.faces)
            ob = common.mesh_object("Wheel_%s%s" % (tag, sname), bm, col)
            for m in (materials.get("M_WheelWhite"), materials.get("M_WheelDark"),
                      materials.get("M_GoldWheel")):
                ob.data.materials.append(m)
            for f in ob.data.polygons:                # remap to the rim's own slots
                f.material_index = RIM_SLOTS.index(f.material_index)
            ob.location = (side * cx, cy, cz)
            paths.parent_to(ob, root)
            uv_car.radial_uv(ob, "UVMap")
            tb = bmesh.new()
            # the left tyre is the right one TURNED AROUND the axle, not
            # mirrored: a mirror would put the lettering on the inboard
            # sidewall. Its u is flipped, so the lettering reads the same way
            # on both sides (review r3 #6).
            _tyre(tb, R, W, Rr, flip_u=(side < 0))
            if side < 0:
                bmesh.ops.transform(tb, matrix=Matrix.Rotation(math.pi, 3, "Z"),
                                    verts=tb.verts)
            tob = common.mesh_object("Tyre_%s%s" % (tag, sname), tb, col)
            tob.data.materials.append(materials.get("M_Tyre_" + tag))
            tob.location = (side * cx, cy, cz)
            paths.parent_to(tob, ob)
            # the brake disc belongs to the caliper: it does not spin (dossier §8.2)
            r_out = 0.205 if key == "front" else 0.195
            cal = bmesh.new()
            _caliper(cal, 0.185 if key == "front" else 0.175, side * (W / 2.0 - 0.075))
            _disc(cal, r_out, 0.105, side * (W / 2.0 - 0.075))
            bmesh.ops.recalc_face_normals(cal, faces=cal.faces)
            cob = common.mesh_object("Caliper_%s%s" % (tag, sname), cal, col)
            cob.data.materials.append(materials.get("M_CaliperBronze"))
            cob.data.materials.append(materials.get("M_Disc"))
            cob.location = (side * cx, cy, cz)
            paths.parent_to(cob, root)
            uv_car.disc_uv(cob, 0.105, r_out)
