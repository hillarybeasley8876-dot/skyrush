"""The signs, the glass and the markings of the props unit (unit: props).

Every printed board of the unit shares the sign atlas, so the signs are one
image material with an optional emission (a light box and a hard LED face).
The markings (the bay numbers, the deck text and the road paint) have their
own alpha sheets: the sign atlas has no alpha channel, so a cut-out on it
would show as a dark tile.
"""
import os

import bpy

from .materials_base import TEX, _cache, _image_material, _img, _new  # noqa: F401


# ------------------------------------------------------------------ signs
def sign():
    """Every printed board, unlit (the retro-reflective plates)."""
    if "sign" in _cache:
        return _cache["sign"]
    mat = _image_material("Prop_Sign", os.path.join(TEX, "prop_signs.png"), roughness=0.42)
    _cache["sign"] = mat
    return mat


def sign_lit(bright=False):
    """Every printed board that glows (LED panels, backlit adverts, signal faces).

    Two strengths exist, so a prop never spends more than two surfaces on
    signs: the soft glow of a light box and the hard glow of a signal face.
    """
    key = "sign_lit_bright" if bright else "sign_lit"
    if key in _cache:
        return _cache[key]
    mat = _image_material("Prop_SignLed" if bright else "Prop_SignLit",
                          os.path.join(TEX, "prop_signs.png"), roughness=0.5,
                          emission_strength=3.0 if bright else 2.4)
    _cache[key] = mat
    return mat


def sign_led_cyan():
    """The cyan LED line of the charging hub: E4, the hero sign of the frame.

    It gets its own material: `Prop_SignLed` is shared with the signal faces
    and the VMS board, and the cyan line is the only saturated element of the
    hub, so it has to be brighter than them.
    """
    if "sign_led_cyan" in _cache:
        return _cache["sign_led_cyan"]
    mat, nt, bsdf = _new("Prop_SignLedCyan")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(os.path.join(TEX, "prop_signs.png"))
    node.location = (-900, 200)
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    # the emission colour is dimmed, so the line stays a saturated cyan at E4
    # instead of clipping to white
    mul.inputs["B"].default_value = (0.0, 0.30, 0.34, 1.0)
    mul.location = (-600, 200)
    nt.links.new(node.outputs["Color"], mul.inputs["A"])
    nt.links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    nt.links.new(mul.outputs["Result"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 4.0
    bsdf.inputs["Roughness"].default_value = 0.4
    mat.use_backface_culling = True
    _cache["sign_led_cyan"] = mat
    return mat


# ------------------------------------------------------------------ special
def glass():
    """Tinted glass for booths, shelters and the metro canopy."""
    if "glass" in _cache:
        return _cache["glass"]
    mat = bpy.data.materials.new("Prop_Glass")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.30, 0.38, 0.46, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.10
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Alpha"].default_value = 0.45
    mat.surface_render_method = "BLENDED"
    mat.use_backface_culling = True
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(os.path.join(TEX, "prop_glass_diff.jpg"))
    node.location = (-500, 200)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    _cache["glass"] = mat
    return mat


def foliage():
    """The shared foliage atlas (alpha-mask cut-out leaves).

    The cards are seen from both sides, so the material is double sided, and
    the alpha is a MASK (0.5) in Godot: blended cards are not sorted per card
    and the canopy would show sorting errors and overdraw.
    """
    if "foliage" in _cache:
        return _cache["foliage"]
    mat = _image_material("Prop_Foliage", os.path.join(TEX, "prop_foliage.png"),
                          roughness=0.78, alpha_clip=True, double_sided=True)
    _cache["foliage"] = mat
    return mat


def bay_numbers():
    """The charging bay numbers: white digits with an alpha cut-out.

    They used to live in the sign atlas, where the alpha was lost, so they
    showed as dark tiles on the green bay paint.
    """
    if "bay_numbers" in _cache:
        return _cache["bay_numbers"]
    mat, nt, bsdf = _new("Prop_BayNumbers")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(os.path.join(TEX, "prop_bay_numbers.png"))
    node.location = (-500, 200)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.1
    bsdf.inputs["Roughness"].default_value = 0.6
    nt.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
    mat.surface_render_method = "DITHERED"
    mat.alpha_threshold = 0.5
    mat.use_backface_culling = False
    _cache["bay_numbers"] = mat
    return mat


def deck_text():
    """The painted marking of the sky-lane deck: white on transparent."""
    if "deck_text" in _cache:
        return _cache["deck_text"]
    mat, nt, bsdf = _new("Prop_DeckText")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(os.path.join(TEX, "prop_deck_text.png"))
    node.location = (-500, 200)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    nt.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
    mat.surface_render_method = "DITHERED"
    mat.alpha_threshold = 0.5
    mat.use_backface_culling = False
    _cache["deck_text"] = mat
    return mat


def road_marks():
    """The painted road markings of the toll plaza: white paint with an alpha cut-out.

    A small emission keeps the retroreflective paint readable at night.
    """
    if "road_marks" in _cache:
        return _cache["road_marks"]
    mat, nt, bsdf = _new("Prop_RoadMarks")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(os.path.join(TEX, "prop_road_marks.png"))
    node.location = (-500, 200)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.8
    bsdf.inputs["Roughness"].default_value = 0.75
    nt.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
    mat.surface_render_method = "DITHERED"
    mat.alpha_threshold = 0.5
    mat.use_backface_culling = False
    _cache["road_marks"] = mat
    return mat


def opal():
    """The opal diffuser of a lamp head: bright core, dimmer rim, faint petal seams."""
    if "opal" in _cache:
        return _cache["opal"]
    mat = _image_material("Prop_Opal", os.path.join(TEX, "prop_opal.png"), roughness=0.55,
                          emission_strength=2.4)
    _cache["opal"] = mat
    return mat


def lens(kind):
    """A traffic-light lens: dark tinted glass that glows when the world unit drives it."""
    key = "lens_" + kind
    if key in _cache:
        return _cache[key]
    colours = {"R": ((0.23, 0.04, 0.04), (1.0, 0.16, 0.16)),
               "A": ((0.23, 0.16, 0.02), (1.0, 0.69, 0.0)),
               "G": ((0.02, 0.19, 0.10), (0.13, 0.88, 0.44))}
    base, emit = colours[kind]
    mat, nt, bsdf = _new("Prop_Lens_" + kind)
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.1
    bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 0.0
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(os.path.join(TEX, "prop_lens_dots_nor_gl.jpg"), non_color=True)
    node.location = (-600, -300)
    normal = nt.nodes.new("ShaderNodeNormalMap")
    normal.location = (-300, -300)
    normal.inputs["Strength"].default_value = 0.5
    nt.links.new(node.outputs["Color"], normal.inputs["Color"])
    nt.links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    _cache[key] = mat
    return mat


def hologram():
    """SH_hologram: replaced in Godot by the shared shader (CONTRACTS §2)."""
    if "hologram" in _cache:
        return _cache["hologram"]
    mat, nt, bsdf = _new("SH_hologram")
    bsdf.inputs["Base Color"].default_value = (0.1, 0.9, 1.0, 0.3)
    bsdf.inputs["Roughness"].default_value = 0.2
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Alpha"].default_value = 0.30
    bsdf.inputs["Emission Color"].default_value = (0.0, 0.9, 1.0, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 3.0
    mat.surface_render_method = "BLENDED"
    mat.use_backface_culling = False      # the ring is seen from both sides
    # the shared SH_hologram shader samples the emission map of the imported
    # material, so the ring needs an artwork (without it, nothing renders)
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(os.path.join(TEX, "prop_hologram.png"))
    node.location = (-500, 200)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
    _cache["hologram"] = mat
    return mat


def neon(colour):
    """SH_neon: the shared neon-tube shader takes over in Godot."""
    key = "neon_" + "_".join("%02x" % int(c * 255) for c in colour)
    if key in _cache:
        return _cache[key]
    mat, nt, bsdf = _new("SH_neon")
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.25
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 10.0
    _cache[key] = mat
    return mat


def chevron(index, colour=(0.0, 0.90, 1.0), strength=1.8):
    """One emissive material per chevron row, so the world unit can animate them.

    The emission is an LED SEGMENT texture (a grid of emitters), not a flat
    colour: a flat emissive chevron at E9 blows out, and ART.md §2.3 allows
    E4 at most for one or two hero signs.
    """
    key = "chevron_%d" % index
    if key in _cache:
        return _cache[key]
    mat, nt, bsdf = _new("Prop_Chevron_%d" % index)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _img(os.path.join(TEX, "prop_led_chevron.png"))
    tex.location = (-900, 200)
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    mul.inputs["B"].default_value = (*colour, 1.0)
    mul.location = (-600, 200)
    nt.links.new(tex.outputs["Color"], mul.inputs["A"])
    nt.links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    nt.links.new(mul.outputs["Result"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.40
    bsdf.inputs["Metallic"].default_value = 0.0
    mat.use_backface_culling = True
    _cache[key] = mat
    return mat
