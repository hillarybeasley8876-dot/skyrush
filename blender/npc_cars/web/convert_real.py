"""Converts the realistic CC BY / CC0 car models into the traffic and police fleet of SKYRUSH.

    python tools/gd.py blender run blender/npc_cars/web/convert_real.py -- [model ids] [--out DIR] [--cache DIR] [--survey]

        model ids   the models to build (default: all of MODELS)
        --out DIR   where the glb files are written (default: game/assets/cars/npc of this checkout)
        --cache DIR the car cache (default: SKYRUSH_CAR_CACHE, else <checkout>/../skyrush-out/cache/cars)
        --survey    print the colours under the textured faces of every source object instead of building
        --debug     print the triangles of every role of every node

The sources (Daniel Zhabotinsky's Kiri '10, Ace '11, Urban '10 and Light Commercial Truck '07, Comrade1280's minivan,
denniswoo1993's SHC MC and Grab3D's city bus; licences and sha256 in blender/npc_cars/sources.json, credits in CREDITS.md) are
fetched into the car cache by `python blender/npc_cars/fetch_sources.py`; the repository does not hold them. The whole fleet
builds in about 15 s.

What the conversion does (CONTRACTS.md 6, the node names the traffic, the police and the damage units look for):

  * every mesh of the source is joined into one working mesh and put into the game frame: the nose looks at +Y (Godot -Z),
    the car stands on z = 0, its origin is the middle of its bounds, a unit is a metre, the scale keeps the proportions (a
    model may be made a few per cent wider or narrower: a scale on X keeps the wheels round);
  * every face gets a node and a role (real_sources.py, real_rules.py): Body, Hood, Bumper_F / Bumper_R (the parts the damage
    unit tears off, their origin is the origin of the car), Mirror_L / Mirror_R, Glass, Lamp_F / Lamp_R, Wheel_FL / FR / RL /
    RR (origin on the hub, spin axis X, the wheels of an axle mirror images); the interiors, the inner surface of double
    panes and the parts hidden behind an opaque lens are dropped;
  * the textures are not exported: a textured face gets the plain material of the colour its texture shows under it. The
    paint is SH_car_paint_npc (the colour of each car is an instance uniform), SH_car_paint_taxi or SH_car_paint_police, the
    glass NPC_glass_dark, the lenses NPC_lamp_front (Lamp_F) and NPC_lamp_rear / NPC_lamp_brake (Lamp_R: of the part of a
    tail lamp that looks straight back, the inner half is the brake lens, the rest is lit all night). A material is a draw
    call per part and the traffic runs 90 cars, so a part keeps few of them (diet()): one black for every trim, the lamp
    housings in the Body, black mirrors, no chrome on the bumpers;
  * the normals of the source are kept (custom normals); a decimated part is smoothed by angle;
  * the empties Light_Front / Light_Rear sit at the lenses; the taxi gets a roof sign (TaxiSign), the robotaxi a roof LiDAR
    (Lidar), the police cars the white / navy / yellow 天巡 SKYPOL look (a navy band along the lower doors and a yellow
    pinstripe above it, cut into the mesh), a light bar (LightBar_Red, LightBar_Blue: one material each; their black base is
    part of the Body) and the Siren empty, the heavy SUV a push bar (part of Bumper_F).

The Body holds no mirror: the box collider of a car is measured from the Body. The sizes of the Body are the sizes of the
fleet table (game/ai/traffic/traffic_fleet.gd): when a car changes, the table and the physics presets
(`python tools/gd.py test res://vehicle/specs/gen_specs.gd`) change with it. The police cars are scaled so that their
presets stay close to the ones the police AI was tuned with (the patrol car is the Kiri '10 at the 4.84 m Body of the old
patrol preset).
"""
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import real_extras  # noqa: E402
import real_mesh as rm  # noqa: E402
from real_rules import Ctx  # noqa: E402
from real_sources import SOURCES  # noqa: E402

CHECKOUT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
GAME_OUT = os.path.join(CHECKOUT, "game", "assets", "cars", "npc")

# model id -> the source, the overall length in metres (or the scale of a source in another unit), an extra scale of the width
# (the Kiri '10 is a narrow 2010 compact, the SHC MC a wide show car: a factor on X keeps the wheels round) and the variant.
MODELS = {
    "sedan_ev": {"source": "kiri", "length": 4.72, "x_scale": 1.05},
    "taxi": {"source": "kiri", "length": 4.72, "x_scale": 1.05, "paint": "SH_car_paint_taxi", "taxi_sign": True},
    "police_patrol": {"source": "kiri", "length": 4.98, "x_scale": 1.07, "police": True},
    "hatch_ev": {"source": "ace", "length": 4.05},
    "suv_ev": {"source": "urban", "length": 4.55},
    "police_suv": {"source": "urban", "length": 4.95, "x_scale": 1.04, "police": True, "push_bar": True},
    "robotaxi": {"source": "shc_mc", "scale": 0.0098, "x_scale": 0.94, "lidar": True},
    "police_interceptor": {"source": "shc_mc", "scale": 0.0098, "x_scale": 0.94, "police": True},
    "van": {"source": "comrade_cars", "length": 5.00},
    "truck": {"source": "lct07", "length": 6.20},
    "bus": {"source": "city_bus", "length": 12.00},
}

# role -> (material name, sRGB colour, roughness, metallic, emission colour, emission strength, clear coat). The roles a
# source gives that are not here (matte, grey, housing, amber, reverse) are merged into black by diet().
MATERIALS = {
    "black": ("NPC_gloss_black", "08080a", 0.38, 0.0, None, 0.0, 0.3),
    "chrome": ("NPC_chrome", "c4c5c7", 0.16, 1.0, None, 0.0, 0.0),
    "silver": ("NPC_trim_silver", "aeb2b6", 0.42, 0.35, None, 0.0, 0.0),
    "glass": ("NPC_glass_dark", "232a33", 0.06, 0.0, None, 0.0, 0.8),
    "head": ("NPC_lamp_front", "f8f9ff", 0.15, 0.0, "ffffff", 0.6, 0.0),
    "tail": ("NPC_lamp_rear", "c2000c", 0.2, 0.0, "ff1218", 0.8, 0.0),
    "brake": ("NPC_lamp_brake", "c2000c", 0.2, 0.0, "ff1218", 0.8, 0.0),
    "tyre": ("NPC_tyre", "2a2a2a", 0.86, 0.0, None, 0.0, 0.0),
    "rim": ("NPC_rim", "a5a8ae", 0.32, 0.85, None, 0.0, 0.0),
    "police_black": ("NPC_police_black", "08080a", 0.34, 0.0, None, 0.0, 0.4),
    "navy": ("NPC_police_navy", "1b2a4e", 0.35, 0.0, None, 0.0, 1.0),
    "yellow": ("NPC_police_yellow", "f5c400", 0.4, 0.0, None, 0.0, 0.8),
    "bar_red": ("NPC_lightbar_red", "e60a10", 0.3, 0.0, "ff2030", 0.3, 0.0),
    "bar_blue": ("NPC_lightbar_blue", "0c1ff2", 0.3, 0.0, "2a5cff", 0.3, 0.0),
    "cargo": ("NPC_cargo_box", "d9dcdf", 0.5, 0.0, None, 0.0, 0.0),
    "roof": ("NPC_roof_white", "e4e6e8", 0.4, 0.0, None, 0.0, 0.6),
    "display": ("NPC_bus_display", "ffb000", 0.4, 0.0, "ffa020", 2.0, 0.0),
    "taxi_sign": ("NPC_taxi_sign", "f2f6f5", 0.3, 0.0, "ffffff", 1.6, 0.0),
    "lidar": ("NPC_lidar", "00b0e0", 0.3, 0.0, "1ae6ff", 2.0, 0.0),
}
# the paint roles: the name is the variant's paint
PAINT_DEFAULT = ("SH_car_paint_npc", "e6e6e6", 0.35, 0.0, None, 0.0, 1.0)
# the order of the material slots of a part
ROLE_ORDER = ["paint", "navy", "yellow", "black", "police_black", "chrome", "silver", "roof", "cargo", "display", "glass",
              "head", "tail", "brake", "tyre", "rim", "bar_red", "bar_blue", "taxi_sign", "lidar"]

WHEELS = {("F", "L"): "Wheel_FL", ("F", "R"): "Wheel_FR", ("R", "L"): "Wheel_RL", ("R", "R"): "Wheel_RR"}
# A tail lens that looks back more than this (the cosine of its normal with -Y) is the part of the lamp that looks straight
# back: its inner half is the brake lens.
BRAKE_FACING = 0.72


# ------------------------------------------------------------------------------------------------ materials

def make_material(name, hex_colour, roughness, metallic, emission, strength, clearcoat):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    rgb = rm.srgb_to_linear([int(hex_colour[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    mat.diffuse_color = (*rgb, 1.0)       # the viewport colour (the preview renders), not exported
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    for key in ("Coat Weight", "Clearcoat"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = clearcoat
    if emission:
        e = rm.srgb_to_linear([int(emission[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*e, 1.0)
                break
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def material_for(role, cfg):
    """The material of a role for a variant: the paint of the variant, the police black for the black of a police car."""
    if role == "black" and cfg.get("police"):
        role = "police_black"
    if role == "paint":
        spec = PAINT_DEFAULT
        if cfg.get("police"):
            name = "SH_car_paint_police"
        else:
            name = cfg.get("paint", spec[0])
        return make_material(name, *spec[1:])
    return make_material(*MATERIALS[role])


# ------------------------------------------------------------------------------------------------ one model

def load_source(source, cache):
    """Imports a source and joins it into one working mesh. Returns (work, names)."""
    path = os.path.join(cache, source["file"])
    if not os.path.exists(path):
        raise RuntimeError("%s is missing: run python blender/npc_cars/fetch_sources.py" % path)
    rm.reset()
    objects = rm.import_model(path, source.get("keep"))
    names = [o.name for o in objects]
    for i, ob in enumerate(objects):
        rm.tag_faces(ob, i)
    work = rm.join(objects, "Work")
    return work, names


def turn_of(source, work, names):
    front = source["front"]
    if front in rm.FRONT_TURN:
        return rm.FRONT_TURN[front]
    return source["turn"](work, names)


def survey(model_id, cfg, cache):
    source = SOURCES[cfg["source"]]
    work, names = load_source(source, cache)
    rm.to_game_frame(work, turn_of(source, work, names), cfg.get("length"), cfg.get("scale"))
    ctx = Ctx(rm.Faces(work, names), model_id)
    print("== SURVEY %s (%s): %.2f x %.2f x %.2f m" % (model_id, cfg["source"], ctx.width, ctx.length, ctx.height))
    for name in names:
        for mat in sorted(set(ctx.f.material[ctx.src(name)])):
            m = ctx.src(name) & ctx.mat(mat)
            if ctx.f.textured[m].any():
                ctx.survey(m, "%s / %s" % (name, mat))
            else:
                lo = ctx.f.lo[m].min(axis=0)
                hi = ctx.f.hi[m].max(axis=0)
                print("   PLAIN %s / %s: %d faces  x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (
                    name, mat, int(m.sum()), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))


def build_model(model_id, cfg, cache, out_dir):
    source = SOURCES[cfg["source"]]
    work, names = load_source(source, cache)
    factor = rm.to_game_frame(work, turn_of(source, work, names), cfg.get("length"), cfg.get("scale"),
                              cfg.get("x_scale", 1.0))
    rm.store_normals(work.data)
    ctx = Ctx(rm.Faces(work, names), model_id)
    source["classify"](ctx, cfg)
    ctx.check()
    ctx.drop_inner_glass()
    resolve(ctx, cfg)
    for note in ctx.notes:
        print("   " + note)
    if cfg.get("debug"):
        for node in sorted(set(ctx.node)):
            m = ctx.node == node
            roles = {r: int(ctx.f.tris[m & (ctx.role == r)].sum()) for r in sorted(set(ctx.role[m]))}
            print("   DEBUG %-16s %s" % (node, roles))

    # the parts (a node "A~b" is a piece of the part A that is decimated on its own, then joined to A)
    parts = {}
    for node in sorted(set(ctx.node)):
        if node == "drop":
            continue
        idx = np.nonzero(ctx.node == node)[0]
        ob = rm.extract(work, idx, node)
        rm.set_materials(ob, ROLE_ORDER, list(ctx.role[idx]), lambda r: material_for(r, cfg))
        parts[node] = ob
    bpy.data.objects.remove(work, do_unlink=True)
    finish_wheels(parts)
    if source.get("wheels_from"):
        donor_wheels(parts, source["wheels_from"], cache, cfg)
    decimated = set()
    for node, ratio in source.get("decimate", {}).items():
        if node in parts:
            rm.decimate(parts[node], ratio)
            decimated.add(node)
    if cfg.get("police"):
        real_extras.livery(parts, lambda r: material_for(r, cfg))
    for name, ob in parts.items():
        if name in decimated:
            rm.smooth_by_angle(ob.data)
        else:
            rm.restore_normals(ob.data)
    for name in [n for n in parts if "~" in n]:
        host = name.split("~")[0]
        if host in parts:
            parts[host] = rm.join([parts[host], parts.pop(name)], host)
        else:
            parts[host] = parts.pop(name)
            parts[host].name = host
            parts[host].data.name = host

    real_extras.backing(parts, ctx.backing, lambda r: material_for(r, cfg))
    extras = real_extras.build(model_id, cfg, parts, lambda r: material_for(r, cfg))
    for ob in list(parts.values()) + extras:
        if ob.type == "MESH":
            rm.strip(ob.data)
    nodes = dict(parts)
    for ob in extras:
        nodes[ob.name] = ob
    nodes.update(markers(ctx.lens))
    root = bpy.data.objects.new(model_id, None)
    bpy.context.scene.collection.objects.link(root)
    for ob in nodes.values():
        ob.parent = root
    report(model_id, nodes, factor)
    export(os.path.join(out_dir, model_id + ".glb"), [root] + list(nodes.values()))


def resolve(ctx, cfg):
    """Splits the placeholders: the wheel faces into the four wheels, the lamp faces into Lamp_F and Lamp_R, the lens
    role into head / tail / brake; the police cars wear the police black."""
    c = ctx.f.centre
    wheel = ctx.node == "wheel"
    for (axle, side), name in WHEELS.items():
        m = wheel & ((c[:, 1] > 0.0) if axle == "F" else (c[:, 1] <= 0.0)) & ((c[:, 0] < 0.0) if side == "L" else (c[:, 0] >= 0.0))
        ctx.node[m] = name
    for node in sorted(set(n for n in ctx.node if n.startswith("lamp"))):
        lamp = ctx.node == node
        front = lamp & (c[:, 1] > 0.0)
        ctx.node[front] = "Lamp_F" + node[4:]
        ctx.node[lamp & ~front] = "Lamp_R" + node[4:]
    lens_f = (ctx.node == "Lamp_F") & (ctx.role == "lens")
    ctx.role[lens_f] = "head"
    # The tail lens is lit all night, the brake lens only while the car brakes (TrafficLamps, CarLights): of the part of
    # a tail lamp that looks straight back, the inner half is the brake lens and the outer half the tail lens (so the
    # lamp glows from behind while the car cruises); the part that wraps around the corner is tail lens too.
    lens_r = (ctx.node == "Lamp_R") & (ctx.role == "lens")
    back = lens_r & (-ctx.f.normal[:, 1] > BRAKE_FACING)
    ctx.role[lens_r] = "tail"
    idx = np.nonzero(back)[0]
    if len(idx):
        inner = idx[np.abs(c[idx, 0]) <= np.median(np.abs(c[idx, 0]))]
        ctx.role[inner] = "brake"
    diet(ctx)
    if cfg.get("police"):
        ctx.role[ctx.role == "black"] = "police_black"
    ctx.lens = {}
    for key, roles in (("F", ("head",)), ("R", ("tail", "brake"))):
        m = np.isin(ctx.role, roles) & (ctx.node == ("Lamp_F" if key == "F" else "Lamp_R"))
        ctx.lens[key] = (ctx.f.lo[m].min(axis=0), ctx.f.hi[m].max(axis=0))


def diet(ctx):
    """Every material of a part is a draw call, and the traffic runs up to 90 cars (CONTRACTS.md: merge by material): one
    black for the trims (the gloss and the matte black of the sources), the housings, the indicators and the reversing
    lenses of the lamps go to the black of the Body (a lamp is its lenses), a mirror is black, a bumper has no chrome, a
    wheel is its tyre and its rim."""
    ctx.role[np.isin(ctx.role, ("matte", "grey"))] = "black"
    lamp = np.array([n.startswith("Lamp_") for n in ctx.node], dtype=bool)
    rest = lamp & ~np.isin(ctx.role, ("head", "tail", "brake"))
    for i in np.nonzero(rest)[0]:
        node = ctx.node[i]
        ctx.node[i] = "Body" + node[6:]          # Lamp_F~housing -> Body~housing (a piece decimated on its own)
    ctx.role[rest] = "black"
    mirror = (ctx.node == "Mirror_L") | (ctx.node == "Mirror_R")
    ctx.role[mirror] = "black"
    bumper = (ctx.node == "Bumper_F") | (ctx.node == "Bumper_R")
    ctx.role[bumper & (ctx.role == "chrome")] = "black"
    wheel = np.array([n.startswith("Wheel_") for n in ctx.node], dtype=bool)
    ctx.role[wheel & (ctx.role != "tyre") & (ctx.role != "rim")] = "tyre"


def finish_wheels(parts):
    """Puts the origin of every wheel on its hub and makes the wheels of an axle mirror images."""
    centres = {}
    for name in WHEELS.values():
        lo, hi = rm.bounds_of(rm.vertices(parts[name].data))
        centres[name] = (lo + hi) * 0.5
    targets = {}
    for left, right in (("Wheel_FL", "Wheel_FR"), ("Wheel_RL", "Wheel_RR")):
        a, b = centres[left], centres[right]
        x = (abs(a[0]) + abs(b[0])) * 0.5
        y = (a[1] + b[1]) * 0.5
        z = (a[2] + b[2]) * 0.5
        targets[left] = (-x, y, z)
        targets[right] = (x, y, z)
    for name, target in targets.items():
        rm.recentre(parts[name], target)
    lowest = min(parts[n].location.z + rm.bounds_of(rm.vertices(parts[n].data))[0][2] for n in targets)
    if lowest < 0.0:
        for name in targets:
            parts[name].location.z -= lowest


def donor_wheels(parts, donor_id, cache, cfg):
    """Replaces the four wheels with the wheels of another source (for a source whose wheels are a flat disc with a
    picture of a rim): every donor wheel is scaled to the diameter and the width of the wheel it replaces and put on its
    hub. The normals of the donor follow the scale."""
    donor = SOURCES[donor_id]
    path = os.path.join(cache, donor["file"])
    objects = rm.import_model(path, donor["wheel_keep"])
    names = [o.name for o in objects]
    for i, ob in enumerate(objects):
        rm.tag_faces(ob, i)
    work = rm.join(objects, "DonorWheels")
    rm.to_game_frame(work, turn_of(donor, work, names), scale=1.0)
    rm.store_normals(work.data)
    ctx = Ctx(rm.Faces(work, names), donor_id)
    donor["wheel_roles"](ctx)
    c = ctx.f.centre
    mid = (ctx.lo + ctx.hi) * 0.5
    for (axle, side), name in WHEELS.items():
        m = (ctx.node == "wheel") & ((c[:, 1] > mid[1]) if axle == "F" else (c[:, 1] <= mid[1])) \
            & ((c[:, 0] < mid[0]) if side == "L" else (c[:, 0] >= mid[0]))
        idx = np.nonzero(m)[0]
        old = parts[name]
        lo, hi = rm.bounds_of(rm.vertices(old.data))
        want = hi - lo
        target = old.location.copy()
        bpy.data.objects.remove(old, do_unlink=True)
        ob = rm.extract(work, idx, name)
        rm.set_materials(ob, ROLE_ORDER, list(ctx.role[idx]), lambda r: material_for(r, cfg))
        rm.recentre(ob)
        dlo, dhi = rm.bounds_of(rm.vertices(ob.data))
        have = dhi - dlo
        diameter = want[2]
        scale = np.array([want[0] / have[0], diameter / max(have[1], have[2]), diameter / max(have[1], have[2])])
        ob.data.transform(Matrix.Diagonal((*scale, 1.0)))
        a = ob.data.attributes[rm.SRC_NORMAL]
        buf = np.empty(len(ob.data.loops) * 3, dtype=np.float32)
        a.data.foreach_get("vector", buf)
        a.data.foreach_set("vector", (buf.reshape(-1, 3) / scale).astype(np.float32).ravel())
        ob.location = target
        parts[name] = ob
    bpy.data.objects.remove(work, do_unlink=True)


def markers(lens):
    """Light_Front / Light_Rear in front of the head lenses and behind the tail lenses, at their height."""
    out = {}
    lo, hi = lens["F"]
    out["Light_Front"] = rm.empty("Light_Front", (0.0, hi[1] - 0.05, (lo[2] + hi[2]) * 0.5))
    lo, hi = lens["R"]
    out["Light_Rear"] = rm.empty("Light_Rear", (0.0, lo[1] + 0.05, (lo[2] + hi[2]) * 0.5))
    return out


# ------------------------------------------------------------------------------------------------ report, export

def report(model_id, nodes, factor):
    total = 0
    surfaces = 0
    print("== %s (scale %.5f)" % (model_id, factor))
    for name in sorted(nodes):
        ob = nodes[name]
        if ob.type != "MESH":
            print("  %-14s empty at %s" % (name, tuple(round(v, 3) for v in ob.location)))
            continue
        lo, hi = rm.world_bounds(ob)
        tris = rm.triangles(ob)
        total += tris
        surfaces += len(ob.data.materials)
        print("  %-14s %6d tris  x %6.3f..%6.3f  y %6.3f..%6.3f  z %6.3f..%6.3f  %s" % (
            name, tris, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], [m.name for m in ob.data.materials]))
    lo, hi = rm.world_bounds(nodes["Body"])
    print("  BODY %.3f long, %.3f wide, top %.3f" % (hi[1] - lo[1], hi[0] - lo[0], hi[2]))
    print("  TOTAL %d tris, %d surfaces" % (total, surfaces))


def export(path, objects):
    """Writes the glb: no texture, no UV, no camera, no light (the materials are plain colours)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scratch = os.path.join(os.path.dirname(CHECKOUT), "skyrush-out", "tmp", "npc-export")
    os.makedirs(scratch, exist_ok=True)
    tmp = os.path.join(scratch, os.path.basename(path))
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    wanted = dict(
        filepath=tmp, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
        export_extras=False, export_cameras=False, export_lights=False, export_materials="EXPORT",
        export_image_format="NONE", export_texcoords=False, export_normals=True, export_tangents=False,
        export_animations=False, export_skins=False, export_morph=False, export_vertex_color="NONE",
        export_attributes=False, export_draco_mesh_compression_enable=False)
    valid = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in wanted.items() if k in valid})
    staging = path + ".part"
    shutil.copyfile(tmp, staging)
    os.replace(staging, path)
    os.remove(tmp)
    print("EXPORTED", path, os.path.getsize(path))


def default_cache():
    env = os.environ.get("SKYRUSH_CAR_CACHE")
    if env:
        return env
    return os.path.join(os.path.dirname(CHECKOUT), "skyrush-out", "cache", "cars")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = GAME_OUT
    cache = default_cache()
    ids = []
    do_survey = False
    debug = False
    i = 0
    while i < len(argv):
        if argv[i] == "--out" and i + 1 < len(argv):
            out_dir = argv[i + 1]
            i += 2
        elif argv[i] == "--cache" and i + 1 < len(argv):
            cache = argv[i + 1]
            i += 2
        elif argv[i] == "--survey":
            do_survey = True
            i += 1
        elif argv[i] == "--debug":
            debug = True
            i += 1
        else:
            ids.append(argv[i])
            i += 1
    for model_id in ids or list(MODELS):
        if model_id not in MODELS:
            raise SystemExit("unknown model %s (known: %s)" % (model_id, ", ".join(MODELS)))
        cfg = dict(MODELS[model_id], debug=debug)
        if do_survey:
            survey(model_id, cfg, cache)
        else:
            build_model(model_id, cfg, cache, out_dir)
    print("CONVERT DONE")


main()
