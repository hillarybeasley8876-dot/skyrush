"""Roof and sign parts: parapets, water tanks, antennas, clutter, neon blades, LED screens."""
import math

from . import shapes
from .parts import bpy_math_offset, _quad_uv


def edge_boxes(bm, poly, h0, h1, thickness, offset=0.0, edges=None):
    """A band of boxes following a closed city-space polygon (parapet, crown, string course).

    `edges` limits the band to some edges of the polygon (the sides of a building in
    a row are party walls and never seen).
    """
    n = len(poly)
    cx = sum(p[0] for p in poly) / n
    cz = sum(p[1] for p in poly) / n
    for i in range(n):
        if edges is not None and i not in edges:
            continue
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        dx, dz = bx - ax, bz - az
        length = math.hypot(dx, dz)
        if length < 0.2:
            continue
        ux, uz = dx / length, dz / length
        nx, nz = -uz, ux
        mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
        if (cx - mx) * nx + (cz - mz) * nz < 0.0:
            nx, nz = -nx, -nz
        px = mx + nx * (offset - thickness * 0.5)
        pz = mz + nz * (offset - thickness * 0.5)
        shapes.add_box(bm, (px, pz), (length, thickness), h0, h1,
                       rot_deg=math.degrees(math.atan2(uz, ux)))


def add_parapet(ctx, poly, h0, height=1.0, thickness=0.24, key="render"):
    """Roof parapet; Shanghai blocks often carry planters on them."""
    edge_boxes(ctx.bag.bm(key), poly, h0, h0 + height, thickness)


def add_crown_strip(ctx, poly, h0, height=0.45, thickness=0.35, key="emissive_cyan"):
    """An emissive edge line along the top of a tower crown."""
    edge_boxes(ctx.bag.bm(key), poly, h0, h0 + height, thickness, offset=0.06)


def add_mechanical_floor(ctx, poly, h0, height=5.0, key="emissive_white", detail=3):
    """The mechanical floor of a tower: a dark service band with a row of lit vents.

    A pale cone on a roof reads as a toy; a service band with lit vents reads as a
    building (ART.md 11, B-NIGHT2).  The lit vents are the first thing to go when
    a tile is over its triangle budget.
    """
    edge_boxes(ctx.bag.bm("granite"), poly, h0, h0 + height, 0.16, offset=0.08)
    lit = ctx.bag.bm(key)
    n = len(poly)
    cx = sum(p[0] for p in poly) / n
    cz = sum(p[1] for p in poly) / n
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        dx, dz = bx - ax, bz - az
        length = math.hypot(dx, dz)
        if length < 0.3:
            continue
        ux, uz = dx / length, dz / length
        nx, nz = -uz, ux
        mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
        if (cx - mx) * nx + (cz - mz) * nz < 0.0:
            nx, nz = -nx, -nz
        rot = math.degrees(math.atan2(uz, ux))
        count = max(1, int(length / 4.0))
        for k in range(count):
            if detail < 2:
                break
            t = (k + 0.5) / count
            px = ax + dx * t + nx * 0.22
            pz = az + dz * t + nz * 0.22
            shapes.add_box(lit, (px, pz), (1.5, 0.16), h0 + height * 0.35,
                           h0 + height * 0.35 + 0.9, rot_deg=rot)


def add_water_tank(ctx, center, radius=1.1, height=1.8, legs=0.9):
    """Rooftop stainless water tank on a steel frame."""
    bm = ctx.bag.bm("metal_galv")
    cx, cz = center
    for i in range(4):
        a = math.pi * 0.25 + i * math.pi * 0.5
        lx, lz = cx + math.cos(a) * radius * 0.8, cz + math.sin(a) * radius * 0.8
        shapes.add_box(bm, (lx, lz), (0.12, 0.12), 0.0, legs)
    res = _cylinder(bm, (cx, cz), radius, legs, legs + height, 12)
    return res


def _cylinder(bm, center, radius, h0, h1, segments=12):
    """Vertical cylinder in city space (approximated with a box ring is not enough - build it)."""
    import bmesh
    from mathutils import Vector
    cx, cz = center
    ring = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        ring.append((cx + math.cos(a) * radius, cz + math.sin(a) * radius))
    lower = [bm.verts.new(shapes.to_blender(x, z, h0)) for x, z in ring]
    upper = [bm.verts.new(shapes.to_blender(x, z, h1)) for x, z in ring]
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bm.faces.new(list(reversed(lower)))
    bm.faces.new(upper)
    return bm


def add_antenna(ctx, base, height=4.0, arms=3, key="metal_dark"):
    """A rooftop aerial mast with cross arms."""
    bm = ctx.bag.bm(key)
    bx, bz = base
    shapes.add_box(bm, (bx, bz), (0.10, 0.10), 0.0, height)
    for i in range(arms):
        h = height * (0.45 + 0.2 * i)
        half = 0.7 - 0.15 * i
        shapes.add_box(bm, (bx, bz), (half * 2.0, 0.05), h, h + 0.05)


def add_roof_clutter(ctx, poly, h, rng, count=4, detail=3):
    """Stair head, vent boxes and vents - the clutter that sells a roof.

    `detail` below 3 drops the clutter but still draws the random numbers, so a
    building that loses its clutter does not change the buildings around it.
    """
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    x0, x1 = min(xs), max(xs)
    z0, z1 = min(zs), max(zs)
    for i in range(count):
        w = rng.uniform(1.2, 3.0)
        d = rng.uniform(1.2, 2.6)
        hh = rng.uniform(1.0, 2.8)
        px = rng.uniform(x0 + 0.5 + w * 0.5, max(x0 + 0.5 + w * 0.5, x1 - w * 0.5))
        pz = rng.uniform(z0 + 0.5 + d * 0.5, max(z0 + 0.5 + d * 0.5, z1 - d * 0.5))
        rot = rng.uniform(0, 180)
        if detail < 3:
            continue
        shapes.add_box(ctx.bag.bm("render"), (px, pz), (w, d), h, h + hh,
                       rot_deg=rot)
    if detail < 3:
        return
    # stair head with a door
    cx = (x0 + x1) * 0.5
    cz = (z0 + z1) * 0.5
    shapes.add_box(ctx.bag.bm("render"), (cx + 2.0, cz + 1.0), (3.2, 2.6), h, h + 2.6)
    shapes.add_box(ctx.bag.bm("metal_dark"), (cx + 2.0, cz + 1.0 - 1.32), (1.0, 0.1), h, h + 2.1)


def add_aviation_light(ctx, base, h=0.0):
    """Small red aviation warning light on a tower roof."""
    shapes.add_box(ctx.bag.bm("beacon"), base, (0.22, 0.22), h, h + 0.18)


def add_blade_sign(ctx, base, normal, width=1.2, height=3.6, bottom=3.6, key="neon_v"):
    """A vertical neon blade sign projecting PERPENDICULAR to the facade.

    The panel plane contains the facade normal and the vertical, so the characters face
    along the street (readable from up and down the road) - dossier 9, art 4.5.  The
    characters sit on a dark anodised back plate 8 cm behind the face.
    """
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(normal[1], normal[0]))
    centre = bpy_math_offset(base, normal, width * 0.5)
    # the dark anodised back plate the characters sit on
    shapes.add_box(ctx.bag.bm("metal_dark"), (centre[0], centre[1]), (width, 0.12),
                   bottom, bottom + height, rot_deg=ang)
    slot = ctx.next_sign(key)
    if slot is not None:
        uv = _quad_uv(slot)
        for sign_n in (t, (-t[0], -t[1])):
            face_base = bpy_math_offset(centre, sign_n, 0.07)
            shapes.add_wall_quad(ctx.bag.bm(key), face_base, sign_n, width,
                                 bottom + 0.05, bottom + height - 0.05, uv=uv)
    # steel brackets back to the wall
    for frac in (0.15, 0.85):
        p = (base[0] + normal[0] * width * frac, base[1] + normal[1] * width * frac)
        shapes.add_box(ctx.bag.bm("metal_dark"), (p[0], p[1]), (0.10, 0.10),
                       bottom + height - 0.35, bottom + height - 0.2,
                       rot_deg=math.degrees(math.atan2(t[1], t[0])))


def add_led_screen(ctx, base, normal, width, height, key="led"):
    """A big LED screen in a dark frame, mounted flat on a facade."""
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(t[1], t[0]))
    c = bpy_math_offset(base, normal, 0.18)
    shapes.add_box(ctx.bag.bm("metal_dark"), c, (width + 0.4, 0.3), 0.0, height + 0.2,
                   rot_deg=ang)
    slot = ctx.next_sign(key)
    if slot is not None:
        shapes.add_wall_quad(ctx.bag.bm(key), bpy_math_offset(base, normal, 0.34), normal,
                             width, 0.1, height, uv=_quad_uv(slot))


def add_laundry_pole(ctx, base, normal, length=1.8, h=3.4):
    """A bamboo laundry pole with a couple of hanging cloths - pure Shanghai."""
    t = shapes.wall_tangent(normal)
    ang = math.degrees(math.atan2(t[1], t[0]))
    c = bpy_math_offset(base, normal, 0.55)
    shapes.add_box(ctx.bag.bm("metal_galv"), c, (length, 0.05), h, h + 0.05, rot_deg=ang)
    for i in range(2):
        p = bpy_math_offset((base[0] + t[0] * length * (0.3 + 0.4 * i),
                             base[1] + t[1] * length * (0.3 + 0.4 * i)), normal, 0.5)
        shapes.add_box(ctx.bag.bm("awning"), p, (0.5, 0.03), h - 0.85, h, rot_deg=ang)


def _mid(a, b):
    return ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)


def add_ridge_course(ctx, poly, h_ridge, ridge_edge=0):
    """A ridge course of upright tiles along the ridge, with a rounded cap."""
    bm = ctx.bag.bm("roof")
    p = [poly[(ridge_edge + i) % 4] for i in range(4)]
    m_a = _mid(p[3], p[0])
    m_b = _mid(p[1], p[2])
    length = math.hypot(m_b[0] - m_a[0], m_b[1] - m_a[1])
    if length < 0.5:
        return
    ang = math.degrees(math.atan2(m_b[1] - m_a[1], m_b[0] - m_a[0]))
    count = max(3, int(length / 1.0))
    for i in range(count + 1):
        t = i / float(count)
        q = (m_a[0] + (m_b[0] - m_a[0]) * t, m_a[1] + (m_b[1] - m_a[1]) * t)
        shapes.add_box(bm, q, (0.30, 0.22), h_ridge, h_ridge + 0.15, rot_deg=ang)
    mid = _mid(m_a, m_b)
    shapes.add_box(bm, mid, (length, 0.28), h_ridge + 0.15, h_ridge + 0.24, rot_deg=ang)


def add_eave_board(ctx, poly, h_eave, ridge_edge=0):
    """The eave board and the gutter along the two eaves of a gable roof."""
    bm = ctx.bag.bm("wood")
    galv = ctx.bag.bm("metal_galv")
    p = [poly[(ridge_edge + i) % 4] for i in range(4)]
    for a, b in ((p[1], p[2]), (p[3], p[0])):
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length < 0.5:
            continue
        ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        mid = _mid(a, b)
        shapes.add_box(bm, mid, (length, 0.10), h_eave - 0.16, h_eave - 0.04, rot_deg=ang)
        shapes.add_box(galv, mid, (length, 0.12), h_eave - 0.26, h_eave - 0.16, rot_deg=ang)


def add_dormer(ctx, fc, h_eave, h_ridge, depth=1.3, width=1.3):
    """A dormer (老虎窗) in the roof slope: a small box with a casement and a cap."""
    ang = math.degrees(math.atan2(fc["t"][1], fc["t"][0]))
    mid = ((fc["a"][0] + fc["b"][0]) * 0.5, (fc["a"][1] + fc["b"][1]) * 0.5)
    base = (mid[0] + fc["n"][0] * depth * 0.5, mid[1] + fc["n"][1] * depth * 0.5)
    bm = ctx.bag.bm("brick")
    shapes.add_box(bm, base, (width, depth), h_eave - 0.1, h_eave + 0.75, rot_deg=ang)
    # the casement window on the front of the dormer
    front = (base[0] + fc["n"][0] * depth * 0.5, base[1] + fc["n"][1] * depth * 0.5)
    shapes.add_box(ctx.bag.bm("wood"), front, (0.70, 0.08), h_eave + 0.05, h_eave + 0.60,
                   rot_deg=ang)
    # a small pitched cap
    cap = ctx.bag.bm("roof")
    shapes.add_box(cap, (base[0], base[1]), (width + 0.22, depth + 0.20), h_eave + 0.75,
                   h_eave + 0.90, rot_deg=ang)
    shapes.add_box(cap, (base[0], base[1]), (width + 0.34, 0.30), h_eave + 0.90,
                   h_eave + 1.02, rot_deg=ang)
