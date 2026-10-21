"""Green expressway guide-sign panels (unit: props).

Dossier §2.6 / GB 5768.2: green ground #00704A, white text and arrows, Chinese cap
height 0.55 m above an English line of 0.28 m, one arrow per lane.

    from guide_sign import guide_panel
    guide_panel("guide_yanan", 3.6, 2.2, [("延安高架路", "Yan'an Elevated Rd", "up")])

The panel size is given in metres so the text lands at the right physical size;
the texture is rasterised at 2048 px across (>= 512 px/m on a 4 m panel).
"""
import os

from PIL import Image, ImageDraw

import fontlib as F
from surfaces import TEX_DIR
import imwrite as IW

GREEN = (0x00, 0x70, 0x4A)
WHITE = (0xFF, 0xFF, 0xFF)


def _px_per_m(width_m, px_w):
    return px_w / max(width_m, 1e-3)


def _cn_size(px_per_m, cap_m):
    """Font size whose CJK glyphs are ~cap_m tall."""
    return max(8, int(round(cap_m * px_per_m / 0.93)))


def _en_size(px_per_m, cap_m):
    """Font size whose Latin caps are ~cap_m tall (Noto cap height ~0.71 em)."""
    return max(6, int(round(cap_m * px_per_m / 0.71)))


def _border(draw, w, h, inset, width, colour):
    draw.rectangle([inset, inset, w - inset, h - inset], outline=colour, width=width)


def _dirt(img, strength=0.16):
    """Road signs are dirty at the bottom (dossier §15): a soft upward grime gradient."""
    import numpy as np
    w, h = img.size
    grad = np.linspace(0.0, 1.0, h, dtype=np.float32) ** 2.2
    arr = np.asarray(img).astype(np.float32) * (1.0 - grad[:, None, None] * strength)
    return Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGB")


def _arrow(draw, cx, cy, length, width, direction, colour):
    F.arrow(draw, cx - length / 2.0, cy - width / 2.0, length, width, colour, direction)


def guide_panel(name, width_m, height_m, rows, px_w=2048, layout="list", arrow_side="right"):
    """Render one guide panel.

    rows  -- list of (chinese, english, arrow) tuples; arrow in {None,"up","left","right"}
    layout -- "list" (rows of destinations) or "exit" (one big destination + arrow)
    """
    px_h = max(64, int(round(px_w * height_m / width_m)))
    ppm = _px_per_m(width_m, px_w)
    img = Image.new("RGB", (px_w, px_h), GREEN)
    d = ImageDraw.Draw(img)
    _border(d, px_w, px_h, int(px_w * 0.012), max(2, int(px_w * 0.008)), WHITE)
    pad = px_w * 0.035
    inner = (pad, pad, px_w - pad, px_h - pad)

    if layout == "exit":
        cn, en, arr = rows[0]
        F.fit_text(d, cn, F.SMILEY, _cn_size(ppm, 0.70),
                   (inner[0], inner[1] + px_h * 0.04, inner[2], inner[1] + px_h * 0.46),
                   fill=WHITE)
        F.fit_text(d, en, F.NOTO, _en_size(ppm, 0.30),
                   (inner[0], inner[1] + px_h * 0.50, inner[2], inner[1] + px_h * 0.72),
                   fill=WHITE)
        if arr:
            _arrow(d, px_w / 2.0, px_h * 0.86, px_h * 0.20, px_h * 0.075, arr, WHITE)
    else:
        n = max(1, len(rows))
        row_h = (inner[3] - inner[1]) / n
        for i, (cn, en, arr) in enumerate(rows):
            top = inner[1] + i * row_h
            cn_h = row_h * 0.46
            en_h = row_h * 0.24
            arrow_w = px_w * 0.13
            if arrow_side == "right":
                tx0, tx1 = inner[0], inner[2] - arrow_w
                ax = inner[2] - arrow_w * 0.5
            else:
                tx0, tx1 = inner[0] + arrow_w, inner[2]
                ax = inner[0] + arrow_w * 0.5
            F.fit_text(d, cn, F.NOTO, _cn_size(ppm, 0.55),
                       (tx0, top + row_h * 0.08, tx1, top + row_h * 0.08 + cn_h), weight=700,
                       fill=WHITE, align="left")
            if en:
                F.fit_text(d, en, F.NOTO, _en_size(ppm, 0.28),
                           (tx0, top + row_h * 0.60, tx1, top + row_h * 0.60 + en_h), weight=500,
                           fill=WHITE, align="left")
            if arr:
                _arrow(d, ax, top + row_h * 0.44, arrow_w * 0.60, row_h * 0.24, arr, WHITE)
    img = _dirt(img)
    path = os.path.join(TEX_DIR, "%s.png" % name)
    os.makedirs(TEX_DIR, exist_ok=True)
    IW.save(img, path, format="PNG")
    return path


def build_all():
    """Every guide panel used by the gantry and the sky lane."""
    out = []
    out.append(guide_panel("guide_yanan", 4.2, 2.4, [
        ("延安高架路", "Yan'an Elevated Rd", "up"),
        ("南北高架路", "N-S Elevated Rd", "up"),
    ]))
    out.append(guide_panel("guide_bund", 4.2, 2.4, [
        ("外滩", "The Bund", "up"),
        ("陆家嘴", "Lujiazui", "up"),
    ]))
    out.append(guide_panel("guide_exit_xizang", 3.6, 2.4, [
        ("西藏中路 出口", "Xizang Rd (M) Exit", "right"),
        ("500 m", "", None),
    ]))
    out.append(guide_panel("guide_bridges", 4.2, 2.4, [
        ("南浦大桥", "Nanpu Bridge", "up"),
        ("内环高架", "Inner Ring", "up"),
    ]))
    out.append(guide_panel("guide_airport", 4.2, 2.4, [
        ("虹桥机场", "Hongqiao Airport", "up"),
        ("G50 沪渝高速", "G50 Huyu Expressway", "up"),
    ]))
    out.append(guide_panel("guide_tunnel", 4.2, 2.4, [
        ("延安东路隧道", "Yan'an E. Rd Tunnel", "up"),
        ("外滩隧道", "Bund Tunnel", "up"),
    ]))
    out.append(guide_panel("guide_skid", 3.2, 2.0, [
        ("出口", "EXIT", "right"),
    ]))
    return out


if __name__ == "__main__":
    for p in build_all():
        print("SIGN %s" % p)
