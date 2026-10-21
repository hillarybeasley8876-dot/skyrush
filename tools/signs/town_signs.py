"""Street-level sign textures (unit: props): road-name plates, VMS, bus-stop panels,
metro totem, police board, light-box ads.

Dossier §9 and art dossier §6/§7. Every board carries real Chinese + English.
"""
import math
import os

from PIL import Image, ImageDraw

import imwrite as IW
import fontlib as F
from surfaces import TEX_DIR

WHITE = (0xFF, 0xFF, 0xFF)
BLACK = (0x10, 0x12, 0x16)
BLUE = (0x1A, 0x5F, 0xB4)     # E-W road name plates
GREEN = (0x00, 0x70, 0x4A)    # N-S road name plates
AMBER = (0xFF, 0xCC, 0x00)


def _save(img, name):
    path = os.path.join(TEX_DIR, "%s.png" % name)
    return IW.save(img, path, format="PNG")


def _rounded(d, box, radius, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


# ------------------------------------------------------------------ road name
def road_name(name, cn, en, west, east, ew=True, width_m=1.8, height_m=0.6, px_w=1536):
    """Shanghai 路名牌: coloured top panel with the name and direction cells, white
    lower strip with the pinyin/English. E-W streets use blue, N-S streets green."""
    px_h = int(round(px_w * height_m / width_m))
    ppm = px_w / width_m
    img = Image.new("RGB", (px_w, px_h), WHITE)
    d = ImageDraw.Draw(img)
    ground = BLUE if ew else GREEN
    top_h = int(px_h * 0.66)
    img = Image.new("RGB", (px_w, px_h), WHITE)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w, top_h], fill=ground)
    d.rounded_rectangle([0, 0, px_w - 1, top_h + int(px_h * 0.20)],
                        radius=int(px_h * 0.14), fill=ground)
    d.rectangle([0, top_h + int(px_h * 0.12), px_w, px_h], fill=WHITE)
    d.rounded_rectangle([0, 0, px_w - 1, px_h - 1], radius=int(px_h * 0.14),
                        outline=(0xC8, 0xCC, 0xD2), width=max(2, int(px_h * 0.02)))

    cell = px_w * 0.12
    F.fit_text(d, cn, F.NOTO, int(0.28 * ppm), (cell, px_h * 0.05, px_w - cell, top_h * 0.80),
               weight=700, fill=WHITE)
    for x, ch, num in ((cell * 0.50, "西", west), (px_w - cell * 0.50, "东", east)):
        F.fit_text(d, ch, F.NOTO, int(0.11 * ppm), (x - cell * 0.45, top_h * 0.08,
                                                    x + cell * 0.45, top_h * 0.42),
                   weight=700, fill=WHITE)
        F.fit_text(d, str(num), F.NOTO, int(0.13 * ppm), (x - cell * 0.45, top_h * 0.44,
                                                          x + cell * 0.45, top_h * 0.92),
                   weight=500, fill=WHITE)
    y = top_h + int(px_h * 0.12)
    bottom = px_h - int(px_h * 0.08)          # 8 % bottom margin: descenders stay clear
    F.fit_text(d, "W" if ew else "S", F.NOTO, int(0.14 * ppm),
               (cell * 0.30, y, cell * 1.05, bottom), weight=500, fill=BLACK)
    F.fit_text(d, en, F.NOTO, int(0.15 * ppm), (cell * 1.15, y, px_w - cell * 1.15, bottom),
               weight=500, fill=BLACK)
    F.fit_text(d, "E" if ew else "N", F.NOTO, int(0.14 * ppm),
               (px_w - cell * 1.35, y, px_w - cell * 0.30, bottom), weight=500, fill=BLACK)
    return _save(img, name)


# ------------------------------------------------------------------ VMS board
def vms(name, width_m=8.0, height_m=2.5, px_w=2048):
    """可变情报板: black board, LED road schematic in green/yellow/red + amber text."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x05, 0x06, 0x08))
    d = ImageDraw.Draw(img)
    led = 4
    # schematic: three lanes running left to right, middle one congested.
    lanes_y = [px_h * 0.30, px_h * 0.52, px_h * 0.74]
    cols = 22
    colours = [(0x2B, 0xFF, 0x6A), (0xFF, 0xD2, 0x3F), (0xFF, 0x2A, 0x2A)]
    for li, ly in enumerate(lanes_y):
        for c in range(cols):
            x0 = px_w * 0.30 + c * (px_w * 0.66 / cols)
            x1 = x0 + px_w * 0.66 / cols - led * 2
            if li == 0:
                col = colours[0] if c < 16 else colours[1]
            elif li == 1:
                col = colours[0] if c < 8 else (colours[2] if c < 13 else colours[1])
            else:
                col = colours[0]
            d.rectangle([x0, ly - led * 2, x1, ly + led * 2], fill=col)
    F.fit_text(d, "前方拥堵 注意减速", F.NOTO, int(px_h * 0.16),
               (px_w * 0.03, px_h * 0.04, px_w * 0.28, px_h * 0.24), weight=700, fill=AMBER)
    F.fit_text(d, "SLOW", F.NOTO, int(px_h * 0.13), (px_w * 0.03, px_h * 0.80,
                                                     px_w * 0.28, px_h * 0.96),
               weight=700, fill=AMBER)
    return _save(img, name)


# ------------------------------------------------------------------ bus stop
def bus_ad(name, width_m=1.2, height_m=1.8, px_w=768):
    """Backlit light-box advertisement (parody brand, art dossier §7.1)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x14, 0x10, 0x1E))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w, px_h * 0.80], fill=(0x2A, 0x14, 0x38))
    F.fit_text(d, "量子奶茶", F.SMILEY, int(px_w * 0.20),
               (px_w * 0.05, px_h * 0.12, px_w * 0.95, px_h * 0.42), fill=(0xFF, 0x2B, 0xD6))
    F.fit_text(d, "QUANTUM MILK TEA", F.NOTO, int(px_w * 0.055),
               (px_w * 0.05, px_h * 0.44, px_w * 0.95, px_h * 0.55), weight=700,
               fill=(0x3B, 0xFF, 0xC8))
    d.rectangle([0, px_h * 0.80, px_w, px_h], fill=(0x0E, 0x0B, 0x16))
    F.fit_text(d, "24 小时营业  ·  外卖专线 6688 1234", F.NOTO, int(px_w * 0.042),
               (px_w * 0.05, px_h * 0.83, px_w * 0.95, px_h * 0.96), weight=500,
               fill=(0xF2, 0xF6, 0xFF))
    return _save(img, name)


def bus_route(name, width_m=1.1, height_m=1.6, px_w=704):
    """Bus route board: line numbers, heads and times."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0xF0, 0xF2, 0xF4))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w, px_h * 0.16], fill=(0x1F, 0x4E, 0x9B))
    F.fit_text(d, "七莘路 → 天山路", F.NOTO, int(px_h * 0.075),
               (px_w * 0.04, px_h * 0.02, px_w * 0.96, px_h * 0.14), weight=700, fill=WHITE)
    lines = [("71", "七莘路 Qixin Rd", "2 min"), ("127", "静安寺 Jing'an Temple", "6 min"),
             ("253", "徐家汇 Xujiahui", "11 min"), ("920", "申江路 Shenjiang Rd", "18 min")]
    y = px_h * 0.20
    row_h = (px_h * 0.80) / len(lines)
    for num, dest, eta in lines:
        d.rectangle([px_w * 0.04, y, px_w * 0.22, y + row_h * 0.72], fill=(0x1F, 0x4E, 0x9B))
        F.fit_text(d, num, F.NOTO, int(row_h * 0.42), (px_w * 0.04, y, px_w * 0.22,
                                                      y + row_h * 0.72), weight=700, fill=WHITE)
        F.fit_text(d, dest, F.NOTO, int(row_h * 0.24), (px_w * 0.25, y, px_w * 0.68,
                                                        y + row_h * 0.72), weight=500, fill=BLACK)
        F.fit_text(d, eta, F.NOTO, int(row_h * 0.22), (px_w * 0.70, y, px_w * 0.96,
                                                       y + row_h * 0.72), weight=500, fill=BLACK)
        y += row_h
    return _save(img, name)


# ------------------------------------------------------------------ metro totem
def metro_totem(name, station_cn, station_en, exit_no="3", width_m=1.0, height_m=3.0,
                px_w=512):
    """Free-standing metro totem: parody red roundel + station name + exit number."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0xF2, 0xF3, 0xF5))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w, px_h * 0.09], fill=(0xD9, 0x16, 0x1C))
    cx, cy, r = px_w * 0.5, px_h * 0.19, px_w * 0.26
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0xD9, 0x16, 0x1C))
    F.fit_text(d, "M", F.SMILEY, int(r * 1.05), (cx - r, cy - r * 0.66, cx + r, cy + r * 0.30),
               fill=(0xF2, 0xF3, 0xF5))
    d.arc([cx - r * 0.80, cy + r * 0.06, cx + r * 0.80, cy + r * 0.62], 205, 335,
          fill=(0xF2, 0xF3, 0xF5), width=max(2, int(r * 0.11)))
    F.fit_text(d, "地铁 METRO", F.NOTO, int(px_h * 0.035),
               (0, px_h * 0.30, px_w, px_h * 0.36), weight=500, fill=(0xD9, 0x16, 0x1C))
    F.fit_text(d, station_cn, F.NOTO, int(px_h * 0.055),
               (0, px_h * 0.38, px_w, px_h * 0.50), weight=700, fill=BLACK)
    F.fit_text(d, station_en, F.NOTO, int(px_h * 0.032),
               (0, px_h * 0.51, px_w, px_h * 0.56), weight=500, fill=(0x55, 0x5A, 0x62))
    d.rectangle([0, px_h * 0.62, px_w, px_h * 0.78], fill=(0x1E, 0x4E, 0x9B))
    F.fit_text(d, "%s 号口" % exit_no, F.NOTO, int(px_h * 0.048),
               (0, px_h * 0.63, px_w, px_h * 0.72), weight=700, fill=WHITE)
    F.fit_text(d, "Exit %s" % exit_no, F.NOTO, int(px_h * 0.030),
               (0, px_h * 0.715, px_w, px_h * 0.765), weight=500, fill=WHITE)
    # small route diagram strip at the foot of the totem
    d.rectangle([0, px_h * 0.83, px_w, px_h * 0.97], fill=(0xE2, 0xE5, 0xE9))
    d.line([px_w * 0.10, px_h * 0.885, px_w * 0.90, px_h * 0.885], fill=(0xD9, 0x16, 0x1C),
           width=max(2, int(px_h * 0.006)))
    stops = (("东昌路", 0.16), ("东方路", 0.38), ("世纪大道", 0.60), ("浦电路", 0.82))
    for label, fx in stops:
        d.ellipse([px_w * fx - px_w * 0.024, px_h * 0.885 - px_w * 0.024,
                   px_w * fx + px_w * 0.024, px_h * 0.885 + px_w * 0.024],
                  fill=(0xFF, 0xFF, 0xFF), outline=(0xD9, 0x16, 0x1C),
                  width=max(1, int(px_h * 0.004)))
        F.fit_text(d, label, F.NOTO, int(px_h * 0.022),
                   (px_w * fx - px_w * 0.115, px_h * 0.912, px_w * fx + px_w * 0.115, px_h * 0.958),
                   weight=500, fill=(0x33, 0x36, 0x3C))
    return _save(img, name)


# ------------------------------------------------------------------ police board
def police_board(name, width_m=1.2, height_m=0.8, px_w=768):
    """Police checkpoint board (parody, no real emblem)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x10, 0x1A, 0x30))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w, px_h * 0.06], fill=(0xFF, 0x20, 0x30))
    F.fit_text(d, "公安 POLICE", F.SMILEY, int(px_h * 0.26),
               (px_w * 0.04, px_h * 0.12, px_w * 0.96, px_h * 0.46), fill=WHITE)
    F.fit_text(d, "前方临检  请减速", F.NOTO, int(px_h * 0.17),
               (px_w * 0.04, px_h * 0.48, px_w * 0.96, px_h * 0.70), weight=700,
               fill=(0xFF, 0xCC, 0x00))
    F.fit_text(d, "CHECKPOINT AHEAD - SLOW DOWN", F.NOTO, int(px_h * 0.11),
               (px_w * 0.04, px_h * 0.72, px_w * 0.96, px_h * 0.92), weight=500, fill=WHITE)
    return _save(img, name)


def _segments(d, x, y, w, h, thick, on):
    """7-segment digit cell (red LED countdown)."""
    segs = {
        "a": (x, y + h - thick, x + w, y + h),
        "g": (x, y + h / 2 - thick / 2, x + w, y + h / 2 + thick / 2),
        "d": (x, y, x + w, y + thick),
        "f": (x, y + h / 2 - thick / 2, x + thick, y + h - thick / 2),
        "b": (x + w - thick, y + h / 2 - thick / 2, x + w, y + h - thick / 2),
        "e": (x, y + thick, x + thick, y + h / 2 - thick / 2),
        "c": (x + w - thick, y + thick, x + w, y + h / 2 - thick / 2),
    }
    lit = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
           "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
           "-": "g", " ": ""}[on]
    for key, box in segs.items():
        if key in lit:
            d.rectangle(box, fill=(0xFF, 0x1E, 0x28))


def countdown(name, digits="23", width_m=0.55, height_m=0.30, px_w=512):
    """Traffic-light countdown box face: red seven-segment digits on black."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x06, 0x06, 0x08))
    d = ImageDraw.Draw(img)
    n = max(1, len(digits))
    cell_w = px_w * 0.36
    gap = px_w * 0.06
    total = n * cell_w + (n - 1) * gap
    x = (px_w - total) / 2.0
    for ch in digits:
        _segments(d, x, px_h * 0.20, cell_w, px_h * 0.60, px_h * 0.10, ch)
        x += cell_w + gap
    return _save(img, name)


def fuel_price(name, width_m=0.34, height_m=0.20, px_w=256):
    """The green LED price window of a fuel dispenser: grade, price and litres."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x04, 0x0A, 0x07))
    d = ImageDraw.Draw(img)
    F.fit_text(d, "92#", F.NOTO, int(px_h * 0.30), (px_w * 0.04, px_h * 0.06,
                                                     px_w * 0.34, px_h * 0.46),
               weight=700, fill=(0x39, 0xFF, 0x88))
    F.fit_text(d, "7.28", F.NOTO, int(px_h * 0.36), (px_w * 0.36, px_h * 0.04,
                                                     px_w * 0.96, px_h * 0.52),
               weight=700, fill=(0x39, 0xFF, 0x88))
    F.fit_text(d, "元/升", F.NOTO, int(px_h * 0.22), (px_w * 0.36, px_h * 0.54,
                                                     px_w * 0.96, px_h * 0.80),
               weight=500, fill=(0x39, 0xFF, 0x88))
    F.fit_text(d, "0.00 L", F.NOTO, int(px_h * 0.24), (px_w * 0.04, px_h * 0.52,
                                                       px_w * 0.34, px_h * 0.82),
               weight=500, fill=(0xFF, 0xD2, 0x3F))
    return _save(img, name)


def projector_screen(name, width_m=1.10, height_m=0.78, px_w=512):
    """The hologram projector screen: a rotating wire-frame globe with a label."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x05, 0x0A, 0x12))
    d = ImageDraw.Draw(img)
    cx, cy, r = px_w * 0.5, px_h * 0.40, px_h * 0.30
    for i in range(6):
        a = math.pi * i / 6.0
        d.ellipse([cx - r * abs(math.cos(a)) - 2, cy - r, cx + r * abs(math.cos(a)) + 2,
                   cy + r], outline=(0x00, 0xE5, 0xFF), width=2)
    for i in range(4):
        yy = cy - r + 2 * r * i / 3.0
        d.line([(cx - r, yy), (cx + r, yy)], fill=(0x00, 0xB0, 0xD0), width=2)
    F.fit_text(d, "申城地图", F.NOTO, int(px_h * 0.15),
               (px_w * 0.05, px_h * 0.74, px_w * 0.95, px_h * 0.96), weight=700,
               fill=(0x00, 0xE5, 0xFF))
    return _save(img, name)


def bin_label(name, cn="可回收物", en="RECYCLABLE", width_m=0.22, height_m=0.14,
              px_w=256):
    """The small plate on a litter bin."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), WHITE)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w - 1, px_h - 1], fill=(0x1E, 0x6E, 0x45))
    d.rectangle([px_w * 0.05, px_h * 0.10, px_w * 0.95, px_h * 0.88],
                fill=WHITE)
    F.fit_text(d, cn, F.SMILEY, int(px_h * 0.34),
               (px_w * 0.08, px_h * 0.14, px_w * 0.92, px_h * 0.56), fill=(0x1E, 0x6E, 0x45))
    F.fit_text(d, en, F.NOTO, int(px_h * 0.17),
               (px_w * 0.08, px_h * 0.58, px_w * 0.92, px_h * 0.86), weight=500,
               fill=(0x33, 0x33, 0x36))
    return _save(img, name)


def spike_label(name, cn="破胎带", en="SPIKE STRIP", width_m=0.30, height_m=0.08,
                px_w=256):
    """The warning plate on a police spike-strip case."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0xE6, 0xB8, 0x00))
    d = ImageDraw.Draw(img)
    for i in range(0, px_w, max(6, px_w // 12)):    # hazard chevrons
        d.polygon([(i, 0), (i + px_w // 24, 0), (i + px_w // 24 - px_h, px_h),
                   (i - px_h, px_h)], fill=(0x18, 0x18, 0x1A))
    d.rectangle([0, 0, px_w - 1, px_h - 1], outline=(0x18, 0x18, 0x1A), width=2)
    F.fit_text(d, cn, F.SMILEY, int(px_h * 0.42),
               (px_w * 0.10, px_h * 0.10, px_w * 0.60, px_h * 0.90),
               fill=(0x18, 0x18, 0x1A))
    F.fit_text(d, en, F.NOTO, int(px_h * 0.30),
               (px_w * 0.60, px_h * 0.26, px_w * 0.97, px_h * 0.80), weight=700,
               fill=(0x18, 0x18, 0x1A))
    return _save(img, name)


def build_all():
    out = []
    out.append(road_name("roadname_xianggang", "香港路", "Xianggang Rd.", 80, 58, ew=True))
    out.append(road_name("roadname_nanjing", "南京东路", "Nanjing Rd. E", 520, 1250, ew=True))
    out.append(road_name("roadname_shenchang", "申长路", "Shenchang Rd.", 12, 340, ew=False))
    out.append(vms("vms_congestion"))
    out.append(bus_ad("bus_ad"))
    out.append(bus_route("bus_route"))
    out.append(metro_totem("metro_totem", "世纪大道", "Century Avenue", "8"))
    out.append(police_board("police_board"))
    out.append(countdown("countdown_23", "23"))
    out.append(countdown("countdown_08", "08"))
    out.append(fuel_price("fuel_price"))
    out.append(projector_screen("projector_screen"))
    out.append(bin_label("bin_label"))
    out.append(spike_label("spike_label"))
    return out


if __name__ == "__main__":
    for p in build_all():
        print("SIGN %s" % p)


def billboard_ad(name, width_m=8.0, height_m=4.0, px_w=2048):
    """Large LED billboard face (parody brand, art dossier §7.1)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x08, 0x0A, 0x12))
    d = ImageDraw.Draw(img)
    for i in range(0, px_h, 4):                      # faint LED pixel grid
        d.line([(0, i), (px_w, i)], fill=(0x12, 0x14, 0x1E), width=1)
    d.rectangle([0, 0, px_w, px_h * 0.12], fill=(0x2A, 0x10, 0x38))
    F.fit_text(d, "浦江电讯", F.SMILEY, int(px_h * 0.20),
               (px_w * 0.04, px_h * 0.16, px_w * 0.60, px_h * 0.48), fill=(0xFF, 0x2A, 0x8A))
    F.fit_text(d, "PUJIANG TELECOM", F.NOTO, int(px_h * 0.075),
               (px_w * 0.04, px_h * 0.50, px_w * 0.60, px_h * 0.60), weight=700,
               fill=(0xFF, 0x2A, 0x8A))
    F.fit_text(d, "5G 全面覆盖  光速城市", F.NOTO, int(px_h * 0.062),
               (px_w * 0.04, px_h * 0.66, px_w * 0.62, px_h * 0.78), weight=500,
               fill=(0xF2, 0xF6, 0xFF))
    F.fit_text(d, "光纤到家 · 装宽带请拨 9688", F.NOTO, int(px_h * 0.048),
               (px_w * 0.04, px_h * 0.80, px_w * 0.62, px_h * 0.90), weight=500,
               fill=(0x9A, 0xA4, 0xC0))
    d.rectangle([px_w * 0.66, px_h * 0.16, px_w * 0.97, px_h * 0.88], fill=(0x18, 0x1C, 0x30))
    for i in range(6):
        x = px_w * (0.68 + i * 0.048)
        h = px_h * (0.10 + 0.035 * ((i * 5) % 7))
        d.rectangle([x, px_h * 0.84 - h, x + px_w * 0.028, px_h * 0.84],
                    fill=(0xFF, 0x2A, 0x8A))
    return _save(img, name)


def build_all_extra():
    out = [billboard_ad("billboard_ad")]
    return out


def neon_blade(name, cn="东方霓虹", width_m=1.20, height_m=4.00, px_w=384,
               colour=(0xFF, 0x2B, 0xD6)):
    """Vertical neon blade sign (Nanjing Rd style, art dossier §7.1)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x07, 0x07, 0x0A))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w - 1, px_h - 1], outline=(0x2A, 0x2C, 0x34), width=4)
    n = len(cn)
    cell = px_h * 0.86 / n
    for i, ch in enumerate(cn):
        cy = px_h * 0.07 + cell * (i + 0.5)
        F.fit_text(d, ch, F.SMILEY, int(cell * 0.82), (px_w * 0.10, cy - cell * 0.5,
                                                       px_w * 0.90, cy + cell * 0.5),
                   fill=colour)
    d.rectangle([px_w * 0.06, px_h * 0.02, px_w * 0.10, px_h * 0.98], fill=colour)
    d.rectangle([px_w * 0.90, px_h * 0.02, px_w * 0.94, px_h * 0.98], fill=colour)
    return _save(img, name)
