"""Giant LED ad facades for the Lujiazui backdrop towers (ART.md 7).

    python3 blender/landmarks/tex_ads.py

Writes 1024 x 576 ad images into game/assets/landmarks/textures/:
each one is a dark back-plate with a parody Chinese wordmark (never a real
brand), a sub-line and the LED pixel grid. The grid pitch is 6 dots per metre
over the 60 m wide screen, so the pixels read as a fine mesh up close and blur
into a glowing panel from the Bund.

This runs under the system python3 (it needs PIL); the Blender builders only
read the finished PNGs.
"""
import os

from PIL import Image, ImageDraw, ImageFont

OUT = os.path.expanduser("~/m/skyrush/game/assets/landmarks/textures")
W, H = 1024, 576
SCREEN_W = 60.0                 # the screen is 60 m wide
DOTS_PER_M = 6.0                # the LED pixel pitch
FONT_CANDIDATES = [
    ("/System/Library/Fonts/Hiragino Sans GB.ttc", 0),
    ("/System/Library/Fonts/STHeiti Medium.ttc", 0),
    ("/System/Library/Fonts/Songti.ttc", 0),
    ("/Library/Fonts/Arial Unicode.ttf", 0),
]

ADS = [
    # file, wordmark, sub-line, accent rgb, background rgb
    ("ad_dongfang.png", "东方霓虹", "霓虹灯具  LED NEON", (255, 62, 160), (18, 6, 20)),
    ("ad_pujiang.png", "浦江电讯", "5G 覆盖 全城  PUJIANG", (64, 208, 255), (6, 14, 24)),
    ("ad_shencheng.png", "申城快递", "次日达  SHENCHENG", (255, 176, 48), (22, 14, 6)),
]


def load_font(size):
    for path, index in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size, index=index)
            except (OSError, ValueError):
                continue
    return ImageFont.load_default()


def pixel_grid(img):
    """Darken every LED pixel gap: 6 dots per metre over the 60 m screen."""
    pitch = W / (SCREEN_W * DOTS_PER_M)          # pixels per dot
    px = img.load()
    w, h = img.size
    step = max(1, int(round(pitch)))
    for y in range(h):
        for x in range(w):
            if (x % step) == 0 or (y % step) == 0:
                r, g, b = px[x, y][:3]
                px[x, y] = (int(r * 0.55), int(g * 0.55), int(b * 0.55), 255)
    return img


def make_ad(path, word, sub, accent, bg):
    img = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(img)
    # a soft accent wash behind the wordmark
    for i in range(160):
        t = i / 159.0
        col = (int(bg[0] + (accent[0] - bg[0]) * t * 0.30),
               int(bg[1] + (accent[1] - bg[1]) * t * 0.30),
               int(bg[2] + (accent[2] - bg[2]) * t * 0.30), 255)
        d.rectangle([0, 120 + i * 2, W, 120 + i * 2 + 2], fill=col)
    # the wordmark
    f = load_font(190)
    bb = d.textbbox((0, 0), word, font=f)
    d.text(((W - (bb[2] - bb[0])) * 0.5, 150), word, font=f, fill=accent + (255,),
           stroke_width=6, stroke_fill=(255, 255, 255, 255))
    # the sub-line
    f2 = load_font(54)
    bb2 = d.textbbox((0, 0), sub, font=f2)
    d.text(((W - (bb2[2] - bb2[0])) * 0.5, 380), sub, font=f2,
           fill=(235, 235, 240, 255))
    # a bright rule under the wordmark
    d.rectangle([90, 470, W - 90, 478], fill=accent + (255,))
    # a small logo block, top left
    d.rectangle([70, 60, 150, 140], outline=accent + (255,), width=7)
    d.rectangle([86, 76, 134, 124], fill=accent + (255,))
    img = pixel_grid(img).convert("RGB")
    img.save(os.path.join(OUT, path), quality=95)
    print("  ad %s (%d x %d)" % (path, W, H))


def main():
    os.makedirs(OUT, exist_ok=True)
    for (name, word, sub, accent, bg) in ADS:
        make_ad(name, word, sub, accent, bg)


if __name__ == "__main__":
    main()
