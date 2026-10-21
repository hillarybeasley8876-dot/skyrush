"""Materials for the NPC fleet (unit: npc_cars).

Principled BSDF only, glTF-safe node graphs (UVMap -> Mapping -> Image ->
Principled), so Godot receives the same look as the Blender preview. Colours are
sRGB hex tokens converted to linear (colors.hex_lin).

Material names follow CONTRACTS.md §2: `SH_` names are replaced at runtime by
the shared shader library, every other name is used as imported.
"""
import os

import bpy

from . import atlas

TEX = atlas.TEXTURE_DIR


def _img(path, non_color=False, alpha=False):
    """Load a texture. `alpha` keeps the alpha channel (the decal sheets)."""
    image = bpy.data.images.load(path, check_existing=True)
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    if not alpha and image.alpha_mode != "NONE":
        # an opaque sheet: the exporter can then embed it as JPEG
        image.alpha_mode = "NONE"
    return image


def _new(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat, None
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    # closed shells do not need backfaces: culling them halves the fragment work
    mat.use_backface_culling = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    return mat, (nt, bsdf)


def _coat(bsdf, amount, rough):
    for key, value in (("Coat Weight", amount), ("Coat Roughness", rough),
                       ("Clearcoat", amount), ("Clearcoat Roughness", rough)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = value


def _uv_node(nt, uv, loc):
    node = nt.nodes.new("ShaderNodeUVMap")
    node.uv_map = uv
    node.location = loc
    return node


def _image_node(nt, path, loc, non_color=False, vector=None, alpha=False):
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(os.path.join(TEX, path), non_color, alpha)
    node.location = loc
    if vector is not None:
        nt.links.new(vector, node.inputs["Vector"])
    return node


def image_mat(name, file, color=(1.0, 1.0, 1.0), roughness=0.5, metallic=0.0,
              uv="UVMap", emission=None, emission_strength=0.0, alpha=1.0,
              normal=None, normal_strength=1.0, coat=0.0, alpha_texture=False,
              scale=1.0):
    """Principled material driven by one image (albedo) plus optional normal map.

    `scale` tiles the sheet: 2.0 means the 1024 px sheet covers 0.5 m, so a
    long skirt never stretches the grain.
    """
    mat, made = _new(name)
    if made is None:
        return mat
    nt, bsdf = made
    uvn = _uv_node(nt, uv, (-1100, 0))
    vector = uvn.outputs["UV"]
    if scale != 1.0:
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.location = (-900, 0)
        mp.inputs["Scale"].default_value = (scale, scale, 1.0)
        nt.links.new(vector, mp.inputs["Vector"])
        vector = mp.outputs["Vector"]
    tex = _image_node(nt, file, (-700, 200), vector=vector,
                       alpha=alpha_texture)
    if color != (1.0, 1.0, 1.0):
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["B"].default_value = (*color[:3], 1.0)
        mix.location = (-400, 200)
        nt.links.new(tex.outputs["Color"], mix.inputs["A"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    else:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if coat > 0.0:
        _coat(bsdf, coat, 0.06)
    if emission is not None:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha_texture:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.surface_render_method = "BLENDED"
        mat.use_backface_culling = False
    if alpha < 0.999:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.surface_render_method = "BLENDED"
        mat.use_backface_culling = False
    if normal:
        ntex = _image_node(nt, normal, (-700, -350), True, vector, alpha=False)
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.location = (-400, -350)
        nmap.inputs["Strength"].default_value = normal_strength
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def plain_mat(name, color, roughness=0.5, metallic=0.0, emission=None,
              emission_strength=0.0, alpha=1.0, texture=None, uv="UVMap",
              normal=None, normal_strength=1.0, coat=0.0, texture_scale=0.5,
              albedo=None):
    """Principled material with an optional detail image (as the roughness map)."""
    mat, made = _new(name)
    if made is None:
        return mat
    nt, bsdf = made
    bsdf.inputs["Base Color"].default_value = (*color[:3], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if coat > 0.0:
        _coat(bsdf, coat, 0.06)
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission[:3], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 0.999:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.surface_render_method = "BLENDED"
    if albedo:
        atex = _image_node(nt, albedo, (-700, 320), alpha=False)
        amix = nt.nodes.new("ShaderNodeMix")
        amix.data_type = "RGBA"
        amix.blend_type = "MULTIPLY"
        amix.inputs["Factor"].default_value = 1.0
        amix.inputs["B"].default_value = (*color[:3], 1.0)
        amix.location = (-400, 320)
        nt.links.new(atex.outputs["Color"], amix.inputs["A"])
        nt.links.new(amix.outputs["Result"], bsdf.inputs["Base Color"])
    if texture or normal:
        uvn = _uv_node(nt, uv, (-1100, 0))
        if texture:
            mp = nt.nodes.new("ShaderNodeMapping")
            mp.location = (-900, 0)
            mp.inputs["Scale"].default_value = (texture_scale, texture_scale, 1.0)
            nt.links.new(uvn.outputs["UV"], mp.inputs["Vector"])
            tex = _image_node(nt, texture, (-700, -150), True, mp.outputs["Vector"],
                              alpha=False)
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Roughness"])
        if normal:
            ntex = _image_node(nt, normal, (-700, -450), True, uvn.outputs["UV"],
                           alpha=False)
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nmap.location = (-400, -450)
            nmap.inputs["Strength"].default_value = normal_strength
            nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def livery_mat(name, file, paint, roughness=0.32, metallic=0.10, uv="UV1",
               coat=0.9):
    """Body paint with a livery decal sheet in the second UV set.

    The sheet is RGBA: the RGB carries the body colour where alpha is 0 and the
    decal (navy band, pinstripe, door text) where alpha is 1, so it can be used
    directly as the base colour and still reads as a transparent decal sheet in
    the runtime car paint shader.
    """
    mat, made = _new(name)
    if made is None:
        return mat
    nt, bsdf = made
    uvn = _uv_node(nt, uv, (-1100, 0))
    tex = _image_node(nt, file, (-700, 200), vector=uvn.outputs["UV"], alpha=False)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    _coat(bsdf, coat, 0.06)
    ruv = _uv_node(nt, "UVMap", (-1100, -150))
    rough = _image_node(nt, "npc_paint_rough.png", (-700, -150), True,
                         ruv.outputs["UV"])
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    return mat
