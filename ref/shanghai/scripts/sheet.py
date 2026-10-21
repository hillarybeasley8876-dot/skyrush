import sys, os
from PIL import Image, ImageDraw, ImageFont
# usage: python3 -I sheet.py <out.jpg> <cols> <tile_w> <img...>  -> labelled contact sheet (index + filename)
out, cols, tw = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]); files = sys.argv[4:]
th = int(tw * 0.75); rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * th), (20, 20, 20)); dr = ImageDraw.Draw(sheet)
try: font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", max(11, tw // 28))
except OSError: font = ImageFont.load_default()
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB"); im.thumbnail((tw, th))
    x, y = (i % cols) * tw, (i // cols) * th
    sheet.paste(im, (x + (tw - im.width) // 2, y + (th - im.height) // 2))
    label = f"{i} {os.path.splitext(os.path.basename(f))[0][:34]}"
    dr.rectangle([x, y, x + tw, y + font.size + 6], fill=(0, 0, 0)); dr.text((x + 3, y + 2), label, fill=(255, 230, 0), font=font)
sheet.save(out, "JPEG", quality=72); print(out, sheet.size)
