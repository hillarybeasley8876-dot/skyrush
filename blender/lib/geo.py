"""Procedural geometry helpers (core-owned): splines, sweeps and lofts used by roads, rails,
light bars, piers and the car body. All functions return bmesh / plain data; wrap with
common.mesh_object(name, bm, col, material)."""
import math

import bmesh
from mathutils import Vector


def catmull_rom(points, step=2.0, closed=False):
    """Centripetal-ish Catmull-Rom through 3D points, resampled roughly every `step` metres."""
    pts = [Vector(p) for p in points]
    if closed:
        pts = [pts[-1]] + pts + [pts[0], pts[1]]
    else:
        pts = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        n = max(1, int(math.ceil((p2 - p1).length / step)))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(pts[-2].copy())
    return out


def resample(points, step):
    """Uniformly resample a polyline every `step` metres (keeps both ends)."""
    pts = [Vector(p) for p in points]
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = (b - a).length
        d = step - carry
        while d <= seg:
            out.append(a.lerp(b, d / seg))
            d += step
        carry = seg - (d - step)
    if (out[-1] - pts[-1]).length > 1e-4:
        out.append(pts[-1])
    return out


def frames(path, up=(0.0, 0.0, 1.0), closed=False):
    """Per-point (tangent, right, up) with world-up stabilised frames (no roll for roads)."""
    U = Vector(up)
    res = []
    n = len(path)
    for i in range(n):
        a = path[(i - 1) % n] if (closed or i > 0) else path[i]
        b = path[(i + 1) % n] if (closed or i < n - 1) else path[i]
        t = (b - a).normalized()
        r = t.cross(U)
        if r.length < 1e-6:
            r = Vector((1.0, 0.0, 0.0))
        r.normalize()
        res.append((t, r, r.cross(t).normalized()))
    return res


def _signed_area(prof):
    return 0.5 * sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(prof, prof[1:] + prof[:1]))


def sweep(profile, path, closed_profile=False, closed_path=False, bank=None, up=(0.0, 0.0, 1.0),
          flip=False):
    """Extrude a 2D profile [(x_right, z_up), ...] along a 3D path. `profile` may be a callable
    f(i, along_m) -> profile (same point count) for varying widths. `bank` = per-point roll (rad).
    Normals: closed profiles always face outward (either winding). Open profiles face to the LEFT
    of the profile's walking direction seen from behind (looking along the path): a road profile
    listed left->right faces up; a wall listed bottom->top faces -x (toward the left).
    `flip=True` reverses that. Stores float vertex attributes 'along' (m along path) and 'across'
    (m along profile) for uv.strip_uv. Returns a bmesh."""
    fr = frames(path, up, closed_path)
    bm = bmesh.new()
    along_l = bm.verts.layers.float.new("along")
    across_l = bm.verts.layers.float.new("across")
    rings, dist = [], 0.0
    for i, p in enumerate(path):
        if i:
            dist += (p - path[i - 1]).length
        prof = profile(i, dist) if callable(profile) else profile
        t, r, u = fr[i]
        if bank:
            c, s = math.cos(bank[i]), math.sin(bank[i])
            r, u = r * c + u * s, u * c - r * s
        ring, acc = [], 0.0
        for k, (x, z) in enumerate(prof):
            if k:
                acc += math.hypot(x - prof[k - 1][0], z - prof[k - 1][1])
            v = bm.verts.new(p + r * x + u * z)
            v[along_l], v[across_l] = dist, acc
            ring.append(v)
        rings.append(ring)
    first = profile(0, 0.0) if callable(profile) else profile
    if closed_profile:
        flip = _signed_area(list(first)) > 0.0  # CCW profiles would face inward
    seg_rings = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if closed_path else [])
    for ra, rb in seg_rings:
        m = len(ra)
        for k in range(m if closed_profile else m - 1):
            k2 = (k + 1) % m
            quad = (ra[k], ra[k2], rb[k2], rb[k])
            bm.faces.new(tuple(reversed(quad)) if flip else quad)
    bm.normal_update()
    return bm


def loft(sections, closed_sections=True, cap_start=False, cap_end=False):
    """Skin consecutive sections (lists of 3D points, equal counts) into quads. Returns a bmesh."""
    bm = bmesh.new()
    rings = [[bm.verts.new(Vector(p)) for p in sec] for sec in sections]
    m = len(rings[0])
    for ra, rb in zip(rings, rings[1:]):
        for k in range(m if closed_sections else m - 1):
            k2 = (k + 1) % m
            bm.faces.new((ra[k], ra[k2], rb[k2], rb[k]))
    if cap_start:
        bm.faces.new(list(reversed(rings[0])))
    if cap_end:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def box(bm, center, size, rot_z=0.0):
    """Add an axis box (optionally rotated about Z) to an existing bmesh; returns its faces."""
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    c, s = math.cos(rot_z), math.sin(rot_z)
    for v in verts:
        x, y, z = v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]
        v.co = Vector((center[0] + x * c - y * s, center[1] + x * s + y * c, center[2] + z))
    return list({f for v in verts for f in v.link_faces})


def cylinder(bm, center, radius, depth, segments=16, axis="Z"):
    """Add a closed cylinder (caps on) along X, Y or Z centred at `center`."""
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius,
                                depth=depth)
    for v in res["verts"]:
        x, y, z = v.co
        if axis == "X":
            x, y, z = z, y, -x
        elif axis == "Y":
            x, y, z = x, z, -y
        v.co = Vector((center[0] + x, center[1] + y, center[2] + z))
    return res["verts"]
