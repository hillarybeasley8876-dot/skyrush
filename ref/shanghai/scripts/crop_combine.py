import sys
from PIL import Image
# usage: python3 crop_combine.py out.jpg height file:x0,y0,x1,y1 [file:x0,y0,x1,y1 ...]  -> crops scaled to same height, side by side
out, H = sys.argv[1], int(sys.argv[2]); tiles = []
for spec in sys.argv[3:]:
    f, box = spec.rsplit(":", 1); x0, y0, x1, y1 = map(int, box.split(","))
    im = Image.open(f).convert("RGB"); print(f, im.size)
    c = im.crop((x0, y0, min(x1, im.width), min(y1, im.height)))
    c = c.resize((max(1, int(c.width * H / c.height)), H)); tiles.append(c)
W = sum(t.width for t in tiles); canvas = Image.new("RGB", (W, H)); x = 0
for t in tiles: canvas.paste(t, (x, 0)); x += t.width
if canvas.width > 1280: canvas = canvas.resize((1280, int(H * 1280 / canvas.width)))
canvas.save(out, "JPEG", quality=78); print(out, canvas.size)
