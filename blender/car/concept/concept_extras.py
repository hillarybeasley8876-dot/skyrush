"""Stage 3 of the hero car: what the concept does not have (the wing, the rocket nozzles, the brake
light), the markers of the contract and the root, then the glb export.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import meshkit

WING_SPAN = 1.22
WING_CHORD = 0.17
WING_THICK = 0.02
WING_LIFT = 0.075  # the blade centre above the deck
WING_Y = -1.90
POSTS_X = 0.36
NOZZLE_XS = (-0.36, -0.12, 0.12, 0.36)
NOZZLE_Z = 0.62
POSES = {"stowed": 0.0, "low_drag": 1.0, "high_downforce": 15.0, "air_brake": 60.0}


def _cast(origin, direction, distance=12.0):
    graph = bpy.context.evaluated_depsgraph_get()
    hit, location, _normal, _index, ob, _matrix = bpy.context.scene.ray_cast(
        graph, Vector(origin), Vector(direction).normalized(), distance=distance)
    if not hit:
        raise RuntimeError("no surface at %s going %s" % (tuple(origin), tuple(direction)))
    return location, ob


def deck_height(x, y):
    return _cast((x, y, 3.0), (0, 0, -1))[0].z


def rear_face_y(x, z):
    return _cast((x, -4.0, z), (0, 1, 0))[0].y


def nose_face_y(x, z):
    return _cast((x, 4.0, z), (0, -1, 0))[0].y


def flank_x(side, y, z):
    return _cast((side * 3.0, y, z), (-side, 0, 0))[0].x


def _bmesh_object(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    return meshkit.new_object(name, me)


def _box(bm, size, centre):
    result = bmesh.ops.create_cube(bm, size=1.0)
    verts = result["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), space=Matrix.Identity(4), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(centre), verts=verts)
    return verts


def build_wing(mats):
    """Wing: a blade on two posts, origin on the hinge (the blade centre), poses in the extras."""
    z = deck_height(0.0, WING_Y) + WING_LIFT
    bm = bmesh.new()
    _box(bm, (WING_SPAN, WING_CHORD, WING_THICK), (0.0, 0.0, 0.0))
    for side in (-1.0, 1.0):  # the end plates
        _box(bm, (0.010, WING_CHORD, 0.060), (side * WING_SPAN * 0.5, 0.0, 0.018))
    bmesh.ops.bevel(bm, geom=[e for e in bm.edges], offset=0.005, segments=2, affect="EDGES")
    wing = _bmesh_object("Wing", bm, mats["SH_car_paint_black"])
    wing.location = Vector((0.0, WING_Y, z))
    meshkit.tidy(wing, 35.0)
    for key, value in (("poses", dict(POSES)), ("span_half", WING_SPAN * 0.5),
                       ("deploy_contract", "rotate the local X axis by -pitch_deg: the trailing edge rises")):
        wing[key] = value
    # the two posts stay on the car
    posts = bmesh.new()
    for side in (-1.0, 1.0):
        deck = deck_height(side * POSTS_X, WING_Y)
        height = z - deck
        _box(posts, (0.03, 0.06, height + 0.02), (side * POSTS_X, WING_Y, deck + height * 0.5 - 0.01))
    post_ob = _bmesh_object("WingPosts", posts, mats["SH_car_paint_black"])
    meshkit.tidy(post_ob, 35.0)
    return wing, post_ob


def build_nozzles(mats):
    """The four rear bells of the rocket trim, on the rear face; returns the objects and the points."""
    objects = []
    points = []
    for index, x in enumerate(NOZZLE_XS):
        y = rear_face_y(x, NOZZLE_Z)
        points.append(Vector((x, y, NOZZLE_Z)))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=20, radius1=0.042, radius2=0.058,
                              depth=0.05, matrix=Matrix.Rotation(math.pi * 0.5, 4, "X"))
        ob = _bmesh_object("NozzleMesh_R%d" % (index + 1), bm, mats["M_Nozzle"])
        ob.location = Vector((x, y + 0.012, NOZZLE_Z))
        # the wide end faces the road behind the car: the bell opens to the rear
        meshkit.tidy(ob, 40.0)
        objects.append(ob)
    return objects, points


def build_brake_light(mats):
    """Brake_Light: a thin strip between the two tail pods, lying on the rear deck."""
    y = -1.77
    z = deck_height(0.0, y) + 0.002
    bm = bmesh.new()
    _box(bm, (0.50, 0.014, 0.012), (0.0, 0.0, 0.0))
    ob = _bmesh_object("Brake_Light", bm, mats["M_BrakeLight"])
    ob.location = Vector((0.0, y, z + 0.006))
    meshkit.tidy(ob, 60.0)
    return ob


def empty(name, location, direction=None, size=0.08):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = "ARROWS"
    ob.empty_display_size = size
    ob.location = Vector(location)
    if direction is not None:
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = Vector((0.0, 1.0, 0.0)).rotation_difference(Vector(direction).normalized())
    meshkit.link(ob)
    return ob


def build_markers(nozzle_points):
    """The empties of CONTRACTS.md 6. Local +Y of a nozzle marker is its jet (-Z in Godot)."""
    out = {}
    down = (0.0, 0.0, -1.0)
    back = (0.0, -1.0, 0.0)
    for index, point in enumerate(nozzle_points):
        out["Nozzle_R%d" % (index + 1)] = empty("Nozzle_R%d" % (index + 1), point, back)
    out["Nozzle_P1"] = empty("Nozzle_P1", (-0.57, 1.95, 0.16), down)
    out["Nozzle_P2"] = empty("Nozzle_P2", (0.57, 1.95, 0.16), down)
    out["Nozzle_P3"] = empty("Nozzle_P3", (-0.73, -1.85, 0.16), down)
    out["Nozzle_P4"] = empty("Nozzle_P4", (0.73, -1.85, 0.16), down)
    out["Nozzle_P5"] = empty("Nozzle_P5", (flank_x(-1, 2.02, 0.30), 2.02, 0.30), (-1.0, 0.0, 0.0))
    out["Nozzle_P6"] = empty("Nozzle_P6", (flank_x(1, 2.02, 0.30), 2.02, 0.30), (1.0, 0.0, 0.0))
    out["Light_Front"] = empty("Light_Front", (0.0, nose_face_y(0.0, 0.52) - 0.02, 0.52), (0.0, 1.0, 0.0))
    out["Light_Rear"] = empty("Light_Rear", (0.0, -1.70, 0.95), back)
    out["Fan_Intake"] = empty("Fan_Intake", (0.0, nose_face_y(0.0, 0.2) - 0.03, 0.2), (0.0, 1.0, 0.0))
    out["Camera_Hood"] = empty("Camera_Hood", (0.0, 1.50, deck_height(0.0, 1.50) + 0.12), (0.0, 1.0, 0.0))
    out["Seat_Driver"] = empty("Seat_Driver", (0.0, 0.15, 0.50), (0.0, 1.0, 0.0))
    return out


def make_root(objects):
    """Parents everything to the empty `Roadster` (identity, at the origin)."""
    root = bpy.data.objects.new("Roadster", None)
    meshkit.link(root)
    for ob in objects:
        ob.parent = root
    return root


def export(path):
    """Writes the glb: no texture, no camera, no light; the custom properties become extras."""
    wanted = dict(
        filepath=path, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
        export_extras=True, export_cameras=False, export_lights=False, export_materials="EXPORT",
        export_image_format="NONE", export_texcoords=False, export_normals=True, export_tangents=False,
        export_animations=False, export_skins=False, export_morph=False, export_vertex_color="NONE",
        export_draco_mesh_compression_enable=False)
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    kwargs = {k: v for k, v in wanted.items() if k in valid}
    for k in wanted:
        if k not in valid:
            print("export option not available:", k)
    bpy.ops.export_scene.gltf(**kwargs)
