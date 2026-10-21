"""Horizontally concat images to same height: hcat.py out.jpg h img1 img2 ..."""
import sys
sys.path.append("/Users/minimax/Library/Python/3.9/lib/python/site-packages")
from PIL import Image

def main() -> None:
    out, h = sys.argv[1], int(sys.argv[2])
    ims = [Image.open(p).convert("RGB") for p in sys.argv[3:]]
    ims = [i.resize((round(i.width * h / i.height), h), Image.LANCZOS) for i in ims]
    sheet = Image.new("RGB", (sum(i.width for i in ims), h))
    x = 0
    for i in ims:
        sheet.paste(i, (x, 0))
        x += i.width
    sheet.save(out, "JPEG", quality=82)
    print(out, sheet.size)

if __name__ == "__main__":
    main()
