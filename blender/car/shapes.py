"""Small procedural primitives shared by the car build scripts."""
import math

import bmesh
from mathutils import Vector


def revolve(bm, profile, seg=32, mat=None, axis="Z", close=False):
    """Revolve a profile of (radius, depth) around an axis.

    `profile` points are (r, d); d runs along the axis. `mat` is a list of material
    indices, one per profile segment (len(profile)-1, or len(profile) if closed).
    """
    n = len(profile)
    rings = []
    for i in range(seg):
        a = 2.0 * math.pi * i / seg
        c, s = math.cos(a), math.sin(a)
        ring = []
        for r, d in profile:
            if axis == "Z":
                co = (r * c, r * s, d)
            elif axis == "Y":
                co = (r * c, d, r * s)
            else:
                co = (d, r * c, r * s)
            ring.append(bm.verts.new(co))
        rings.append(ring)
    count = n if close else n - 1
    for i in range(seg):
        j = (i + 1) % seg
        for k in range(count):
            k2 = (k + 1) % n
            try:
                f = bm.faces.new((rings[i][k], rings[j][k], rings[j][k2], rings[i][k2]))
            except ValueError:
                continue
            if mat:
                f.material_index = mat[k]
    return rings


def box(bm, center, size, mat=0, rot=None):
    """Axis-aligned (or rotated) box; `size` is the full extent per axis."""
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    pts = []
    for sz in (-hz, hz):
        for sy in (-hy, hy):
            for sx in (-hx, hx):
                p = Vector((sx, sy, sz))
                if rot is not None:
                    p = rot @ p
                pts.append(bm.verts.new((p.x + center[0], p.y + center[1], p.z + center[2])))
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in faces:
        try:
            face = bm.faces.new([pts[i] for i in f])
            face.material_index = mat
        except ValueError:
            pass
    return pts


def plate(bm, corners, mat=0):
    """A single quad from four 3D points (in order)."""
    vs = [bm.verts.new(Vector(c)) for c in corners]
    try:
        f = bm.faces.new(vs)
        f.material_index = mat
        return f
    except ValueError:
        return None


def strip(bm, rows, mat=0, close=False):
    """Bridge a list of point rows (each row the same length) into quads."""
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        for k in range(len(a) - 1):
            try:
                f = bm.faces.new((a[k], b[k], b[k + 1], a[k + 1]))
                f.material_index = mat
            except ValueError:
                pass
    if close and len(rows) > 2:
        a, b = rows[-1], rows[0]
        for k in range(len(a) - 1):
            try:
                f = bm.faces.new((a[k], b[k], b[k + 1], a[k + 1]))
                f.material_index = mat
            except ValueError:
                pass


def ring_points(cx, cy, cz, r, seg, axis="X"):
    """Points on a circle in the plane perpendicular to `axis`."""
    out = []
    for i in range(seg):
        a = 2.0 * math.pi * i / seg
        c, s = math.cos(a) * r, math.sin(a) * r
        if axis == "X":
            out.append((cx, cy + c, cz + s))
        elif axis == "Y":
            out.append((cx + c, cy, cz + s))
        else:
            out.append((cx + c, cy + s, cz))
    return out


def lerp(a, b, t):
    return a + (b - a) * t


def sweep_profile(bm, profile, path, mat=0, up=(0.0, 0.0, 1.0), closed=True):
    """Sweep a 2D profile along a 3D path (aerofoils, strakes, fins).

    `profile` is a list of (a, b) points in the plane perpendicular to the path.
    """
    pts = [Vector(p) for p in path]
    up = Vector(up)
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == len(pts) - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = (pts[i + 1] - pts[i - 1]).normalized()
        u = up - t * up.dot(t)
        if u.length < 1e-6:
            u = Vector((1.0, 0.0, 0.0)) - t * t.x
        u.normalize()
        v = t.cross(u).normalized()
        rings.append([bm.verts.new(p + u * a + v * b) for a, b in profile])
    n = len(rings[0])
    for i in range(len(rings) - 1):
        for k in range(n if closed else n - 1):
            k2 = (k + 1) % n
            try:
                f = bm.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2]))
                f.material_index = mat
            except ValueError:
                pass
    if closed:
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            try:
                f = bm.faces.new(list(reversed(ring)) if flip else ring)
                f.material_index = mat
            except ValueError:
                pass
    return rings


def airfoil(chord, thick, camber=0.0, n=12):
    """A simple aerofoil section (chord along a, thickness along b)."""
    pts = []
    for i in range(n + 1):
        t = i / n
        x = t * chord
        th = thick * 5.0 * (0.2969 * math.sqrt(max(t, 0.0)) - 0.1260 * t - 0.3516 * t * t
                            + 0.2843 * t ** 3 - 0.1015 * t ** 4)
        pts.append((x, camber * math.sin(math.pi * t) + th * 0.5))
    for i in range(n, -1, -1):
        t = i / n
        x = t * chord
        th = thick * 5.0 * (0.2969 * math.sqrt(max(t, 0.0)) - 0.1260 * t - 0.3516 * t * t
                            + 0.2843 * t ** 3 - 0.1015 * t ** 4)
        pts.append((x, camber * math.sin(math.pi * t) - th * 0.5))
    return pts


def tube(bm, path, radius, seg=8, mat=0, closed=False, cap=True):
    """Sweep a circle of `radius` along a 3D path (parallel-transport frames)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    tangents = []
    for i in range(n):
        if closed:
            t = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
        elif i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == n - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = (pts[i + 1] - pts[i - 1]).normalized()
        tangents.append(t)
    ref = Vector((0.0, 0.0, 1.0))
    if abs(tangents[0].dot(ref)) > 0.9:
        ref = Vector((1.0, 0.0, 0.0))
    normals = [(ref - tangents[0] * ref.dot(tangents[0])).normalized()]
    for i in range(1, n):
        prev = normals[-1]
        t = tangents[i]
        nvec = (prev - t * prev.dot(t))
        if nvec.length < 1e-6:
            nvec = Vector((0.0, 0.0, 1.0)) - t * t.z
        normals.append(nvec.normalized())
    rings = []
    for i, p in enumerate(pts):
        t, nv = tangents[i], normals[i]
        bv = t.cross(nv).normalized()
        ring = []
        for k in range(seg):
            a = 2.0 * math.pi * k / seg
            co = p + nv * (radius * math.cos(a)) + bv * (radius * math.sin(a))
            ring.append(bm.verts.new(co))
        rings.append(ring)
    count = n if closed else n - 1
    for i in range(count):
        j = (i + 1) % n
        for k in range(seg):
            k2 = (k + 1) % seg
            try:
                f = bm.faces.new((rings[i][k], rings[j][k], rings[j][k2], rings[i][k2]))
                f.material_index = mat
            except ValueError:
                pass
    if cap and not closed:
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            try:
                f = bm.faces.new(list(reversed(ring)) if flip else ring)
                f.material_index = mat
            except ValueError:
                pass
    return rings


def rounded_rect(cx, cy, cz, w, h, r, plane="XZ", n=8):
    """Points of a rounded rectangle (used for the yoke rim)."""
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0.0), (-w / 2 + r, h / 2 - r, math.pi / 2),
               (-w / 2 + r, -h / 2 + r, math.pi), (w / 2 - r, -h / 2 + r, 3 * math.pi / 2)]
    for ox, oy, a0 in corners:
        for i in range(n + 1):
            a = a0 + (math.pi / 2) * i / n
            x = ox + r * math.cos(a)
            y = oy + r * math.sin(a)
            if plane == "XZ":
                pts.append((cx + x, cy, cz + y))
            else:
                pts.append((cx + x, cy + y, cz))
    return pts


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def fill_polygon(bm, pts2d, z=0.0, cuts=6):
    """Fill a 2D polygon (list of (a, b)) with a triangulated, subdivided patch.

    The polygon is built in the XY plane of `bm`; the caller maps the result onto
    the car. Returns the list of new faces.
    """
    verts = [bm.verts.new((a, b, z)) for a, b in pts2d]
    edges = []
    for i in range(len(verts)):
        try:
            edges.append(bm.edges.new((verts[i], verts[(i + 1) % len(verts)])))
        except ValueError:
            pass
    res = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=edges)
    faces = [f for f in res.get("faces", []) if f.is_valid]
    if faces and cuts > 0:
        sub = bmesh.ops.subdivide_edges(bm, edges=list({e for f in faces for e in f.edges}),
                                        cuts=cuts, use_grid_fill=True)
        faces = list({f for f in sub.get("faces", []) if f.is_valid})
    return faces
