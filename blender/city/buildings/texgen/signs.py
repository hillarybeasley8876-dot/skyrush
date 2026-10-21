"""Builds the neon / plaque atlases and writes the slot manifest the Blender
building builder reads (blender/city/buildings/texgen/atlas_neon.py draws them).

Cell sizes follow the art dossier: a blade face is 1:3, a fascia lightbox 4:1, a
lane plaque 2:1.  Every slot is asserted to lie inside the atlas - a slot that
samples outside would show another sign's characters.
"""
import json
import os

from PIL import Image

from . import atlas as atl
from . import atlas_neon as an

V_ATLAS = (4096, 3072)
V_CELL = (256, 768)
H_ATLAS = (4096, 1024)
H_CELL = (512, 128)
P_ATLAS = (2048, 1024)
P_CELL = (256, 128)

COLOR_ORDER = ["red", "magenta", "cyan", "yellow", "green", "amber", "violet", "white"]


def _cells(atlas, cell):
    return (atlas[0] // cell[0]) * (atlas[1] // cell[1])


def _font_count():
    return max(1, len(an.available_fonts()))


def build_vertical():
    """Vertical blade signs (neon characters on a dark back plate)."""
    w, h = V_ATLAS
    img = Image.new("RGB", (w, h), (0, 0, 0))
    manifest = []
    cols = w // V_CELL[0]
    for i, name in enumerate(an.BLADE_NAMES):
        if i >= _cells(V_ATLAS, V_CELL):
            break
        cx = (i % cols) * V_CELL[0]
        cy = (i // cols) * V_CELL[1]
        cname = COLOR_ORDER[i % len(COLOR_ORDER)]
        colour = an.NEON_COLS[cname]
        cell = Image.new("RGB", V_CELL, (0, 0, 0))
        an.draw_vertical_cell(cell, name, colour, dead=(i % 12 == 11),
                              font_index=i % _font_count())
        img.paste(cell, (cx, cy))
        u0, v0, u1, v1 = atl.slot(w, h, cx, cy, V_CELL[0], V_CELL[1])
        manifest.append({"id": "blade_%02d" % i, "atlas": "neon_vertical", "text": name,
                         "color": cname, "u0": u0, "v0": v0, "u1": u1, "v1": v1,
                         "aspect": V_CELL[0] / float(V_CELL[1]), "style": "blade"})
    return img, manifest


def build_horizontal():
    """Fascia lightboxes: printed backlit panels with an English line and a phone."""
    w, h = H_ATLAS
    img = Image.new("RGB", (w, h), (0, 0, 0))
    manifest = []
    cols = w // H_CELL[0]
    for i, name in enumerate(an.BOX_NAMES):
        if i >= _cells(H_ATLAS, H_CELL):
            break
        cx = (i % cols) * H_CELL[0]
        cy = (i // cols) * H_CELL[1]
        ground = an.BOX_COLOURS[i % len(an.BOX_COLOURS)]
        ink = (250, 244, 230) if sum(ground) < 330 else (24, 22, 20)
        cell = Image.new("RGB", H_CELL, ground)
        an.draw_box_cell(cell, name, an.BOX_EN[i % len(an.BOX_EN)], ground, ink,
                         font_index=i % _font_count())
        img.paste(cell, (cx, cy))
        u0, v0, u1, v1 = atl.slot(w, h, cx, cy, H_CELL[0], H_CELL[1])
        manifest.append({"id": "box_%02d" % i, "atlas": "neon_horizontal", "text": name,
                         "color": "printed", "u0": u0, "v0": v0, "u1": u1, "v1": v1,
                         "aspect": H_CELL[0] / float(H_CELL[1]), "style": "box"})
    return img, manifest


def build_plaques():
    """Carved stone plaques for the lane names (弄里)."""
    w, h = P_ATLAS
    img = Image.new("RGB", (w, h), (0, 0, 0))
    manifest = []
    cols = w // P_CELL[0]
    for i, name in enumerate(an.LANE_NAMES):
        if i >= _cells(P_ATLAS, P_CELL):
            break
        cx = (i % cols) * P_CELL[0]
        cy = (i // cols) * P_CELL[1]
        cell = Image.new("RGB", P_CELL, (207, 200, 184))
        an.draw_plaque_cell(cell, name, font_index=i % _font_count())
        img.paste(cell, (cx, cy))
        u0, v0, u1, v1 = atl.slot(w, h, cx, cy, P_CELL[0], P_CELL[1])
        manifest.append({"id": "plaque_%02d" % i, "atlas": "plaques", "text": name,
                         "color": "stone", "u0": u0, "v0": v0, "u1": u1, "v1": v1,
                         "aspect": P_CELL[0] / float(P_CELL[1]), "style": "plaque"})
    return img, manifest


def build_fascia_red():
    """Red shop boards with gold characters (the second fascia template).

    The same shop names as the lightbox, printed in gold on a red board: a row of
    shopfronts in Shanghai carries both, and the two must not look alike.
    """
    w, h = H_ATLAS
    img = Image.new("RGB", (w, h), (0, 0, 0))
    manifest = []
    cols = w // H_CELL[0]
    ground = (156, 32, 28)
    ink = (238, 202, 96)
    for i, name in enumerate(an.BOX_NAMES):
        if i >= _cells(H_ATLAS, H_CELL):
            break
        cx = (i % cols) * H_CELL[0]
        cy = (i // cols) * H_CELL[1]
        cell = Image.new("RGB", H_CELL, ground)
        an.draw_box_cell(cell, name, an.BOX_EN[i % len(an.BOX_EN)], ground, ink,
                         font_index=i % _font_count())
        img.paste(cell, (cx, cy))
        u0, v0, u1, v1 = atl.slot(w, h, cx, cy, H_CELL[0], H_CELL[1])
        manifest.append({"id": "redbox_%02d" % i, "atlas": "fascia_red", "text": name,
                         "color": "red", "u0": u0, "v0": v0, "u1": u1, "v1": v1,
                         "aspect": H_CELL[0] / float(H_CELL[1]), "style": "redbox"})
    return img, manifest


def write_atlases(out_dir):
    """Render the sign atlases to `out_dir`; returns their combined manifest list."""
    os.makedirs(out_dir, exist_ok=True)
    manifest = []
    for name, fn in (("neon_vertical", build_vertical), ("neon_horizontal", build_horizontal),
                     ("fascia_red", build_fascia_red), ("plaques", build_plaques)):
        img, entries = fn()
        img.save(os.path.join(out_dir, name + ".jpg"), quality=92)
        manifest.extend(entries)
    return manifest


def write_manifest(out_dir, entries):
    """Write the shared slot manifest (signs, props, cloth, interiors)."""
    path = os.path.join(out_dir, "signs.json")
    with open(path, "w") as fh:
        json.dump(entries, fh, ensure_ascii=False, indent=1)
    return path


def write_all(out_dir, extra=None):
    """Render every sign atlas and write the slot manifest."""
    manifest = write_atlases(out_dir)
    manifest.extend(extra or [])
    write_manifest(out_dir, manifest)
    return manifest
