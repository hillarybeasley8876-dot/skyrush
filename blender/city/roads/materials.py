"""Materials for the road kit.

Two families:

* `SH_*` — the shared shader materials of the project (game/shaders/materials).
  Godot replaces them at runtime with the library's .tres, so the glTF only
  carries their colour: the maps are stripped before the export.
* `Road_*` — the local materials of the road kit. They carry their own albedo,
  normal and ORM maps, so the glTF has to keep them: the maps are written into
  the shared city texture folder (game/assets/city/_tex) and every tile
  references the same files.

The real colour of a Road_* material lives in the glTF's baseColorFactor and
its albedo is a neutral detail map, so a white pot is white because the factor
says so. The foliage and the ivy keep their colour in the texture (a magenta
bract cannot come from a grey factor) and their factor stays white.
"""
import os

import bpy

import sys
sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))
from lib import mats  # noqa: E402

from city.roads import texgen  # noqa: E402

# the Road_* materials: (texture set, sRGB colour or None, UV size in m, metallic)
ROAD_MATERIALS = {
    "Road_Tactile_Strip": ("tactile", "#E8C34A", 0.6, 0.0),
    "Road_Planter_White": ("pot", "#EDEDE8", 0.6, 0.0),
    "Road_Planter_Box": ("pot", "#EDEDE8", 0.6, 0.0),
    "Road_Planter_Soil": ("soil", "#4A3B2E", 0.5, 0.0),
    "Road_Foliage_Bougainvillea": ("leaf_boug", None, 0.5, 0.0),
    "Road_Foliage_Privet": ("leaf_privet", None, 0.5, 0.0),
    "Road_Ivy": ("ivy", None, 1.0, 0.0),
    "Road_Steel_Girder": ("steel", "#9AA4AE", 1.5, 0.65),
    "Road_Expansion_Joint": ("joint", "#4A4E52", 0.6, 0.50),
    "Road_Tunnel_Enamel": ("enamel", "#ECEFF0", 1.2, 0.0),
    "Road_Tunnel_Dark": ("dark", "#3A3D42", 2.0, 0.0),
    "Road_Tunnel_Stripe": ("stripe", "#2C6BD8", 0.5, 0.0),
    "Road_Sign_Green": ("enamel", "#0F7A4A", 1.2, 0.0),
    "Road_Planter_Row": ("row", None, 9.3, 0.0),
}

# the materials whose UV is not square: the planted strip is a long thin band
UV_SIZE = {
    "Road_Planter_Row": (9.3, 0.22),
}

# the materials whose alpha is a cut-out mask (the foliage cards and the ivy)
ALPHA_MATERIALS = ("Road_Foliage_Bougainvillea", "Road_Foliage_Privet", "Road_Ivy")

# the factors the glTF carries, in linear space: {material: (r, g, b, a)}
FACTORS = {}


def linear(hex_colour):
    """An sRGB hex colour as a linear RGBA tuple."""
    def one(v):
        c = v / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    text = hex_colour.lstrip("#")
    r = int(text[0:2], 16)
    g = int(text[2:4], 16)
    b = int(text[4:6], 16)
    return (one(r), one(g), one(b), 1.0)


def _image(path, non_color):
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def _tex_node(nt, path, non_color, mapping, x, y):
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _image(path, non_color)
    node.location = (x, y)
    nt.links.new(mapping.outputs["Vector"], node.inputs["Vector"])
    return node


def _road_material(name, sets, colour, size_m, metallic):
    """Build one Road_* material: albedo, normal and ORM, with the real colour."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (200, 0)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (520, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.location = (-1000, 0)
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.location = (-800, 0)
    size_u, size_v = UV_SIZE.get(name, (size_m, size_m))
    mapping.inputs["Scale"].default_value = (1.0 / max(size_u, 1e-4),
                                             1.0 / max(size_v, 1e-4), 1.0)
    nt.links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    diff = _tex_node(nt, sets["diff"], False, mapping, -560, 320)
    if colour is None:
        nt.links.new(diff.outputs["Color"], bsdf.inputs["Base Color"])
        factor = (1.0, 1.0, 1.0, 1.0)
    else:
        factor = linear(colour)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.location = (-200, 320)
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["B"].default_value = factor
        nt.links.new(diff.outputs["Color"], mix.inputs["A"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Base Color"].default_value = factor
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = 0.5
    orm = _tex_node(nt, sets["orm"], True, mapping, -560, 0)
    nt.links.new(orm.outputs["Color"], bsdf.inputs["Roughness"])
    nt.links.new(orm.outputs["Color"], bsdf.inputs["Metallic"])
    nor = _tex_node(nt, sets["nor"], True, mapping, -560, -320)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.location = (-260, -320)
    nm.inputs["Strength"].default_value = 1.0
    nt.links.new(nor.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if name in ALPHA_MATERIALS:
        nt.links.new(diff.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.surface_render_method = "DITHERED"
    FACTORS[name] = factor
    return mat


def strip_shader_textures():
    """Drop the image maps of the SH_* materials before the export.

    Godot replaces them with the shared shader library, and the library's own
    maps are the ones the art direction approved: the tiles must not carry a
    second copy of the library's textures.
    """
    for mat in bpy.data.materials:
        if not mat.name.startswith("SH_") or not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE":
                node.image = None


def build(tex_dir=None, sets=None):
    """Create every material the road kit needs; returns {name: material}."""
    sets = sets or texgen.build_all(tex_dir or os.path.expanduser("~/m/skyrush/tmp/roads/tex"))
    out = {}
    for name, (set_name, colour, size_m, metallic) in ROAD_MATERIALS.items():
        out[name] = _road_material(name, sets[set_name], colour, size_m, metallic)
    _shader_materials(out)
    return out


def _shader_materials(out):
    """The shared shader materials (replaced at runtime) and the emissive ones."""
    def m(name, *args, **kw):
        out[name] = mats.pbr(name, *args, **kw)
        return out[name]

    m("SH_wet_asphalt", tex="asphalt_02", color=(0.62, 0.62, 0.64), roughness=0.42, tile_m=3.0)
    m("SH_concrete_pier", tex="concrete", color=(0.74, 0.73, 0.70), roughness=0.82, tile_m=4.0)
    m("SH_concrete_barrier", tex="concrete_wall_008", color=(0.78, 0.79, 0.76),
      roughness=0.78, tile_m=2.71)
    m("SH_soffit_blue", tex="concrete", color=(0.66, 0.67, 0.70), roughness=0.72, tile_m=4.0)
    m("SH_road_marking_white", tex="concrete_pavement", color=(0.91, 0.91, 0.88),
      roughness=0.42, tile_m=1.8)
    m("SH_road_marking_yellow", tex="concrete_pavement", color=(0.95, 0.76, 0.05),
      roughness=0.42, tile_m=1.8, tint=(1.0, 0.80, 0.06))
    m("SH_kerb", color=(0.62, 0.61, 0.59), roughness=0.55)
    m("SH_sidewalk", color=(0.66, 0.645, 0.62), roughness=0.62)
    # emission tier E3 (dossier §2.3): the LED tubes, not the hero tier
    out["Road_Led_Soffit"] = mats.emissive("Road_Led_Soffit", (0.353, 0.239, 1.0), strength=4.5)
    out["Road_Led_Bridge"] = mats.emissive("Road_Led_Bridge", (0.239, 0.482, 1.0), strength=4.5)
    out["Road_Led_Tunnel"] = mats.emissive("Road_Led_Tunnel", (1.0, 0.914, 0.784), strength=6.0)
    out["Road_Led_Stripe"] = mats.emissive("Road_Led_Stripe", (0.11, 0.71, 0.42), strength=3.0)
