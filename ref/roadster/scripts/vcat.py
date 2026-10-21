"""Vertically stack images scaled to the same width: vcat.py out.jpg width img1 img2 ..."""
import sys
sys.path.append("/Users/minimax/Library/Python/3.9/lib/python/site-packages")
from PIL import Image

def main() -> None:
    out, w = sys.argv[1], int(sys.argv[2])
    ims = [Image.open(p).convert("RGB") for p in sys.argv[3:]]
    ims = [i.resize((w, round(i.height * w / i.width)), Image.LANCZOS) for i in ims]
    sheet = Image.new("RGB", (w, sum(i.height for i in ims)))
    y = 0
    for i in ims:
        sheet.paste(i, (0, y))
        y += i.height
    sheet.save(out, "JPEG", quality=80)
    print(out, sheet.size)

if __name__ == "__main__":
    main()
