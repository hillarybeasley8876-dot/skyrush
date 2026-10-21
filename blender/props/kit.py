"""Geometry kit for the SKYRUSH props unit.

`Prop` collects the objects of one prop, gives every part a sensible origin and
exports the whole thing as a single .glb. The primitives live in `geom.py`.

Frame (CONTRACTS.md §1): metres, Z up, +Y forward, +X right, origin on the ground.
Every part is built with its geometry local and its object placed at the part's
centre, so a dynamic part (a barrier arm, a canopy column) has a usable origin.

UVs come in two flavours:
  * `surface="galv"` - the part belongs to a tileable family (metal, mineral,
    panel, bark).  Its UV is metres / FAMILY_METRES, so the family texture
    repeats without a seam at a constant 512 px/m, and its colour is a VERTEX
    TINT written into a COLOR_0 attribute.
  * `uv_rect=(u0,v0,u1,v1)` - the 0..1 UVs of a sign quad mapped into the sign
    atlas cell.
"""
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

from lib import common, geo, uv

from . import atlas
from .geom import (add_card, add_quad, cone, cyl_uv, lathe,
                    map_rect_uv, map_strip_uv, ring, scale_uv, set_tint,
                    sign_quad, sphere, torus, tube, unit_uv)

FLAT = (-math.pi / 2.0, 0.0, 0.0)   # rotation that lays a quad flat, facing up

# Node names that must stay separate (the world and gameplay units drive them).
# Only the exact contract names and the contract prefixes: everything else is
# static and is joined into one node, so a prop costs one draw call per
# material family and not one per part.
DYNAMIC_EXACT = ("Lens_R", "Lens_A", "Lens_G", "Spikes", "Canopy", "BayNumbers")
DYNAMIC_PREFIXES = ("Barrier_", "LaneSignal_", "Support_", "Chevron_")

# Where the shared texture atlases live, relative to the exported prop.
SHARED_TEX_DIR = "../_tex"


def _is_dynamic(name, keep_exact, keep_prefix):
    return name in keep_exact or any(name.startswith(k) for k in keep_prefix)


class Prop:
    """Collects the objects of one prop and exports them as a single .glb."""

    def __init__(self, name, col=None):
        self.name = name
        self.col = col if col is not None else common.collection(name)
        self.parts = []

    # -- object helpers -------------------------------------------------
    def add(self, obj):
        self.parts.append(obj)
        return obj

    def _surface_material(self, surface):
        """The material of a family surface ("metal", "mineral", "panel", ...)."""
        from . import materials as M
        return M.family(atlas.surface_material(surface))

    def mesh(self, name, bm, material=None, loc=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0),
             box_map=True, smooth=False, bevel=0.0, triangulate=True, surface=None,
             uv_rect=None, uv_unit=False, tint=None, uv_ready=False):
        """Create a mesh object from a bmesh.

        `surface` names a surface of the shared table ("galv", "concrete", ...):
        the part gets the family material, the family UV (metres / tile size)
        and the vertex tint of that surface.  `tint` overrides the tint.
        `uv_rect` maps the 0..1 UVs into a rectangle of the sign atlas.
        """
        if triangulate:
            bmesh.ops.triangulate(bm, faces=bm.faces[:])
        colour = tint if tint is not None else (atlas.surface_tint(surface) if surface
                                                else (1.0, 1.0, 1.0))
        if surface:
            material = self._surface_material(surface)
        obj = common.mesh_object(name, bm, self.col, material)
        obj.location = loc
        obj.rotation_euler = rot
        if box_map:
            uv.box_uv(obj)
        if uv_rect:
            map_rect_uv(obj, *uv_rect)
        elif uv_unit:
            unit_uv(obj)
        if surface and not uv_ready:
            scale_uv(obj, 1.0 / atlas.FAMILY_METRES)
        set_tint(obj, colour)
        if smooth:
            common.smooth(obj)
        if bevel > 0.0:
            common.bevel(obj, width=bevel, segments=1)
        return self.add(obj)

    def empty(self, name, loc, direction=(0.0, 1.0, 0.0), size=0.3, parent=None):
        """Marker Empty: local +Y points along the effect direction (CONTRACTS §2)."""
        obj = common.empty(name, loc, direction=direction, col=self.col, size=size,
                           parent=parent)
        return self.add(obj)

    def box(self, name, center, size, material, rot_z=0.0, bevel=0.0, rot=None,
            surface=None, tint=None):
        """An axis box whose object origin sits at `center`."""
        bm = bmesh.new()
        geo.box(bm, (0.0, 0.0, 0.0), size, 0.0)
        rot = rot if rot is not None else (0.0, 0.0, rot_z)
        m = Euler(rot, "XYZ").to_matrix().to_4x4()
        for v in bm.verts:
            v.co = m @ v.co
        return self.mesh(name, bm, material, loc=center, bevel=bevel, surface=surface,
                         tint=tint)

    def cyl(self, name, center, r, depth, material, axis="Z", segments=12, rot_z=0.0,
            r2=None, smooth=True, surface=None, tint=None, uv_unit=False):
        bm = bmesh.new()
        if r2 is None:
            geo.cylinder(bm, (0.0, 0.0, 0.0), r, depth, segments=segments, axis=axis)
        else:
            cone(bm, (0.0, 0.0, 0.0), r, r2, depth, segments=segments, axis=axis)
        obj = self.mesh(name, bm, material, loc=center, smooth=smooth, surface=surface,
                        tint=tint, uv_ready=bool(surface))
        axis_vec = {"X": (1.0, 0.0, 0.0), "Y": (0.0, 1.0, 0.0), "Z": (0.0, 0.0, 1.0)}[axis]
        cyl_uv(obj, axis_vec, radius=(r + (r2 or r)) * 0.5, length=depth,
               tile_m=atlas.FAMILY_METRES if surface else None)
        if uv_unit:
            unit_uv(obj)
        if rot_z:
            obj.rotation_euler = (0.0, 0.0, rot_z)
        return obj

    def tube(self, name, p0, p1, r, material, segments=10, smooth=True, surface=None,
             cap=True, tint=None):
        """A cylinder between two world points; the object origin is the midpoint."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        length = d.length
        if length < 1e-6:
            return None
        bm = bmesh.new()
        tube(bm, (0.0, 0.0, -length * 0.5), (0.0, 0.0, length * 0.5), r, segments=segments,
             cap=cap)
        quat = d.to_track_quat("Z", "Y")
        m = quat.to_matrix().to_4x4()
        for v in bm.verts:
            v.co = m @ v.co
        obj = self.mesh(name, bm, material, loc=(p0 + p1) * 0.5, smooth=smooth,
                        surface=surface, tint=tint, uv_ready=bool(surface))
        # the rotation was baked into the vertices, so the axis of the tube in
        # the mesh's own coordinates is the direction of the tube
        local_axis = d.normalized()
        cyl_uv(obj, local_axis, radius=r, length=length,
               tile_m=atlas.FAMILY_METRES if surface else None)
        return obj

    def ring(self, name, center, radius, thickness, height, material, segments=24,
             axis="Z", surface=None, tint=None):
        bm = bmesh.new()
        ring(bm, (0.0, 0.0, 0.0), radius, thickness, height, segments=segments, axis=axis)
        return self.mesh(name, bm, material, loc=center, smooth=True, surface=surface,
                         tint=tint)

    def sign(self, name, center, width, height, sign_material, frame_material,
             board, rot_z=0.0, rot_x=0.0, frame=0.05, depth=0.05, flip=False,
             frame_surface="galv"):
        """A sign panel: one UV-mapped quad (the printed face) plus a thin frame box.

        `board` is the name of the board in the sign atlas. The frame sits
        BEHIND the printed face, otherwise it would swallow it.
        """
        u0, v0, u1, v1 = atlas.sign_uv(board)
        bm = bmesh.new()
        sign_quad(bm, width, height)
        obj = self.mesh(name, bm, sign_material, loc=center, rot=(rot_x, 0.0, rot_z),
                        box_map=False, uv_rect=(u0, v0, u1, v1))
        if flip:
            obj.scale = (1.0, -1.0, 1.0)
        back = self.box(name + "_Frame", (0.0, 0.0, 0.0),
                        (width + frame * 2.0, depth, height + frame * 2.0),
                        frame_material, surface=frame_surface)
        # push the frame behind the printed face, in the sign's own frame
        rot = Euler((rot_x, 0.0, rot_z), "XYZ").to_matrix()
        off = rot @ Vector((0.0, depth * 0.5 + 0.008, 0.0))
        back.location = Vector(center) + off
        back.rotation_euler = (rot_x, 0.0, rot_z)
        return obj

    def quad(self, name, width, height, material, center, rot=(0.0, 0.0, 0.0),
             board=None, uv_rect=None, uv_unit=False, surface=None, tint=None):
        """A single UV-mapped quad (lane markings, LED faces, decals).

        With `surface` the 0..1 UV is read as metres, so a painted bay keeps
        the material's detail scale.
        """
        bm = bmesh.new()
        sign_quad(bm, width, height)
        rect = uv_rect
        if board is not None:
            rect = atlas.sign_uv(board)
        if surface:
            obj = self.mesh(name, bm, material, loc=center, rot=rot, box_map=False,
                            surface=surface, tint=tint, uv_ready=True)
            me = obj.data
            layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
            for loop in me.loops:
                u, v = layer.data[loop.index].uv
                layer.data[loop.index].uv = (u * width / atlas.FAMILY_METRES,
                                             v * height / atlas.FAMILY_METRES)
            return obj
        return self.mesh(name, bm, material, loc=center, rot=rot, box_map=False,
                         uv_rect=rect, uv_unit=uv_unit)

    def quads(self, name, specs, material, board=None, surface=None, tint=None):
        """Many UV-mapped quads in one object: specs = [(w, h, center, rot), ...].

        With `surface` the 0..1 UV of every quad is read as metres and mapped
        into the tileable family.
        """
        rect = atlas.sign_uv(board) if board else None
        bm = bmesh.new()
        for spec in specs:
            w, h, center = spec[0], spec[1], spec[2]
            rot = spec[3] if len(spec) > 3 else (0.0, 0.0, 0.0)
            if rect:
                add_quad(bm, w, h, center, rot, rect)
            else:
                add_quad(bm, w, h, center, rot)
        obj = self.mesh(name, bm, material, box_map=False, surface=surface, tint=tint,
                        uv_ready=True)
        if surface:
            me = obj.data
            layer = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
            for loop in me.loops:
                u, v = layer.data[loop.index].uv
                layer.data[loop.index].uv = (u / atlas.FAMILY_METRES,
                                             v / atlas.FAMILY_METRES)
        return obj

    def join_parts(self, name, objects):
        """Join a group of parts into one node (the gas canopy is one droppable body)."""
        objects = [o for o in objects if o is not None]
        if not objects:
            return None
        keep_out = {id(o) for o in objects}
        joined = common.join(objects, name)
        if joined.matrix_basis != Matrix.Identity(4):
            joined.data.transform(joined.matrix_basis)
            joined.matrix_basis = Matrix.Identity(4)
        self.parts = [o for o in self.parts if id(o) not in keep_out]
        self.parts.append(joined)
        return joined

    def wear_band(self, name, center, radius, height=1.0, surface="scuffed"):
        """A scuff band at the foot of a column or post (ART.md §5d)."""
        from . import materials as M
        return self.cyl(name, (center[0], center[1], center[2] + height * 0.5),
                        radius + 0.012, height, M.surface(), segments=14,
                        surface=surface)

    def set_origin(self, obj, point):
        """Move an object's origin to a world point (hinges, pivots)."""
        common.set_origin(obj, point)
        return obj

    def finalize(self, name=None, keep_exact=DYNAMIC_EXACT, keep_prefix=DYNAMIC_PREFIXES):
        """Join every static mesh part into one node; the dynamic parts keep theirs.

        One node per prop (with one surface per material family) is what the
        world unit needs: it can then instance, hide or swap a whole prop.
        """
        name = name or self.name
        static = []
        for obj in self.parts:
            if obj.type != "MESH":
                continue
            if obj.name.endswith("-convcolonly"):
                continue
            if _is_dynamic(obj.name, keep_exact, keep_prefix):
                continue
            static.append(obj)
        if not static:
            return self
        keep_out = {id(o) for o in static}
        joined = common.join(static, name)
        if joined.matrix_basis != Matrix.Identity(4):
            joined.data.transform(joined.matrix_basis)
            joined.matrix_basis = Matrix.Identity(4)
        # the join operator removed every part but the first from bpy.data
        self.parts = [o for o in self.parts if id(o) not in keep_out]
        self.parts.append(joined)
        return self

    def translate(self, offset):
        """Move the whole prop by `offset` (metres) without changing its layout."""
        off = Vector(offset)
        for obj in self.parts:
            if obj.type == "MESH":
                obj.data.transform(Matrix.Translation(off))
            else:
                obj.matrix_world = obj.matrix_world @ Matrix.Translation(off)
        return self

    def finish(self, path, origin=(0.0, 0.0, 0.0), shared_textures=False):
        """Move the whole prop so its origin sits at `origin`, then export.

        With `shared_textures` the texture atlases are written to one shared
        folder next to the assets and the .glb keeps them external, so Godot
        imports every atlas once instead of once per prop.
        """
        if origin != (0.0, 0.0, 0.0):
            for obj in self.parts:
                if obj.type == "MESH":
                    obj.data.transform(Matrix.Translation(Vector(origin)))
                else:
                    obj.matrix_world = obj.matrix_world @ Matrix.Translation(Vector(origin))
        from lib import export
        if not shared_textures:
            return export.export_glb(path, objects=self.parts)
        export.export_glb(path, objects=self.parts, shared_texture_dir=SHARED_TEX_DIR)
        from . import pack_glb
        return pack_glb.pack(os.path.splitext(path)[0] + ".gltf")
