"""The boards of the charging hub (unit: props).

The totem, the VOLTA post text, the kW read-out and the lightning bolt of the
charging hub (dossier §8.2).

    /usr/bin/python3 tools/signs/site_signs_charge.py
"""
import os

from PIL import Image, ImageDraw

import fontlib as F
import imwrite as IW
from surfaces import TEX_DIR

WHITE = (0xFF, 0xFF, 0xFF)
BLACK = (0x0A, 0x0A, 0x0C)
CYAN = (0x00, 0xE5, 0xFF)
GREEN = (0x3B, 0xFF, 0x88)


def _save(img, name):
    os.makedirs(TEX_DIR, exist_ok=True)
    path = os.path.join(TEX_DIR, "%s.png" % name)
    IW.save(img, path, format="PNG")
    return path


def charge_totem(name, width_m=1.2, height_m=7.0, px_w=384):
    """Tall totem with the lightning bolt and the parody flash-charge brand."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0xF3, 0xF5, 0xF7))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px_w, px_h * 0.05], fill=CYAN)
    bolt = [(px_w * 0.78, px_h * 0.075), (px_w * 0.58, px_h * 0.145), (px_w * 0.70, px_h * 0.145),
            (px_w * 0.60, px_h * 0.215), (px_w * 0.84, px_h * 0.135), (px_w * 0.72, px_h * 0.135)]
    d.polygon(bolt, fill=CYAN)
    F.fit_text(d, "闪充", F.SMILEY, int(px_w * 0.26), (px_w * 0.05, px_h * 0.07,
                                                       px_w * 0.56, px_h * 0.19), fill=BLACK)
    F.fit_text(d, "SKY 闪充 FLASH", F.NOTO, int(px_w * 0.085),
               (px_w * 0.05, px_h * 0.22, px_w * 0.95, px_h * 0.27), weight=700, fill=BLACK)
    F.fit_text(d, "1000 kW", F.SMILEY, int(px_w * 0.20), (px_w * 0.05, px_h * 0.28,
                                                          px_w * 0.95, px_h * 0.36), fill=CYAN)
    F.fit_text(d, "超快充电 ULTRA FAST CHARGE", F.NOTO, int(px_w * 0.055),
               (px_w * 0.05, px_h * 0.56, px_w * 0.95, px_h * 0.60), weight=500,
               fill=(0x44, 0x4A, 0x52))
    d.rectangle([0, px_h * 0.66, px_w, px_h * 0.70], fill=(0x1E, 0x9E, 0x5A))
    F.fit_text(d, "12 充电车位  BAY 01-12", F.NOTO, int(px_w * 0.055),
               (px_w * 0.05, px_h * 0.71, px_w * 0.95, px_h * 0.75), weight=500, fill=BLACK)
    F.fit_text(d, "24 小时营业  OPEN 24H", F.NOTO, int(px_w * 0.055),
               (px_w * 0.05, px_h * 0.76, px_w * 0.95, px_h * 0.80), weight=500,
               fill=(0x44, 0x4A, 0x52))
    return _save(img, name)


def charge_post_text(name, width_m=0.30, height_m=0.20, px=512):
    """Lit 'VOLTA' lettering plate for the slim charging post."""
    w, h = px, int(px * height_m / width_m)
    img = Image.new("RGB", (w, h), (0xF0, 0xF1, 0xF3))
    d = ImageDraw.Draw(img)
    F.fit_text(d, "VOLTA", F.NOTO, int(h * 0.62), (0, 0, w, h), weight=700,
               fill=(0xE3, 0x19, 0x37))
    return _save(img, name)


def charge_kw_readout(name, kw=500, width_m=1.1, height_m=0.5, px_w=1024):
    """Big digital kW readout on the dispensers."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x04, 0x08, 0x0C))
    d = ImageDraw.Draw(img)
    ppm = px_w / width_m
    F.fit_text(d, str(kw), F.SMILEY, int(0.36 * ppm), (px_w * 0.03, px_h * 0.06, px_w * 0.62,
                                                       px_h * 0.92), fill=(0x39, 0xFF, 0x88))
    F.fit_text(d, "kW", F.NOTO, int(0.22 * ppm), (px_w * 0.60, px_h * 0.18, px_w * 0.98,
                                                 px_h * 0.80), weight=700, fill=(0x39, 0xFF, 0x88))
    return _save(img, name)



def charge_bolt(name, width_m=1.30, height_m=2.00, px_w=256):
    """The cyan lightning bolt of the charging totem (a hero sign, E4)."""
    px_h = int(round(px_w * height_m / width_m))
    img = Image.new("RGB", (px_w, px_h), (0x04, 0x0A, 0x12))
    d = ImageDraw.Draw(img)
    cx, cy = px_w * 0.5, px_h * 0.5
    w = px_w * 0.30
    h = px_h * 0.40
    bolt = [(cx - w * 0.35, cy - h), (cx + w * 0.55, cy - h), (cx + w * 0.05, cy - h * 0.05),
            (cx + w * 0.65, cy - h * 0.05), (cx - w * 0.45, cy + h), (cx + w * 0.05, cy - h * 0.05),
            (cx - w * 0.65, cy - h * 0.05)]
    d.polygon(bolt, fill=(0x3C, 0xF2, 0xFF))
    d.polygon([(x * 0.72 + cx * 0.28, y * 0.72 + cy * 0.28) for x, y in bolt],
              fill=(0xB8, 0xFA, 0xFF))
    return _save(img, name)
