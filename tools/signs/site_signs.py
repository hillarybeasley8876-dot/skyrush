"""Site sign textures: toll plaza fascia and lane signals, gas station fascia and
price pylon, sky-lane gantry and chevrons.

Dossier §7 (toll plaza), §8 (gas + charging), gameplay dossier §5.6 (sky lanes).
The boards of the charging hub live in `site_signs_charge.py`.
"""
import os

from PIL import Image, ImageDraw

import fontlib as F
from surfaces import TEX_DIR
import imwrite as IW
from site_signs_charge import (charge_bolt, charge_kw_readout, charge_post_text,
                               charge_totem)

WHITE = (0xFF, 0xFF, 0xFF)
BLACK = (0x0A, 0x0A, 0x0C)
GREEN = (0x00, 0x70, 0x4A)
BLUE = (0x1F, 0x57, 0xC3)
RED = (0xE6, 0x00, 0x12)
CYAN = (0x00, 0xE5, 0xFF)
MAGENTA = (0xFF, 0x2B, 0xD6)
NIGHT_PANEL = (0x0A, 0x1A, 0x2A)


def _save(img, name):
    os.makedirs(TEX_DIR, exist_ok=True)
    path = os.path.join(TEX_DIR, "%s.png" % name)
    IW.save(img, path, format="PNG")
    return path

# ------------------------------------------------------------------ toll plaza
def _panel_seams(d, px_w, px_h, ppm, colour=(0, 0, 0), width=2):
    """Aluminium composite panel seams (1.2 x 0.6 m, dossier §15): thin dark lines."""
    step_x = 1.2 * ppm
    step_y = 0.6 * ppm
    x = step_x
    while x < px_w:
        d.line([(x, 0), (x, px_h)], fill=colour, width=width)
        x += step_x
    y = step_y
    while y < px_h:
        d.line([(0, y), (px_w, y)], fill=colour, width=width)
        y += step_y


def toll_fascia(name, cn="申城西收费站", en="SHENCHENG WEST TOLL", width_m=24.0,
                height_m=2.4, px_w=2048):
    """The green name panel on the toll canopy bull-nose (8 m of the fascia band)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), GREEN)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w - 1, px_h - 1], outline=WHITE, width=max(2, px_h // 30))
    ppm = px_w / width_m
    F.fit_text(d, cn, F.SMILEY, int(0.78 * ppm), (px_w * 0.04, px_h * 0.08, px_w * 0.62,
                                                  px_h * 0.92), fill=WHITE)
    F.fit_text(d, en, F.NOTO, int(0.30 * ppm), (px_w * 0.63, px_h * 0.34, px_w * 0.97,
                                                px_h * 0.72), weight=700, fill=WHITE)
    return _save(img, name)


def toll_lane_label(name, cn, en, width_m=1.6, height_m=0.5, px_w=1024):
    """Lane label strip under the fascia: blue for ETC-only, white for mixed."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), BLUE)
    d = ImageDraw.Draw(img)
    ppm = px_w / width_m
    F.fit_text(d, cn, F.NOTO, int(0.26 * ppm), (px_w * 0.05, px_h * 0.08, px_w * 0.95,
                                                px_h * 0.58), weight=700, fill=WHITE)
    F.fit_text(d, en, F.NOTO, int(0.14 * ppm), (px_w * 0.05, px_h * 0.56, px_w * 0.95,
                                                px_h * 0.94), weight=500, fill=WHITE)
    return _save(img, name)


def toll_etc_strip(name, width_m=3.0, height_m=0.5, px_w=768):
    """Green LED 'ETC' strip on the fascia."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x03, 0x0A, 0x07))
    d = ImageDraw.Draw(img)
    ppm = px_w / width_m
    F.fit_text(d, "ETC", F.SMILEY, int(0.34 * ppm), (px_w * 0.05, px_h * 0.10, px_w * 0.95,
                                                     px_h * 0.90), fill=(0x20, 0xE0, 0x70))
    return _save(img, name)


def _cross(d, cx, cy, size, colour, thick):
    arm = size * 0.62
    d.polygon([(cx - arm, cy - arm * 0.30), (cx - arm * 0.30, cy - arm), (cx + arm, cy + arm * 0.30),
               (cx + arm * 0.30, cy + arm), (cx - arm, cy - arm * 0.30)], fill=colour)
    del thick


def _bar(d, p0, p1, half_w, colour):
    """A rectangle between two points (used for the red X strokes)."""
    import math
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / length * half_w, dx / length * half_w
    d.polygon([(p0[0] + nx, p0[1] + ny), (p1[0] + nx, p1[1] + ny),
               (p1[0] - nx, p1[1] - ny), (p0[0] - nx, p0[1] - ny)], fill=colour)


def toll_signal(name, kind, size_m=0.8, px=512):
    """Lane control light face: red X (closed) or green down arrow (open)."""
    img = Image.new("RGB", (px, px), (0x08, 0x08, 0x0A))
    d = ImageDraw.Draw(img)
    cx, cy = px / 2.0, px / 2.0
    if kind == "red":
        a = px * 0.28
        t = px * 0.075
        _bar(d, (cx - a, cy - a), (cx + a, cy + a), t, (0xFF, 0x2A, 0x2A))
        _bar(d, (cx + a, cy - a), (cx - a, cy + a), t, (0xFF, 0x2A, 0x2A))
    else:
        d.rectangle([cx - px * 0.055, cy - px * 0.26, cx + px * 0.055, cy + px * 0.10],
                    fill=(0x20, 0xE0, 0x70))
        d.polygon([(cx - px * 0.20, cy + px * 0.06), (cx + px * 0.20, cy + px * 0.06),
                   (cx, cy + px * 0.30)], fill=(0x20, 0xE0, 0x70))
    return _save(img, name)


# ------------------------------------------------------------------ gas station
def gas_fascia(name, cn="中国石华", en="SINOPEX", width_m=16.0, height_m=1.0, px_w=2048):
    """Red name panel with the parody brand: name and Latin word adjacent, thin seams."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), RED)
    d = ImageDraw.Draw(img)
    ppm = px_w / width_m
    F.fit_text(d, cn, F.SMILEY, int(0.74 * ppm), (px_w * 0.04, px_h * 0.10, px_w * 0.56,
                                                  px_h * 0.90), fill=WHITE)
    F.fit_text(d, en, F.NOTO, int(0.40 * ppm), (px_w * 0.58, px_h * 0.30, px_w * 0.97,
                                                px_h * 0.74), weight=700, fill=WHITE)
    _panel_seams(d, px_w, px_h, ppm, (0x6A, 0x00, 0x06), width=2)
    return _save(img, name)


def gas_logo(name, width_m=2.6, height_m=0.95, px_w=256):
    """The brand end cap of the fascia: the logo mark on a red field."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), RED)
    d = ImageDraw.Draw(img)
    cx, cy = px_w * 0.5, px_h * 0.5
    r = min(px_w, px_h) * 0.36
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=WHITE, width=max(2, px_h // 14))
    d.polygon([(cx - r * 0.30, cy + r * 0.45), (cx + r * 0.22, cy - r * 0.55),
               (cx + r * 0.42, cy - r * 0.18), (cx - r * 0.08, cy + r * 0.62)],
              fill=WHITE)
    return _save(img, name)


def gas_pylon_crown(name, cn="中国石华", en="SINOPEX", width_m=1.9, height_m=1.1,
                    px_w=512):
    """The crown board of the 9 m price pylon."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), RED)
    d = ImageDraw.Draw(img)
    ppm = px_w / width_m
    F.fit_text(d, cn, F.SMILEY, int(0.62 * ppm), (px_w * 0.05, px_h * 0.10, px_w * 0.58,
                                                  px_h * 0.90), fill=WHITE)
    F.fit_text(d, en, F.NOTO, int(0.34 * ppm), (px_w * 0.60, px_h * 0.30, px_w * 0.96,
                                                px_h * 0.74), weight=700, fill=WHITE)
    return _save(img, name)


def gas_price_board(name, width_m=1.8, height_m=2.4, px_w=768):
    """Price pylon board: 92#/95#/98#/0# with red digits."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x11, 0x11, 0x14))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w, px_h * 0.16], fill=RED)
    F.fit_text(d, "今日油价", F.SMILEY, int(px_h * 0.10),
               (px_w * 0.05, px_h * 0.015, px_w * 0.95, px_h * 0.145), fill=WHITE)
    F.fit_text(d, "TODAY'S PRICE", F.NOTO, int(px_h * 0.045),
               (px_w * 0.05, px_h * 0.145, px_w * 0.95, px_h * 0.20), weight=500, fill=WHITE)
    rows = (("92#", "7.28"), ("95#", "7.79"), ("98#", "8.91"), ("0#", "7.15"))
    y = px_h * 0.24
    row_h = (px_h * 0.74) / len(rows)
    for label, value in rows:
        F.fit_text(d, label, F.NOTO, int(row_h * 0.42), (px_w * 0.06, y, px_w * 0.38,
                                                         y + row_h * 0.72), weight=700,
                   fill=(0xFF, 0xD2, 0x3F))
        F.fit_text(d, value, F.NOTO, int(row_h * 0.50), (px_w * 0.40, y, px_w * 0.95,
                                                         y + row_h * 0.72), weight=700,
                   fill=(0xFF, 0x3B, 0x30))
        y += row_h
    return _save(img, name)


def gas_store_band(name, cn="易快", en="EZ-JOY", width_m=8.0, height_m=0.8, px_w=1536):
    """Storefront band above the shop doors."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), WHITE)
    d = ImageDraw.Draw(img)
    ppm = px_w / width_m
    F.fit_text(d, cn, F.SMILEY, int(0.52 * ppm), (px_w * 0.04, px_h * 0.10, px_w * 0.56,
                                                  px_h * 0.90), fill=RED)
    F.fit_text(d, en, F.NOTO, int(0.34 * ppm), (px_w * 0.56, px_h * 0.18, px_w * 0.97,
                                                px_h * 0.82), weight=700, fill=RED)
    d.rectangle([0, 0, px_w, px_h * 0.10], fill=RED)
    d.rectangle([0, px_h * 0.90, px_w, px_h], fill=RED)
    return _save(img, name)


# ------------------------------------------------------------------ sky lane
def sky_lane_gantry_sign(name, cn="飞行航道", en="SKY LANE", dist="300 m",
                         width_m=6.0, height_m=1.8, px_w=2048):
    """Overhead sky-lane sign: cyan text on a dark panel (gameplay dossier §5.6)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), NIGHT_PANEL)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w - 1, px_h - 1], outline=CYAN, width=max(3, px_h // 30))
    ppm = px_w / width_m
    F.fit_text(d, cn, F.SMILEY, int(0.72 * ppm), (px_w * 0.04, px_h * 0.10, px_w * 0.66,
                                                  px_h * 0.60), fill=CYAN)
    F.fit_text(d, en, F.NOTO, int(0.26 * ppm), (px_w * 0.04, px_h * 0.62, px_w * 0.66,
                                                px_h * 0.92), weight=700, fill=CYAN)
    F.triangle(d, px_w * 0.80, px_h * 0.36, px_h * 0.26, CYAN, up=True)
    F.fit_text(d, dist, F.NOTO, int(0.34 * ppm), (px_w * 0.66, px_h * 0.50, px_w * 0.98,
                                                  px_h * 0.92), weight=700, fill=CYAN)
    return _save(img, name)


def sky_lane_chevron(name, colour=CYAN, width_m=1.6, height_m=2.4, px_w=256):
    """One animated chevron plate for the launch ramp (cyan) or the ring gate (magenta)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x05, 0x0A, 0x10))
    d = ImageDraw.Draw(img)
    band = px_h * 0.30
    for i in range(3):
        y = px_h * (0.18 + i * 0.26)
        d.polygon([(px_w * 0.08, y + band), (px_w * 0.5, y), (px_w * 0.92, y + band),
                   (px_w * 0.92, y + band * 1.35), (px_w * 0.5, y + band * 0.35),
                   (px_w * 0.08, y + band * 1.35)], fill=colour)
    return _save(img, name)


def sky_lane_pad_arrow(name, width_m=1.4, height_m=4.0, px_w=256):
    """Cyan road arrow painted before the launch pad (gameplay dossier §5.6)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x0C, 0x0E, 0x12))
    d = ImageDraw.Draw(img)
    cx = px_w * 0.5
    head_w, head_h = px_w * 0.62, px_h * 0.26
    shaft_w = px_w * 0.24
    d.polygon([(cx - shaft_w / 2, px_h * 0.10), (cx + shaft_w / 2, px_h * 0.10),
               (cx + shaft_w / 2, px_h * 0.10 + head_h),
               (cx + head_w / 2, px_h * 0.10 + head_h),
               (cx, px_h * 0.10 + head_h + head_h * 1.25),
               (cx - head_w / 2, px_h * 0.10 + head_h),
               (cx - shaft_w / 2, px_h * 0.10 + head_h)], fill=CYAN)
    d.rectangle([cx - shaft_w / 2, px_h * 0.10 + head_h, cx + shaft_w / 2, px_h * 0.92],
                fill=CYAN)
    return _save(img, name)


def build_all():
    out = []
    out.append(toll_fascia("toll_fascia"))
    out.append(toll_lane_label("toll_lane_etc", "ETC 专用", "ETC ONLY"))
    out.append(toll_lane_label("toll_lane_mixed", "ETC/人工", "ETC / MANUAL"))
    out.append(toll_etc_strip("toll_etc_strip"))
    out.append(toll_signal("toll_signal_red", "red"))
    out.append(toll_signal("toll_signal_green", "green"))
    out.append(gas_fascia("gas_fascia"))
    out.append(gas_price_board("gas_price_board"))
    out.append(gas_store_band("gas_store_band"))
    out.append(charge_totem("charge_totem"))
    out.append(charge_post_text("charge_post_volta"))
    out.append(charge_kw_readout("charge_kw_500"))
    out.append(sky_lane_gantry_sign("skylane_gantry_sign"))
    out.append(sky_lane_chevron("skylane_chevron_cyan", CYAN))
    out.append(sky_lane_chevron("skylane_chevron_magenta", MAGENTA))
    out.append(sky_lane_pad_arrow("skylane_pad_arrow"))
    return out


if __name__ == "__main__":
    for p in build_all():
        print("SIGN %s" % p)


def barrier_arm(name, width_m=3.0, height_m=0.14, px_w=768):
    """Red/white banded barrier arm (0.5 m bands, dossier §7.2)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0xB4, 0x06, 0x0A))
    d = ImageDraw.Draw(img)
    bands = int(round(width_m / 0.5))
    for i in range(bands):
        if i % 2 == 0:
            d.rectangle([px_w * i / bands, 0, px_w * (i + 1) / bands, px_h],
                        fill=(0xF0, 0xF0, 0xEC))
    d.rectangle([0, 0, px_w, max(1, px_h * 0.12)], fill=(0x6A, 0x04, 0x07))
    d.rectangle([0, px_h * 0.88, px_w, px_h], fill=(0x6A, 0x04, 0x07))
    return _save(img, name)


def build_all_extra():
    out = [barrier_arm("barrier_arm")]
    return out


def bay_number(name, number, size=256):
    """A white bay number painted on the charging bay (transparent PNG)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    F.fit_text(d, "%02d" % number, F.NOTO, int(size * 0.70), (0, 0, size, size),
               weight=700, fill=WHITE)
    path = os.path.join(TEX_DIR, "%s.png" % name)
    IW.save(img, path, format="PNG")
    return path


def build_all_bays():
    return [bay_number("bay_number_%02d" % i, i) for i in range(1, 13)]


def digital_battery(name, width_m=0.30, height_m=0.18, px_w=384):
    """A small status readout (battery on the e-scooter and the bike-share docks)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x08, 0x0A, 0x0C))
    d = ImageDraw.Draw(img)
    bw, bh = px_w * 0.30, px_h * 0.46
    x0, y0 = px_w * 0.12, (px_h - bh) * 0.5
    d.rectangle([x0, y0, x0 + bw, y0 + bh], outline=(0x3B, 0xFF, 0x88), width=3)
    d.rectangle([x0 + bw, y0 + bh * 0.3, x0 + bw + px_w * 0.03, y0 + bh * 0.7],
                fill=(0x3B, 0xFF, 0x88))
    d.rectangle([x0 + 4, y0 + 4, x0 + bw * 0.78, y0 + bh - 4], fill=(0x3B, 0xFF, 0x88))
    F.fit_text(d, "OK", F.NOTO, int(px_h * 0.30), (px_w * 0.52, px_h * 0.26,
                                                    px_w * 0.95, px_h * 0.74),
               weight=700, fill=(0x3B, 0xFF, 0x88))
    return _save(img, name)


def build_all_extra2():
    return [digital_battery("digital_battery"), charge_bolt("charge_bolt")]
