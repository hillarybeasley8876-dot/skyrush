"""The assembly of the Bund kit: the geometry of one building, grouped per material
(bund unit).

One building is assembled in a bucket per material and turned into one mesh object per
bucket, so the 25 buildings of the Bund ship as 500 objects and not as 200 000.
"""
import math

import bmesh

from lib import common, geo, uv

from . import parts
from .parts import _axis_dir, merge


class Assembly:
    """Collects geometry per material and turns it into Blender objects.

    The Bund has 25 buildings; grouping the geometry by material keeps the object count low
    (one node per material per building) and the draw calls in Godot sane.
    """

    def __init__(self, name):
        self.name = name
        self.buckets = {}
        self.loose = {}

    def bm(self, mat):
        """The bmesh accumulator for the solid geometry of a material."""
        if mat not in self.buckets:
            self.buckets[mat] = bmesh.new()
        return self.buckets[mat]

    def loose_bm(self, mat):
        """The bmesh accumulator for the loose quads of a material.

        A pane of glass, a glazing bar, a wash card or a crown shell is a single quad
        with no volume around it. The normal recalculation cannot orient such a face and
        flips some of them at random, so they are kept apart from the solids and merged
        in after the recalculation (review r3, MF2)."""
        if mat not in self.loose:
            self.loose[mat] = bmesh.new()
        return self.loose[mat]

    def box(self, mat, center, size, rot_z=0.0):
        geo.box(self.bm(mat), center, size, rot_z)
        return self

    def gbox(self, mat, center, size, step=4.0):
        """A box diced into cells of at most `step` m, so the tint can vary over it."""
        parts.grid_box(self.bm(mat), center, size, step)
        return self

    def chamfered_box(self, mat, center, size, chamfer=0.075, axis="X", depth=None):
        parts.chamfered_box(self.bm(mat), center, size, chamfer, axis, depth)
        return self

    def prism(self, mat, profile, y0, y1, x_off=0.0, z_off=0.0):
        parts.prism(self.bm(mat), profile, y0, y1, x_off, z_off)
        return self

    def prism_x(self, mat, profile, x0, x1, y_off=0.0, z_off=0.0):
        parts.prism_x(self.bm(mat), profile, x0, x1, y_off, z_off)
        return self

    def lathe(self, mat, profile, segments=16, center=(0.0, 0.0, 0.0)):
        parts.lathe(self.bm(mat), profile, segments, center)
        return self

    def prism_trim(self, mat, profile, y0, y1, band, tile=2.0, x_off=0.0, z_off=0.0):
        """A prism carrying the trim sheet's UVs (the cornices, the bands, the sills)."""
        parts.prism_trim(self.bm(mat), profile, y0, y1, band, tile, x_off, z_off)
        return self

    def lathe_trim(self, mat, profile, segments, center, band):
        """A revolved capital carrying the trim sheet's UVs."""
        parts.lathe_trim(self.bm(mat), profile, segments, center, band)
        return self

    def quad(self, mat, p0, p1, p2, p3):
        """A single quad; returns the face so the caller can check its orientation."""
        return parts.quad(self.loose_bm(mat), p0, p1, p2, p3)

    def disc(self, mat, center, radius, depth, axis="Z", segments=24):
        """A flat disc (a clock face, a lamp lens) with its axis along X, Y or Z."""
        geo.cylinder(self.bm(mat), center, radius, depth, segments, axis)
        return self

    def quad_uv(self, role, verts, uvs):
        """A quad with explicit UVs (a window pane showing one cell of an atlas).

        Returns the face, so the caller can check its orientation."""
        bm = self.loose_bm(role)
        vs = [bm.verts.new(v) for v in verts]
        face = bm.faces.new(vs)
        layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
        for loop, uv in zip(face.loops, uvs):
            loop[layer].uv = uv
        return face

    def disc_uv(self, role, center, radius, axis="X", segments=24, flip=False, depth=0.12):
        """A closed disc whose front face UVs map the 0..1 square onto the circle.

        It is a closed volume (front fan + back fan + rim) so the normals are unambiguous
        after the recalculation, and the dial texture lands on the front face."""
        bm = self.bm(role)
        layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
        cx, cy, cz = center
        front, back = [], []
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            u, v = 0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)
            if axis == "X":
                p = [cx, cy + radius * math.cos(a), cz + radius * math.sin(a)]
            elif axis == "Y":
                p = [cx + radius * math.cos(a), cy, cz + radius * math.sin(a)]
            else:
                p = [cx + radius * math.cos(a), cy + radius * math.sin(a), cz]
            front.append((bm.verts.new(p), (u, v)))
            back.append((bm.verts.new([p[0] - depth * _axis_dir(axis)[0],
                                       p[1] - depth * _axis_dir(axis)[1],
                                       p[2] - depth * _axis_dir(axis)[2]]), (u, v)))
        cf = bm.verts.new(center)
        cb = bm.verts.new([cx - depth * _axis_dir(axis)[0], cy - depth * _axis_dir(axis)[1],
                           cz - depth * _axis_dir(axis)[2]])
        for i in range(segments):
            j = (i + 1) % segments
            f1, u1 = front[i][0], front[i][1]
            f2, u2 = front[j][0], front[j][1]
            b1, b2 = back[i][0], back[j][0]
            quad = (cf, f1, f2) if not flip else (cf, f2, f1)
            face = bm.faces.new(quad)
            for loop, uv in zip(face.loops, ((0.5, 0.5), u1, u2)):
                loop[layer].uv = uv
            face = bm.faces.new((cb, b2, b1) if not flip else (cb, b1, b2))
            for loop, uv in zip(face.loops, ((0.5, 0.5), u2, u1)):
                loop[layer].uv = uv
            face = bm.faces.new((f1, b1, b2, f2) if not flip else (f2, b2, b1, f1))
            for loop, uv in zip(face.loops, (u1, u1, u2, u2)):
                loop[layer].uv = uv
        return self

    def merge_bm(self, mat, src):
        merge(self.bm(mat), src)
        return self

    def tint(self, role, fn):
        """Write a per-vertex colour (COLOR_0) into a bucket.

        `fn(co)` returns an (r, g, b) multiplier; the material multiplies the base texture
        with it, so the facade carries its AO, dirt and macro variation."""
        bm = self.buckets.get(role)
        if bm is None or len(bm.verts) == 0:
            return
        layer = bm.verts.layers.float_color.get("Col") or bm.verts.layers.float_color.new("Col")
        for v in bm.verts:
            r, g, b = fn(v.co)
            v[layer] = (min(1.0, max(0.0, r)), min(1.0, max(0.0, g)),
                        min(1.0, max(0.0, b)), 1.0)

    def to_objects(self, col, materials, parent=None):
        """Create one mesh object per material; returns the list of objects.

        A role without a material is an error, not a warning: a material-less mesh ships
        to Godot as a white slab and the only way to catch it is here."""
        objs = []
        for mat_name in sorted(set(self.buckets) | set(self.loose)):
            if mat_name not in materials:
                raise KeyError("role %r has no material (known roles: %s)"
                               % (mat_name, ", ".join(sorted(materials))))
            bm = self.buckets.get(mat_name)
            loose = self.loose.get(mat_name)
            if bm is None and (loose is None or len(loose.faces) == 0):
                continue
            if bm is None:
                bm = loose
            else:
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
                if loose is not None and len(loose.faces) > 0:
                    # the loose quads are already wound: they are merged after the recalc
                    merge(bm, loose)
                    loose.free()
            if len(bm.faces) == 0:
                bm.free()
                continue
            obj = common.mesh_object("%s_%s" % (self.name, mat_name), bm, col, materials.get(mat_name))
            if obj.data.uv_layers.get("UVMap") is None:
                uv.box_uv(obj)      # builders that set their own UVs keep them
            common.smooth(obj, 32.0)
            if parent is not None:
                # the mesh data is in the parent's local frame: inherit its transform
                obj.parent = parent
            objs.append(obj)
        self.buckets = {}
        self.loose = {}
        return objs
