"""Material set for the SKYRUSH props unit.

Five tileable families carry every surface of every prop (metal, mineral,
panel, paint, bark) plus the lit canopy soffit; one shared sign atlas carries
every printed board.  A prop therefore needs only a handful of materials no
matter how many colours it uses: the colour of a part is its VERTEX TINT, not
its material.

Material names follow CONTRACTS.md §2: `SH_` names are replaced at runtime by
the shared shader library, every other name is used as imported.

The helpers live in `materials_base.py`, the signs and the markings in
`materials_marks.py` (they are re-exported here, so `M.sign()` still works).
"""
import os

import bpy

from .materials_base import TEX, _cache, _image_material, _img, _new  # noqa: F401
from .materials_marks import (bay_numbers, chevron, deck_text, foliage,  # noqa: F401
                              glass, hologram, lens, neon, opal, road_marks,
                              sign, sign_lit, sign_led_cyan)

# ------------------------------------------------------------------ families
def family(key):
    """One of the tileable families, or a named variant of one.

    The family texture is a neutral light grey; the colour of the part comes
    from its vertex tint, which the Color Attribute node multiplies into the
    base colour (so the Blender preview matches the game).

    The `paint` family is a DIELECTRIC: a painted booth, a dispenser or a
    white post must keep its value under a canopy, not mirror the night sky
    the way bare metal does.
    """
    if key in _cache:
        return _cache[key]
    name = "Prop_" + key.capitalize()
    mat, nt, bsdf = _new(name)
    base = key
    rough = {"metal": 0.45, "mineral": 0.80, "panel": 0.42, "paint": 1.0,
             "bark": 0.85}.get(base, 0.5)
    metallic = 0.8 if base == "metal" else 0.0
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    mat.use_backface_culling = True

    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.location = (-1200, 0)
    diff = nt.nodes.new("ShaderNodeTexImage")
    diff.image = _img(os.path.join(TEX, "prop_%s_diff.jpg" % base))
    diff.location = (-900, 300)
    nt.links.new(uv.outputs["UV"], diff.inputs["Vector"])
    tint = nt.nodes.new("ShaderNodeVertexColor")
    tint.layer_name = "Col"
    tint.location = (-900, 60)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    mix.location = (-600, 200)
    nt.links.new(diff.outputs["Color"], mix.inputs["A"])
    nt.links.new(tint.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])

    rough_tex = nt.nodes.new("ShaderNodeTexImage")
    rough_tex.image = _img(os.path.join(TEX, "prop_%s_rough.jpg" % base), non_color=True)
    rough_tex.location = (-900, -180)
    nt.links.new(uv.outputs["UV"], rough_tex.inputs["Vector"])
    nt.links.new(rough_tex.outputs["Color"], bsdf.inputs["Roughness"])

    nor = nt.nodes.new("ShaderNodeTexImage")
    nor.image = _img(os.path.join(TEX, "prop_%s_nor_gl.jpg" % base), non_color=True)
    nor.location = (-900, -420)
    nt.links.new(uv.outputs["UV"], nor.inputs["Vector"])
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-600, -420)
    nmap.inputs["Strength"].default_value = 1.0
    nt.links.new(nor.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    _cache[key] = mat
    return mat


def soffit():
    """The canopy soffit: white panels with a dim glow (E0.08).

    The soffit used to be a uniformly emissive white plane (E2), which blew
    the whole canopy out and hid the LED panels.  Now the ceiling is a white
    panel (roughness 0.5) with a small glow, and the recessed LED panels are
    separate emissive geometry, so the ceiling keeps its value structure.
    """
    if "soffit" in _cache:
        return _cache["soffit"]
    mat, nt, bsdf = _new("Prop_Soffit")
    bsdf.inputs["Roughness"].default_value = 0.50
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.957, 0.910, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 0.08
    mat.use_backface_culling = True
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.location = (-1200, 0)
    diff = nt.nodes.new("ShaderNodeTexImage")
    diff.image = _img(os.path.join(TEX, "prop_panel_diff.jpg"))
    diff.location = (-900, 300)
    nt.links.new(uv.outputs["UV"], diff.inputs["Vector"])
    tint = nt.nodes.new("ShaderNodeVertexColor")
    tint.layer_name = "Col"
    tint.location = (-900, 60)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    mix.location = (-600, 200)
    nt.links.new(diff.outputs["Color"], mix.inputs["A"])
    nt.links.new(tint.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Emission Color"])
    nor = nt.nodes.new("ShaderNodeTexImage")
    nor.image = _img(os.path.join(TEX, "prop_panel_nor_gl.jpg"), non_color=True)
    nor.location = (-900, -420)
    nt.links.new(uv.outputs["UV"], nor.inputs["Vector"])
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-600, -420)
    nmap.inputs["Strength"].default_value = 1.0
    nt.links.new(nor.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    _cache["soffit"] = mat
    return mat


def light_pool(kind="gas"):
    """The baked ground light pool of a canopy: an unlit additive sheet.

    In Godot the material is ADDITIVE and UNSHADED (the .tres), so the pool
    ADDS light to the concrete instead of painting an opaque white sheet over
    the forecourt.  Here it is an emission shader, which is the same look.
    """
    key = "lightpool_" + kind
    if key in _cache:
        return _cache[key]
    mat = bpy.data.materials.new("Prop_LightPool" + kind.capitalize())
    mat.use_nodes = True
    nt = mat.node_tree
    for node in list(nt.nodes):
        if node.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(node)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.location = (-300, 0)
    emit.inputs["Strength"].default_value = 0.7
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _img(os.path.join(TEX, "prop_lightpool_%s.png" % kind))
    tex.location = (-600, 0)
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    mat.use_backface_culling = True
    _cache[key] = mat
    return mat


def surface():
    """Placeholder material: the real one is picked by the surface name.

    The builders pass this to every part; `Prop.mesh` replaces it with the
    family material of the part's surface (and writes the vertex tint).
    """
    return family("metal")


def streaks():
    """The alpha-masked rain-streak decal hung under a canopy edge."""
    if "streaks" in _cache:
        return _cache["streaks"]
    mat = _image_material("Prop_Streaks", os.path.join(TEX, "prop_streaks.png"),
                          roughness=0.8, alpha_clip=True)
    _cache["streaks"] = mat
    return mat


def clear_cache():
    """Drop cached materials (Blender's factory reset removes them from the scene)."""
    _cache.clear()
