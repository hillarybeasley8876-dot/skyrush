"""Contact sheet: sheet.py out.jpg cols tile_w file1 file2 ... (labels = file stem)."""
import sys
sys.path.append("/Users/minimax/Library/Python/3.9/lib/python/site-packages")
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

def main() -> None:
    out, cols, tw = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    files = sys.argv[4:]
    ims = []
    for f in files:
        im = Image.open(f).convert("RGB")
        h = round(im.height * tw / im.width)
        ims.append((Path(f).stem, im.resize((tw, h), Image.LANCZOS)))
    th = max(i.height for _, i in ims)
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * th), (40, 40, 40))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    for k, (name, im) in enumerate(ims):
        x, y = (k % cols) * tw, (k // cols) * th
        sheet.paste(im, (x, y))
        d.rectangle([x, y, x + 8 + 13 * len(name), y + 28], fill=(0, 0, 0))
        d.text((x + 4, y + 2), name, fill=(255, 255, 0), font=font)
    sheet.save(out, "JPEG", quality=72)
    print(out, sheet.size)

if __name__ == "__main__":
    main()
