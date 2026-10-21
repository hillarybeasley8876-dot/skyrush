"""The Godot side of the props unit: the shared materials and the import
overrides (unit: props).

The four tileable families are the same StandardMaterial3D in every prop, so
they are EXTERNAL materials: `game/assets/props/materials/prop_<family>.tres`.
The .glb files reference them by name, and the importer override in the
`.glb.import` file points the glTF material at the .tres.

Two things make this work (CONTRACTS.md §2):
  * the family texture is a neutral light grey and the colour of a part is its
    VERTEX TINT, so the material has `vertex_color_use_as_albedo = true` and
    the imported COLOR_0 tints it;
  * the UVs of a part are metres divided by the tile size, so the texture
    repeats without a transform (uv1_scale stays 1).

    /usr/bin/python3 blender/props/godot_assets.py
"""
import json
import os
import struct

ROOT = os.path.expanduser("~/m/skyrush")
GAME = os.path.join(ROOT, "game")
TEX_DIR = os.path.join(GAME, "assets", "props", "_tex")
MAT_DIR = os.path.join(GAME, "assets", "props", "materials")
STREET = os.path.join(GAME, "assets", "props", "street")
SITES = os.path.join(GAME, "assets", "props", "sites")

# family -> (material name, metallic, roughness)
# The roughness maps are written in the glTF layout (G = roughness, R and B
# unused), so the material reads the GREEN channel and the scalar multiplies
# it.  The metal family carries the raw steel value of ART.md (rough 0.45)
# through its map: the map averages 0.391, so 1.15 brings the mean to 0.45.
FAMILIES = {
    "metal": ("Prop_Metal", 0.8, 1.15),
    "mineral": ("Prop_Mineral", 0.0, 1.0),
    "panel": ("Prop_Panel", 0.0, 1.0),
    "paint": ("Prop_Paint", 0.0, 1.0),
    "bark": ("Prop_Bark", 0.0, 1.0),
}
# the material names the importer override points at a .tres
EXTERNAL = {
    "Prop_Metal": "prop_metal",
    "Prop_Mineral": "prop_mineral",
    "Prop_Panel": "prop_panel",
    "Prop_Paint": "prop_paint",
    "Prop_Bark": "prop_bark",
    "Prop_Soffit": "prop_soffit",
    "Prop_LightPoolGas": "prop_lightpool_gas",
    "Prop_LightPoolCharge": "prop_lightpool_charge",
    "Prop_Foliage": "prop_foliage",
    "Prop_BayNumbers": "prop_bay_numbers",
    "Prop_DeckText": "prop_deck_text",
    "Prop_RoadMarks": "prop_road_marks",
}


def _find(stem):
    """The path of a shared map in _tex (the exporter may write .jpg or .png)."""
    for ext in ("jpg", "png"):
        path = os.path.join(TEX_DIR, "%s.%s" % (stem, ext))
        if os.path.exists(path):
            return path
    return None


def _res(path, res_id):
    """An ExtResource line for a file in the game folder."""
    rel = os.path.relpath(path, GAME).replace(os.sep, "/")
    return '[ext_resource type="Texture2D" path="res://%s" id="%s"]' % (rel, res_id)


def _family_tres(family):
    """The .tres of one tileable family."""
    name, metallic, roughness = FAMILIES[family]
    diff = _find("prop_%s_diff" % family)
    nor = _find("prop_%s_nor_gl" % family)
    rough = _find("prop_%s_rough" % family)
    if not diff:
        return None
    lines = ["[gd_resource type=\"StandardMaterial3D\" load_steps=%d format=3]" % 4,
             ""]
    lines.append(_res(diff, "1_diff"))
    if nor:
        lines.append(_res(nor, "2_nrm"))
    if rough:
        lines.append(_res(rough, "3_rgh"))
    lines += ["", "[resource]",
              'resource_name = "%s"' % name,
              "albedo_texture = ExtResource(\"1_diff\")",
              "metallic = %s" % metallic,
              "metallic_specular = 0.5",
              # the roughness map carries the absolute value, so the scalar scales it
              "roughness = %s" % roughness]
    if rough:
        lines.append("roughness_texture = ExtResource(\"3_rgh\")")
        # the map is written in the glTF layout: the roughness is in GREEN
        lines.append("roughness_texture_channel = 1")
    if nor:
        lines += ["normal_enabled = true",
                  "normal_texture = ExtResource(\"2_nrm\")",
                  "normal_scale = 1.0"]
    lines.append("vertex_color_use_as_albedo = true")
    return "\n".join(lines) + "\n"


def _soffit_tres():
    """The canopy soffit: white panels with a dim glow (ART.md §4.10).

    A uniform E2 white plane blew the canopy out and hid the LED panels; the
    ceiling now keeps its value structure and the LED panels are separate
    emissive geometry.
    """
    diff = _find("prop_panel_diff")
    nor = _find("prop_panel_nor_gl")
    rough = _find("prop_panel_rough")
    if not diff:
        return None
    lines = ["[gd_resource type=\"StandardMaterial3D\" load_steps=4 format=3]", "",
             _res(diff, "1_diff")]
    if nor:
        lines.append(_res(nor, "2_nrm"))
    if rough:
        lines.append(_res(rough, "3_rgh"))
    lines += ["", "[resource]",
              'resource_name = "Prop_Soffit"',
              'albedo_texture = ExtResource("1_diff")',
              "metallic = 0.0",
              "roughness = 1.0"]
    if rough:
        lines += ["roughness_texture = ExtResource(\"3_rgh\")",
                  "roughness_texture_channel = 1"]
    if nor:
        lines += ["normal_enabled = true",
                  'normal_texture = ExtResource("2_nrm")']
    lines += ["vertex_color_use_as_albedo = true",
              "emission_enabled = true",
              "emission = Color(1, 0.957, 0.91, 1)",
              "emission_energy_multiplier = 0.08"]
    return "\n".join(lines) + "\n"


def _light_pool_tres(kind):
    """The baked ground light pool of a canopy: ADDITIVE and UNSHADED.

    The pool adds light to the concrete instead of painting an opaque white
    sheet over the forecourt (ART.md §4.10).
    """
    path = _find("prop_lightpool_%s" % kind)
    if not path:
        return None
    name = "Prop_LightPool" + kind.capitalize()
    lines = ["[gd_resource type=\"StandardMaterial3D\" load_steps=2 format=3]", "",
             _res(path, "1_pool"), "", "[resource]",
             'resource_name = "%s"' % name,
             'albedo_texture = ExtResource("1_pool")',
             "albedo_color = Color(0, 0, 0, 1)",
             "transparency = 1",
             "blend_mode = 1",          # ADD
             "shading_mode = 0",        # UNSHADED
             "roughness = 0.9",
             "emission_enabled = true",
             'emission_texture = ExtResource("1_pool")',
             "emission = Color(1, 0.957, 0.91, 1)",
             "emission_energy_multiplier = 0.7"]
    return "\n".join(lines) + "\n"


def _cutout_tres(name, stem, emission=None, energy=1.0, roughness=0.6):
    """A .tres for a marking with an alpha cut-out (the bay numbers, the deck text)."""
    path = _find(stem)
    if not path:
        return None
    lines = ["[gd_resource type=\"StandardMaterial3D\" load_steps=2 format=3]", "",
             _res(path, "1_cut"), "", "[resource]",
             'resource_name = "%s"' % name,
             'albedo_texture = ExtResource("1_cut")',
             "roughness = %s" % roughness,
             "metallic = 0.0",
             "transparency = 2",              # ALPHA_SCISSOR
             "alpha_scissor_threshold = 0.5",
             "alpha_antialiasing_mode = 2",  # ALPHA_TO_COVERAGE
             "cull_mode = 2"]                 # DISABLED
    if emission is not None:
        lines += ["emission_enabled = true",
                  "emission_texture = ExtResource(\"1_cut\")",
                  "emission = Color(%s, 1)" % emission,
                  "emission_energy_multiplier = %s" % energy]
    return "\n".join(lines) + "\n"


def _foliage_tres():
    """The foliage: an alpha MASK with the culling off (ART.md §4.9).

    Blended cards are not sorted per card: the canopy of a plane tree would
    show sorting errors and overdraw.  The mask keeps a depth, and the
    backlight lifts the leaves against the night sky.
    """
    path = _find("prop_foliage")
    if not path:
        return None
    lines = ["[gd_resource type=\"StandardMaterial3D\" load_steps=2 format=3]", "",
             _res(path, "1_fol"), "", "[resource]",
             'resource_name = "Prop_Foliage"',
             'albedo_texture = ExtResource("1_fol")',
             "roughness = 0.78",
             "metallic = 0.0",
             "transparency = 2",          # ALPHA_SCISSOR
             "alpha_scissor_threshold = 0.5",
             "alpha_antialiasing_mode = 2",   # ALPHA_TO_COVERAGE
             "cull_mode = 2",             # DISABLED: the cards are seen from both sides
             "backlight_enabled = true",
             "backlight = Color(0.431, 0.478, 0.165, 1)"]
    return "\n".join(lines) + "\n"


def _write(path, text):
    """Write a file only when its bytes changed (Godot re-imports on an mtime move)."""
    if os.path.exists(path) and open(path, "r").read() == text:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)
    return True


def write_materials():
    """Write the shared .tres files of the unit."""
    written = []
    for family in FAMILIES:
        text = _family_tres(family)
        if text:
            path = os.path.join(MAT_DIR, "prop_%s.tres" % family)
            if _write(path, text):
                written.append(path)
    for name, text in (("prop_soffit", _soffit_tres()),
                       ("prop_lightpool_gas", _light_pool_tres("gas")),
                       ("prop_lightpool_charge", _light_pool_tres("charge")),
                       ("prop_foliage", _foliage_tres()),
                       ("prop_bay_numbers", _cutout_tres("Prop_BayNumbers",
                                                         "prop_bay_numbers",
                                                         emission="1, 1, 1", energy=1.1)),
                       ("prop_deck_text", _cutout_tres("Prop_DeckText",
                                                      "prop_deck_text",
                                                      roughness=0.7)),
                       ("prop_road_marks", _cutout_tres("Prop_RoadMarks",
                                                        "prop_road_marks",
                                                        emission="1, 1, 1",
                                                        energy=0.8, roughness=0.75))):
        if text:
            path = os.path.join(MAT_DIR, "%s.tres" % name)
            if _write(path, text):
                written.append(path)
    return written


# ------------------------------------------------------------------ imports
def _glb_materials(path):
    """The material names of a packed .glb."""
    with open(path, "rb") as fh:
        data = fh.read()
    pos = 12
    while pos + 8 <= len(data):
        size, kind = struct.unpack("<II", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + size]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk.decode("utf-8"))
            return [m.get("name", "") for m in doc.get("materials", [])]
        pos += 8 + size
    return []


def _import_path(glb):
    return glb + ".import"


def _patch_one(glb):
    """Point the external materials of one .glb at the shared .tres files."""
    path = _import_path(glb)
    if not os.path.exists(path):
        return False
    names = [n for n in _glb_materials(glb) if n in EXTERNAL]
    if not names:
        return False
    with open(path, "r") as fh:
        text = fh.read()
    block = "_subresources={\n\"materials\": {\n"
    for i, name in enumerate(sorted(names)):
        block += '"%s": {\n"use_external/enabled": true,\n"use_external/path": ' \
                 '"res://assets/props/materials/%s.tres"\n}%s\n' % (
                     name, EXTERNAL[name], "," if i < len(names) - 1 else "")
    block += "}\n}\n"
    start = text.find("_subresources={")
    if start < 0:
        new = text.replace("gltf/naming_version=2", block + "gltf/naming_version=2", 1)
    else:
        end = text.find("gltf/naming_version=2", start)
        new = text[:start] + block + text[end:]
    if new == text:
        return False
    with open(path, "w") as fh:
        fh.write(new)
    return True


def patch_imports():
    """Point every prop at the shared materials (the importer override)."""
    changed = []
    for folder in (STREET, SITES):
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".glb"):
                continue
            if _patch_one(os.path.join(folder, name)):
                changed.append(name)
    return changed


def run():
    """Write the materials and patch the import files."""
    written = write_materials()
    changed = patch_imports()
    print("GODOT ASSETS %d materials, %d imports patched" % (len(written), len(changed)))
    for path in written:
        print("  %s" % os.path.basename(path))
    return written, changed


if __name__ == "__main__":
    run()
