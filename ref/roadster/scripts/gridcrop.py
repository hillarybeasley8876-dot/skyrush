"""Crop regions, overlay a source-pixel grid, stack vertically.
usage: gridcrop.py out.jpg width step img:x0:y0:x1:y1 [img:x0:y0:x1:y1 ...]"""
import sys
sys.path.append("/Users/minimax/Library/Python/3.9/lib/python/site-packages")
from PIL import Image, ImageDraw, ImageFont, ImageOps
import os

def crop_with_grid(spec: str, width: int, step: int) -> Image.Image:
    path, x0, y0, x1, y1 = spec.rsplit(":", 4)
    x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
    im = Image.open(path).convert("RGB").crop((x0, y0, x1, y1))
    if os.environ.get("AUTOC"):
        im = ImageOps.autocontrast(im, cutoff=float(os.environ["AUTOC"]))
    s = width / im.width
    im = im.resize((width, round(im.height * s)), Image.LANCZOS)
    d = ImageDraw.Draw(im, "RGBA")
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 13)
    gx = (x0 // step + 1) * step
    while gx < x1:
        X = (gx - x0) * s
        d.line([(X, 0), (X, im.height)], fill=(0, 255, 255, 90), width=1)
        d.text((X + 2, 2), str(gx), fill=(0, 255, 255, 255), font=font)
        gx += step
    gy = (y0 // step + 1) * step
    while gy < y1:
        Y = (gy - y0) * s
        d.line([(0, Y), (im.width, Y)], fill=(255, 0, 255, 90), width=1)
        d.text((2, Y + 1), str(gy), fill=(255, 0, 255, 255), font=font)
        gy += step
    return im

def main() -> None:
    out, width, step = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    tiles = [crop_with_grid(sp, width, step) for sp in sys.argv[4:]]
    sheet = Image.new("RGB", (width, sum(t.height for t in tiles)), (0, 0, 0))
    y = 0
    for t in tiles:
        sheet.paste(t, (0, y))
        y += t.height
    sheet.save(out, "JPEG", quality=80)
    print(out, sheet.size)

if __name__ == "__main__":
    main()
