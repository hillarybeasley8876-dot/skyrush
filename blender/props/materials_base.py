"""The shared base of the props materials (unit: props).

The image helpers every material of the unit is built with: the texture
loader, the fresh Principled material and the one-image material (an atlas
cell with an optional emission and an optional alpha cut-out).

The families live in `materials.py`, the signs and the markings in
`materials_marks.py`.
"""
import os

import bpy

ROOT = os.path.expanduser("~/m/skyrush")
# The generated maps live in a scratch folder; the Blender exporter writes the
# copies the .glb files reference into game/assets/props/_tex/, so the game
# holds one copy of every atlas (lead note: IMPORT-CHURN).
TEX = os.path.join(ROOT, "tmp", "props", "tex")

_cache = {}


def _img(path, non_color=False):
    image = bpy.data.images.load(path, check_existing=True)
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    return image


def _new(name):
    """A fresh Principled material (never reuse: the scene is reset between props)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    return mat, nt, bsdf


def _image_material(name, path, roughness=0.5, emission_strength=0.0, alpha_clip=False,
                    emission=None, double_sided=False):
    """Base colour (and optionally emission) from one image, UV 0..1 per atlas cell."""
    if name in _cache:
        return _cache[name]
    mat, nt, bsdf = _new(name)
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(path)
    node.location = (-500, 200)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if emission is not None:
        nt.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    elif emission_strength > 0.0:
        nt.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    bsdf.inputs["Roughness"].default_value = roughness
    if alpha_clip:
        nt.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.surface_render_method = "DITHERED"
        mat.alpha_threshold = 0.5
    # every surface is single sided: a sign quad gets a back panel, a closed
    # mesh needs no back face (and the mirrored text of a sign seen from behind
    # disappears with it).
    mat.use_backface_culling = not double_sided
    _cache[name] = mat
    return mat
