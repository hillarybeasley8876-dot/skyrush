"""The materials of the hero car: black and white, nothing else.

The paint names start with SH_: the game swaps them for its own shader materials at load
(core/materials/material_library.gd), so the Principled versions here are what Blender shows and
what the glb carries as the fallback. Every other material is a plain colour: the car has no
texture, so the export has no image and Godot extracts nothing next to the glb.
"""
import bpy

WHITE = (0.925, 0.929, 0.937)
BLACK = (0.011, 0.011, 0.013)


def _principled(name, base, metallic=0.0, rough=0.5, coat=0.0, coat_rough=0.03, emission=None,
                strength=1.0, alpha=1.0, culling=True):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (base[0], base[1], base[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = coat_rough
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
    mat.use_backface_culling = culling
    return mat


def make_all():
    """Every material of the car by name."""
    m = {}
    # the two paints: white pearl and gloss black (the game's SH_car_paint shaders replace these)
    m["SH_car_paint"] = _principled("SH_car_paint", WHITE, 0.0, 0.18, coat=1.0, culling=False)
    m["SH_car_paint_black"] = _principled("SH_car_paint_black", BLACK, 0.0, 0.16, coat=1.0, culling=False)
    # glass: neutral smoke, the interior shows through
    m["SH_glass_smoke"] = _principled("SH_glass_smoke", (0.02, 0.022, 0.026), 0.0, 0.04, alpha=0.5,
                                      culling=False)
    # trims and the dark insides
    m["M_BlackTrim"] = _principled("M_BlackTrim", BLACK, 0.0, 0.5)
    m["M_InnerDark"] = _principled("M_InnerDark", (0.005, 0.005, 0.006), 0.0, 0.85, culling=False)
    m["M_CabinBlack"] = _principled("M_CabinBlack", (0.012, 0.012, 0.014), 0.0, 0.6)
    m["M_SeatWhite"] = _principled("M_SeatWhite", (0.78, 0.78, 0.79), 0.0, 0.7, culling=False)
    m["M_Hardware"] = _principled("M_Hardware", (0.30, 0.30, 0.31), 1.0, 0.45)
    m["M_Mirror"] = _principled("M_Mirror", (0.8, 0.8, 0.82), 1.0, 0.02)
    m["M_Plate"] = _principled("M_Plate", (0.8, 0.8, 0.78), 0.0, 0.35)
    # the lamps: the energy is the strength the game reads (the brake light doubles it on the brake)
    m["M_Headlamp"] = _principled("M_Headlamp", (0.0, 0.0, 0.0), 0.0, 0.2, emission=(0.88, 0.93, 1.0),
                                  strength=8.0)
    m["M_BrakeLight"] = _principled("M_BrakeLight", (0.02, 0.0, 0.0), 0.0, 0.25, emission=(0.95, 0.02, 0.02),
                                    strength=3.2)
    m["M_Screen"] = _principled("M_Screen", (0.0, 0.0, 0.0), 0.0, 0.15, emission=(0.75, 0.85, 1.0),
                                strength=2.0)
    # wheels
    m["M_Tyre"] = _principled("M_Tyre", (0.012, 0.012, 0.013), 0.0, 0.62)
    m["M_RimBlack"] = _principled("M_RimBlack", (0.02, 0.02, 0.023), 0.85, 0.3, coat=0.5)
    m["M_RimSilver"] = _principled("M_RimSilver", (0.86, 0.86, 0.88), 1.0, 0.18)
    m["M_Disc"] = _principled("M_Disc", (0.55, 0.55, 0.56), 1.0, 0.38, culling=False)
    m["M_CaliperWhite"] = _principled("M_CaliperWhite", (0.88, 0.88, 0.9), 0.0, 0.3)
    # the nozzles of the rocket trim: dark metal
    m["M_Nozzle"] = _principled("M_Nozzle", (0.06, 0.06, 0.065), 1.0, 0.4, culling=False)
    return m


# which of the concept's materials becomes which of ours
CONCEPT_MAP = {
    "Paint 1 Carmine": "SH_car_paint",
    "Paint 2 Carmine": "SH_car_paint_black",
    "Glass": "SH_glass_smoke",
    "Mechanical": "M_BlackTrim",
    "Material_2": "M_BlackTrim",
    "Panel Sides": "M_InnerDark",
    "Interior 1": "M_CabinBlack",
    "Interior 2": "M_CabinBlack",
    "Interior 3 Carmine": "M_SeatWhite",
    "Floormat": "M_CabinBlack",
    "Dashboard": "M_Screen",
    "Hardware": "M_Hardware",
    "Mirror": "M_Mirror",
    "Headlight": "M_Headlamp",
    "Brakelight": "M_BrakeLight",
    "Signallight": "M_BlackTrim",
    "License": "M_Plate",
    "Tireside": "M_Tyre",
    "Tiretread": "M_Tyre",
    "Rim1": "M_RimSilver",
    "Rim2": "M_RimBlack",
    "Disc": "M_Disc",
    "Brake": "M_CaliperWhite",
}


def remap(ob, mats):
    """Swaps the concept's materials of an object for ours; slots that end up equal are merged."""
    me = ob.data
    names = []
    for slot in me.materials:
        names.append(CONCEPT_MAP.get(slot.name, slot.name) if slot is not None else "M_BlackTrim")
    unique = []
    for n in names:
        if n not in unique:
            unique.append(n)
    index_of = [unique.index(n) for n in names]
    for p in me.polygons:
        p.material_index = index_of[p.material_index] if p.material_index < len(index_of) else 0
    me.materials.clear()
    for n in unique:
        me.materials.append(mats[n])
