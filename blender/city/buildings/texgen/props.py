"""The prop sheet: the flat faces of the street clutter, drawn with PIL.

One 2048 sheet with 4 x 4 cells of 512 px (the props are 0.5-1.5 m, so the sheet
carries 512 px/m - the old 1024 sheet was 256 px per cell and 386 px/m):
  0 AC casing front   1 AC casing side   2 window cage   3 roller shutter
  4 powder-coated steel  5 galvanised steel  6 drain pipe  7 bracket
  8 planter  9 bin  10 satellite dish  11 wall lamp  12 bike rack
  13 louvre vent  14 grime patch  15 blank

The cells are mapped onto the props with explicit UVs, so the AC unit really shows a
fan grille and a brand plate instead of being a coloured box.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from .atlas import slot

FONT_BOLD = "~/Library/Fonts/NotoSansCJKsc-Bold.otf"

SHEET = 2048
CELL = 512
OUT_SIZE = 2048   # the sheet is NOT downscaled: 512 px per cell is 512 px/m
COLS = 4
ROWS = 4

CASING = (217, 214, 204)      # off-white #D9D6CC
CASING_DARK = (176, 173, 165)
STEEL = (58, 60, 64)
GALV = (183, 189, 194)
RUST = (122, 74, 44)
SHUTTER = (150, 152, 148)


def _font(size):
    import os
    return ImageFont.truetype(os.path.expanduser(FONT_BOLD), size)


def _noise_overlay(img, amount=16, seed=3):
    """Speckle a drawn cell so it does not read as flat vector art."""
    import numpy as np
    arr = np.asarray(img).astype(np.int16)
    rng = np.random.default_rng(seed)
    n = rng.normal(0.0, amount, arr.shape[:2])[..., None]
    arr = np.clip(arr + n, 0, 255).astype(np.uint8)
    return Image.fromarray(arr)


def _ac_front(cell):
    """The front of a split AC condenser: louvres, a fan disc and a brand plate."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=CASING)
    d.rectangle([0, 0, w - 1, h - 1], outline=(140, 138, 132), width=6)
    # the recessed panel with the fan behind a grille
    d.rectangle([28, 40, w - 28, h - 120], fill=(206, 203, 194), outline=(150, 148, 142),
                width=5)
    cx, cy, r = w // 2, h // 2 - 30, min(w, h) // 3
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(52, 54, 58))
    for i in range(9):
        d.arc([cx - r + 6, cy - r + 6, cx + r - 6, cy + r - 6], i * 40, i * 40 + 24,
              fill=(150, 152, 156), width=4)
    d.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=(120, 122, 126))
    for i in range(-r + 14, r, 16):
        d.line([cx - r + 6, cy + i, cx + r - 6, cy + i], fill=(168, 170, 174), width=3)
    # the brand plate and the rust drip under it
    d.rectangle([60, h - 96, w - 60, h - 58], fill=(176, 173, 165))
    d.text((74, h - 92), "华信", font=_font(30), fill=(70, 68, 64))
    d.rectangle([w - 96, h - 96, w - 62, h - 58], outline=(120, 118, 112), width=3)
    d.ellipse([w - 88, h - 86, w - 70, h - 68], fill=(150, 40, 36))
    d.rectangle([96, h - 58, 112, h - 12], fill=RUST)
    d.rectangle([w - 130, h - 58, w - 116, h - 18], fill=(150, 92, 56))
    return cell


def _ac_side(cell):
    """The side of a condenser: the louvred heat exchanger."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=CASING)
    d.rectangle([0, 0, w - 1, h - 1], outline=(140, 138, 132), width=6)
    for i in range(14):
        y = 60 + i * 22
        d.rectangle([40, y, w - 40, y + 13], fill=(188, 186, 178), outline=(160, 158, 152))
    d.rectangle([0, h - 40, w, h], fill=CASING_DARK)
    return cell


def _cage(cell):
    """A window security cage: steel bars welded over the opening."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(14, 15, 18))
    for i in range(9):
        x = 24 + i * 58
        d.rectangle([x, 10, x + 12, h - 10], fill=STEEL)
        d.rectangle([x, 10, x + 4, h - 10], fill=(92, 94, 98))
    for i in range(7):
        y = 30 + i * 68
        d.rectangle([14, y, w - 14, y + 11], fill=(64, 66, 70))
    d.rectangle([0, 0, w - 1, 18], fill=STEEL)
    d.rectangle([0, h - 18, w - 1, h - 1], fill=STEEL)
    return cell


def _shutter(cell):
    """A roller shutter (卷帘门): ribbed steel, a lock bar and a few stickers."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=SHUTTER)
    for y in range(0, h, 26):
        d.rectangle([0, y, w - 1, y + 14], fill=(168, 170, 166))
        d.rectangle([0, y + 14, w - 1, y + 25], fill=(126, 128, 124))
    d.rectangle([0, 0, w - 1, 34], fill=(96, 98, 96))
    d.rectangle([0, h - 54, w - 1, h - 1], fill=(88, 90, 88))
    d.rectangle([w // 2 - 14, h - 120, w // 2 + 14, h - 40], fill=(70, 72, 70))
    d.ellipse([w // 2 - 30, h - 90, w // 2 + 30, h - 40], outline=(60, 62, 60), width=6)
    # stickers
    d.rectangle([40, 120, 150, 190], fill=(214, 206, 180))
    d.text((52, 132), "旺铺", font=_font(34), fill=(180, 40, 40))
    d.rectangle([330, 300, 440, 360], fill=(230, 228, 220))
    d.text((344, 310), "吉", font=_font(30), fill=(40, 40, 44))
    return cell


def _steel_panel(cell, base, seed):
    """A plain steel plate with scratches and a weld seam."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=base)
    d.rectangle([0, 0, w - 1, 12], fill=tuple(max(0, c - 18) for c in base))
    d.rectangle([0, h - 12, w - 1, h - 1], fill=tuple(max(0, c - 22) for c in base))
    for i in range(26):
        x = (i * 97 + seed * 13) % w
        y = (i * 53 + seed * 7) % h
        d.line([x, y, x + 40 + (i * 7) % 90, y + 18], fill=tuple(max(0, c - 26) for c in base),
               width=2)
    return cell


def _pipe(cell):
    """A drain pipe with brackets."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(40, 42, 45))
    d.rectangle([w // 3, 0, w // 3 + 150, h - 1], fill=(176, 178, 176))
    d.rectangle([w // 3, 0, w // 3 + 26, h - 1], fill=(206, 208, 206))
    d.rectangle([w // 3 + 124, 0, w // 3 + 150, h - 1], fill=(126, 128, 126))
    for y in (80, 300):
        d.rectangle([w // 3 - 18, y, w // 3 + 168, y + 24], fill=STEEL)
    return cell


def _bracket(cell):
    """A steel wall bracket."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(48, 50, 53))
    d.polygon([(60, 460), (60, 120), (420, 300), (420, 340)], fill=STEEL)
    d.polygon([(60, 120), (90, 108), (450, 288), (420, 300)], fill=(96, 98, 102))
    d.rectangle([40, 440, 110, 490], fill=(70, 72, 76))
    return cell


def _planter(cell):
    """A concrete planter with a shrub."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(178, 176, 168))
    d.rectangle([40, 150, w - 40, h - 30], fill=(150, 148, 141))
    d.rectangle([40, 150, w - 40, 196], fill=(128, 126, 120))
    d.ellipse([90, 40, w - 90, 210], fill=(52, 78, 38))
    d.ellipse([140, 20, w - 140, 170], fill=(66, 96, 46))
    return cell


def _bin(cell):
    """A galvanised rubbish bin."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(120, 122, 124))
    d.rectangle([120, 90, w - 120, h - 40], fill=GALV)
    d.rectangle([120, 90, 160, h - 40], fill=(206, 210, 214))
    d.ellipse([120, 60, w - 120, 120], fill=(168, 172, 176))
    d.rectangle([180, 40, w - 180, 74], fill=(90, 92, 96))
    d.rectangle([150, 240, w - 150, 268], fill=(96, 98, 102))
    return cell


def _dish(cell):
    """A satellite dish."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(30, 31, 34))
    d.ellipse([70, 50, w - 70, h - 60], fill=(196, 194, 188))
    d.ellipse([100, 80, w - 100, h - 90], fill=(216, 214, 208))
    d.rectangle([w // 2 - 14, h // 2 - 60, w // 2 + 14, h // 2 + 90], fill=(120, 122, 126))
    d.ellipse([w // 2 - 26, h // 2 - 78, w // 2 + 26, h // 2 - 34], fill=(80, 82, 86))
    return cell


def _lamp(cell):
    """A wall lamp (a bulkhead light over a door)."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(26, 27, 30))
    d.rounded_rectangle([110, 150, w - 110, 330], radius=26, fill=(52, 54, 58))
    d.rounded_rectangle([128, 168, w - 128, 312], radius=20, fill=(255, 214, 150))
    d.ellipse([w // 2 - 40, 190, w // 2 + 40, 290], fill=(255, 236, 196))
    d.rectangle([w // 2 - 16, 96, w // 2 + 16, 160], fill=(60, 62, 66))
    return cell


def _bike_rack(cell):
    """A bicycle rack."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=(58, 60, 64))
    for i in range(3):
        x = 70 + i * 150
        d.arc([x, 120, x + 120, 400], start=180, end=360, fill=(196, 198, 200), width=16)
        d.rectangle([x - 8, 300, x + 8, 440], fill=(196, 198, 200))
        d.rectangle([x + 112, 300, x + 128, 440], fill=(196, 198, 200))
    return cell


def _louvre(cell):
    """An air louvre / vent panel."""
    w, h = cell.size
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, w - 1, h - 1], fill=GALV)
    for i in range(11):
        y = 40 + i * 38
        d.polygon([(40, y), (w - 40, y), (w - 40, y + 22), (40, y + 30)],
                  fill=(150, 156, 160), outline=(120, 126, 130))
    d.rectangle([30, 30, w - 30, h - 30], outline=(110, 116, 120), width=6)
    return cell


def _grime(cell):
    """A grime patch: the dirt that collects at the foot of a wall."""
    w, h = cell.size
    img = Image.new("RGB", (w, h), (74, 74, 70))
    d = ImageDraw.Draw(img)
    for i in range(40):
        x = (i * 71) % w
        r = 30 + (i * 37) % 90
        d.ellipse([x - r, h - r - 30, x + r, h + r], fill=(52, 52, 48))
    img = img.filter(ImageFilter.GaussianBlur(9))
    return img


def _blank(cell):
    d = ImageDraw.Draw(cell)
    d.rectangle([0, 0, cell.size[0] - 1, cell.size[1] - 1], fill=(120, 120, 118))
    return cell


DRAWERS = {
    "ac_front": _ac_front,
    "ac_side": _ac_side,
    "cage": _cage,
    "shutter": _shutter,
    "steel_powder": lambda c: _steel_panel(c, STEEL, 3),
    "steel_galv": lambda c: _steel_panel(c, GALV, 5),
    "pipe": _pipe,
    "bracket": _bracket,
    "planter": _planter,
    "bin": _bin,
    "dish": _dish,
    "lamp": _lamp,
    "bike_rack": _bike_rack,
    "louvre": _louvre,
    "grime": _grime,
    "blank": _blank,
}

ORDER = ["ac_front", "ac_side", "cage", "shutter", "steel_powder", "steel_galv", "pipe",
         "bracket", "planter", "bin", "dish", "lamp", "bike_rack", "louvre", "grime", "blank"]


# the material of every cell: (metallic, roughness).  The props are metal, concrete
# or fabric, and the ORM has to say so - a flat clip-art cell has no surface.
CELL_SURFACE = {
    "ac_front": (0.15, 0.52),
    "ac_side": (0.15, 0.58),
    "cage": (0.85, 0.42),
    "shutter": (0.80, 0.38),
    "steel_powder": (0.70, 0.45),
    "steel_galv": (0.88, 0.32),
    "pipe": (0.80, 0.40),
    "bracket": (0.75, 0.45),
    "planter": (0.0, 0.88),
    "bin": (0.85, 0.36),
    "dish": (0.60, 0.35),
    "lamp": (0.30, 0.30),
    "bike_rack": (0.85, 0.38),
    "louvre": (0.85, 0.34),
    "grime": (0.0, 0.92),
    "blank": (0.0, 0.80),
}


def build():
    """The prop sheet image, its normal and ORM maps, and the manifest of its cells."""
    import numpy as np
    from .height import normal_from_height, orm_pack
    img = Image.new("RGB", (SHEET, SHEET), (0, 0, 0))
    entries = []
    metal = np.zeros((SHEET, SHEET), dtype=np.float32)
    rough = np.zeros((SHEET, SHEET), dtype=np.float32)
    for i, name in enumerate(ORDER):
        cx = (i % COLS) * CELL
        cy = (i // COLS) * CELL
        cell = Image.new("RGB", (CELL, CELL), (0, 0, 0))
        DRAWERS[name](cell)
        cell = _noise_overlay(cell, amount=10, seed=i * 17 + 3)
        img.paste(cell, (cx, cy))
        m, r = CELL_SURFACE[name]
        metal[cy:cy + CELL, cx:cx + CELL] = m
        rough[cy:cy + CELL, cx:cx + CELL] = r
        u0, v0, u1, v1 = slot(SHEET, SHEET, cx, cy, CELL, CELL)
        entries.append({"id": name, "atlas": "props", "u0": u0, "v0": v0, "u1": u1, "v1": v1,
                        "cell": [cx // CELL, cy // CELL]})
    if OUT_SIZE != SHEET:
        img = img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    # the relief of the cell: the drawn edges ARE the geometric edges, so the blurred
    # luminance of the sheet is a good height field (the shutter ribs, the cage bars
    # and the recessed AC panel all come out of it)
    lum = np.asarray(img.convert("L")).astype(np.float32) / 255.0
    height = np.asarray(Image.fromarray((lum * 255).astype(np.uint8))
                         .filter(ImageFilter.GaussianBlur(1.0)), dtype=np.float32) / 255.0
    height = np.clip((height - 0.5) * 3.0 + 0.5, 0.0, 1.0)
    # the roughness varies with the surface: the dark recesses are the dirty ones
    rough = np.clip(rough + (0.5 - lum) * 0.22, 0.05, 0.98)
    ao = np.clip(0.75 + 0.25 * lum, 0.4, 1.0)
    normal = normal_from_height(height, 1.6)
    return img, entries, normal, orm_pack(ao, rough, metal)
