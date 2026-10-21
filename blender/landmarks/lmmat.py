"""Materials for SKYRUSH landmarks (unit-owned; core lib/mats.py stays untouched).

`tex_mat` wires image maps into a Principled BSDF with a Mapping node so the
same sheet can tile in metres; `emit_mat` makes a dark surface with an emissive
image (LED dot grids); `glow` is a plain emissive (tier energies from ref/art
DOSSIER.md 2.3: E1 windows .. E4 hero crowns).
"""
import os

import bpy

from lib import common, mats

TEX = os.path.join(os.path.expanduser("~/m/skyrush/blender"), "landmarks", "src_tex")


def hexcol(code):
    """'#RRGGBB' -> linear float triple (sRGB decoded)."""
    c = [int(code[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def _img(name, non_color=False):
    """Load a texture from the unit folder, else from the shared CC0 library."""
    path = os.path.join(TEX, name)
    if not os.path.exists(path):
        path = os.path.join(common.GAME, "assets", "textures", name)
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def _new(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat, None
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    return mat, (nt, bsdf)


def _mapping(nt, tile, uv_map, x=-1100):
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.location = (x, 0)
    if uv_map:
        uv.uv_map = uv_map
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.location = (x + 200, 0)
    mp.inputs["Scale"].default_value = (tile[0], tile[1], 1.0)
    nt.links.new(uv.outputs["UV"], mp.inputs["Vector"])
    return mp


def _tex(nt, mp, name, non_color, x, y, strength=None):
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = _img(name, non_color)
    node.location = (x, y)
    nt.links.new(mp.outputs["Vector"], node.inputs["Vector"])
    if strength is not None and "Strength" in node.inputs:
        node.inputs["Strength"].default_value = strength
    return node


def jpeg_copy(src, quality=85, max_size=0, out_name=None):
    """Re-encode a texture as JPEG (much smaller glb) and optionally downscale it.

    `src` is a file in the unit texture folder or a path relative to the shared
    CC0 library. The master file stays in the folder as the delivered source;
    the JPEG is only what the material embeds. The copy is refreshed whenever
    the master is newer, so a rebuilt texture never ships a stale JPEG.
    Returns the file name to use."""
    src_path = src if os.path.isabs(src) else os.path.join(TEX, src)
    if not os.path.exists(src_path):
        src_path = os.path.join(common.GAME, "assets", "textures", src)
    stem = out_name or (os.path.basename(src_path).rsplit(".", 1)[0] + ".jpg")
    dst = os.path.join(TEX, stem)
    fresh = (not os.path.exists(dst)
             or os.path.getmtime(src_path) > os.path.getmtime(dst) + 0.5)
    if not fresh and max_size:
        # the cached copy must match the resolution we were asked for
        try:
            cached = bpy.data.images.load(dst)
            fresh = max(cached.size) != max_size
            bpy.data.images.remove(cached)
        except RuntimeError:
            fresh = True
    if fresh:
        img = bpy.data.images.load(src_path)
        try:
            _ = img.pixels[0]      # force the lazy buffer to load
        except (RuntimeError, IndexError):
            pass
        if max_size and max(img.size) > max_size:
            w, h = img.size
            if w >= h:
                img.scale(max_size, max(1, int(round(max_size * h / float(w)))))
            else:
                img.scale(max(1, int(round(max_size * w / float(h)))), max_size)
        img.file_format = "JPEG"
        try:
            bpy.context.scene.render.image_settings.quality = quality
        except (AttributeError, TypeError):
            pass
        # write to a scratch file and only replace the cache when the bytes
        # differ (the IMPORT-CHURN lead note: a rebuild must not touch the
        # files that did not change)
        tmp_dir = os.path.expanduser("~/m/skyrush/tmp/landmarks/export")
        os.makedirs(tmp_dir, exist_ok=True)
        tmp = os.path.join(tmp_dir, stem)
        img.filepath_raw = tmp
        img.save()
        bpy.data.images.remove(img)
        import texio
        texio.copy_if_changed(tmp, dst)
        try:
            os.remove(tmp)
        except OSError:
            pass
    return stem


def gltf_output_group():
    """The 'glTF Material Output' node group the glTF exporter looks for.

    Its `Occlusion` input is what makes the exporter write an
    `occlusionTexture` into the glb."""
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is not None:
        return ng
    ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    ng.interface.new_socket("Occlusion", socket_type="NodeSocketFloat")
    for nm, dv in (("Thickness", 0.0), ("Dispersion", 0.0),
                   ("Iridescence Factor", 0.0), ("Iridescence Thickness Minimum", 100.0)):
        try:
            s = ng.interface.new_socket(nm, socket_type="NodeSocketFloat")
            s.default_value = dv
        except (AttributeError, TypeError, RuntimeError):
            pass
    ng.nodes.new("NodeGroupOutput")
    ng.nodes.new("NodeGroupInput")
    return ng


def orm_mat(name, diff=None, normal=None, orm=None, color=(0.8, 0.8, 0.8),
            tile=(1.0, 1.0), normal_strength=1.0, uv_map=None, ao_strength=1.0,
            metallic=1.0, roughness=0.5, pack=True):
    """PBR material with an ORM map: R = ambient occlusion, G = roughness,
    B = metallic.

    The AO is wired into the glTF exporter's 'Occlusion' input, so the glb
    carries a real `occlusionTexture` and not just a baked-in base colour.
    With `pack` off only the AO channel is used and the roughness / metalness
    stay the material's own constants (the loader must not re-interpret the
    packed channels as sRGB)."""
    mat, ctx = _new(name)
    if ctx is None:
        return mat
    nt, bsdf = ctx
    bsdf.inputs["Base Color"].default_value = (*color[:3], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    mp = _mapping(nt, tile, uv_map)
    if diff:
        t = _tex(nt, mp, diff, False, -600, 320)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if normal:
        t = _tex(nt, mp, normal, True, -600, -340)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.location = (-330, -340)
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if orm:
        t = _tex(nt, mp, orm, True, -600, 60)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.mode = "RGB"
        sep.location = (-420, 60)
        nt.links.new(t.outputs["Color"], sep.inputs["Color"])
        if pack:
            nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
            nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        grp = nt.nodes.new("ShaderNodeGroup")
        grp.node_tree = gltf_output_group()
        grp.location = (-420, -140)
        nt.links.new(sep.outputs["Red"], grp.inputs["Occlusion"])
    return mat


def shrink_material_images(mat, max_size=1024, quality=80):
    """Replace a material's images with downscaled JPEG copies (wiring untouched).

    Keeps the shared library look but stops a 2K sheet from adding megabytes to
    every glb that uses it."""
    lib = os.path.join(common.GAME, "assets", "textures")
    for node in list(mat.node_tree.nodes):
        if node.type != "TEX_IMAGE" or node.image is None:
            continue
        src = bpy.path.abspath(node.image.filepath)
        if not src or not os.path.exists(src):
            continue
        rel = os.path.relpath(src, lib)
        stem = os.path.basename(rel).rsplit(".", 1)[0]
        out = jpeg_copy(rel, quality, max_size, "%s_%d.jpg" % (stem, max_size))
        node.image = bpy.data.images.load(os.path.join(TEX, out), check_existing=True)
    return mat


def tex_mat(name, diff=None, rough=None, normal=None, ao=None, emit=None, emit_strength=0.0,
             color=(0.8, 0.8, 0.8), roughness=0.5, metallic=0.0, tile=(1.0, 1.0),
             normal_strength=1.0, uv_map=None, emission=None, emission_strength=0.0,
             alpha_mask=False, alpha_blend=False, alpha_value=None, tint=None):
    """PBR material with optional diffuse / roughness / normal / ao / emission maps.
    `tile` = texture repeats per UV unit; with UVs measured in metres use
    1/tile_size_m (a 4 m sheet -> 0.25).
    `tint` = multiplier for the base colour (the texture is kept, the colour is not).
    `alpha_mask` = cut the surface with the diffuse texture's alpha (glTF MASK 0.5).
    `alpha_blend` = fade the surface with the diffuse texture's alpha (glTF BLEND)."""
    mat, ctx = _new(name)
    if ctx is None:
        return mat
    nt, bsdf = ctx
    bsdf.inputs["Base Color"].default_value = (*color[:3], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mp = _mapping(nt, tile, uv_map)
    if diff:
        t = _tex(nt, mp, diff, False, -600, 320)
        if ao:
            a = _tex(nt, mp, ao, True, -600, -140)
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.location = (-400, 320)
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(t.outputs["Color"], mix.inputs["A"])
            nt.links.new(a.outputs["Color"], mix.inputs["B"])
            nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        elif tint is not None:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.location = (-400, 320)
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs["B"].default_value = (*tint[:3], 1.0)
            nt.links.new(t.outputs["Color"], mix.inputs["A"])
            nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        else:
            nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_mask:
            # ROUND(alpha) -> the exporter reads it as glTF alphaMode MASK (cutoff 0.5)
            rnd = nt.nodes.new("ShaderNodeMath")
            rnd.operation = "ROUND"
            rnd.location = (-400, -60)
            nt.links.new(t.outputs["Alpha"], rnd.inputs[0])
            nt.links.new(rnd.outputs[0], bsdf.inputs["Alpha"])
            mat.surface_render_method = "DITHERED"
            mat.use_transparent_shadow = True
        elif alpha_blend:
            # a straight alpha link -> the exporter reads it as glTF alphaMode BLEND
            nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.surface_render_method = "BLENDED"
            mat.use_transparent_shadow = True
        if alpha_value is not None:
            # a constant alpha: the exporter puts it into baseColorFactor.a
            val = nt.nodes.new("ShaderNodeValue")
            val.location = (-600, -140)
            val.outputs[0].default_value = float(alpha_value)
            nt.links.new(val.outputs[0], bsdf.inputs["Alpha"])
            mat.surface_render_method = "BLENDED"
            mat.use_transparent_shadow = True
    if rough:
        t = _tex(nt, mp, rough, True, -600, 60)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Roughness"])
    if normal:
        t = _tex(nt, mp, normal, True, -600, -340)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.location = (-330, -340)
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emit:
        t = _tex(nt, mp, emit, False, -600, 520)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    elif emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission[:3], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def emit_mat(name, image, color, strength=2.5, tile=(1.0, 1.0), base=(0.03, 0.03, 0.04),
             uv_map=None, rough=0.4):
    """Dark backing surface + emissive image (LED dot grids, band lights).

    The image is exported as the glTF emissive texture; `color` is only used for
    the (unlit) backing so the gaps read in the right hue. The world unit animates
    the tint at runtime via StandardMaterial3D.emission / emission_energy_multiplier."""
    mat, ctx = _new(name)
    if ctx is None:
        return mat
    nt, bsdf = ctx
    bsdf.inputs["Base Color"].default_value = (*base[:3], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    mp = _mapping(nt, tile, uv_map)
    t = _tex(nt, mp, image, False, -600, 320)
    nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def glow(name, color, strength=4.0, base=(0.04, 0.04, 0.05), rough=0.35):
    """Plain emissive surface (neon strips, crowns, sign faces)."""
    mat, ctx = _new(name)
    if ctx is None:
        return mat
    nt, bsdf = ctx
    bsdf.inputs["Base Color"].default_value = (*base[:3], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Emission Color"].default_value = (*color[:3], 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def bridge_materials():
    """The material set for the three Shanghai bridges (Nanpu, Lupu, Waibaidu)."""
    from lib import mats
    return {
        "nanpu_concrete": tex_mat("LM_NANPU_Concrete", diff="formwork_diff.png",
                                  normal="formwork_nor.png", rough="formwork_rough.png",
                                  color=hexcol("#D8D8D2"), roughness=0.68,
                                  tile=(0.25, 0.25), normal_strength=0.9),
        "nanpu_cable": tex_mat("LED_Nanpu_Cables", color=hexcol("#F2F2F0"), roughness=0.4,
                               metallic=0.3, tile=(0.4, 0.4), emission=hexcol("#C9D6E8"),
                               emission_strength=0.32),
        "sign_red": glow("LED_Nanpu_Sign", hexcol("#FF2020"), strength=5.0),
        "sign_back": tex_mat("LM_NANPU_SignPlate", diff="metal_dark_diff.png",
                             normal="metal_dark_nor.png", rough="metal_dark_rough.png",
                             color=hexcol("#141416"), roughness=0.4, metallic=0.2,
                             tile=(0.55, 0.55), normal_strength=0.8),
        "collider": tex_mat("LM_BRIDGE_Collider", color=(0.1, 0.1, 0.1), roughness=0.9),
        "nanpu_deck_led": glow("LED_Nanpu_DeckEdge", hexcol("#2F7BFF"), strength=3.0),
        "nanpu_wash": glow("LED_Nanpu_WashLow", hexcol("#FFF4E6"), strength=1.2),
        "nanpu_wash_dim": glow("LED_Nanpu_WashHigh", hexcol("#FFF4E6"), strength=0.6),
        "nanpu_under": glow("LED_Nanpu_UnderStrip", hexcol("#FF8A2A"), strength=2.0),
        "nanpu_avia": glow("LED_Aviation_Nanpu", hexcol("#FF2A3A"), strength=8.0),
        "lupu_steel": tex_mat("LM_LUPU_Steel", diff="metal_white_diff.png",
                              normal="metal_white_nor.png", rough="metal_white_rough.png",
                              color=hexcol("#E8EAEA"), roughness=0.4, metallic=0.3,
                              tile=(0.4, 0.4), normal_strength=0.8),
        "rainbow_bands": [glow("LED_Lupu_Band_%d" % (i + 1), hexcol(c), strength=1.4)
                             for i, c in enumerate(("#FF2A2A", "#FF8A2A", "#FFE24A", "#3AFF6A",
                                                  "#3AC8FF", "#6A4CFF", "#FF4CDA"))],
        "lupu_sign": glow("LED_Lupu_Sign", hexcol("#D9161C"), strength=4.5),
        "waibaidu_steel": tex_mat("LM_WAIBAIDU_Steel", diff="steel_paint_diff.png",
                                  rough="steel_paint_rough.png", normal="rivets_nor.png",
                                  color=hexcol("#9AA0A6"), roughness=0.5, metallic=0.6,
                                  tile=(0.5, 0.5), normal_strength=0.7),
        "waibaidu_granite": shrink_material_images(
            mats.pbr("LM_WAIBAIDU_Granite", tex="granite_tile_03", color=(1.0, 1.0, 1.0),
                     roughness=0.65, metallic=0.0, tile_m=2.0, tint=(0.30, 0.30, 0.31)), 512, 80),
        "timber": tex_mat("LM_WAIBAIDU_Timber", diff="timber_diff.png",
                          normal="timber_nor.png", rough="timber_rough.png",
                          color=hexcol("#6B5741"), roughness=0.72, tile=(0.5, 0.5),
                          normal_strength=1.0),
        "waibaidu_led": glow("LED_Waibaidu", hexcol("#FFC24D"), strength=3.2),
    }
