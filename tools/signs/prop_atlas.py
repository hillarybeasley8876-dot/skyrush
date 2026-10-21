"""Composes the props sign atlas: every printed board in one image.

Each board is rendered by the generator that owns it, at the pixel size its atlas
cell has, then packed. The layout lives in `blender/props/atlas.py`, so the
Blender builders and this generator can never disagree about where a board sits.

    /usr/bin/python3 tools/signs/prop_atlas.py
"""
import os
import sys
import tempfile

from PIL import Image

import imwrite as IW

ROOT = os.path.expanduser("~/m/skyrush")
sys.path.insert(0, os.path.join(ROOT, "blender"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

OUT_DIR = os.path.join(ROOT, "game", "assets", "props", "textures")
ATLAS_NAME = "prop_signs.png"

# Solid LED patches (the world unit drives these by name, so they are just colours).
LED_PATCHES = {
    "billboard_led": (255, 250, 240),
    "warm_led": (255, 215, 160),
    "billboard_cyan": (0, 229, 255),
    "billboard_magenta": (255, 43, 214),
    "billboard_green": (57, 255, 136),
    "billboard_amber": (255, 176, 0),
    "billboard_red": (255, 42, 42),
    "billboard_blue": (58, 92, 255),
}

# The patches that are a panel of LED cells (a downlight, a troffer) and not a
# thin line of light.
LED_PANELS = ("billboard_led", "warm_led")


def _led_grid(patch, colour):
    """Draw the cells of an LED panel into a patch."""
    from PIL import ImageDraw
    w, h = patch.size
    d = ImageDraw.Draw(patch)
    cells = 4
    gap = max(1, int(w * 0.06))
    step_x = w // cells
    step_y = h // cells
    dark = tuple(max(0, int(c * 0.18)) for c in colour)
    for iy in range(cells):
        for ix in range(cells):
            x0 = ix * step_x + gap
            y0 = iy * step_y + gap
            d.rectangle([x0, y0, x0 + step_x - gap * 2, y0 + step_y - gap * 2], fill=colour)
    d.rectangle([0, 0, w - 1, h - 1], outline=dark, width=max(1, gap))


GUIDE_ROWS = {
    "guide_yanan": [("延安高架路", "Yan'an Elevated Rd", "up"),
                    ("南北高架路", "N-S Elevated Rd", "up")],
    "guide_bund": [("外滩", "The Bund", "up"), ("陆家嘴", "Lujiazui", "up")],
    "guide_exit_xizang": [("西藏中路 出口", "Xizang Rd (M) Exit", "right"),
                          ("500 m", "", None)],
    "guide_bridges": [("南浦大桥", "Nanpu Bridge", "up"),
                      ("内环高架", "Inner Ring", "up")],
    "guide_airport": [("虹桥机场", "Hongqiao Airport", "up"),
                      ("G50 沪渝高速", "G50 Huyu Expressway", "up")],
    "guide_tunnel": [("延安东路隧道", "Yan'an E. Rd Tunnel", "up"),
                     ("外滩隧道", "Bund Tunnel", "up")],
    "guide_skid": [("出口", "EXIT", "right")],
}


def _table():
    """name -> (module name, function name, kwargs)."""
    from props import atlas
    t = {}
    for name, (w, h) in atlas.SIGN_SOURCES.items():
        if name in LED_PATCHES:
            continue
        if name.startswith("guide_"):
            t[name] = ("guide_sign", "guide_panel",
                       {"width_m": 4.2, "height_m": 2.4, "rows": GUIDE_ROWS[name], "px_w": w})
        elif name.startswith("bay_number_"):
            t[name] = ("site_signs", "bay_number", {"number": int(name[-2:]), "size": w})
        else:
            t[name] = _specific_table().get(name)
    return t


def _specific_table():
    """Boards that need their own arguments (pure data)."""
    from props import atlas
    s = atlas.SIGN_SOURCES
    table = {}
    table.update(_street_table(s))
    table.update(_site_table(s))
    return table


def _street_table(s):
    """The boards of the street kit."""
    return {
        "roadname_xianggang": ("town_signs", "road_name",
                               {"cn": "香港路", "en": "Xianggang Rd.", "west": 80, "east": 58,
                                "ew": True, "width_m": 1.8, "height_m": 0.6,
                                "px_w": s["roadname_xianggang"][0]}),
        "vms_congestion": ("town_signs", "vms",
                           {"width_m": 8.0, "height_m": 2.5,
                            "px_w": s["vms_congestion"][0]}),
        "bus_ad": ("town_signs", "bus_ad",
                   {"width_m": 1.2, "height_m": 1.8, "px_w": s["bus_ad"][0]}),
        "bus_route": ("town_signs", "bus_route",
                      {"width_m": 1.1, "height_m": 1.6, "px_w": s["bus_route"][0]}),
        "metro_totem": ("town_signs", "metro_totem",
                         {"station_cn": "世纪大道", "station_en": "Century Avenue",
                          "exit_no": "8", "width_m": 1.0, "height_m": 3.0,
                          "px_w": s["metro_totem"][0]}),
        "police_board": ("town_signs", "police_board",
                         {"width_m": 1.2, "height_m": 0.8, "px_w": s["police_board"][0]}),
        "countdown_23": ("town_signs", "countdown",
                         {"digits": "23", "width_m": 0.55, "height_m": 0.33,
                          "px_w": s["countdown_23"][0]}),
        "countdown_08": ("town_signs", "countdown",
                         {"digits": "08", "width_m": 0.55, "height_m": 0.33,
                          "px_w": s["countdown_08"][0]}),
        "billboard_ad": ("town_signs", "billboard_ad",
                         {"width_m": 8.0, "height_m": 4.0, "px_w": s["billboard_ad"][0]}),
        "neon_blade": ("town_signs", "neon_blade",
                       {"cn": "东方霓虹", "width_m": 1.2, "height_m": 4.0,
                        "px_w": s["neon_blade"][0]}),
        "fuel_price": ("town_signs", "fuel_price",
                       {"width_m": 0.34, "height_m": 0.20, "px_w": s["fuel_price"][0]}),
        "projector_screen": ("town_signs", "projector_screen",
                             {"width_m": 1.10, "height_m": 0.78,
                              "px_w": s["projector_screen"][0]}),
        "bin_label": ("town_signs", "bin_label",
                      {"width_m": 0.22, "height_m": 0.14, "px_w": s["bin_label"][0]}),
        "spike_label": ("town_signs", "spike_label",
                        {"width_m": 0.30, "height_m": 0.08, "px_w": s["spike_label"][0]}),
    }


def _site_table(s):
    """The boards of the three sites."""
    return {
        "toll_fascia": ("site_signs", "toll_fascia",
                        {"width_m": 24.0, "height_m": 2.4, "px_w": s["toll_fascia"][0]}),
        "toll_lane_etc": ("site_signs", "toll_lane_label",
                          {"cn": "ETC 专用", "en": "ETC ONLY", "width_m": 1.6, "height_m": 0.5,
                           "px_w": s["toll_lane_etc"][0]}),
        "toll_lane_mixed": ("site_signs", "toll_lane_label",
                            {"cn": "ETC/人工", "en": "ETC / MANUAL", "width_m": 1.6,
                             "height_m": 0.5, "px_w": s["toll_lane_mixed"][0]}),
        "toll_etc_strip": ("site_signs", "toll_etc_strip",
                           {"width_m": 3.0, "height_m": 0.5,
                            "px_w": s["toll_etc_strip"][0]}),
        "toll_signal_red": ("site_signs", "toll_signal",
                            {"kind": "red", "size_m": 0.8, "px": s["toll_signal_red"][0]}),
        "toll_signal_green": ("site_signs", "toll_signal",
                              {"kind": "green", "size_m": 0.8, "px": s["toll_signal_green"][0]}),
        "gas_fascia": ("site_signs", "gas_fascia",
                       {"width_m": 16.0, "height_m": 1.0, "px_w": s["gas_fascia"][0]}),
        "gas_logo": ("site_signs", "gas_logo",
                     {"width_m": 2.6, "height_m": 0.95, "px_w": s["gas_logo"][0]}),
        "gas_pylon_crown": ("site_signs", "gas_pylon_crown",
                            {"width_m": 1.9, "height_m": 1.1,
                             "px_w": s["gas_pylon_crown"][0]}),
        "gas_price_board": ("site_signs", "gas_price_board",
                            {"width_m": 1.8, "height_m": 2.4, "px_w": s["gas_price_board"][0]}),
        "gas_store_band": ("site_signs", "gas_store_band",
                           {"width_m": 10.0, "height_m": 0.95, "px_w": s["gas_store_band"][0]}),
        "charge_totem": ("site_signs_charge", "charge_totem",
                         {"width_m": 1.2, "height_m": 7.0, "px_w": s["charge_totem"][0]}),
        "charge_bolt": ("site_signs_charge", "charge_bolt",
                        {"width_m": 1.3, "height_m": 2.0, "px_w": s["charge_bolt"][0]}),
        "charge_post_volta": ("site_signs_charge", "charge_post_text",
                              {"width_m": 0.34, "height_m": 0.24, "px": s["charge_post_volta"][0]}),
        "charge_kw_500": ("site_signs_charge", "charge_kw_readout",
                          {"kw": 500, "width_m": 1.1, "height_m": 0.5,
                           "px_w": s["charge_kw_500"][0]}),
        "skylane_pad_arrow": ("site_signs", "sky_lane_pad_arrow",
                              {"width_m": 1.4, "height_m": 4.0,
                               "px_w": s["skylane_pad_arrow"][0]}),
        "skylane_gantry_sign": ("site_signs", "sky_lane_gantry_sign",
                                {"width_m": 6.0, "height_m": 1.8,
                                 "px_w": s["skylane_gantry_sign"][0]}),
        "barrier_arm": ("site_signs", "barrier_arm",
                        {"width_m": 3.0, "height_m": 0.14, "px_w": s["barrier_arm"][0]}),
        "digital_battery": ("site_signs", "digital_battery",
                            {"width_m": 0.30, "height_m": 0.18,
                             "px_w": s["digital_battery"][0]}),
    }


def build(out_dir=None):
    """Render every board, pack the atlas and write it to `out_dir`."""
    from props import atlas
    import guide_sign
    import site_signs
    import town_signs

    modules = {"town_signs": town_signs, "guide_sign": guide_sign, "site_signs": site_signs}
    tmp = os.path.join(ROOT, "tmp", "props", "boards")
    os.makedirs(tmp, exist_ok=True)
    os.environ["PROP_TEX_DIR"] = tmp
    for mod in modules.values():
        if hasattr(mod, "TEX_DIR"):
            mod.TEX_DIR = tmp
    try:
        table = _table()
        img = Image.new("RGB", (atlas.SIGN_W, atlas.SIGN_H), (20, 20, 22))
        for name, (mod_name, fn_name, kwargs) in sorted(table.items()):
            fn = getattr(modules[mod_name], fn_name)
            path = fn(name, **kwargs)
            x0, y0, x1, y1 = atlas.SIGN_RECTS[name]
            board = Image.open(path).convert("RGB")
            if board.size != (x1 - x0, y1 - y0):
                board = board.resize((x1 - x0, y1 - y0), Image.LANCZOS)
            img.paste(board, (x0, y0))
        for name, colour in LED_PATCHES.items():
            x0, y0, x1, y1 = atlas.SIGN_CELLS[name]
            patch = Image.new("RGB", (x1 - x0, y1 - y0), colour)
            if name in LED_PANELS:
                _led_grid(patch, colour)
            img.paste(patch, (x0, y0))
        out_dir = out_dir or OUT_DIR
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, ATLAS_NAME)
        IW.save(img, out, format="PNG")
        return out
    finally:
        pass


if __name__ == "__main__":
    print("SIGN ATLAS %s" % build())
