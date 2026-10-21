"""Materials for the Bund (bund unit).

Every surface has maps: the granite ashlar, the brick, the glazed tile, the iron, the
paving, the flood wall, the copper, the clock dial, the flag cloth, the bronze, the
lantern paper, the foliage, the LED cove, the moulding trim sheet and the far-field wash.
The facades carry their AO / dirt / macro variation in a colour attribute (COLOR_0) that
multiplies the base texture - the gold comes from the lights, not from an emission on the
stone.
"""
import os

import bpy

from . import texbase

BUND_TEX = texbase.OUT


def _image(tex):
    """The path of a generated map (jpg, or png for the wash cards with their alpha)."""
    for ext in ("jpg", "png"):
        p = os.path.join(BUND_TEX, "%s_diff.%s" % (tex, ext))
        if os.path.exists(p):
            return p
    p = os.path.join(BUND_TEX, "%s.png" % tex)
    if os.path.exists(p):
        return p
    return os.path.join(BUND_TEX, "%s_diff.jpg" % tex)


def _pbr(name, tex, tile, rough=0.55, normal=0.8, tint=None, emission=None,
         strength=0.0, colour_attribute=False, cull=True, emission_tex=None,
         emission_strength=None, metallic=0.0):
    """A textured Principled material.

    `colour_attribute` multiplies the map by COLOR_0 (the facade's AO / dirt / hue);
    `emission_tex` is a second image that drives the emission (the lit window interiors,
    the pyramid's glow)."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Base Color"].default_value = (*(tint or (0.7, 0.7, 0.7)), 1.0)
    bsdf.inputs["Alpha"].default_value = 1.0
    mat.use_backface_culling = cull
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.location = (-1200, 0)
    map_node = nt.nodes.new("ShaderNodeMapping")
    map_node.location = (-1000, 0)
    s = 1.0 / max(tile, 1e-4)
    map_node.inputs["Scale"].default_value = (s, s, 1.0)
    nt.links.new(uv.outputs["UV"], map_node.inputs["Vector"])
    base = bsdf.inputs["Base Color"]
    if tex:
        img = bpy.data.images.load(_image(tex), check_existing=True)
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        t.location = (-700, 300)
        nt.links.new(map_node.outputs["Vector"], t.inputs["Vector"])
        colour_in = t.outputs["Color"]
        if tint is not None:
            # multiply the map with the tint (a darker / warmer variant of the same stone)
            tint_node = nt.nodes.new("ShaderNodeRGB")
            tint_node.location = (-700, 60)
            tint_node.outputs[0].default_value = (*tint, 1.0)
            tmix = nt.nodes.new("ShaderNodeMix")
            tmix.data_type = "RGBA"
            tmix.blend_type = "MULTIPLY"
            tmix.location = (-600, 300)
            tmix.inputs["Factor"].default_value = 1.0
            nt.links.new(t.outputs["Color"], tmix.inputs[6])
            nt.links.new(tint_node.outputs[0], tmix.inputs[7])
            colour_in = tmix.outputs[2]
        if colour_attribute:
            attr = nt.nodes.new("ShaderNodeVertexColor")
            attr.location = (-700, 0)
            attr.layer_name = "Col"
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.location = (-450, 300)
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(colour_in, mix.inputs[6])              # A
            nt.links.new(attr.outputs["Color"], mix.inputs[7])   # B
            nt.links.new(mix.outputs[2], base)
        else:
            nt.links.new(colour_in, base)
        for kind, socket in (("nor_gl", "Normal"), ("rough", "Roughness")):
            path = os.path.join(BUND_TEX, "%s_%s.jpg" % (tex, kind))
            if not os.path.exists(path):
                continue
            node = nt.nodes.new("ShaderNodeTexImage")
            node.image = bpy.data.images.load(path, check_existing=True)
            node.location = (-700, -300)
            nt.links.new(map_node.outputs["Vector"], node.inputs["Vector"])
            if kind == "nor_gl":
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nm.location = (-450, -300)
                nm.inputs["Strength"].default_value = normal
                nt.links.new(node.outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
            else:
                nt.links.new(node.outputs["Color"], bsdf.inputs["Roughness"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if emission_tex:
        img = bpy.data.images.load(_image(emission_tex), check_existing=True)
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.location = (-700, 500)
        nt.links.new(uv.outputs["UV"], node.inputs["Vector"])
        nt.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = (
            strength if emission_strength is None else emission_strength)
    return mat


def _emissive_map(name, tex, strength, base=(0.02, 0.02, 0.02), cull=True):
    """A material whose emission comes from a texture (clock dial, cove, flood curtain)."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.45
    mat.use_backface_culling = cull
    img = bpy.data.images.load(_image(tex), check_existing=True)
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    t.location = (-600, 200)
    nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def build():
    """Create (or fetch) every material the Bund uses; returns role -> material."""
    from . import ao, data
    m = {}
    # The stone family: every dossier colour is its own material, so the row reads as
    # one quarry with a slightly different tone per building. The hue is the base colour
    # tint, not a vertex colour - glTF clamps COLOR_0 to 1.0 and would lose it.
    used = set((s["stone_family"], s["colour"]) for s in data.SPECS)
    used.add(("brick", "brick_band"))      # the red band of the Palace Hotel
    for fam, hue in sorted(used):
        col = ao.HUE.get(hue, (1.0, 1.0, 1.0))
        if fam == "granite":
            # three seed variants of the same quarry: the buildings pick one
            for i in range(3):
                m["stone_granite_%s_v%d" % (hue, i)] = _pbr(
                    "Bund_Stone_Granite_%s_%d" % (hue, i), "granite_%d" % i, 2.4,
                    rough=0.62, normal=1.0, tint=col, colour_attribute=True)
        elif fam == "brick":
            m["stone_brick_%s" % hue] = _pbr("Bund_Brick_%s" % hue, "brick_0", 1.2,
                                            rough=0.78, normal=1.0, tint=col,
                                            colour_attribute=True)
        elif fam == "tile":
            m["stone_tile_%s" % hue] = _pbr("Bund_Tile_%s" % hue, "tile_white", 1.0,
                                           rough=0.32, normal=0.7, tint=col,
                                           colour_attribute=True)
        else:
            m["stone_coffee_%s" % hue] = _pbr("Bund_Coffee_%s" % hue, "tile_coffee", 1.0,
                                             rough=0.38, normal=0.7, tint=col,
                                             colour_attribute=True)
    m["trim"] = _pbr("Bund_Trim_Moulding", "trim_sheet", 1.0, rough=0.55, normal=1.0,
                     colour_attribute=True)
    m["glasslit"] = _pbr("Bund_Window_Lit", "interior_atlas", 1.0, rough=0.22, normal=0.4,
                         emission_tex="interior_glow", emission_strength=3.2)
    # the unlit glass is never a black hole: it keeps a readable albedo and a faint
    # interior glow, so the frames and the curtains read (B-ART4)
    m["glassdark"] = _pbr("Bund_Window_Dark", "interior_atlas", 1.0, rough=0.08, normal=0.4,
                          tint=(0.70, 0.71, 0.76), emission_tex="interior_glow",
                          emission_strength=0.30)
    m["iron"] = _pbr("Bund_Iron", "iron_dark", 1.0, rough=0.55, normal=0.8)
    m["roof"] = _pbr("Bund_Roof_Tar", "roof_tar", 2.0, rough=0.9, normal=0.6)
    # the domes are neutral stone: the gold comes from the crown floods and the far-field
    # wash (art dossier rule - no emission on the stone itself)
    m["dome"] = _pbr("Bund_Dome_Stone", "granite_0", 2.4, rough=0.5, normal=1.0,
                     colour_attribute=True)
    # the Peace Hotel pyramid: dark copper lit from below (dossier 5.4: #21C08B)
    # the tile is 1/4.5: the copper texture covers 4.5 m, so its standing seams keep
    # their 0.45 m spacing on the pyramid (the emission uses the raw UVs, so the glow
    # runs once from the base to the apex)
    m["rooflit"] = _pbr("Bund_Copper_Lit", "copper_pyramid", 1.0 / 4.5, rough=0.42,
                        normal=1.4, emission_tex="pyramid_glow", emission_strength=2.5)
    # the Bank of China roof: glazed blue-green cylinder tile, lit from the eaves
    m["tileteal"] = _pbr("Bund_Tile_Teal", "tile_teal", 1.0, rough=0.22, normal=0.9,
                         emission_tex="tile_teal", emission_strength=0.55)
    m["clock"] = _emissive_map("Bund_Clock_Dial", "clock_dial", 2.0,
                                base=(0.9, 0.88, 0.8), cull=False)
    m["red"] = _pbr("Bund_Flag_Red", "flag_red", 0.6, rough=0.75, normal=1.0, cull=False)
    m["goldstrip"] = _emissive_map("Bund_Cove_Gold", "cove_gold", 2.0,
                                   base=(0.3, 0.26, 0.2), cull=False)
    # the bull is cast bronze: a metal, so it reads dark with a sky reflection on the
    # shoulders instead of a flat olive lump
    m["bronze"] = _pbr("Bund_Bronze", "bronze", 1.0, rough=0.34, normal=0.9,
                       metallic=0.85)
    m["lantern"] = _emissive_map("Bund_Lantern_Paper", "lantern_paper", 2.2,
                                 base=(0.8, 0.5, 0.25), cull=False)
    m["leaf"] = _pbr("Bund_Foliage", "foliage", 1.0, rough=0.8, normal=0.6, cull=False)
    m["flood"] = _emissive_map("Bund_Flood_Wash", "flood_cascade", 2.4,
                               base=(0.03, 0.1, 0.22), cull=False)
    m["paving"] = _pbr("Bund_Paving", "paving", 1.8, rough=0.7, normal=0.9)
    m["wall"] = _pbr("Bund_Flood_Wall", "wall", 2.4, rough=0.85, normal=1.2)
    m["granite"] = _pbr("Bund_Stone_Granite", "granite_0", 2.4, rough=0.62, normal=1.0,
                        colour_attribute=True)
    m["planter"] = _pbr("Bund_Planter", "wall", 1.4, rough=0.8, normal=1.0)
    m["grass"] = _pbr("Bund_Lawn", "grass", 1.4, rough=0.85, normal=0.7)
    m["hedge"] = _pbr("Bund_Hedge", "hedge", 1.0, rough=0.85, normal=0.8)
    # the far-field wash: one card per facade, sampling the baked light map (washmap.py)
    m["wash"] = _emissive_map("Bund_Wash", "wash_atlas", 1.2, base=(0.0, 0.0, 0.0),
                              cull=False)
    # the crown wash: the shell of the crown form, with the base-to-top ramp
    m["washcrown"] = _emissive_map("Bund_Crown_Wash", "wash_crown", 1.2,
                                   base=(0.0, 0.0, 0.0), cull=False)
    # the clock stage of the Customs House is lit by its own crown floods, like every
    # other crown - it is a separate material so the floods do not hit the facade
    m["clockstone"] = m["stone_granite_granite_light_v1"]
    return m
