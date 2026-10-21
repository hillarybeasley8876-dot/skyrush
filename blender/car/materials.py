"""Materials for the hero Roadster (dossier §7 + ART.md §5).

Every material is a plain Principled BSDF plus image textures (glTF-safe node
graphs), so Godot imports the same look. The `SH_*` names are replaced at runtime
by the shared shader library (CONTRACTS.md §2); the rest are used as imported.

The whole set is built ONCE by build_all(): Blender names a second material with
the same name "M_BlackTrim.001", and Godot would then import two different
materials for the same surface. Every module asks for a material with get().
"""
import os

import bpy

from car import paths

_REGISTRY = {}


def _fresh(name):
    """The one material with that name, with a clean node tree.

    The datablock is reused (never removed and re-created): removing it would
    empty the material slot of every object that already uses it.
    """
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (0, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, bsdf


def _img(path, non_color=False):
    if not path or not os.path.exists(path):
        return None
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def get(name):
    """The one and only material with that name (None if it was never built)."""
    return _REGISTRY.get(name) or bpy.data.materials.get(name)


def pbr(name, color="#FFFFFF", rough=0.5, metal=0.0, base_map=None, normal_map=None,
        rough_map=None, uv="UVMap", tile=1.0, uv_m=1.0, emission=None,
        emission_strength=0.0, alpha=1.0, clearcoat=0.0, normal_strength=1.0,
        alpha_from_map=False, specular=None):
    """Build (or rebuild) a Principled material with optional image textures.

    `tile` is the physical size of one texture repeat in METRES and `uv_m` the
    number of metres one UV unit covers in this material's UV space (the
    normalised box projection covers the whole model, so uv_m = the model's
    length). The Mapping scale is uv_m / tile.
    """
    mat, b = _fresh(name)
    b.inputs["Base Color"].default_value = paths.srgb(color)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Alpha"].default_value = alpha
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = clearcoat
        b.inputs["Coat Roughness"].default_value = 0.12
    if specular is not None and "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = specular
    if alpha < 0.999:
        mat.surface_render_method = "BLENDED"
    if base_map is None and normal_map is None and rough_map is None:
        _REGISTRY[name] = mat
        return mat
    nt = mat.node_tree
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = uv
    uvn.location = (-1200, 0)
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.location = (-1000, 0)
    scale = uv_m / max(tile, 1e-6)
    mp.inputs["Scale"].default_value = (scale, scale, 1.0)
    nt.links.new(uvn.outputs["UV"], mp.inputs["Vector"])
    _wire(nt, b, mp, mat, base_map, normal_map, rough_map, alpha_from_map,
           emission, normal_strength)
    if emission is not None:
        if base_map is None:
            b.inputs["Emission Color"].default_value = paths.srgb(emission)
        b.inputs["Emission Strength"].default_value = emission_strength
    _REGISTRY[name] = mat
    return mat


def _wire(nt, b, mp, mat, base_map, normal_map, rough_map, alpha_from_map,
          emission, normal_strength):
    """Wire the image textures of a material into its Principled BSDF."""
    if base_map:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = _img(base_map)
        n.location = (-750, 300)
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        nt.links.new(n.outputs["Color"], b.inputs["Base Color"])
        if emission is not None:
            nt.links.new(n.outputs["Color"], b.inputs["Emission Color"])
        if alpha_from_map:
            nt.links.new(n.outputs["Alpha"], b.inputs["Alpha"])
            mat.surface_render_method = "BLENDED"
    if rough_map:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = _img(rough_map, True)
        n.location = (-750, 0)
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        nt.links.new(n.outputs["Color"], b.inputs["Roughness"])
    if normal_map:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = _img(normal_map, True)
        n.location = (-750, -300)
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.location = (-500, -300)
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
