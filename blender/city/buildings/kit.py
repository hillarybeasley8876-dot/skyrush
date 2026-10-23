"""Shared kit for the city block builder: material registry, mesh bag, sign slots."""
import os

import bmesh
from mathutils import Vector

from lib import mats as libmats

from . import cells, matsb, shapes

# logical key -> (blender material name, uv mode: "box" = metres, "atlas" = 0..1 per face)
MATS = {
    "facade_office": ("SH_facade_office", "box"),
    "facade_res": ("SH_facade_residential", "box"),
    "neon_tube": ("SH_neon", "box"),
    "brick": ("Brick_Grey", "box"),
    "brick_red": ("Brick_Red", "box"),
    "granite": ("Stone_Granite", "box"),
    "stone_pale": ("Stone_Pale", "box"),
    "tile": ("Tile_White", "box"),
    "render": ("Render_Grey", "box"),
    "corrugated": ("Metal_Corrugated", "box"),
    "shutter": ("Shutter_Steel", "box"),
    "metal_dark": ("Metal_Dark", "box"),
    "metal_galv": ("Metal_Galv", "box"),
    "glass": ("Glass_Dirty", "box"),
    "shop_glass": ("Shop_Glass", "box"),
    "wood": ("Wood_Lacquer", "box"),
    "brass": ("Brass_Knocker", "box"),
    "roof": ("Roof_Tile", "box"),
    "prop": ("Prop_Sheet", "atlas"),
    "neon_v": ("Neon_Sign_Vertical", "atlas"),
    "neon_h": ("Neon_Sign_Horizontal", "atlas"),
    "neon_red": ("Neon_Sign_Red", "atlas"),
    "plaque": ("Plaque_Atlas", "atlas"),
    "carving": ("Carving_Stone", "atlas"),
    "led": ("LED_Screen", "atlas"),
    "interior": ("Interior_Atlas", "atlas"),
    "shop_interior": ("Shop_Interior", "atlas"),
    "cloth": ("Cloth_Atlas", "atlas"),
    "emissive_warm": ("Emissive_Warm", "box"),
    "emissive_cyan": ("Emissive_Cyan", "box"),
    "emissive_magenta": ("Emissive_Magenta", "box"),
    "beacon": ("SH_beacon", "box"),
    "emissive_white": ("Emissive_White", "box"),
    "awning": ("Awning_Fabric", "box"),
    "foliage": ("Foliage_Dark", "box"),
    "grass": ("Grass_Lawn", "box"),
    "paving": ("Paving_Concrete", "box"),
}


def build_materials():
    """Create (or fetch) every material the builder needs. Returns key -> material."""
    out = {}
    out["facade_office"] = matsb.placeholder("SH_facade_office", (0.10, 0.11, 0.13, 1.0), 0.55)
    out["facade_res"] = matsb.placeholder("SH_facade_residential", (0.30, 0.29, 0.26, 1.0), 0.7)
    out["neon_tube"] = matsb.placeholder("SH_neon", (0.05, 0.05, 0.05, 1.0), 0.15)
    out["brick"] = matsb.pbr_tex("Brick_Grey", "brick_grey", (3.00, 1.30), 0.86, cull=True)
    out["brick_red"] = matsb.pbr_tex("Brick_Red", "brick_red", (3.00, 1.30), 0.86, cull=True)
    out["granite"] = matsb.pbr_tex("Stone_Granite", "stone_granite", 2.40, 0.66, cull=True)
    out["stone_pale"] = matsb.pbr_tex("Stone_Pale", "stone_pale", 1.20, 0.78, cull=True)
    out["tile"] = matsb.pbr_tex("Tile_White", "tile_white", 2.00, 0.42, cull=True)
    out["render"] = matsb.pbr_tex("Render_Grey", "render_grey", 2.00, 0.85, cull=True)
    out["corrugated"] = matsb.pbr_tex("Metal_Corrugated", "metal_corrugated", 2.70, 0.45,
                                     metallic=0.55)
    out["shutter"] = matsb.pbr_tex("Shutter_Steel", "shutter_steel", 1.20, 0.45,
                                   metallic=0.85)
    out["metal_dark"] = matsb.pbr_tex("Metal_Dark", "steel_powder", 1.60, 0.55, metallic=0.7,
                                 cull=True)
    out["metal_galv"] = matsb.pbr_tex("Metal_Galv", "steel_galv", 1.60, 0.35, metallic=0.85,
                                  cull=True)
    out["glass"] = matsb.pbr_tex("Glass_Dirty", "glass_dirty", 2.00, 0.12)
    out["shop_glass"] = matsb.pbr_tex("Shop_Glass", "glass_dirty", 2.00, 0.08, alpha=0.30)
    out["brass"] = matsb.pbr_tex("Brass_Knocker", "brass", 0.50, 0.35, cull=True)
    out["wood"] = matsb.pbr_tex("Wood_Lacquer", "wood_lacquer", 1.20, 0.32, cull=True)
    out["roof"] = matsb.pbr_tex("Roof_Tile", "roof_tile", 1.60, 0.86, cull=True)
    out["awning"] = matsb.pbr_tex("Awning_Fabric", "awning_canvas", 2.00, 0.82, cull=True)
    out["foliage"] = matsb.pbr_tex("Foliage_Dark", "leaf_card", 2.00, 0.85, cull=True)
    out["grass"] = matsb.pbr_tex("Grass_Lawn", "lawn", 3.00, 0.92, cull=True)
    out["paving"] = matsb.pbr_tex("Paving_Concrete", "paving_stone", 3.00, 0.86, cull=True)
    out["prop"] = matsb.pbr_atlas("Prop_Sheet", "props", 0.60, cull=True)
    out["interior"] = matsb.emissive_tex("Interior_Atlas", "interiors", 0.85, 0.55)
    out["shop_interior"] = matsb.emissive_tex("Shop_Interior", "shop_interiors", 0.85, 0.5)
    out["cloth"] = matsb.image_mat("Cloth_Atlas", "cloth", 0.85)
    out["neon_v"] = matsb.emissive_tex("Neon_Sign_Vertical", "neon_vertical", 2.4)
    out["neon_h"] = matsb.emissive_tex("Neon_Sign_Horizontal", "neon_horizontal", 2.2)
    out["neon_red"] = matsb.emissive_tex("Neon_Sign_Red", "fascia_red", 1.8)
    out["plaque"] = matsb.emissive_tex("Plaque_Atlas", "plaques", 0.0, 0.7)
    out["carving"] = matsb.pbr_atlas("Carving_Stone", "carvings", 0.72, cull=True)
    out["led"] = matsb.emissive_tex("LED_Screen", "led_ads", 2.0)
    out["emissive_warm"] = matsb.emissive_tex("Emissive_Warm", "emissive_warm", 1.0, 0.4)
    out["emissive_cyan"] = matsb.emissive_tex("Emissive_Cyan", "emissive_cyan", 1.0, 0.4)
    out["emissive_magenta"] = matsb.emissive_tex("Emissive_Magenta", "emissive_magenta", 1.0, 0.4)
    # the aviation beacon is named SH_beacon: the shaders unit can then swap it for
    # the blinking 1 Hz material (res://shaders/materials/SH_beacon.tres)
    out["beacon"] = matsb.emissive_tex("SH_beacon", "emissive_red", 1.0, 0.4)
    out["emissive_white"] = matsb.emissive_tex("Emissive_White", "emissive_white", 1.0, 0.4)
    # the far LOD is only drawn beyond 350 m, where the depth fog takes 34 % of the
    # light away: the emission is 1.6 so that a lit cell still reads at 1 km
    # (1.6 * 0.87 * 0.66 = 0.92 at 350 m, under the 1.1 glow threshold)
    out["window_far_office"] = matsb.emissive_pair("Window_Far_Office", "windows_far_office",
                                                  "windows_far_office_emit", 1.6)
    out["window_far_resi"] = matsb.emissive_pair("Window_Far_Resi", "windows_far_resi",
                                                 "windows_far_resi_emit", 1.6)
    return out


def _face_uv(face, mode, src_uv):
    """The UVs of a face: metres for the tiling materials, the atlas for the signs."""
    if mode == "atlas" and src_uv is not None:
        return [loop[src_uv].uv for loop in face.loops]
    # the normal comes from the winding: `face.normal` of a face that was never
    # through `normal_update()` is (0, 0, 0), and the projection axis was then always
    # 0 - 84 % of the textured area had zero-area UVs (the paving, the brick, the roof).
    n = shapes.face_normal(face)
    if n.length < 1e-9:
        n = Vector((0.0, 0.0, 1.0))
    ax = max(range(3), key=lambda i: abs(n[i]))
    out = []
    for loop in face.loops:
        p = loop.vert.co
        if ax == 0:
            uv = (p.y if n.x > 0 else -p.y, p.z)
        elif ax == 1:
            uv = (-p.x if n.y > 0 else p.x, p.z)
        else:
            uv = (p.x, p.y if n.z > 0 else -p.y)
        out.append(uv)
    return out


class Bag(object):
    """Accumulates geometry per material key, then emits one object per (key, cell).

    Every face of a building is tagged with the 128 m cell of that building, so the
    whole building ends up in ONE node: the facade shader computes its window grid
    from the object-space position, and a building split over two cells would show
    its window grid jumping in the middle of a wall.
    """

    def __init__(self, materials):
        self.materials = materials
        self.groups = {}
        self.cell = (0, 0)
        self._marks = None
        self._cell_value = {}     # cell -> the face tag of that cell
        self._value_cell = {}     # the face tag -> the cell
        self._next_value = 1
        self.last_tris = 0        # the triangles of the building that just ended
        self.building_tris = []   # (footprint key, triangles) of every building

    def bm(self, key):
        """The bmesh of a material group (created on demand)."""
        if key not in self.groups:
            self.groups[key] = bmesh.new()
        return self.groups[key]

    def begin_building(self, cell):
        """Start a building: its faces are tagged with the building's cell.

        Only the face COUNT is taken here: `ensure_lookup_table` walks every face
        of every material group, and with 600 buildings per tile that was minutes
        of build time.
        """
        self.cell = (int(cell[0]), int(cell[1]))
        self._marks = {}
        for key, bm in self.groups.items():
            self._marks[key] = len(bm.faces)
        if os.environ.get("BAG_DEBUG"):
            print("BAG begin cell=%s marks=%s" % (self.cell, self._marks))

    def pending_faces(self):
        """The faces of the current building (for the pane assertions).

        The BVH of the assertion is built over these faces only: it used to be built
        over every face of the tile, for every building.
        """
        out = []
        for key, bm in self.groups.items():
            bm.faces.ensure_lookup_table()
            # a group that was created during the building has no mark: all of its
            # faces are new
            start = self._marks.get(key, 0)
            out.extend(bm.faces[start:len(bm.faces)])
        return out

    def end_building(self):
        """Tag the faces added since begin_building with the building's cell."""
        if self._marks is None:
            return
        value = self._cell_value.get(self.cell)
        if value is None:
            value = self._next_value
            self._next_value += 1
            self._cell_value[self.cell] = value
            self._value_cell[value] = self.cell
        tris = 0
        for key, bm in self.groups.items():
            bm.faces.ensure_lookup_table()
            # a group created during the building has no mark: all its faces are new
            start = self._marks.get(key, 0)
            layer = bm.faces.layers.int.get("bcell")
            if layer is None:
                layer = bm.faces.layers.int.new("bcell")
            for i in range(start, len(bm.faces)):
                bm.faces[i][layer] = value
                tris += len(bm.faces[i].verts) - 2
        # the triangles of this building: the near-LOD budget needs them per
        # building to know what a building loses when its decoration goes
        self.last_tris = tris
        if os.environ.get("BAG_DEBUG"):
            print("BAG end cell=%s value=%s faces=%s tris=%d" % (self.cell, value,
                                                                 {k: len(b.faces) for k, b in self.groups.items()}, tris))
        self._marks = None

    def tris(self):
        """Total TRIANGLES across all groups (a quad counts as two)."""
        n = 0
        for bm in self.groups.values():
            bm.faces.ensure_lookup_table()
            for f in bm.faces:
                n += len(f.verts) - 2
        return n

    def emit(self, col, prefix):
        """Create one object per (material, cell); returns the list of objects."""
        objs = []
        for key, bm in sorted(self.groups.items()):
            if len(bm.faces) == 0:
                bm.free()
                continue
            _name, mode = MATS[key]
            for cell, cbm in self._split(bm, mode).items():
                obj = self._make(col, "%s_%s_c%d_%d" % (prefix, key, cell[0], cell[1]),
                                 key, cbm, cell)
                objs.append(obj)
        self.groups = {}
        return objs

    def _split(self, bm, mode):
        """One bmesh per cell, in cell-local coordinates."""
        bm.faces.ensure_lookup_table()
        layer = bm.faces.layers.int.get("bcell")
        buckets = {}
        for f in bm.faces:
            value = f[layer] if layer is not None else 0
            buckets.setdefault(value, []).append(f)
        src_uv = bm.loops.layers.uv.active
        out = {}
        for value, faces in buckets.items():
            cell = self._value_cell.get(value, self.cell)
            centre = cells.cell_centre_blender(cell[0], cell[1])
            new = bmesh.new()
            for f in faces:
                uvs = _face_uv(f, mode, src_uv)
                src_uvs = {v: uv for v, uv in zip(f.verts, uvs)}
                vs = [new.verts.new(v.co - centre) for v in f.verts]
                nf = new.faces.new(vs)
                shapes.set_uvs(new, nf, {nv: src_uvs[sv] for nv, sv in zip(vs, f.verts)})
            out[cell] = new
        return out

    def _make(self, col, obj_name, mat_key, bm, cell):
        """A mesh object at the cell centre, in world coordinates."""
        import bpy
        bm.verts.ensure_lookup_table()
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        me = bpy.data.meshes.new(obj_name)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(obj_name, me)
        obj.location = cells.cell_centre_blender(cell[0], cell[1])
        col.objects.link(obj)
        me.materials.append(self.materials[mat_key])
        print("  %-16s c%d_%d %7d tris" % (mat_key, cell[0], cell[1], len(me.polygons)))
        return obj
