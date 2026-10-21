"""Build the evidence sheets: my render next to the reference photo.

    python3 blender/landmarks/sheets.py

Writes ~/m/skyrush/captures/landmarks/side_<asset>.jpg (night render left,
reference photo right) and a contact sheet of every asset.
"""
import os
import sys

from PIL import Image

ROOT = os.path.expanduser("~/m/skyrush")
OUT = os.path.join(ROOT, "captures", "landmarks")
BL = os.path.join(ROOT, "captures", "blender")
REF = os.path.join(ROOT, "ref", "shanghai")

# asset, my capture (game render), reference photo
PAIRS = [
    ("oriental_pearl", "r3_skyline_opt_sphere20.jpg",
     "img/06_lujiazui/opt_night_2014.jpg"),
    ("jin_mao", "r3_skyline_jinmao_base.jpg",
     "img/06_lujiazui/swfc_jinmao_night_2009.jpg"),
    ("swfc", "r3_skyline_swfc_ap.jpg",
     "img/06_lujiazui/swfc_jinmao_night_2009.jpg"),
    ("shanghai_tower", "r3_skyline_st_crown.jpg",
     "img/06_lujiazui/lujiazui_night_2023.jpg"),
    ("lujiazui_backdrop", "r3_skyline_bund.jpg",
     "img/06_lujiazui/lujiazui_from_bund_night_2016_01.jpg"),
    ("pearl_ring", "r3_skyline_ring_street.jpg",
     "img/06_lujiazui/lujiazui_intersection_ring_2014.jpg"),
    ("nanpu_bridge", "r3_skyline_nanpu_w_main.jpg",
     "img/03_nanpu_lupu_bridges/nanpu_night_2026.jpg"),
    ("lupu_bridge_far", "r3_skyline_lupu.jpg",
     "img/03_nanpu_lupu_bridges/lupu_night.jpg"),
    ("waibaidu_bridge", "r3_skyline_wb_side.jpg",
     "img/05_bund/waibaidu_bridge_night_2019.jpg"),
    ("dragon_pillar", "r3_skyline_pillar_2m.jpg", "sheets/c_pillar.jpg"),
]


def fit(path, width):
    im = Image.open(path).convert("RGB")
    return im.resize((width, max(1, int(im.height * width / im.width))), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for (name, mine, ref) in PAIRS:
        a = fit(os.path.join(ROOT, "captures", mine), 780)
        b = fit(os.path.join(REF, ref), 780)
        h = max(a.height, b.height)
        sheet = Image.new("RGB", (a.width + b.width + 10, h), (18, 18, 22))
        sheet.paste(a, (0, 0))
        sheet.paste(b, (a.width + 10, 0))
        path = os.path.join(OUT, "side_%s.jpg" % name)
        sheet.save(path, quality=88)
        print("wrote %s (%dx%d)" % (os.path.basename(path), sheet.width, sheet.height))


if __name__ == "__main__":
    main()
