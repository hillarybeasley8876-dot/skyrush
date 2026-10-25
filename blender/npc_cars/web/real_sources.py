"""The source models of the realistic fleet and how their faces map onto the car contract (see real_rules.py).

Every source is a dict:

  file          the file in the car cache (blender/npc_cars/sources.json, fetched by fetch_sources.py)
  keep          the objects to keep (a pack holds several cars), by name; default: all
  front         the axis the nose of the source looks at ("-X", "+X", "-Y", "+Y"), or "wheels" with `turn`, a function of the
                working mesh that returns the turn about Z (a pack that stands its cars in a circle)
  classify      the function that names the node and the role of every face (Ctx -> None)
  decimate      the parts that are decimated (node -> ratio; a node "A~b" is a piece of A that is decimated on its own)
  wheels_from   the source whose wheels replace the wheels of this one (wheel_keep / wheel_roles of that source)

The colours of the texture atlases (sRGB hex) were measured with `convert_real.py --survey`.
"""
import math

import numpy as np

DARK = ["0a0a0a", "151515", "202020", "2a2a2a"]
PAINT_LIGHT = ["aaaaaa", "bbbbbb", "cccccc", "dddddd", "eeeeee", "ffffff", "ccbbbb", "bbaaaa", "aa9999", "ddcccc"]


# ------------------------------------------------------------------------------------------------ helpers

def lamp_glass(ctx, glass, grow=0.03):
    """The glass faces inside the bounds of the lamp faces of either end (the lens covers of a source that keeps them with
    the windows) become lamp lenses."""
    for front in (True, False):
        b = ctx.lamp_bounds(front)
        if b is None:
            continue
        lo, hi = b[0] - grow, b[1] + grow
        c = ctx.f.centre
        inside = glass & np.all((c >= lo) & (c <= hi), axis=1)
        ctx.set(inside, "lamp", "lens")


def by_hue(ctx, mask, node, paint_red=0.035, bright=0.33):
    """Sorts the faces of a dark red atlas (the paint has baked shading, some of it near black): reddish -> paint, a
    neutral bright grey -> chrome, the rest -> black."""
    idx = np.nonzero(mask)[0]
    rgb = ctx.f.rgb[idx]
    red = rgb[:, 0] - np.maximum(rgb[:, 1], rgb[:, 2])
    lum = rgb.mean(axis=1)
    role = np.where(red > paint_red, "paint", np.where(lum > bright, "chrome", "black"))
    ctx.node[idx] = node
    ctx.role[idx] = role.astype(object)


def comrade_turn(work, names):
    """The pack stands its cars in a circle: the minivan is turned so that the line from the middle of its rear axle
    (Wheel_D001, Wheel_D003) to the middle of its front axle (Wheel_D, Wheel_D002) looks at +Y."""
    me = work.data
    n = len(me.polygons)
    sid = np.empty(n, dtype=np.int32)
    me.attributes["src_id"].data.foreach_get("value", sid)
    centre = np.empty(n * 3)
    me.polygons.foreach_get("center", centre)
    centre = centre.reshape(-1, 3)

    def mid(keys):
        m = np.array([any(k in names[i] for k in keys) for i in sid], dtype=bool)
        return centre[m].mean(axis=0)

    d = mid(("Wheel_D_", "Wheel_D002")) - mid(("Wheel_D001", "Wheel_D003"))
    return 90.0 - math.degrees(math.atan2(d[1], d[0]))


# ------------------------------------------------------------------------------------------------ Daniel Zhabotinsky's cars

def kiri(ctx, cfg):
    """Kiri '10: body (paint), plastic_trim (an atlas: black plastic, chrome), glass + glass_trim_colour, headlight_left (both
    head lamps: housing, reflector, lens glass), stoplights (both tail lamps), wheels (all four rims in one object, the tyres
    in another), interior."""
    ctx.drop(ctx.src("interior_", "plastic_trim_solar_headlights"))
    wheels = ctx.src("wheels_")
    ctx.set(wheels, "wheel", "tyre")
    ctx.by_colour(wheels & ctx.mat("solar_bottom"), {"rim": ["9a9a9a", "c8c8c8", "707070"], "tyre": DARK + ["3a3a3a"]})
    ctx.set(ctx.src("glass_solar_glass"), "Glass", "glass")
    ctx.set(ctx.src("glass_trim_colour"), "Body", "black")
    for lamp in ("headlight_left", "stoplights"):
        m = ctx.src(lamp)
        ctx.set(m, "lamp", "housing")
        ctx.set(m & ctx.mat("solar_glass"), "lamp", "lens")
    body = ctx.src("body_solar_body")
    ctx.set(body, "Body", "paint")
    trim = ctx.src("plastic_trim_solar_bottom")
    ctx.by_colour(trim, {"matte": DARK + ["3a3a3a"], "chrome": ["8a8a8a", "b0b0b0", "d0d0d0"]}, node="Body")
    shell = body | trim
    ctx.mirrors(shell)
    head = ctx.lamp_bounds(True, lens_only=True)
    tail = ctx.lamp_bounds(False, lens_only=True)
    ctx.bumpers(shell & (ctx.node == "Body"), head[0][2] - 0.01, tail[0][2] - 0.01)
    base = ctx.windscreen_base()
    ctx.hood(body & (ctx.node == "Body"), base + 0.03, head[1][2] - 0.02, 0.42 * ctx.width)


def kiri_wheels(ctx):
    """The wheels of the Kiri '10 (a donor for the cars whose wheels are a picture of a rim on a disc)."""
    ctx.set(ctx.free(), "wheel", "tyre")
    ctx.by_colour(ctx.mat("solar_bottom"), {"rim": ["9a9a9a", "c8c8c8", "707070"], "tyre": DARK + ["3a3a3a"]})


def ace(ctx, cfg):
    """Ace '11: ONE textured material for the whole car (paint, trim, the tail lamps are drawn on the rear panels, the wheels),
    separate objects for the bumpers, the bonnet, the doors and the tailgate (their glass is GLASS), the head lamps (housing in
    the atlas, lens glass in headlights_GLASS), interiors. Its wheels are a picture of a rim on a flat disc: the converter puts
    the wheels of the Kiri '10 in their place (`wheels_from`)."""
    ctx.drop(ctx.src("INTERIOR"))
    wheels = ctx.src("wheel_")
    ctx.by_colour(wheels, {"tyre": DARK + ["333333", "444444"], "rim": ["777777", "999999", "bbbbbb", "cccccc"]},
                  node="wheel")
    head = ctx.src("headlights_")
    ctx.by_colour(head, {"housing": DARK + ["333333", "666666", "777777"], "amber": ["994422", "883311", "cc6622"]},
                  node="lamp")
    ctx.set(head & ctx.mat("GLASS"), "lamp", "lens")
    ctx.set(ctx.free() & ctx.mat("GLASS"), "Glass", "glass")
    painted = ctx.free()
    ctx.by_colour(painted, {"paint": PAINT_LIGHT, "black": ["000000", "111111", "1a1a1a"], "matte": ["222222", "333333"]},
                  node="Body")
    # the tail lamps are a drawing in the atlas (u 0.027..0.098, v 0.17..0.272) on the rear quarters
    tail = painted & ctx.uv_box((0.02, 0.10), (0.165, 0.275)) & (ctx.f.centre[:, 1] < 0.0)
    ctx.set(tail, "lamp", "lens")
    ctx.set(painted & ctx.src("bumper_front"), "Bumper_F")
    ctx.set(painted & ctx.src("bumper_rear"), "Bumper_R")
    ctx.set(painted & ctx.src("hood_"), "Hood")
    ctx.mirrors(painted & (ctx.node == "Body"))


def urban(ctx, cfg):
    """Urban '10: body (paint), bottom (an atlas: black plastic and the mirrors), Object001 (the silver skid plates of the
    bumpers), glass (windows and the lens covers of the lamps), glass_rim, light (the lamp housings and the lamp atlas: the
    tail lamps behind, the reflectors in front), wheels (the four rims in one object, the tyres in another), interior."""
    ctx.drop(ctx.src("interior_"))
    wheels = ctx.src("wheels_")
    ctx.set(wheels, "wheel", "tyre")
    ctx.by_colour(wheels & ctx.mat("dust_bottom"), {"rim": ["ffffff", "eeeeee", "999999", "888888"],
                                                     "tyre": DARK + ["444444", "555555"]})
    lamps = ctx.src("light_")
    ctx.set(lamps, "lamp", "housing")
    ctx.set(lamps & ctx.mat("dust_headlights") & (ctx.f.centre[:, 1] < 0.0), "lamp", "lens")
    glass = ctx.src("glass_dust_glass")
    ctx.set(glass, "Glass", "glass")
    lamp_glass(ctx, glass)
    ctx.set(ctx.src("glass_rim_dust_glass_rim"), "Body", "black")
    ctx.set(ctx.src("glass_rim_dust_bottom"), "Body", "matte")
    body = ctx.src("body_dust_body")
    ctx.set(body, "Body", "paint")
    trim = ctx.src("bottom_dust_bottom")
    ctx.by_colour(trim, {"matte": DARK + ["333333", "444444", "555555"], "silver": ["bbbbbb", "cccccc", "eeeeee"]},
                  node="Body")
    skid = ctx.src("Object001")
    ctx.by_colour(skid, {"silver": ["eeeeee", "bbbbbb", "dddddd", "cccccc", "ffffff"], "matte": DARK}, node="Body")
    shell = body | trim | skid
    ctx.mirrors(shell)
    head = ctx.lamp_bounds(True, lens_only=True)
    tail = ctx.lamp_bounds(False, lens_only=True)
    ctx.bumpers(shell & (ctx.node == "Body"), head[0][2] - 0.01, tail[0][2] - 0.01)
    base = ctx.windscreen_base()
    ctx.hood(body & (ctx.node == "Body"), base + 0.03, head[1][2] - 0.02, 0.42 * ctx.width)


def lct07(ctx, cfg):
    """Light Commercial Truck '07: a cab-over truck with a box. BODY (the cab, its wind deflector and the panels of the box:
    the box gets the white of a cargo box, the cab the paint), BOX_METAL (the corner profiles of the box), bottom (an atlas:
    the chassis, the tank, the steps, the rear under-run bar), BUMPER_FRONT, CABIN_PLASTIC (grille, mirrors, trims; the
    METALL of the cabin is the mirror arms), GLASS, LIGHTS (housings and lens covers of both ends), the wheels (the rear
    ones are twin tyres), interior."""
    ctx.drop(ctx.src("interior_"))
    wheels = ctx.src("wheel_")
    ctx.set(wheels, "wheel", "tyre")
    ctx.by_colour(wheels & ctx.mat("material"), {"rim": ["999999", "aaaaaa", "bbbbbb", "cccccc", "777777"],
                                                  "tyre": DARK + ["333333", "444444", "555555"]})
    lights = ctx.src("LIGHTS_")
    ctx.set(lights, "lamp", "housing")
    covers = lights & ctx.mat("LIGHTS_GLASS")
    ctx.by_colour(covers, {"lens": ["551111", "992222", "aa2222", "bb4422", "662222", "666666", "555555", "777766",
                                    "bbbbaa", "aaaa99", "556666"], "amber": ["994422", "883322"]}, node="lamp")
    rear = covers & (ctx.f.centre[:, 1] < 0.0)
    ctx.by_colour(rear, {"lens": ["551111", "992222", "aa2222", "bb4422", "662222"], "amber": ["994422", "883322"],
                         "reverse": ["666666", "555555", "777766", "bbbbaa", "aaaa99", "556666"]}, node="lamp")
    ctx.set(ctx.src("GLASS_GLASS"), "Glass", "glass")
    body = ctx.src("BODY_BODY")
    ctx.set(body, "Body", "paint")
    box_start = float(ctx.f.lo[ctx.src("BOX_METAL")][:, 1].max()) - 0.15
    ctx.set(body & (ctx.f.centre[:, 1] < box_start), "Body", "cargo")
    ctx.set(ctx.src("BOX_METAL"), "Body", "silver")
    ctx.set(ctx.src("bottom_07"), "Body", "matte")
    bottom = ctx.src("bottom_BOTTOM")
    ctx.by_colour(bottom, {"matte": DARK + ["333333", "444444"], "silver": ["aaaaaa", "bbbbbb", "cccccc", "dddddd",
                                                                           "777777"]}, node="Body")
    ctx.set(ctx.src("BUMPER_FRONT"), "Bumper_F", "matte")
    cabin = ctx.src("CABIN_PLASTIC")
    ctx.set(cabin, "Body", "matte")
    ctx.set(cabin & ctx.mat("METALL"), "Body", "black")
    ctx.mirrors(body | cabin, below=1.25, max_size=0.9)
    # the rear under-run bar: the chassis under the end of the box
    end = float(ctx.f.lo[body][:, 1].min())
    ctx.set(bottom & (ctx.f.centre[:, 1] < end + 0.45) & (ctx.f.centre[:, 2] < 0.85), "Bumper_R")


# ------------------------------------------------------------------------------------------------ the other sources

def minivan(ctx, cfg):
    """The minivan of Comrade1280's passenger car pack: ONE textured material for the body (a dark red paint with baked
    shading, black trim, a chrome grille), Glass, Optics (the lamps: red tail lamps, clear head lamps, amber indicators) and
    four wheel objects (a steel wheel with a hub cap)."""
    wheels = ctx.src("Wheel_D")
    ctx.by_colour(wheels, {"tyre": DARK + ["333333"], "rim": ["555555", "666666", "777777", "888888", "999999",
                                                              "998888", "554444"]}, node="wheel")
    optics = ctx.src("Optics")
    front = optics & (ctx.f.centre[:, 1] > 0.0)
    ctx.by_colour(front, {"lens": ["cccccc", "dddddd", "bbbbbb", "999999", "888888", "aaaa99"],
                          "amber": ["bb6611", "773311", "663311"], "housing": DARK + ["333333", "444444"]},
                  node="lamp")
    ctx.by_colour(optics & ~front, {"lens": ["440011", "550011", "660011", "330000", "882222"],
                                    "reverse": ["cccccc", "dddddd", "bbbbbb", "999999"],
                                    "amber": ["bb6611", "773311", "663311"], "housing": DARK}, node="lamp")
    ctx.set(ctx.src("Glass"), "Glass", "glass")
    body = ctx.src("minivan body_Body")
    by_hue(ctx, body, "Body")
    ctx.mirrors(body)
    tail = ctx.lamp_bounds(False, lens_only=True)
    # the fog lamps sit low in the front bumper: its top is under the grille, not under the lowest lens
    ctx.bumpers(body & (ctx.node == "Body"), 0.62, tail[0][2] - 0.01)


def shc_mc(ctx, cfg):
    """SHC MC Free Promotion Car: plain materials, no texture. grey_car_paint (the paint and the mirror caps), Chrome_Trim,
    Matte_plastic (the grilles, the diffuser, the wipers), Glass_Black_Edge, Main_Glass (the windows, both surfaces of each
    pane, and the lens covers of the lamps), Light_Casing / Headlight / Led_light (the head lamps), Rear_light_casing /
    Rear_light_led (the tail lamps), Mirror_Material, and four wheels (Alloy_Wheel, Tires, a chrome cap, a brake disc)."""
    wheel_objects = ctx.src("Car.004_", "Car.005_", "Car.006_", "Car.007_")
    ctx.set(wheel_objects, "wheel", "rim")
    ctx.set(wheel_objects & ctx.mat("Tires"), "wheel", "tyre")
    ctx.drop(ctx.mat("Brakedisk", "Rear_light_led", "Headlight", "Led_light"))
    ctx.set(ctx.mat("Light_Casing", "Rear_light_casing"), "lamp~housing", "housing")
    glass = ctx.mat("Main_Glass")
    ctx.set(glass, "Glass", "glass")
    lamp_glass(ctx, glass, grow=0.02)
    paint = ctx.mat("grey_car_paint")
    ctx.set(paint, "Body", "paint")
    ctx.set(ctx.free() & ctx.mat("Chrome_Trim"), "Body", "chrome")
    ctx.set(ctx.mat("Glass_Black_Edge", "Glossy_Lens", "Mirror_Material"), "Body", "black")
    ctx.set(ctx.mat("Matte_plastic", "FrontColor"), "Body", "matte")
    shell = ctx.node == "Body"
    ctx.mirrors(shell)
    ctx.bumpers(shell & (ctx.node == "Body"), 0.64, ctx.lamp_bounds(False, lens_only=True)[0][2] - 0.01)
    # The grilles are deep honeycombs (5 k triangles of thin cells): seen at a grazing angle their cells mirror the lit
    # road like glass, and a decimated honeycomb is worse. They are replaced by a dark plate behind each opening; the
    # chrome slats in front of them stay, in black (chrome there mirrors the road under the car too).
    grille = (ctx.node == "Bumper_F") & ctx.mat("Matte_plastic")
    ctx.back_openings(grille, "Bumper_F")
    ctx.drop(grille)
    ctx.set((ctx.node == "Bumper_F") & ctx.mat("Chrome_Trim"), None, "matte")
    head = ctx.lamp_bounds(True, lens_only=True)
    base = ctx.windscreen_base()
    ctx.hood(paint & (ctx.node == "Body"), base + 0.03, head[1][2] - 0.02, 0.42 * ctx.width)


def city_bus(ctx, cfg):
    """Grab3D's City Bus (Cozy Vehicles Kit, CC0): body (an atlas: the sky blue paint, the white roof and skirts, the dark
    rubber of the windows), windows and door_windows (glass), headlights (lens + white bezel), taillights, the destination
    display (it glows), four wheels (tyre, white rim, blue hub cap; the rear ones are twin tyres)."""
    wheels = ctx.src("wheel_")
    ctx.set(wheels, "wheel", "rim")
    ctx.set(wheels & ctx.mat("tire"), "wheel", "tyre")
    head = ctx.src("headlights")
    ctx.set(head, "lamp", "chrome")
    ctx.set(head & ctx.mat("light_butter"), "lamp", "lens")
    ctx.set(ctx.src("taillights"), "lamp", "lens")
    ctx.set(ctx.src("windows"), "Glass", "glass")
    ctx.set(ctx.src("destination_display"), "Body", "display")
    body = ctx.src("city-bus_body")
    ctx.by_colour(body, {"paint": ["77bbee", "77aadd", "77bbdd", "88bbdd"], "roof": ["ffffee", "eeeeee", "ffeeee", "eedddd",
                                                                                     "eeeedd", "dddddd"],
                         "matte": ["444444", "333344", "333333", "334444"]}, node="Body")
    ctx.mirrors(body, max_size=0.9)
    ctx.bumpers(body & (ctx.node == "Body"), 0.52, 0.62, depth=0.4)


SOURCES = {
    "kiri": {"file": "7fd6e15785fa4aa9bfd6e31eb7c97ba6.glb", "front": "-X", "classify": kiri,
             "wheel_keep": lambda name: name.startswith("wheels_"), "wheel_roles": kiri_wheels},
    "ace": {"file": "055ff8a21b8d4d279debca089e2fafcd.glb", "front": "-X", "classify": ace, "wheels_from": "kiri"},
    "urban": {"file": "2866efdfa943484391ef8313768e074d.glb", "front": "-X", "classify": urban},
    "lct07": {"file": "3be03b6a43aa41898c9ca806b8787052.glb", "front": "-X", "classify": lct07},
    "comrade_cars": {"file": "20f9af9b8a404d5cb022ac6fe87f21f5.glb", "front": "wheels", "turn": comrade_turn,
                     "keep": lambda name: "minivan" in name or name.startswith("Wheel_D"), "classify": minivan},
    "shc_mc": {"file": "shc_mc/scene.gltf", "front": "-X", "classify": shc_mc,
               "decimate": {"Wheel_FL": 0.4, "Wheel_FR": 0.4, "Wheel_RL": 0.4, "Wheel_RR": 0.4, "Body~housing": 0.3}},
    "city_bus": {"file": "city-bus.glb", "front": "-Y", "classify": city_bus, "decimate": {"Glass": 0.5}},
}
