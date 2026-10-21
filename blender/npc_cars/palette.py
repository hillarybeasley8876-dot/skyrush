"""Material palette for one NPC vehicle (unit: npc_cars).

Returns a dict of Blender materials keyed by role. Names starting with `SH_` are
replaced at runtime by the shared shader library (CONTRACTS.md §2); the rest are
used as imported. All colours come from colors.py (sRGB hex -> linear).
"""
import os

from . import atlas, colors, materials

TEX = atlas.TEXTURE_DIR

# plate slots in the shared plate atlas (4 columns x 3 rows of 512x160)
PLATE_COLS = 4
PLATE_ROWS = 3
PLATE_W, PLATE_H = 512, 160
PLATE_ATLAS = (2048, 480)


def plate_rect(index):
    """Rect of one vehicle's plate inside the shared plate atlas."""
    col = index % PLATE_COLS
    row = index // PLATE_COLS
    return (col * PLATE_W, row * PLATE_H, (col + 1) * PLATE_W, (row + 1) * PLATE_H)


def vehicle_materials(spec, police=False, plate_index=0):
    """Material set for one vehicle spec."""
    mats = {}
    paint_hex = spec.get("paint", colors.PAINT_WHITE)
    paint = colors.hex_lin(paint_hex)
    if spec.get("livery") == "police":
        mats["paint"] = materials.livery_mat(
            "SH_car_paint_police", "livery_%s.png" % spec["name"], paint)
    elif spec.get("livery") == "taxi":
        mats["paint"] = materials.livery_mat(
            "SH_car_paint_taxi", "livery_taxi.png", paint)
        # the skirt wears its own material: the runtime paint shader would
        # multiply the livery sheet with the teal and turn the silver dark
        mats["skirt"] = materials.plain_mat(
            "NPC_taxi_skirt", colors.hex_lin(colors.TAXI_SKIRT), roughness=0.30,
            metallic=0.12, coat=0.9, texture="npc_paint_rough.png",
            albedo="npc_paint_detail.png")
    else:
        mats["paint"] = materials.plain_mat(
            "SH_car_paint_npc", paint, roughness=0.30, metallic=0.12,
            texture="npc_paint_rough.png", coat=0.9, albedo="npc_paint_detail.png")
    mats["paint_plain"] = materials.plain_mat(
        "NPC_paint_plain", paint, roughness=0.30, metallic=0.12,
        texture="npc_paint_rough.png", coat=0.9, albedo="npc_paint_detail.png")
    # dark tinted glass: opaque, so the cabin reads as a window at 30-80 m
    # the cars show their modelled cabin through the glass; the box vehicles
    # have no interior, so their windows stay dark and opaque
    glass_alpha = 0.55 if spec.get("kind", "car") == "car" else 1.0
    mats["glass"] = materials.image_mat(
        "SH_glass_tinted", "npc_glass_grime.png", color=colors.hex_lin(colors.GLASS_TINT),
        roughness=0.06, alpha=glass_alpha)
    # the wheel: a rubber tyre (the tread and the sidewall lettering come
    # from the normal map) and a bright alloy rim with five twin spokes
    mats["wheel_tyre"] = materials.plain_mat(
        "NPC_tyre", colors.hex_lin(colors.TYRE_RUBBER), roughness=0.88,
        normal="npc_tyre_nrm.png", normal_strength=1.2)
    rim_hex = colors.RIM_GUNMETAL if spec.get("livery") == "police" else colors.RIM_ALLOY
    # a fully metallic rim turns black in a dark world, so the alloy is only
    # half metallic: it stays a light grey at night as well
    mats["wheel_rim"] = materials.plain_mat(
        "NPC_rim", colors.hex_lin(rim_hex), roughness=0.32, metallic=0.35)
    mats["brake"] = materials.plain_mat(
        "NPC_brake", colors.hex_lin(colors.BRAKE_DISC), roughness=0.45,
        metallic=0.30)
    # gloss black: the mirror glass, the lamp reflectors
    mats["gloss"] = materials.plain_mat(
        "NPC_gloss_black", colors.hex_lin(colors.GLOSS_BLACK), roughness=0.12,
        metallic=0.0)
    # one tileable black plastic for every black part (wheel wells, bumpers,
    # mirrors, inner panels) - it tiles with the body's metre UVs, so no atlas
    # rectangle can bleed across the body
    mats["trim"] = materials.image_mat("NPC_trim", "npc_black_plastic.png",
                                       roughness=0.55, scale=2.0,
                                       normal="npc_black_plastic_nrm.png",
                                       normal_strength=0.6)
    mats["mesh"] = materials.image_mat("NPC_grille", "npc_trim.png", roughness=0.42,
                                       metallic=0.55,
                                       normal="npc_black_plastic_nrm.png",
                                       normal_strength=0.5)
    mats["well"] = mats["trim"]
    mats["inner"] = mats["trim"]
    mats["sill"] = mats["trim"]
    mats["lamp_f"] = materials.image_mat("NPC_lamp_front", "npc_trim.png",
                                         color=(0.55, 0.6, 0.68), roughness=0.12,
                                         emission=colors.hex_lin(colors.LAMP_WHITE),
                                         emission_strength=6.0)
    mats["lamp_r"] = materials.image_mat("NPC_lamp_rear", "npc_trim.png",
                                         color=(0.32, 0.02, 0.03), roughness=0.15,
                                         emission=colors.hex_lin(colors.LAMP_RED),
                                         emission_strength=4.0)
    mats["lamp_brake"] = materials.image_mat(
        "NPC_lamp_brake", "npc_trim.png", color=(0.25, 0.02, 0.03), roughness=0.15,
        emission=colors.hex_lin(colors.LAMP_RED), emission_strength=4.0)
    # the robotaxi sensor ring: a cyan laser scanner
    mats["lidar"] = materials.plain_mat(
        "NPC_lidar", colors.hex_lin(colors.LIDAR_CYAN), roughness=0.12,
        emission=colors.hex_lin(colors.LIDAR_CYAN), emission_strength=2.0,
        texture="npc_paint_rough.png")
    mats["plate"] = materials.image_mat("NPC_plate", "npc_plates.png",
                                        roughness=0.35, normal="npc_plates_nrm.png",
                                        normal_strength=0.7)
    mats["plate_rect"] = plate_rect(plate_index)
    mats["plate_atlas"] = PLATE_ATLAS
    mats.update(interior_materials())
    return mats


def interior_materials():
    """One interior material: each part maps its own rectangle of the atlas."""
    def make(name):
        return materials.image_mat(name, "npc_interior.png", roughness=0.68,
                                   normal="npc_interior_nrm.png",
                                   normal_strength=0.8)

    return {
        "interior": make("NPC_interior"),
        "seat": make("NPC_interior"),
        "dash": make("NPC_interior"),
        "interior_trim": make("NPC_interior"),
    }


def drone_materials():
    """Materials for the police drone."""
    pm = police_materials()
    return {
        "body": materials.plain_mat("NPC_drone_body", colors.hex_lin("#1A1C20"),
                                    roughness=0.42, metallic=0.25,
                                    texture="npc_paint_rough.png"),
        "trim": materials.plain_mat("NPC_drone_trim", colors.hex_lin("#101216"),
                                    roughness=0.5, texture="npc_paint_rough.png"),
        "glass": materials.image_mat("SH_glass_tinted", "npc_glass_grime.png",
                                     color=colors.hex_lin(colors.GLASS_TINT),
                                     roughness=0.06, alpha=0.62),
        "lamp_f": materials.plain_mat("NPC_lamp_front", colors.hex_lin("#C9CED6"),
                                      roughness=0.1,
                                      emission=colors.hex_lin(colors.LAMP_WHITE),
                                      emission_strength=8.0,
                                      texture="npc_paint_rough.png"),
        "blur": materials.plain_mat("NPC_prop_blur", (0.55, 0.58, 0.62),
                                    roughness=0.35, alpha=0.16,
                                    texture="npc_paint_rough.png"),
        "red": pm["red"], "blue": pm["blue"],
    }


def police_materials():
    """Light bar and siren materials (strobed by the police unit at runtime)."""
    return {
        "red": materials.plain_mat("NPC_lightbar_red", colors.hex_lin("#3A0508"),
                                   roughness=0.15,
                                   emission=colors.hex_lin(colors.POLICE_RED),
                                   emission_strength=12.0,
                                   texture="npc_paint_rough.png"),
        "blue": materials.plain_mat("NPC_lightbar_blue", colors.hex_lin("#050A28"),
                                    roughness=0.15,
                                    emission=colors.hex_lin(colors.POLICE_BLUE),
                                    emission_strength=12.0,
                                    texture="npc_paint_rough.png"),
        "clear": materials.plain_mat("NPC_lightbar_clear", colors.hex_lin("#8A9099"),
                                     roughness=0.1,
                                     emission=colors.hex_lin(colors.LAMP_WHITE),
                                     emission_strength=2.0,
                                     texture="npc_paint_rough.png"),
    }
