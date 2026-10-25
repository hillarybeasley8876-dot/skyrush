"""Mesh helpers of the realistic fleet converter (blender/npc_cars/web/convert_real.py).

The converter joins every mesh of a source model into ONE working mesh, so a face can be classified with numpy arrays: the
source object and material it came from, the colour its texture shows under it, its centre, normal and bounds, and the
connected part (welded by position) it belongs to. The parts of the car contract are then cut out of the working mesh.

The normals of the source are kept: after the car is put into the game frame, the corner normals are copied into the corner
attribute `src_normal`, which survives the cuts (a custom normal of Blender is stored relative to its smooth fan, and a cut
changes the fans), and every part gets them back as custom normals before the export.
"""
import math
import os
from collections import defaultdict

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

SRC_ID = "src_id"          # face: the index of the source object
SRC_RGB = "src_rgb"        # face: the colour under the face (sRGB, the texture sampled at the face or the material colour)
SRC_TEX = "src_tex"        # face: 1 when the colour came from a texture
SRC_UV = "src_uv"          # face: the centre of the face in the UV space of its texture (-1, -1 without a texture)
SRC_NORMAL = "src_normal"  # corner: the normal of the source in the game frame
HELPERS = (SRC_ID, SRC_RGB, SRC_TEX, SRC_UV, SRC_NORMAL)


# ------------------------------------------------------------------------------------------------ import

def reset():
    """An empty scene (and an empty pixel cache: the images of two sources share names like Image_0)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _PIXELS.clear()


def import_model(path, keep=None):
    """Imports a glb/gltf, bakes every mesh into the scene frame and deletes everything else. `keep(name)` filters the
    meshes by object name (a pack of several cars). Returns the mesh objects."""
    ext = os.path.splitext(path)[1].lower()
    before = set(bpy.data.objects)
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        raise RuntimeError("cannot import %s" % path)
    objects = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in objects if o.type == "MESH" and (keep is None or keep(o.name))]
    worlds = {o.name: o.matrix_world.copy() for o in meshes}
    for ob in meshes:
        if ob.data.users > 1:
            ob.data = ob.data.copy()
    for ob in meshes:
        m = worlds[ob.name]
        ob.data.transform(m)
        if m.determinant() < 0.0:
            ob.data.flip_normals()
    for ob in meshes:
        ob.parent = None
        ob.matrix_world = Matrix.Identity(4)
    for ob in objects:
        if ob not in meshes:
            bpy.data.objects.remove(ob, do_unlink=True)
    return meshes


def join(objects, name):
    """Joins the objects into the first one and names it."""
    with bpy.context.temp_override(active_object=objects[0], object=objects[0], selected_objects=objects,
                                   selected_editable_objects=objects):
        bpy.ops.object.join()
    ob = objects[0]
    ob.name = name
    ob.data.name = name
    return ob


# ------------------------------------------------------------------------------------------------ the colour under a face

def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1.0 / 2.4) - 0.055)


def _principled(mat):
    if mat is None or mat.node_tree is None:
        return None
    return next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)


def material_source(mat):
    """(image, uv map name, factor) of the base colour of a material, or (None, None, colour): the colour is linear."""
    bsdf = _principled(mat)
    if bsdf is None:
        colour = tuple(mat.diffuse_color[:3]) if mat is not None else (0.5, 0.5, 0.5)
        return None, None, colour
    socket = bsdf.inputs["Base Color"]
    if not socket.is_linked:
        return None, None, tuple(socket.default_value[:3])
    factor = [1.0, 1.0, 1.0]
    stack = [socket.links[0].from_node]
    seen = set()
    image_node = None
    while stack:
        node = stack.pop()
        if node.name in seen:
            continue
        seen.add(node.name)
        if node.type == "TEX_IMAGE" and node.image is not None:
            image_node = node
            break
        for inp in node.inputs:
            if inp.is_linked:
                stack.append(inp.links[0].from_node)
            elif inp.type == "RGBA" and node.type in ("MIX", "MIX_RGB") and inp.name in ("B", "Color2"):
                factor = [a * b for a, b in zip(factor, inp.default_value[:3])]
    if image_node is None:
        return None, None, (0.8, 0.8, 0.8)
    uv_name = None
    vec = image_node.inputs.get("Vector")
    while vec is not None and vec.is_linked:
        node = vec.links[0].from_node
        if node.type == "UVMAP":
            uv_name = node.uv_map
            break
        vec = node.inputs.get("Vector")
    return image_node.image, uv_name, tuple(factor)


_PIXELS = {}


def image_pixels(image):
    """The pixels of an image as a (h, w, 3) array of sRGB values (cached for the source being converted)."""
    key = image.as_pointer()
    if key not in _PIXELS:
        w, h = image.size
        buf = np.empty(w * h * image.channels, dtype=np.float32)
        image.pixels.foreach_get(buf)
        _PIXELS[key] = buf.reshape(h, w, image.channels)[:, :, :3]
    return _PIXELS[key]


def sample_faces(ob):
    """The colour under every face of an object (sRGB), whether it came from a texture and the centre of the face in the UV
    space of that texture: the base colour texture is sampled at the centre of the face in UV space and at its corners
    pulled 40 % towards the centre."""
    me = ob.data
    n = len(me.polygons)
    rgb = np.zeros((n, 3))
    textured = np.zeros(n, dtype=np.int32)
    uv_centre = np.full((n, 2), -1.0)
    if n == 0:
        return rgb, textured, uv_centre
    mat_index = np.empty(n, dtype=np.int32)
    me.polygons.foreach_get("material_index", mat_index)
    starts = np.empty(n, dtype=np.int32)
    me.polygons.foreach_get("loop_start", starts)
    totals = np.empty(n, dtype=np.int32)
    me.polygons.foreach_get("loop_total", totals)
    for slot, mat in enumerate(me.materials):
        faces = np.nonzero(mat_index == slot)[0]
        if len(faces) == 0:
            continue
        image, uv_name, factor = material_source(mat)
        if image is None or not me.uv_layers or image.size[0] == 0:
            rgb[faces] = linear_to_srgb(factor)
            continue
        layer = me.uv_layers.get(uv_name) if uv_name else None
        layer = layer or me.uv_layers[0]
        uv = np.empty(len(me.loops) * 2, dtype=np.float32)
        layer.data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2)
        pix = image_pixels(image)
        h, w = pix.shape[:2]
        acc = np.zeros((len(faces), 3))
        cnt = np.zeros(len(faces))
        loops = np.concatenate([np.arange(starts[f], starts[f] + totals[f]) for f in faces])
        owner = np.repeat(np.arange(len(faces)), totals[faces])
        centre = np.zeros((len(faces), 2))
        np.add.at(centre, owner, uv[loops])
        centre /= totals[faces][:, None]
        points = np.concatenate([centre, centre[owner] + (uv[loops] - centre[owner]) * 0.6])
        who = np.concatenate([np.arange(len(faces)), owner])
        px = np.floor(points[:, 0] * w).astype(np.int64) % w
        py = np.floor(points[:, 1] * h).astype(np.int64) % h
        np.add.at(acc, who, pix[py, px])
        np.add.at(cnt, who, 1.0)
        colour = acc / cnt[:, None]
        if factor != (1.0, 1.0, 1.0):
            colour = linear_to_srgb(srgb_to_linear(colour) * np.asarray(factor))
        rgb[faces] = colour
        textured[faces] = 1
        uv_centre[faces] = centre
    return rgb, textured, uv_centre


def tag_faces(ob, index):
    """Stores the source index, the colour under every face and its UV centre in face attributes (before the join)."""
    me = ob.data
    rgb, textured, uv_centre = sample_faces(ob)
    n = len(me.polygons)
    a = me.attributes.new(SRC_ID, "INT", "FACE")
    a.data.foreach_set("value", np.full(n, index, dtype=np.int32))
    a = me.attributes.new(SRC_RGB, "FLOAT_VECTOR", "FACE")
    a.data.foreach_set("vector", rgb.astype(np.float32).ravel())
    a = me.attributes.new(SRC_TEX, "INT", "FACE")
    a.data.foreach_set("value", textured)
    a = me.attributes.new(SRC_UV, "FLOAT2", "FACE")
    a.data.foreach_set("vector", uv_centre.astype(np.float32).ravel())


# ------------------------------------------------------------------------------------------------ the game frame

FRONT_TURN = {"+Y": 0.0, "-X": -90.0, "+X": 90.0, "-Y": 180.0}


def bounds_of(points):
    pts = np.asarray(points).reshape(-1, 3)
    return pts.min(axis=0), pts.max(axis=0)


def vertices(me):
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def to_game_frame(ob, turn_deg, length=None, scale=None, x_scale=1.0):
    """Turns the car about Z so that its nose looks at +Y, scales it to `length` (overall, bumper to bumper) or by
    `scale` (and its width by `x_scale` more: a car modelled too wide), stands it on z = 0 and centres it in X and Y.
    Returns the scale."""
    me = ob.data
    me.transform(Matrix.Rotation(math.radians(turn_deg), 4, "Z"))
    lo, hi = bounds_of(vertices(me))
    factor = scale if scale else length / (hi[1] - lo[1])
    shift = Vector((-(lo[0] + hi[0]) * 0.5 * factor * x_scale, -(lo[1] + hi[1]) * 0.5 * factor, -lo[2] * factor))
    me.transform(Matrix.Translation(shift) @ Matrix.Diagonal((factor * x_scale, factor, factor, 1.0)))
    return factor


def store_normals(me):
    """Copies the corner normals into the corner attribute src_normal (they survive the cuts)."""
    buf = np.empty(len(me.loops) * 3, dtype=np.float32)
    me.corner_normals.foreach_get("vector", buf)
    a = me.attributes.new(SRC_NORMAL, "FLOAT_VECTOR", "CORNER")
    a.data.foreach_set("vector", buf)


def restore_normals(me):
    """Gives a part the normals of its source back (custom normals from src_normal)."""
    a = me.attributes.get(SRC_NORMAL)
    if a is None or len(me.loops) == 0:
        return False
    buf = np.empty(len(me.loops) * 3, dtype=np.float32)
    a.data.foreach_get("vector", buf)
    normals = buf.reshape(-1, 3).astype(np.float64)
    length = np.linalg.norm(normals, axis=1)
    bad = length < 1e-6
    normals[bad] = (0.0, 0.0, 1.0)
    normals[~bad] /= length[~bad][:, None]
    me.shade_smooth()
    me.normals_split_custom_set([tuple(v) for v in normals])
    return True


def smooth_by_angle(me, degrees=40.0):
    """Smooth shading with the edges sharper than `degrees` kept hard (a decimated part, a part built here)."""
    if "custom_normal" in me.attributes:
        me.attributes.remove(me.attributes["custom_normal"])
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(degrees))


def strip(me):
    """Drops the helper attributes and the UV maps (the fleet has no texture)."""
    for name in HELPERS:
        a = me.attributes.get(name)
        if a is not None:
            me.attributes.remove(a)
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)


# ------------------------------------------------------------------------------------------------ the faces as arrays

class Faces:
    """The faces of the working mesh as numpy arrays: centre, normal, area, bounds, the source object, the material, the
    colour under the face, the connected part."""

    def __init__(self, ob, names):
        me = ob.data
        n = len(me.polygons)
        self.n = n
        self.centre = np.empty(n * 3)
        me.polygons.foreach_get("center", self.centre)
        self.centre = self.centre.reshape(-1, 3)
        self.normal = np.empty(n * 3)
        me.polygons.foreach_get("normal", self.normal)
        self.normal = self.normal.reshape(-1, 3)
        self.area = np.empty(n)
        me.polygons.foreach_get("area", self.area)
        self.tris = np.empty(n, dtype=np.int32)
        me.polygons.foreach_get("loop_total", self.tris)
        self.tris -= 2
        mat_index = np.empty(n, dtype=np.int32)
        me.polygons.foreach_get("material_index", mat_index)
        mats = [m.name if m else "" for m in me.materials]
        self.material = np.array([mats[i] for i in mat_index], dtype=object)
        sid = np.empty(n, dtype=np.int32)
        me.attributes[SRC_ID].data.foreach_get("value", sid)
        self.source = np.array([names[i] for i in sid], dtype=object)
        self.rgb = np.empty(n * 3, dtype=np.float32)
        me.attributes[SRC_RGB].data.foreach_get("vector", self.rgb)
        self.rgb = self.rgb.reshape(-1, 3).astype(np.float64)
        self.textured = np.empty(n, dtype=np.int32)
        me.attributes[SRC_TEX].data.foreach_get("value", self.textured)
        self.uv = np.empty(n * 2, dtype=np.float32)
        me.attributes[SRC_UV].data.foreach_get("vector", self.uv)
        self.uv = self.uv.reshape(-1, 2).astype(np.float64)
        co = vertices(me)
        starts = np.empty(n, dtype=np.int32)
        me.polygons.foreach_get("loop_start", starts)
        corner_vert = np.empty(len(me.loops), dtype=np.int32)
        me.loops.foreach_get("vertex_index", corner_vert)
        pts = co[corner_vert]
        self.lo = np.minimum.reduceat(pts, starts, axis=0)
        self.hi = np.maximum.reduceat(pts, starts, axis=0)
        self.part, self.face_verts = _parts(co, corner_vert, starts)


def _parts(co, corner_vert, starts):
    """The connected part of every face, the vertices welded by position (a glTF mesh is split at its UV seams)."""
    span = float(np.max(co.max(axis=0) - co.min(axis=0))) if len(co) else 1.0
    tol = max(span * 2e-5, 1e-6)
    keys = np.round(co / tol).astype(np.int64)
    _, weld = np.unique(keys, axis=0, return_inverse=True)
    weld = weld.ravel()
    parent = np.arange(weld.max() + 1 if len(weld) else 0)

    def find(i):
        root = i
        while parent[root] != root:
            root = parent[root]
        while parent[i] != root:
            parent[i], i = root, parent[i]
        return root

    face_verts = np.split(weld[corner_vert], starts[1:])
    for verts in face_verts:
        a = find(verts[0])
        for v in verts[1:]:
            b = find(v)
            if a != b:
                parent[b] = a
    return np.array([find(v[0]) for v in face_verts], dtype=np.int64), face_verts


def local_components(mask, face_verts):
    """The connected pieces among the selected faces only (two faces are connected when they share a welded vertex):
    {piece id: face indices}."""
    idx = np.nonzero(mask)[0]
    parent = {}

    def find(i):
        root = i
        while parent.setdefault(root, root) != root:
            root = parent[root]
        while parent[i] != root:
            parent[i], i = root, parent[i]
        return root

    owner = {}
    for f in idx:
        for v in face_verts[f]:
            v = int(v)
            if v in owner:
                a, b = find(owner[v]), find(int(f))
                if a != b:
                    parent[b] = a
            else:
                owner[v] = int(f)
                find(int(f))
    out = defaultdict(list)
    for f in idx:
        out[find(int(f))].append(int(f))
    return {k: np.array(v) for k, v in out.items()}


# ------------------------------------------------------------------------------------------------ cutting the parts

def extract(work, faces, name):
    """A new object with the given faces of the working mesh (the materials are kept, the helper attributes too)."""
    me = work.data.copy()
    me.name = name
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    keep = np.zeros(len(bm.faces), dtype=bool)
    keep[np.asarray(faces, dtype=np.int64)] = True
    drop = [f for f in bm.faces if not keep[f.index]]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def set_materials(ob, roles, role_of_face, material_of_role):
    """Gives the part one material slot per role it holds: `role_of_face` lists the role of every face of the part, in
    the order of its faces."""
    me = ob.data
    order = sorted(set(role_of_face), key=lambda r: list(roles).index(r) if r in roles else 999)
    me.materials.clear()
    for role in order:
        me.materials.append(material_of_role(role))
    index = np.array([order.index(r) for r in role_of_face], dtype=np.int32)
    me.polygons.foreach_set("material_index", index)
    me.update()


def recentre(ob, target=None):
    """Moves the origin of an object to the centre of its bounds (or the mesh so that the centre of its bounds sits on
    `target`): the object keeps its place in the first case and moves to `target` in the second."""
    lo, hi = bounds_of(vertices(ob.data))
    centre = Vector(((lo + hi) * 0.5).tolist())
    ob.data.transform(Matrix.Translation(-centre))
    ob.location = centre if target is None else Vector(target)
    return centre


def decimate(ob, ratio):
    """Collapse decimation of a part (the normals are then smoothed by angle)."""
    if ratio >= 0.999 or len(ob.data.polygons) < 50:
        return
    mod = ob.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = False
    with bpy.context.temp_override(object=ob, active_object=ob):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def triangles(ob):
    if ob.type != "MESH":
        return 0
    totals = np.empty(len(ob.data.polygons), dtype=np.int32)
    ob.data.polygons.foreach_get("loop_total", totals)
    return int((totals - 2).sum())


def world_bounds(ob):
    lo, hi = bounds_of(vertices(ob.data))
    loc = np.array(ob.location[:])
    return lo + loc, hi + loc


# ------------------------------------------------------------------------------------------------ primitives

def new_object(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if isinstance(material, (list, tuple)):
        for m in material:
            me.materials.append(m)
    else:
        me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def bevel_box(bm, size, centre, bevel=0.0, segments=2, material_index=0):
    """Adds a box (optionally with bevelled edges) to a bmesh."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0.0:
        bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bevel, segments=segments, affect="EDGES", profile=0.5)
    for f in tmp.faces:
        f.material_index = material_index
    for v in tmp.verts:
        v.co += Vector(centre)
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def cylinder(bm, radius_bottom, radius_top, depth, centre, segments=16, material_index=0):
    """Adds a capped cylinder (axis Z) to a bmesh."""
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=segments, radius1=radius_bottom, radius2=radius_top, depth=depth)
    for f in tmp.faces:
        f.material_index = material_index
    for v in tmp.verts:
        v.co += Vector(centre)
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def tube(bm, start, end, radius, segments=12, material_index=0):
    """Adds a capped tube from `start` to `end` to a bmesh."""
    a = Vector(start)
    b = Vector(end)
    axis = b - a
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=axis.length)
    turn = Vector((0.0, 0.0, 1.0)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(tmp, matrix=Matrix.Translation((a + b) * 0.5) @ turn, verts=tmp.verts)
    for f in tmp.faces:
        f.material_index = material_index
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def empty(name, location):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = 0.1
    ob.location = location
    bpy.context.scene.collection.objects.link(ob)
    return ob


def ray_down(objects, x, y, top=10.0):
    """The height of the highest face of `objects` under (x, y), or None."""
    from mathutils.bvhtree import BVHTree
    best = None
    deps = bpy.context.evaluated_depsgraph_get()
    for ob in objects:
        tree = BVHTree.FromObject(ob, deps)
        local = ob.matrix_world.inverted() @ Vector((x, y, top))
        hit, _, _, _ = tree.ray_cast(local, Vector((0.0, 0.0, -1.0)))
        if hit is not None:
            z = (ob.matrix_world @ hit).z
            best = z if best is None else max(best, z)
    return best


def components(faces_mask, part):
    """The connected parts among the selected faces: {part id: face indices}."""
    out = defaultdict(list)
    for i in np.nonzero(faces_mask)[0]:
        out[int(part[i])].append(int(i))
    return {k: np.array(v) for k, v in out.items()}
