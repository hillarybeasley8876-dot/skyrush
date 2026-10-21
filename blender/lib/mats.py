"""PBR materials for SKYRUSH (core-owned). glTF-safe node graphs only, so Godot gets the same look:
UV map -> Mapping (exported as KHR_texture_transform) -> Image Textures -> Principled BSDF.

Textures come from the shared CC0 library game/assets/textures/<id>/<id>_<map>.(jpg|png)
(fetch new ones with tools/textures/fetch.py). UVs should be in metres (lib/uv.py box_uv), then
`tile_m` = how many metres one texture repeat covers (defaults to the library's real size).

    m = mats.pbr("Concrete_Pier", tex="concrete_floor_02", tint=(0.9, 0.9, 0.95))
    m = mats.pbr("SH_car_paint", color=(0.93, 0.93, 0.95), roughness=0.25)   # replaced in Godot
    m = mats.emissive("Neon_Pink", (1.0, 0.1, 0.6), strength=12.0)
"""
import json
import os

import bpy

from . import common

TEX_DIR = os.path.join(common.GAME, "assets", "textures")
_manifest = None


def tex_path(tid, kind):
    """Path of a library map (kind: diff, nor_gl, rough, ao, metal, opacity, disp) or None."""
    for ext in ("jpg", "png"):
        p = os.path.join(TEX_DIR, tid, "%s_%s.%s" % (tid, kind, ext))
        if os.path.exists(p):
            return p
    return None


def tex_size_m(tid, default=2.0):
    global _manifest
    if _manifest is None:
        path = os.path.join(TEX_DIR, "manifest.json")
        _manifest = json.load(open(path)) if os.path.exists(path) else {}
    size = (_manifest.get(tid) or {}).get("size_m")
    return float(size[0]) if size else default


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


def pbr(name, tex=None, color=(0.8, 0.8, 0.8), roughness=0.5, metallic=0.0, tile_m=None,
        normal_strength=1.0, tint=None, emission=None, emission_strength=0.0, alpha=None,
        use_rough_map=True, uv_map=None):
    """Create or reuse material `name`. With `tex`, the library maps found are wired in; `tint`
    multiplies the albedo (glTF baseColorFactor). Without `tex`, plain colour/roughness/metallic."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Base Color"].default_value = (*color[:3], 1.0)
    if tex:
        _wire_textures(nt, bsdf, tex, tile_m or tex_size_m(tex), normal_strength, tint, use_rough_map, uv_map)
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission[:3], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha is not None:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.surface_render_method = "BLENDED" if alpha < 0.999 else "DITHERED"
    return mat


def _wire_textures(nt, bsdf, tex, tile_m, normal_strength, tint, use_rough_map, uv_map):
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.location = (-1100, 0)
    if uv_map:
        uv.uv_map = uv_map
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.location = (-900, 0)
    s = 1.0 / max(tile_m, 1e-4)
    mapping.inputs["Scale"].default_value = (s, s, 1.0)
    nt.links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    diff = tex_path(tex, "diff")
    if diff:
        d = _tex_node(nt, diff, False, mapping, -600, 300)
        if tint:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs["B"].default_value = (*tint[:3], 1.0)
            nt.links.new(d.outputs["Color"], mix.inputs["A"])
            nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        else:
            nt.links.new(d.outputs["Color"], bsdf.inputs["Base Color"])
    rough = tex_path(tex, "rough")
    if rough and use_rough_map:
        r = _tex_node(nt, rough, True, mapping, -600, 0)
        nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    nor = tex_path(tex, "nor_gl")
    if nor:
        n = _tex_node(nt, nor, True, mapping, -600, -300)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.location = (-300, -300)
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    metal = tex_path(tex, "metal")
    if metal:
        m = _tex_node(nt, metal, True, mapping, -600, -600)
        nt.links.new(m.outputs["Color"], bsdf.inputs["Metallic"])


def emissive(name, color, strength=8.0, base=(0.02, 0.02, 0.02)):
    """Light-emitting surface (neon tube, light bar, lit sign). Godot gets emission energy=strength."""
    return pbr(name, color=base, roughness=0.35, emission=color, emission_strength=strength)


def image_material(name, path, roughness=0.5, emission_strength=0.0, alpha_clip=False):
    """Material from a single generated image (signs, liveries, decals). UV 0..1 = whole image."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = pbr(name, roughness=roughness)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _image(path, False)
    node.location = (-500, 200)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if emission_strength > 0.0:
        nt.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha_clip:
        nt.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.surface_render_method = "DITHERED"
    return mat
