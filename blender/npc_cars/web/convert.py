"""Converts the CC0 "Free Low Poly Vehicles Pack" by Rgsdev into the traffic and police fleet of SKYRUSH.

    python tools/gd.py blender run blender/npc_cars/web/convert.py -- [model ids] [--out DIR]

        model ids   the models to build (default: all of MODELS)
        --out DIR   where the glb files are written (default: game/assets/cars/npc)

The pack is one low poly car per FBX: a body mesh that carries the paint, the glass, the lamps (and the
flashers of the police cars) as materials, and four wheels. The conversion puts a car into the game
frame and the car contract (CONTRACTS.md 6, the node names that the traffic, the police and the damage
units look for):

  * the car faces +Y (Godot -Z), stands on z = 0, its origin is the middle of the body, one unit is a metre;
  * the body mesh is split by face into Body (paint, trim), Glass, Lamp_F (head lamps), Lamp_R (tail lamps),
    Mirror_L / Mirror_R, the parts that the damage unit tears off (Bumper_F, Bumper_R and, on a car with a bonnet,
    Hood) and, on the police cars, LightBar_Red / LightBar_Blue;
  * the wheels are Wheel_FL / FR / RL / RR, the origin of each is the centre of the wheel, the spin axis is X;
  * the empties Light_Front / Light_Rear (where the head lamp of a traffic car sits) and, on the police cars, Siren;
  * the paint of a traffic car is the shader material SH_car_paint_npc (the colour of each car is an instance
    uniform; the taxi wears SH_car_paint_taxi, the white of a police car SH_car_paint_police), the glass is the dark
    glass of the fleet, every other material is a plain material.

The Body does NOT contain the mirrors: the box collider of a traffic car is measured from the Body, and a
mirror is 30 cm of width that the car does not have. The box truck is the cab of the pack's truck with a
cargo box built on its frame; the robotaxi gets a roof LiDAR.

The licence of the pack is in source/License.txt (CC0, no credit needed; CREDITS.md names it anyway).
"""
import math
import os
import sys
from collections import defaultdict

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "source")
GAME_OUT = os.path.join(os.path.expanduser("~/m/skyrush/game"), "assets", "cars", "npc")

# id -> {src: the FBX of the pack, length: the length of the body in metres (the bumpers included), police: bool, ...}
# The lengths are the ones of the fleet table (game/ai/traffic/traffic_fleet.gd) and of the police presets.
MODELS = {
    "sedan_ev": {"src": "Sedan", "length": 4.84, "width": 1.90, "roof": 1.50},
    "hatch_ev": {"src": "Hatchback", "length": 3.94, "width": 1.77, "roof": 1.50},
    "suv_ev": {"src": "SUV", "length": 4.74, "width": 1.94, "roof": 1.72},
    "taxi": {"src": "Taxi", "length": 4.84, "width": 1.90, "roof": 1.50, "paint": "SH_car_paint_taxi"},
    "robotaxi": {"src": "Sports", "length": 4.60, "width": 1.86, "lidar": True, "hood": False},
    "van": {"src": "Van", "length": 5.30, "width": 2.00, "roof": 2.15, "belt": 0.95, "hood": False},
    "bus": {"src": "Bus", "length": 12.00, "width": 2.40, "roof": 3.20, "belt": 1.0, "hood": False},
    "truck": {"src": "Truck", "scale": 0.88, "width": 2.35, "hood": False,
              "cargo": {"length": 3.6, "extra_height": 0.25}},
    "police_patrol": {"src": "Police Sedan", "length": 4.84, "width": 1.90, "roof": 1.50, "police": True},
    "police_interceptor": {"src": "Police Sports", "length": 4.69, "width": 1.92, "police": True},
    "police_suv": {"src": "Police SUV", "length": 5.19, "width": 2.06, "roof": 1.80, "police": True},
}
# The cars of the pack are wider and taller than the fleet table says (2.1 x 1.9 m for the sedan, a roof at 1.86 m): the body is
# narrowed to `width` and the part above the belt line (`belt`, default 0.75 m) is squeezed so that the roof stands at `roof`. The
# wheels keep their size and their height, the lower body and the wheel arches stay as they are, the lamps move with the body.
BELT = 0.75

# the materials of the pack that are not the paint
GLASS = "windows"
HEAD = "headlights"
TAIL = "rear lights"
BLACK = "body black"
WHITE = "body white"
FLASH_RED = "flashers siren red"
FLASH_BLUE = "flashers siren blue"
RIM = "wheels"
TYRE = "tires"

MIRROR_STEP = 0.06     # a face with a vertex this far outside the side of the body is a mirror (source units)
BUMPER_DEPTH = 0.45    # a bumper reaches this far (m) back from the nose or forward from the tail
BUMPER_MARGIN = 0.03   # ... and up to this far (m) under the lowest edge of the lamps of its end
HOOD_WIDTH = 0.80      # the bonnet is this share of the width of the body (the fenders stay on the car)
WHEEL_NAMES = {("front", "left"): "Wheel_FL", ("front", "right"): "Wheel_FR",
               ("rear", "left"): "Wheel_RL", ("rear", "right"): "Wheel_RR"}


# ------------------------------------------------------------------------------------------------ materials

def _linear(rgb):
    return tuple(rgb[:3])


def make_material(name, color, roughness=0.5, metallic=0.0, emission=None, strength=0.0, clearcoat=0.0):
    """A Principled material (glTF safe: base colour and constants only)."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*_linear(color), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    for key in ("Coat Weight", "Clearcoat"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = clearcoat
    if emission is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*_linear(emission), 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def source_colors(ob):
    """Material name -> base colour of the source object."""
    out = {}
    for m in ob.data.materials:
        color = None
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    color = tuple(n.inputs["Base Color"].default_value[:3])
        out[m.name] = color or tuple(m.diffuse_color[:3])
    return out


# ------------------------------------------------------------------------------------------------ the source

def import_source(src):
    """Clears the scene, imports one FBX and returns (body, wheels): the body object and the wheel objects."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(SOURCE, src + ".fbx"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    wheels = [o for o in meshes if "wheel" in o.name.lower()]
    body = [o for o in meshes if o not in wheels]
    if len(body) != 1 or len(wheels) < 4:
        raise RuntimeError("%s: %d bodies and %d wheels" % (src, len(body), len(wheels)))
    for ob in meshes:
        bake(ob)
    return body[0], wheels


def bake(ob):
    """Applies the object transform to the mesh and drops the parent: the vertices are in the scene frame."""
    ob.data.transform(ob.matrix_world)
    ob.parent = None
    ob.matrix_world = Matrix.Identity(4)


def bounds(points):
    xs = [p.x for p in points]
    ys = [p.y for p in points]
    zs = [p.z for p in points]
    return (Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs))))


def vertices(ob):
    return [v.co.copy() for v in ob.data.vertices]


def to_game_frame(body, wheels, length, scale):
    """Turns the nose to +Y, scales the car to `length` (or by `scale`), stands it on z = 0 and puts the origin in the
    middle of the body. Returns the scale that was used."""
    turn = Matrix.Rotation(math.pi, 4, "Z")
    for ob in [body] + wheels:
        ob.data.transform(turn)
    lo, hi = bounds(vertices(body))
    factor = scale if scale else length / (hi.y - lo.y)
    wlo, whi = bounds([v for w in wheels for v in vertices(w)])
    shift = Vector((0.0, -(lo.y + hi.y) * 0.5 * factor, -wlo.z * factor))
    move = Matrix.Translation(shift) @ Matrix.Scale(factor, 4)
    for ob in [body] + wheels:
        ob.data.transform(move)
    return factor


# ------------------------------------------------------------------------------------------------ splitting

def side_of_body(me):
    """The half width of the side of the body: the most common large |x| of the vertices (the mirrors are further out)."""
    counts = defaultdict(int)
    for v in me.vertices:
        counts[round(abs(v.co.x), 2)] += 1
    return max(k for k, c in counts.items() if c >= 12)


def body_half_width(me):
    """The half width of the side of the body (the |x| that most vertices have)."""
    counts = defaultdict(int)
    for v in me.vertices:
        if abs(v.co.x) > 0.8:
            counts[round(abs(v.co.x), 2)] += 1
    return max(counts.items(), key=lambda kv: kv[1])[0]


def shape(parts, wheels, x_factor, belt, roof_from, roof_to):
    """Narrows every part by x_factor and squeezes the part above the belt line: the roof goes from roof_from to roof_to.
    What is above the roof (the light bar, the sign, the lidar) keeps its size and moves with it."""
    for ob in list(parts) + list(wheels):
        for v in ob.data.vertices:
            v.co.x *= x_factor
    if roof_to is None:
        return
    k = (roof_to - belt) / (roof_from - belt)
    for ob in parts:
        for v in ob.data.vertices:
            z = v.co.z
            if z > roof_from:
                v.co.z = roof_to + (z - roof_from)
            elif z > belt:
                v.co.z = belt + (z - belt) * k


def cut_levels(me, mats):
    """(head_z, tail_z, glass_base): the lowest edge of the head lamps and of the tail lamps, and the y of the front edge of the
    windscreen, in the game frame before the shaping. The bumpers are what is under the lamps at the two ends, the bonnet is what
    lies flat in front of the windscreen. A level the model does not have is None."""
    low = {HEAD: None, TAIL: None}
    base = None
    for p in me.polygons:
        material = mats[p.material_index]
        verts = [me.vertices[i].co for i in p.vertices]
        if material in low:
            z = min(v.z for v in verts)
            low[material] = z if low[material] is None else min(low[material], z)
        elif material == GLASS and p.normal.y > 0.3 and p.center.y > 0.0:
            y = max(v.y for v in verts)
            base = y if base is None else max(base, y)
    return low[HEAD], low[TAIL], base


def split_faces(body, rules):
    """Returns {part name: [face indices]}. `rules` is the function that names the part of a face."""
    me = body.data
    parts = defaultdict(list)
    for p in me.polygons:
        parts[rules(p)].append(p.index)
    return parts


def extract(body, face_indices, name, materials):
    """A new object with only the given faces of the body (the materials of the body are kept by name)."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.faces.ensure_lookup_table()
    keep = set(face_indices)
    drop = [f for f in bm.faces if f.index not in keep]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in body.data.materials:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = False
    return ob


def split_tail_lens(ob, tail, brake):
    """The rear lamp of the pack is one material: the faces that look straight back become the brake lens (NPC_lamp_brake, the
    surface that CarLights flares up on a car with physics and that TrafficLamps lights up when the traffic car brakes), the
    rest of the cluster (the corners and the sides) stays the tail lens (NPC_lamp_rear, lit all night). A lamp that has no
    such rest (the bus) gives the outer half of its back faces to the tail lens."""
    me = ob.data
    me.materials.clear()
    me.materials.append(tail)
    me.materials.append(brake)
    back = [p for p in me.polygons if p.normal.y < -0.9]
    outer = sorted(back, key=lambda p: -abs(sum(me.vertices[i].co.x for i in p.vertices) / len(p.vertices)))
    for p in me.polygons:
        p.material_index = 0
    for p in back:
        p.material_index = 1
    if len(back) == len(me.polygons) and back:
        for p in outer[:max(1, len(outer) // 2)]:
            p.material_index = 0


def retarget(ob, mapping):
    """Swaps the materials of an object by name and drops the unused slots."""
    me = ob.data
    old_index = [p.material_index for p in me.polygons]      # clearing the slots resets the index of every face
    mats = list(me.materials)
    me.materials.clear()
    slot = {}
    for i in sorted(set(old_index)):
        target = mapping(mats[i].name)
        names = [x.name for x in me.materials]
        if target.name not in names:
            me.materials.append(target)
            names.append(target.name)
        slot[i] = names.index(target.name)
    for p, i in zip(me.polygons, old_index):
        p.material_index = slot[i]
    return ob


# ------------------------------------------------------------------------------------------------ extras

def box(name, size, centre, material, bevel=0.0):
    """A box object (flat shaded, like the pack)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] + centre[0], v.co.y * size[1] + centre[1], v.co.z * size[2] + centre[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def join(objects, name):
    """Joins objects into the first one (materials merged by the join) and renames it."""
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def empty(name, location):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = 0.1
    ob.location = location
    bpy.context.scene.collection.objects.link(ob)
    return ob


def recentre(ob):
    """Moves the origin of an object to the centre of its bounds (the mesh keeps its place)."""
    lo, hi = bounds(vertices(ob))
    centre = (lo + hi) * 0.5
    ob.data.transform(Matrix.Translation(-centre))
    ob.location = centre
    return centre


# ------------------------------------------------------------------------------------------------ one model

def wheel_role(ob):
    """(axle, side) from the name of the source wheel: 'Sedan wheel front left'."""
    name = ob.name.lower()
    axle = "front" if "front" in name else "rear"
    side = "left" if "left" in name else "right"
    return axle, side


def build_model(model_id, cfg, out_dir):
    police = bool(cfg.get("police"))
    body, wheels = import_source(cfg["src"])
    colors = source_colors(body)
    side = side_of_body(body.data)
    body_half_width_value = body_half_width(body.data)
    factor = to_game_frame(body, wheels, cfg.get("length"), cfg.get("scale"))
    lo, hi = bounds(vertices(body))
    mirror_x = (side + MIRROR_STEP) * factor

    # the materials of the fleet
    paint_name = None
    if not police:
        areas = defaultdict(float)
        for p in body.data.polygons:
            areas[body.data.materials[p.material_index].name] += p.area
        candidates = [(a, n) for n, a in areas.items() if n.startswith("body ") and n not in (BLACK, WHITE)]
        paint_name = max(candidates)[1] if candidates else None
    # the paint is a material of the shader library (shaders/materials): the traffic paint is tinted per car by an instance uniform,
    # the taxi has its own teal one, the white of a police car is the police paint (the game swaps the SH_ names for the library)
    paint = make_material(cfg.get("paint", "SH_car_paint_npc"), (0.9, 0.9, 0.9), 0.35, 0.0)
    black = make_material("NPC_gloss_black", (0.012, 0.012, 0.014), 0.28, 0.0, clearcoat=0.5)
    trim_white = make_material("NPC_trim_white", (0.80, 0.80, 0.82), 0.45, 0.0)
    police_black = make_material("NPC_police_black", (0.012, 0.012, 0.015), 0.26, 0.0, clearcoat=0.6)
    police_white = make_material("SH_car_paint_police", (0.95, 0.96, 0.96), 0.35, 0.0, clearcoat=1.0)
    glass = make_material("NPC_glass_dark", (0.018, 0.024, 0.034), 0.06, 0.0, clearcoat=0.8)
    lamp_front = make_material("NPC_lamp_front", (0.95, 0.96, 1.0), 0.15, 0.0, (1.0, 1.0, 1.0), 0.6)
    lamp_rear = make_material("NPC_lamp_rear", (0.55, 0.0, 0.02), 0.2, 0.0, (1.0, 0.04, 0.05), 0.8)
    lamp_brake = make_material("NPC_lamp_brake", (0.55, 0.0, 0.02), 0.2, 0.0, (1.0, 0.04, 0.05), 0.8)
    tyre = make_material("NPC_tyre", (0.015, 0.015, 0.017), 0.85, 0.0)
    rim = make_material("NPC_rim", (0.62, 0.64, 0.68), 0.35, 0.8)
    bar_red = make_material("NPC_lightbar_red", (0.9, 0.04, 0.05), 0.3, 0.0, (1.0, 0.05, 0.08), 0.3)
    bar_blue = make_material("NPC_lightbar_blue", (0.05, 0.12, 0.95), 0.3, 0.0, (0.1, 0.25, 1.0), 0.3)
    other = {}

    def body_material(name):
        if name == paint_name:
            return paint
        if name == BLACK:
            return police_black if police else black
        if name == WHITE:
            return police_white if police else trim_white
        if name == TYRE:
            return tyre
        if name == RIM:
            return rim
        if name not in other:
            other[name] = make_material("NPC_" + name.replace(" ", "_"), colors.get(name, (0.5, 0.5, 0.5)), 0.4)
        return other[name]

    mats = [m.name for m in body.data.materials]
    head_z, tail_z, glass_base = cut_levels(body.data, mats)
    nose_y, tail_y = hi.y, lo.y
    hood_x = HOOD_WIDTH * body_half_width_value * factor
    has_hood = cfg.get("hood", True) and glass_base is not None
    has_rear_bumper = not cfg.get("cargo")        # the box truck gets its bumper at the end of the cargo box
    print("   levels: head_z %s tail_z %s windscreen y %s nose %.2f tail %.2f hood half %.2f" % (
        None if head_z is None else round(head_z, 2), None if tail_z is None else round(tail_z, 2),
        None if glass_base is None else round(glass_base, 2), nose_y, tail_y, hood_x))

    def rules(p):
        material = mats[p.material_index]
        verts = [body.data.vertices[i].co for i in p.vertices]
        if max(abs(v.x) for v in verts) > mirror_x:
            return "Mirror_L" if sum(v.x for v in verts) < 0 else "Mirror_R"
        if material == GLASS:
            return "Glass"
        if material == HEAD:
            return "Lamp_F"
        if material == TAIL:
            return "Lamp_R"
        if material == FLASH_RED:
            return "LightBar_Red"
        if material == FLASH_BLUE:
            return "LightBar_Blue"
        c = p.center
        end_face = abs(p.normal.x) < 0.85          # the flank of the car (the wheel arch trim) is not a bumper
        if end_face and head_z is not None and c.y > nose_y - BUMPER_DEPTH and c.z < head_z - BUMPER_MARGIN:
            return "Bumper_F"
        if end_face and has_rear_bumper and tail_z is not None and c.y < tail_y + BUMPER_DEPTH and c.z < tail_z - BUMPER_MARGIN:
            return "Bumper_R"
        if has_hood and c.y > glass_base - 0.02 and p.normal.z > 0.2 and abs(c.x) < hood_x and c.z > head_z - BUMPER_MARGIN:
            return "Hood"
        return "Body"

    parts = split_faces(body, rules)
    objects = {}
    for name, faces in parts.items():
        objects[name] = extract(body, faces, name, mats)
    bpy.data.objects.remove(body)

    for name, ob in objects.items():
        if name in ("Body", "Bumper_F", "Bumper_R", "Hood"):
            retarget(ob, body_material)
        elif name == "Glass":
            retarget(ob, lambda n: glass)
        elif name == "Lamp_F":
            retarget(ob, lambda n: lamp_front)
        elif name == "Lamp_R":
            retarget(ob, lambda n: lamp_rear)
            split_tail_lens(ob, lamp_rear, lamp_brake)
        elif name == "LightBar_Red":
            retarget(ob, lambda n: bar_red)
        elif name == "LightBar_Blue":
            retarget(ob, lambda n: bar_blue)
        elif name.startswith("Mirror"):
            retarget(ob, lambda n: police_black if police else black)

    # the size of the fleet table
    half = body_half_width_value * factor
    roof_from = None
    if cfg.get("roof"):
        glass_top = max(v.z for v in vertices(objects["Glass"]))
        roof_from = glass_top + 0.04
    shape(list(objects.values()), wheels, cfg["width"] / (2.0 * half), cfg.get("belt", BELT), roof_from, cfg.get("roof"))

    # wheels: the four of the contract are Wheel_*; the other axles of a truck are static (part of the body)
    groups = defaultdict(list)
    for w in wheels:
        groups[wheel_role(w)].append(w)
    named = {}
    extras = []
    for role, group in groups.items():
        group.sort(key=lambda w: vertices(w)[0].y)          # the rearmost wheel of the group first (the nose is +Y now)
        pick = group[0] if role[0] == "rear" else group[-1]
        named[role] = pick
        extras.extend(w for w in group if w is not pick)
    if sorted(named) != sorted(WHEEL_NAMES):
        raise RuntimeError("%s: the wheels are %s" % (model_id, sorted(named)))
    for role, w in named.items():
        retarget(w, lambda n: rim if n == RIM else tyre)
        w.name = WHEEL_NAMES[role]
        w.data.name = w.name
        recentre(w)
    for w in extras:
        retarget(w, lambda n: rim if n == RIM else tyre)
    if extras:
        objects["Body"] = join([objects["Body"]] + extras, "Body")

    if cfg.get("cargo"):
        add_cargo(objects, cfg["cargo"], paint, black, lamp_rear, lamp_brake)
    if cfg.get("sign"):
        add_taxi_sign(objects, trim_white)
    if cfg.get("lidar"):
        add_lidar(objects, black, make_material("NPC_lidar", (0.0, 0.7, 0.9), 0.3, 0.0, (0.1, 0.9, 1.0), 2.0))

    for ob in objects.values():
        if ob.type == "MESH" and not ob.data.materials:
            raise RuntimeError("%s: %s has no material" % (model_id, ob.name))
    lo, hi = bounds([v for ob in objects.values() if ob.name == "Body" for v in vertices(ob)])
    front_y = hi.y
    rear_y = lo.y
    top = hi.z
    nodes = dict(objects)
    for w in named.values():
        nodes[w.name] = w
    lamp_z = min(0.75, top * 0.45)
    nodes["Light_Front"] = empty("Light_Front", (0.0, front_y - 0.1, lamp_z))
    nodes["Light_Rear"] = empty("Light_Rear", (0.0, rear_y + 0.1, lamp_z))
    if police:
        nodes["Siren"] = empty("Siren", (0.0, 0.0, top + 0.05))
    root = bpy.data.objects.new(model_id, None)
    bpy.context.scene.collection.objects.link(root)
    for ob in nodes.values():
        ob.parent = root
    report(model_id, nodes, factor)
    export(os.path.join(out_dir, model_id + ".glb"))


def add_cargo(objects, cfg, paint, black, lamp_rear, lamp_brake):
    """A cargo box on the frame behind the cab of the truck (the pack's truck is a tractor unit; the cab is at +Y)."""
    body = objects["Body"]
    lo, hi = bounds(vertices(body))
    width = (hi.x - lo.x) * 0.99
    # the cab is the part of the body that is as high as its roof: the box starts at the rear wall of the cab
    roof = [v for v in vertices(body) if v.z > hi.z - 0.35]
    cab_rear = min(v.y for v in roof) - 0.05
    length = cfg["length"]
    height = hi.z + cfg["extra_height"] - 0.95
    centre_y = cab_rear - length * 0.5
    cargo = box("Cargo", (width, length, height), (0.0, centre_y, 0.95 + height * 0.5), paint)
    under = box("Cargo_Frame", (width * 0.9, length - 0.1, 0.22), (0.0, centre_y, 0.84), black)
    objects["Body"] = join([body, cargo, under], "Body")
    # the tail lamps move to the end of the box
    end_y = cab_rear - length
    lamps = []
    for sign in (-1.0, 1.0):
        lamps.append(box("TailLamp", (0.14, 0.06, 0.18), (sign * (width * 0.5 - 0.18), end_y - 0.02, 1.15), lamp_rear))
        lamps.append(box("BrakeLamp", (0.20, 0.06, 0.18), (sign * (width * 0.5 - 0.35), end_y - 0.02, 1.15), lamp_brake))
    old = objects.get("Lamp_R")
    if old is not None:
        bpy.data.objects.remove(old)
    objects["Lamp_R"] = join(lamps, "Lamp_R")
    objects["Bumper_R"] = box("Bumper_R", (width * 0.96, 0.20, 0.34), (0.0, end_y, 0.62), black)    # the under-run bar


def add_taxi_sign(objects, trim_white):
    """The roof sign of the taxi is part of the white trim of the source; a lit face is added on its front and back."""
    return


def add_lidar(objects, black, lidar):
    """A roof LiDAR puck of the robotaxi."""
    body = objects["Body"]
    lo, hi = bounds(vertices(body))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.17, radius2=0.14, depth=0.14)
    for v in bm.verts:
        v.co += Vector((0.0, (lo.y + hi.y) * 0.05, hi.z + 0.06))
    me = bpy.data.meshes.new("Lidar")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(lidar)
    ob = bpy.data.objects.new("Lidar", me)
    bpy.context.scene.collection.objects.link(ob)
    objects["Body"] = join([body, ob], "Body")


# ------------------------------------------------------------------------------------------------ report, export

def report(model_id, nodes, factor):
    total = 0
    print("== %s (scale %.3f)" % (model_id, factor))
    for name in sorted(nodes):
        ob = nodes[name]
        if ob.type != "MESH":
            continue
        lo, hi = bounds(vertices(ob))
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        total += tris
        print("  %-14s %5d tris  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f  %s" % (
            name, tris, lo.x + ob.location.x, hi.x + ob.location.x, lo.y + ob.location.y, hi.y + ob.location.y,
            lo.z + ob.location.z, hi.z + ob.location.z, [m.name for m in ob.data.materials]))
    print("  TOTAL %d tris" % total)


def export(path):
    """Writes the glb: no texture, no camera, no light (the materials are plain colours)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    wanted = dict(
        filepath=path, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
        export_extras=False, export_cameras=False, export_lights=False, export_materials="EXPORT",
        export_image_format="NONE", export_texcoords=False, export_normals=True, export_tangents=False,
        export_animations=False, export_skins=False, export_morph=False, export_vertex_color="NONE",
        export_draco_mesh_compression_enable=False)
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in wanted.items() if k in valid})
    print("EXPORTED", path, os.path.getsize(path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = GAME_OUT
    ids = []
    i = 0
    while i < len(argv):
        if argv[i] == "--out" and i + 1 < len(argv):
            out_dir = argv[i + 1]
            i += 2
        else:
            ids.append(argv[i])
            i += 1
    for model_id in ids or list(MODELS):
        build_model(model_id, MODELS[model_id], out_dir)
    print("CONVERT DONE")


main()
