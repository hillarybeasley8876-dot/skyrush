"""The bronze bull of the Bund Financial Plaza (bund unit).

A generic charging bull - a stylised animal form, deliberately not a copy of the real
sculpture's trademarked look. The body is lofted from a spine of elliptical sections, the
head is carried low, the horns point forward and the tail is whipped up. The whole animal
is a single smooth bronze surface (no separate boxes), so it reads as a sculpture.
"""
import math

BODY_SECTIONS = 26
BODY_RING = 24
HEAD_SECTIONS = 12
HEAD_RING = 20
LEG_SECTIONS = 10
LEG_RING = 12


def _ring(centre, rx, rz, n, axis_u, axis_v, phase=0.0):
    """A ring of points on an ellipse in the plane perpendicular to the spine."""
    pts = []
    for i in range(n):
        a = 2.0 * math.pi * i / n + phase
        c, s = math.cos(a), math.sin(a)
        pts.append((centre[0] + axis_u[0] * rx * c + axis_v[0] * rz * s,
                    centre[1] + axis_u[1] * rx * c + axis_v[1] * rz * s,
                    centre[2] + axis_u[2] * rx * c + axis_v[2] * rz * s))
    return pts


def _loft(dst, rings, cap_start=True, cap_end=True):
    """Skin a list of equal-length rings into quads."""
    n = len(rings[0])
    vs = [[dst.verts.new(p) for p in ring] for ring in rings]
    for a, b in zip(vs[:-1], vs[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            dst.faces.new((a[k], a[k2], b[k2], b[k]))
    if cap_start:
        dst.faces.new(vs[0])
    if cap_end:
        dst.faces.new(vs[-1])
    return dst


def _body_sections():
    """The spine of the bull: (along, across, up, half width, half height)."""
    # a charging bull: the weight forward, the shoulders high, the hindquarters lower
    raw = [
        (-1.55, 0.00, 1.02, 0.16, 0.16),     # the rump
        (-1.40, 0.00, 1.06, 0.34, 0.36),
        (-1.20, 0.00, 1.10, 0.48, 0.50),
        (-0.95, 0.00, 1.12, 0.56, 0.58),
        (-0.65, 0.00, 1.14, 0.60, 0.60),
        (-0.35, 0.00, 1.16, 0.62, 0.58),
        (-0.05, 0.00, 1.18, 0.62, 0.55),     # the barrel
        (0.25, 0.00, 1.18, 0.60, 0.52),
        (0.50, 0.00, 1.16, 0.58, 0.50),
        (0.72, 0.00, 1.12, 0.54, 0.48),     # the shoulders
        (0.90, 0.00, 1.06, 0.46, 0.44),
        (1.02, 0.00, 0.98, 0.36, 0.36),     # the neck
        (1.10, 0.00, 0.88, 0.28, 0.28),
        (1.16, 0.00, 0.78, 0.22, 0.22),
    ]
    out = []
    for i in range(BODY_SECTIONS):
        t = i / (BODY_SECTIONS - 1) * (len(raw) - 1)
        i0 = min(int(t), len(raw) - 2)
        f = t - i0
        a, b = raw[i0], raw[i0 + 1]
        out.append(tuple(a[k] + (b[k] - a[k]) * f for k in range(5)))
    return out


def build(dst, origin, heading):
    """The bull: `origin` is the ground point of its centre, `heading` its facing angle."""
    ux, uy = math.cos(heading), math.sin(heading)     # the direction the bull faces
    vx, vy = -uy, ux                                  # its flank
    up = (0.0, 0.0, 1.0)

    def place(along, across, z):
        return (origin[0] + ux * along + vx * across,
                origin[1] + uy * along + vy * across,
                origin[2] + z)

    # the body
    rings = []
    for (along, across, z, rx, rz) in _body_sections():
        c = place(along, across, z)
        rings.append(_ring(c, rx, rz, BODY_RING, (vx, vy, 0.0), up))
    _loft(dst, rings)

    # the head: carried low, in front of the shoulders
    head = []
    for i in range(HEAD_SECTIONS):
        t = i / (HEAD_SECTIONS - 1)
        along = 1.10 + t * 0.52
        z = 0.86 - t * 0.40
        rx = 0.24 - t * 0.07
        rz = 0.23 - t * 0.05
        c = place(along, 0.0, z)
        head.append(_ring(c, rx, rz, HEAD_RING, (vx, vy, 0.0), up))
    _loft(dst, head)

    # the muzzle
    muzzle = []
    for i in range(6):
        t = i / 5.0
        c = place(1.62 + t * 0.14, 0.0, 0.46 - t * 0.03)
        muzzle.append(_ring(c, 0.17 - t * 0.06, 0.16 - t * 0.06, 12, (vx, vy, 0.0), up))
    _loft(dst, muzzle)

    # the horns: forward and out
    for sy in (-1.0, 1.0):
        rings = []
        for i in range(10):
            t = i / 9.0
            along = 1.52 + t * 0.30
            across = sy * (0.14 + t * 0.16)
            z = 0.60 + t * 0.16 - t * t * 0.10
            r = 0.055 * (1.0 - t * 0.85)
            c = place(along, across, z)
            rings.append(_ring(c, r, r, 10, (ux, uy, 0.0), up))
        _loft(dst, rings, cap_start=True, cap_end=True)

    # the ears
    for sy in (-1.0, 1.0):
        c = place(1.06, sy * 0.22, 0.98)
        ear = _ring(c, 0.10, 0.05, 8, (vx, vy, 0.0), (ux, uy, 0.0))
        _loft(dst, [ear, ear], cap_start=True, cap_end=True)

    # the legs: four tapered columns down to the ground
    for (along, across) in ((0.62, 0.34), (0.62, -0.34), (-0.95, 0.36), (-0.95, -0.36)):
        rings = []
        for i in range(LEG_SECTIONS):
            t = i / (LEG_SECTIONS - 1)
            z = 0.02 + (1.05 - 0.02) * t
            lean = 0.10 * (1.0 - t) * (1 if along > 0 else -1)
            r = 0.15 * (1.0 - 0.45 * t) + 0.035
            c = place(along + lean, across * (1.0 - 0.06 * t), z)
            rings.append(_ring(c, r, r * 0.85, LEG_RING, (vx, vy, 0.0), up))
        _loft(dst, rings)

    # the tail: whipped up over the back
    rings = []
    for i in range(12):
        t = i / 11.0
        along = -1.52 - t * 0.22
        z = 1.02 + t * 0.52
        r = 0.055 * (1.0 - t * 0.6)
        c = place(along, 0.0, z)
        rings.append(_ring(c, r, r, 10, (ux, uy, 0.0), up))
    _loft(dst, rings)
    return dst
