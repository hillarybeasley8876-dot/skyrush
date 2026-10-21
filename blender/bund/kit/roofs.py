"""Roof cues for the Bund buildings (bund unit): domes, the clock tower, the Peace Hotel
pyramid, the Bank of China Chinese roof and the smaller crown forms.

The four faces of every tower stage are built as real walls with real openings, so the
clock tower and the Broadway Mansions setbacks read as buildings and not as blank boxes.
"""
import math

from . import parts, profiles, columns, walls


def dome_profile(radius, height, rings=8):
    """The profile of a segmental dome: (radius, z) from the springing line to the apex."""
    prof = []
    for i in range(rings + 1):
        t = i / rings
        prof.append((radius * math.cos(t * math.pi * 0.5),
                     height * (math.sin(t * math.pi * 0.5) ** 0.85)))
    return prof


def dome_outline(radius, height, rings=8):
    """The silhouette of a dome in the (y, z) plane: the crown-shaped wash card."""
    prof = dome_profile(radius, height, rings)
    return [(-r, z) for (r, z) in prof] + [(r, z) for (r, z) in reversed(prof)]


def dome(asm, mat, x, y, z0, radius, height, segments=28, rings=8, ribs=0):
    """A segmental dome on top of a drum (z0 = the springing line)."""
    prof = []
    for i in range(rings + 1):
        t = i / rings
        r = radius * math.cos(t * math.pi * 0.5)
        z = height * (math.sin(t * math.pi * 0.5) ** 0.85)
        prof.append((r, z))
    asm.lathe(mat, prof, segments, (x, y, z0))
    if ribs:
        bm = asm.bm(mat)
        w = 0.16
        for k in range(ribs):
            a = 2.0 * math.pi * k / ribs
            ca, sa = math.cos(a), math.sin(a)
            for i in range(rings):
                t0, t1 = i / rings, (i + 1) / rings
                r0 = radius * math.cos(t0 * math.pi * 0.5) + 0.03
                r1 = radius * math.cos(t1 * math.pi * 0.5) + 0.03
                z0b = height * (math.sin(t0 * math.pi * 0.5) ** 0.85)
                z1b = height * (math.sin(t1 * math.pi * 0.5) ** 0.85)
                # a closed rib: a thin slab standing on the dome
                top = []
                for (rr, zz, sgn) in ((r0, z0b, 1.0), (r1, z1b, 1.0),
                                      (r1, z1b, -1.0), (r0, z0b, -1.0)):
                    top.append((x + rr * ca - sgn * w * 0.5 * sa,
                                y + rr * sa + sgn * w * 0.5 * ca, zz))
                low = []
                for (rr, zz, sgn) in ((r0, z0b, 1.0), (r1, z1b, 1.0),
                                      (r1, z1b, -1.0), (r0, z0b, -1.0)):
                    low.append((x + (rr + 0.07) * ca - sgn * w * 0.5 * sa,
                                y + (rr + 0.07) * sa + sgn * w * 0.5 * ca, zz))
                a_v = [bm.verts.new(p) for p in top]
                b_v = [bm.verts.new(p) for p in low]
                bm.faces.new(a_v)
                bm.faces.new(list(reversed(b_v)))
                for j in range(4):
                    j2 = (j + 1) % 4
                    bm.faces.new((a_v[j], a_v[j2], b_v[j2], b_v[j]))


def drum(asm, mat, x, y, z0, radius, height, segments=24, columns_n=16, order="ionic"):
    """The drum under a dome, with a colonnade around it."""
    asm.lathe(mat, [(0.0, 0.0), (radius, 0.0), (radius, height), (0.0, height)],
              segments, (x, y, z0))
    for i in range(columns_n):
        a = 2.0 * math.pi * i / columns_n
        # the columns stand in front of the drum wall, not inside it
        cx = x + (radius + 0.35) * math.cos(a)
        cy = y + (radius + 0.35) * math.sin(a)
        columns.column(asm, mat, cx, cy, z0, height * 0.92, order, fluted=False, segments=8)
    asm.lathe(mat, [(0.0, 0.0), (radius + 0.7, 0.0), (radius + 0.7, 0.45),
                    (radius + 0.35, 0.7), (0.0, 0.7)], segments, (x, y, z0 + height))


def dome_drum(asm, s, x, y):
    """HSBC: a tall drum on 16 paired Ionic columns, a stilted ribbed dome, a lantern
    with oculi and a finial - the dome has to clear the roofline (dossier 5.3)."""
    z = s["cornice"]
    r = 6.0
    drum_h = 5.5
    # the attic block under the drum: the storey the dome stands on
    asm.gbox("stone", (x - 1.0, y, z + 1.2), (9.0, 15.0, 2.4), 1.5)
    _drum_windows(asm, x, y, z + 0.1, z + 2.3, 4.2, 6.6)
    z0 = z + 2.4
    # the drum: 16 columns in 8 pairs around a 6.0 m radius
    asm.lathe("stone", [(0.0, 0.0), (r, 0.0), (r, drum_h), (0.0, drum_h)], 24, (x, y, z0))
    for k in range(8):
        a = 2.0 * math.pi * k / 8
        for side in (-1.0, 1.0):
            ang = a + side * 0.19
            # the columns stand in front of the drum wall, not inside it
            cx = x + (r + 0.45) * math.cos(ang)
            cy = y + (r + 0.45) * math.sin(ang)
            columns.column(asm, "stone", cx, cy, z0, drum_h * 0.86, "ionic",
                           fluted=False, segments=24)
    # the cornice ring on top of the drum
    asm.lathe("stone", [(0.0, 0.0), (r + 1.1, 0.0), (r + 1.1, 0.50),
                        (r + 0.5, 0.75), (0.0, 0.75)], 24, (x, y, z0 + drum_h))
    zd = z0 + drum_h + 0.75
    dome(asm, "dome", x, y, zd, r + 0.4, (r + 0.4) * 1.10, 28, 9, ribs=8)
    top = zd + (r + 0.4) * 1.10
    # the lantern with its oculi and the overhanging disc
    asm.lathe("stone", [(0.0, 0.0), (1.9, 0.0), (1.9, 0.30), (0.0, 0.30)], 16, (x, y, top))
    asm.lathe("stone", [(0.0, 0.0), (1.55, 0.0), (1.55, 1.40), (0.0, 1.40)], 16, (x, y, top + 0.30))
    for k in range(8):
        a = 2.0 * math.pi * k / 8
        asm.box("glassdark", (x + 1.56 * math.cos(a), y + 1.56 * math.sin(a), top + 1.0),
                (0.12, 0.55, 0.7))
    asm.lathe("stone", [(0.0, 0.0), (2.3, 0.0), (2.3, 0.24), (1.7, 0.42), (0.0, 0.42)], 16,
              (x, y, top + 1.70))
    asm.lathe("iron", [(0.0, 0.0), (0.16, 0.0), (0.10, 2.0), (0.0, 2.0)], 8, (x, y, top + 2.1))
    return top + 4.1


def _drum_windows(asm, x, y, z0, z1, hx, hy):
    """The windows of the attic block under the HSBC drum."""
    holes = []
    n = 3
    for i in range(n):
        yc = y - hy + (i + 0.5) * (2 * hy / n)
        holes.append((yc, 0.8, z0 + 0.5, z1 - 0.3))
    walls.opening_wall(asm, "stone", "glasslit", x + hx, "X", 1.0, y - hy, y + hy,
                       z0, z1, holes, rng=None, lit_fraction=0.25, cell_base=5)
    walls.opening_wall(asm, "stone", "glasslit", x - hx, "X", -1.0, y - hy, y + hy,
                       z0, z1, holes, rng=None, lit_fraction=0.25, cell_base=5)


def _stage(asm, x, y, z0, z1, hx, hy, windows=True, mat="stone"):
    """One articulated square stage of a tower: four real walls, corner piers, a cornice."""
    prof = profiles.cornice(0.9, 0.7)
    if windows:
        wz0 = z0 + (z1 - z0) * 0.42
        wz1 = z0 + (z1 - z0) * 0.82
        half = 0.68
        for sign in (1.0, -1.0):
            holes = []
            n = 2
            for i in range(n):
                c = -hy * 0.5 + (i + 0.5) * (hy / n)
                holes.append((c, half, wz0, wz1))
            walls.opening_wall(asm, mat, "glasslit", x + sign * hx, "X", sign,
                               y - hy, y + hy, z0, z1, holes,
                               rng=None, lit_fraction=0.22, cell_base=2)
            holes = []
            for i in range(n):
                c = x - hx * 0.5 + (i + 0.5) * (hx / n)
                holes.append((c, half, wz0, wz1))
            walls.opening_wall(asm, mat, "glasslit", y + sign * hy, "Y", sign,
                               x - hx, x + hx, z0, z1, holes,
                               rng=None, lit_fraction=0.22, cell_base=9)
    else:
        asm.box(mat, (x, y, (z0 + z1) * 0.5), (hx * 2.0, hy * 2.0, z1 - z0))
    # corner pilasters
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            asm.box(mat, (x + sx * (hx - 0.35), y + sy * (hy - 0.35), (z0 + z1) * 0.5),
                    (0.7, 0.7, z1 - z0))
    # cornices on the four sides
    for sx in (-1.0, 1.0):
        asm.prism(mat, prof, y - hy - 0.7, y + hy + 0.7, x_off=x + sx * hx, z_off=z1)
    for sy in (-1.0, 1.0):
        prof_y = prof if sy > 0 else [(-px, pz) for (px, pz) in prof]
        asm.prism_x(mat, prof_y, x - hx - 0.7, x + hx + 0.7, y_off=y + sy * hy, z_off=z1)
    # a string course at the foot of the stage
    asm.box(mat, (x, y, z0 + 0.35), (hx * 2.0 + 0.5, hy * 2.0 + 0.5, 0.7))


def clock_tower(asm, s, x, y):
    """Customs House: a square clock tower with 4 backlit faces, a stepped top and a mast."""
    z = s["cornice"]            # 36.2
    hx, hy = 6.4, 6.4
    _stage(asm, x, y, z, z + 9.2, hx, hy)
    _stage(asm, x, y, z + 10.0, z + 18.4, hx * 0.95, hy * 0.95)
    # the clock stage: the four backlit dials
    cz = z + 22.5
    _stage(asm, x, y, z + 19.2, z + 25.8, hx * 0.90, hy * 0.90, windows=False,
           mat="clockstone")
    r = 2.9
    for face in range(4):
        a = face * math.pi * 0.5
        cx = x + (hx * 0.90 + 0.02) * math.cos(a)
        cy = y + (hy * 0.90 + 0.02) * math.sin(a)
        axis = "X" if face % 2 == 0 else "Y"
        # the stone panel the dial sits in
        asm.disc("stone", (cx - 0.10 * math.cos(a), cy - 0.10 * math.sin(a), cz),
                 r * 1.22, 0.3, axis)
        # the dial: a disc whose UVs map the clock face texture onto the circle
        asm.disc_uv("clock", (cx + 0.10 * math.cos(a), cy + 0.10 * math.sin(a), cz),
                    r, axis, 32, flip=(face in (1, 2)))
    # the stepped top with its corner urns
    zz = z + 25.8
    for k, sc in enumerate((0.80, 0.66, 0.52, 0.40)):
        asm.box("stone", (x, y, zz + 1.3 + k * 2.6), (hx * 2 * sc, hy * 2 * sc, 2.6))
        for sx in (-1.0, 1.0):
            asm.prism("stone", profiles.cornice(0.5, 0.45), y - hy * sc, y + hy * sc,
                      x_off=x + sx * hx * sc, z_off=zz + 2.6 + k * 2.6)
        if k == 3:
            for sx in (-1.0, 1.0):
                for sy in (-1.0, 1.0):
                    urn = (x + sx * hx * sc * 0.92, y + sy * hy * sc * 0.92)
                    asm.lathe("stone", [(0.0, 0.0), (0.42, 0.0), (0.34, 0.3), (0.46, 0.75),
                                        (0.30, 0.95), (0.0, 1.05)], 10,
                              (urn[0], urn[1], zz + 2.6 + k * 2.6))
    top = zz + 2.6 * 4
    asm.lathe("stone", [(0.0, 0.0), (1.5, 0.0), (1.2, 0.6), (0.0, 0.6)], 10, (x, y, top))
    # the 5 m mast with its flag
    asm.lathe("iron", [(0.0, 0.0), (0.22, 0.0), (0.14, 5.0), (0.0, 5.0)], 8, (x, y, top + 0.6))
    _flag_on_mast(asm, x, y, top + 0.8, 4.4)
    return top + 5.6


def _flag_on_mast(asm, x, y, z, h):
    """A small red flag on a mast (the Customs House flies the national flag)."""
    n, m = 5, 3
    bm = asm.loose_bm("red")
    verts = []
    for i in range(n + 1):
        row = []
        for j in range(m + 1):
            u = i / n
            v = j / m
            wave = math.sin(u * 5.0) * 0.18 * v
            row.append((x + u * 1.8, y + wave, z + h - 0.5 - v * 1.1))
        verts.append(row)
    for i in range(n):
        for j in range(m):
            a = bm.verts.new(verts[i][j])
            b = bm.verts.new(verts[i + 1][j])
            c = bm.verts.new(verts[i + 1][j + 1])
            d = bm.verts.new(verts[i][j + 1])
            bm.faces.new((a, b, c, d))


def pyramid_roof(asm, s, x, y, z0, height, hx, hy):
    """Sassoon House: the dark-green copper pyramid on the Peace Hotel tower."""
    parts.pyramid_lit(asm.bm("rooflit"), (hx, hy), height, (x, y, z0))
    # ribs along the four hips
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            asm.box("roof", (x + sx * hx * 0.5, y + sy * hy * 0.5, z0 + height * 0.5),
                    (0.30 if sx else hx * 2, 0.30 if sy else hy * 2, height))
    asm.box("stone", (x, y, z0 + height + 0.7), (2.2, 2.2, 1.4))
    asm.lathe("roof", [(0.0, 0.0), (1.1, 0.0), (0.8, 1.2), (0.0, 1.2)], 10, (x, y, z0 + height + 1.4))
    return z0 + height + 2.6


def stepped_tower(asm, s, x, y, z0, z1, half, mat="stone"):
    """The narrow stepped tower the Peace Hotel pyramid stands on (dossier 5.3).

    A 16 x 16 m shaft with two setbacks, its own cornices and lit windows."""
    stages = ((z0, z0 + (z1 - z0) * 0.42, half),
              (z0 + (z1 - z0) * 0.42, z0 + (z1 - z0) * 0.72, half * 0.86),
              (z0 + (z1 - z0) * 0.72, z1, half * 0.74))
    for i, (a, b, h) in enumerate(stages):
        _stage(asm, x, y, a, b, h, h, windows=True, mat=mat)
        asm.prism("stone", profiles.cornice(0.8, 0.6), y - h - 0.6, y + h + 0.6,
                  x_off=x + h, z_off=b)
        asm.prism("stone", profiles.cornice(0.8, 0.6), y - h - 0.6, y + h + 0.6,
                  x_off=x - h, z_off=b)
    return z1


def chinese_roof(asm, s, x, y, z0, height, hx, hy):
    """Bank of China: a hipped roof with flared, up-turned eaves and a ridge finial."""
    def ring(scale, z):
        c = [(x + hx * scale, y + hy * scale, z + 1.1),
             (x, y + hy * scale, z),
             (x - hx * scale, y + hy * scale, z + 1.1),
             (x - hx * scale, y, z + 0.5),
             (x - hx * scale, y - hy * scale, z + 1.1),
             (x, y - hy * scale, z),
             (x + hx * scale, y - hy * scale, z + 1.1),
             (x + hx * scale, y, z + 0.5)]
        return c
    sections = [ring(1.0, z0), ring(0.86, z0 + 1.6), ring(0.55, z0 + height * 0.62),
                ring(0.16, z0 + height)]
    from lib import geo
    parts.merge(asm.bm("tileteal"), geo.loft(sections, closed_sections=True,
                                             cap_start=True, cap_end=True))
    # the ridge beam and its finial urn
    asm.box("tileteal", (x, y, z0 + height + 0.5), (hx * 0.36, hy * 2.0, 0.9))
    for sy in (-1.0, 1.0):
        asm.lathe("tileteal", [(0.0, 0.0), (0.55, 0.0), (0.45, 0.9), (0.0, 1.5)], 10,
                  (x, y + sy * hy * 0.95, z0 + height + 0.9))
    return z0 + height + 2.4


def cupola(asm, x, y, z0, size=2.8, height=4.2):
    """A small corner cupola (Shanghai Club, Great Northern Telegraph)."""
    asm.box("stone", (x, y, z0 + 0.5), (size, size, 1.0))
    asm.box("stone", (x, y, z0 + 1.0 + (height - 1.0) * 0.55), (size * 0.8, size * 0.8, height - 1.0))
    asm.prism("stone", profiles.cornice(0.6, 0.5), y - size * 0.45, y + size * 0.45,
              x_off=x + size * 0.4, z_off=z0 + height)
    dome(asm, "dome", x, y, z0 + height + 0.6, size * 0.45, size * 0.5, 14, 5)
    asm.lathe("iron", [(0.0, 0.0), (0.12, 0.0), (0.08, 1.1), (0.0, 1.1)], 6, (x, y, z0 + height + 1.4))
    return z0 + height + 2.5
