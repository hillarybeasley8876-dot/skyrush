"""Build the contact sheet of the neon sign cells (the evidence of the text fitting).

    python3 blender/city/buildings/sign_sheet.py [--out captures/blocks_signs.jpg]

It cuts every cell of the vertical and the horizontal neon atlas out of the texture
and lays them out in a grid, so a reviewer can read the names and see that none of
them is truncated.
"""
import argparse
import json
import os

from PIL import Image

TEX_DIR = os.path.expanduser("~/m/skyrush/game/assets/city/_tex")
OUT = os.path.expanduser("~/m/skyrush/captures/blocks_signs.jpg")
COLS = 8
CELL = 190


def cells_of(atlas, manifest, prefix):
    """The cells of one atlas, in the order of the manifest."""
    out = []
    for entry in manifest:
        if entry.get("atlas") != atlas:
            continue
        out.append(entry)
    return out


def sheet(entries, image, out, title):
    """One grid of cropped cells."""
    rows = (len(entries) + COLS - 1) // COLS
    canvas = Image.new("RGB", (COLS * CELL, rows * CELL), (14, 14, 18))
    for i, entry in enumerate(entries):
        u0, v0, u1, v1 = entry["u0"], entry["v0"], entry["u1"], entry["v1"]
        w, h = image.size
        # the manifest is in the Blender UV convention (v from the bottom)
        box = (int(u0 * w), int((1.0 - v1) * h), int(u1 * w), int((1.0 - v0) * h))
        crop = image.crop(box)
        crop.thumbnail((CELL - 8, CELL - 8))
        x = (i % COLS) * CELL + 4
        y = (i // COLS) * CELL + 4
        canvas.paste(crop, (x, y))
    canvas.save(out, quality=90)
    print("%s: %d cells -> %s" % (title, len(entries), out))
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=OUT)
    opts = ap.parse_args()
    manifest = json.load(open(os.path.join(TEX_DIR, "signs.json")))
    vertical = Image.open(os.path.join(TEX_DIR, "neon_vertical.jpg"))
    horizontal = Image.open(os.path.join(TEX_DIR, "neon_horizontal.jpg"))
    v_cells = cells_of("neon_vertical", manifest, "v")
    h_cells = cells_of("neon_horizontal", manifest, "h")
    a = sheet(v_cells, vertical, opts.out.replace(".jpg", "_v.jpg"), "blade")
    b = sheet(h_cells, horizontal, opts.out.replace(".jpg", "_h.jpg"), "fascia")
    # one contact sheet with both
    width = max(a.width, b.width)
    canvas = Image.new("RGB", (width, a.height + b.height), (10, 10, 14))
    canvas.paste(a, (0, 0))
    canvas.paste(b, (0, a.height))
    canvas.save(opts.out, quality=90)
    print("contact sheet -> %s" % opts.out)


if __name__ == "__main__":
    main()
