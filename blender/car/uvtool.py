"""UV-space helpers for the body and glass maps (run inside Blender).

The lead's shell uses a smart UV projection, so the panel-gap lines and the
ceramic frit band cannot be drawn in a fixed atlas any more: they have to be
projected from the 3D surface onto the mesh's own UVs. These helpers do that.
"""
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


class Projector:
    """Maps a 3D point on a mesh to the mesh's UV coordinates."""

    def __init__(self, obj, uv_name="UVMap"):
        me = obj.data
        me.calc_loop_triangles()
        layer = me.uv_layers[uv_name]
        self.tris = []
        verts = [v.co.copy() for v in me.vertices]
        coords, index = [], []
        for t in me.loop_triangles:
            ids = list(t.vertices)
            uvs = [layer.data[t.loops[i]].uv.copy() for i in range(3)]
            base = len(coords)
            for i in ids:
                coords.append(verts[i])
            index.append((base, base + 1, base + 2))
            self.tris.append((ids, uvs))
        self.coords = coords
        self.tree = BVHTree.FromPolygons(coords, index, all_triangles=True)
        self.area3d = []
        self.area_uv = []
        for ids, uvs in self.tris:
            a, b, c = [verts[i] for i in ids]
            self.area3d.append((b - a).cross(c - a).length / 2.0)
            du = uvs[1] - uvs[0]
            dv = uvs[2] - uvs[0]
            self.area_uv.append(abs(du.x * dv.y - du.y * dv.x) / 2.0)

    def uv_at(self, p):
        """The UV of the point of the mesh nearest to p (None if nothing is near)."""
        loc, _nrm, idx, dist = self.tree.find_nearest(Vector(p))
        if loc is None:
            return None
        ids, uvs = self.tris[idx]
        a, b, c = ids
        v0, v1, v2 = self.coords[a], self.coords[b], self.coords[c]
        d = (v2 - v0).cross(v1 - v0)
        if d.length < 1e-12:
            return uvs[0]
        w1 = ((v2 - v0).cross(loc - v0)).dot(d) / d.length_squared
        w2 = ((v0 - v1).cross(loc - v0)).dot(d) / d.length_squared
        w0 = 1.0 - w1 - w2
        u = uvs[0] * w0 + uvs[1] * w1 + uvs[2] * w2
        return (u.x, u.y)

    def uv_per_m(self, idx):
        """UV units per metre for a triangle (the local texel density)."""
        if self.area3d[idx] < 1e-12:
            return 1.0
        return (self.area_uv[idx] / self.area3d[idx]) ** 0.5

    def nearest_index(self, p):
        _loc, _nrm, idx, _dist = self.tree.find_nearest(Vector(p))
        return idx


def polyline(points, step=0.004):
    """Split a polyline into points that are at most `step` apart."""
    out = []
    for a, b in zip(points, points[1:]):
        a, b = Vector(a), Vector(b)
        n = max(1, int((b - a).length / step))
        for i in range(n):
            out.append(a.lerp(b, i / float(n)))
    if points:
        out.append(Vector(points[-1]))
    return out


def draw_line(height, p0, p1, depth, width_px):
    """Carve a V groove into a height field (metres) along a segment (pixels)."""
    x0, y0 = p0
    x1, y1 = p1
    lo_x = int(max(0, min(x0, x1) - width_px - 2))
    hi_x = int(min(height.shape[1], max(x0, x1) + width_px + 3))
    lo_y = int(max(0, min(y0, y1) - width_px - 2))
    hi_y = int(min(height.shape[0], max(y0, y1) + width_px + 3))
    if hi_x <= lo_x or hi_y <= lo_y:
        return
    ys, xs = np.mgrid[lo_y:hi_y, lo_x:hi_x]
    dx, dy = x1 - x0, y1 - y0
    l2 = dx * dx + dy * dy
    t = np.clip(((xs - x0) * dx + (ys - y0) * dy) / max(l2, 1e-9), 0.0, 1.0)
    d = np.hypot(xs - (x0 + t * dx), ys - (y0 + t * dy))
    prof = np.clip((width_px - d) / max(width_px * 0.22, 1e-6), 0.0, 1.0)
    height[lo_y:hi_y, lo_x:hi_x] -= (depth * prof).astype(height.dtype)


def paint_line(rgb, p0, p1, color, width_px):
    """Paint a dark AO line into an RGB image (pixels)."""
    x0, y0 = p0
    x1, y1 = p1
    lo_x = int(max(0, min(x0, x1) - width_px - 2))
    hi_x = int(min(rgb.shape[1], max(x0, x1) + width_px + 3))
    lo_y = int(max(0, min(y0, y1) - width_px - 2))
    hi_y = int(min(rgb.shape[0], max(y0, y1) + width_px + 3))
    if hi_x <= lo_x or hi_y <= lo_y:
        return
    ys, xs = np.mgrid[lo_y:hi_y, lo_x:hi_x]
    dx, dy = x1 - x0, y1 - y0
    l2 = dx * dx + dy * dy
    t = np.clip(((xs - x0) * dx + (ys - y0) * dy) / max(l2, 1e-9), 0.0, 1.0)
    d = np.hypot(xs - (x0 + t * dx), ys - (y0 + t * dy))
    m = np.clip((width_px - d) / max(width_px * 0.4, 1e-6), 0.0, 1.0)[..., None]
    reg = rgb[lo_y:hi_y, lo_x:hi_x]
    rgb[lo_y:hi_y, lo_x:hi_x] = reg * (1.0 - m) + np.array(color, np.float32) * m


def rasterize(verts_uv, verts_val, size, comps=1):
    """Rasterise triangles into a square image, interpolating the vertex values.

    `verts_uv` are (u, v) in 0..1 (v up), `verts_val` the value at each vertex
    (comps values per vertex). Returns a float array of shape (size, size, comps).
    """
    img = np.zeros((size, size, comps), np.float32)
    for i in range(0, len(verts_uv), 3):
        tri = []
        for k in range(3):
            u, v = verts_uv[i + k]
            tri.append((u * (size - 1), (1.0 - v) * (size - 1)))
        (x0, y0), (x1, y1), (x2, y2) = tri
        det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(det) < 1e-9:
            continue
        lo_x = int(max(0, min(x0, x1, x2)))
        hi_x = int(min(size - 1, max(x0, x1, x2) + 1))
        lo_y = int(max(0, min(y0, y1, y2)))
        hi_y = int(min(size - 1, max(y0, y1, y2) + 1))
        if hi_x < lo_x or hi_y < lo_y:
            continue
        ys, xs = np.mgrid[lo_y:hi_y + 1, lo_x:hi_x + 1]
        w1 = ((x2 - x0) * (ys - y0) - (y2 - y0) * (xs - x0)) / det
        w2 = ((x1 - x0) * (ys - y0) - (y1 - y0) * (xs - x0)) / det
        w0 = 1.0 - w1 - w2
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        patch = img[lo_y:hi_y + 1, lo_x:hi_x + 1]
        for c in range(comps):
            v0 = verts_val[i + 0][c]
            v1 = verts_val[i + 1][c]
            v2 = verts_val[i + 2][c]
            val = w0 * v0 + w1 * v1 + w2 * v2
            np.copyto(patch[:, :, c], val, where=inside)
    return img[:, :, 0] if comps == 1 else img


def distance_to_points(pos, points):
    """The distance from every pixel of a 3D position map to the nearest point."""
    out = np.full(pos.shape[:2], 1e9, np.float32)
    for p in points:
        d = np.sqrt(((pos - np.asarray(p, np.float32)) ** 2).sum(axis=2))
        np.minimum(out, d, out=out)
    return out
