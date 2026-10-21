"""Far-LOD window atlases: the lit-window pattern the distant city blocks use.

Two atlases, one per facade preset, so the cell size matches the near shader and the
hand-off does not pop:
  office       1.5 x 3.9 m cells (narrow bays, dark spandrel, cool LED offices)
  residential  3.3 x 2.95 m cells (wide bays, warm flats, a few TV-blue windows)

The lighting is NOT a polka dot.  Every floor row of the atlas gets a state, and the
states come in contiguous RUNS, so the city reads as bands of lit floors with dark
floors between them (ART.md 11, B-NIGHT1):
  office        20-30 % of the windows lit, in full-lit bands of 2-4 floors, cool white
  residential   15-25 % lit, scattered, warm, with curtains and TV-blue flats
The far building offsets the atlas per building, so two towers do not share a pattern.
"""
import numpy as np
from PIL import Image, ImageDraw

OFFICE_CELL_M = (1.5, 3.9)
RESI_CELL_M = (3.3, 2.95)

OFFICE_ROWS = 12        # floor rows in the office atlas (12 x 3.9 m = 46.8 m of pattern)
OFFICE_COLS = 31
RESI_ROWS = 14          # 14 x 2.95 m = 41.3 m of pattern
RESI_COLS = 12

OFFICE_WALL = (46, 47, 50)     # #2E2F32 spandrel
OFFICE_GLASS = (11, 14, 19)    # #0B0E13 glass
RESI_WALL = (92, 88, 82)        # a dark rendered wall: the city is seen at night
RESI_GLASS = (11, 14, 19)

LIT_WARM = (255, 167, 87)
LIT_NEUTRAL = (255, 193, 141)
LIT_COOL = (222, 232, 255)
LIT_TV = (110, 140, 255)

# the floor states: (state, share of the rows, run length range, lit probability)
OFFICE_ROW_STATES = (("full", 0.18, (2, 4), 1.00),
                     ("scatter", 0.50, (1, 3), 0.15),
                     ("dark", 0.32, (1, 3), 0.04))
RESI_ROW_STATES = (("scatter", 0.65, (1, 3), 0.36),
                   ("dark", 0.35, (1, 3), 0.02))


def _cell_px(size, cell_m, rows, cols):
    """The pixel size of a cell: the atlas keeps the real world aspect."""
    ph = size / float(rows * cell_m[1])
    return max(8, int(round(cell_m[0] * ph))), max(8, int(round(cell_m[1] * ph)))


def _row_states(rows, rng, spec):
    """The state of every floor row.

    The rows are composed first (how many are full-lit, scattered, dark) and then
    arranged: the full-lit rows stay together as one band, the rest go in short
    runs.  A random draw per run could leave an atlas with no lit band at all.
    """
    counts = []
    for s in spec:
        counts.append([s[0], int(round(rows * s[1])), list(s[2]), s[3]])
    # fix the rounding: the rows must add up
    while sum(c[1] for c in counts) > rows:
        counts[-1][1] -= 1
    while sum(c[1] for c in counts) < rows:
        counts[0][1] += 1
    runs = []
    for c in counts:
        left = c[1]
        if c[0] == "full":
            # one contiguous band of lit floors
            runs.append((c[0], left))
            continue
        while left > 0:
            take = int(rng.integers(c[2][0], c[2][1] + 1))
            take = min(take, left)
            runs.append((c[0], take))
            left -= take
    order = list(range(len(runs)))
    rng.shuffle(order)
    states = []
    for i in order:
        states.extend([runs[i][0]] * runs[i][1])
    return states


def _office_cell(size, rng, lit):
    """A dark spandrel wall with one narrow office window (lit, tv-blue or dark)."""
    w, h = size
    img = Image.new("RGB", size, OFFICE_WALL)
    d = ImageDraw.Draw(img)
    band = int(h * 0.22)
    d.rectangle([mx := int(w * 0.12), band, w - mx - 1, h - band - 1], fill=OFFICE_GLASS)
    if lit == "tv":
        d.rectangle([mx, band, w - mx - 1, h - band - 1], fill=LIT_TV)
    elif lit == "lit":
        # offices read cool white: a cool LED panel, a few neutral and a few warm
        r = rng.random()
        colour = LIT_COOL if r < 0.80 else (LIT_NEUTRAL if r < 0.95 else LIT_WARM)
        d.rectangle([mx, band, w - mx - 1, h - band - 1], fill=colour)
        d.rectangle([mx, band, w - mx - 1, band + int(h * 0.10)], fill=(245, 245, 235))
        if rng.random() < 0.3:
            d.rectangle([mx, h // 2, w - mx - 1, h // 2 + int(h * 0.16)], fill=(60, 60, 66))
    d.rectangle([w // 2 - 2, band, w // 2 + 2, h - band - 1], fill=OFFICE_WALL)
    return img


def _resi_cell(size, rng, lit):
    """A warm rendered wall with a wide flat window (and a balcony rail)."""
    w, h = size
    img = Image.new("RGB", size, RESI_WALL)
    d = ImageDraw.Draw(img)
    mx = int(w * 0.18)
    top, bot = int(h * 0.18), int(h * 0.80)
    d.rectangle([mx, top, w - mx - 1, bot], fill=RESI_GLASS)
    if lit == "tv":
        d.rectangle([mx, top, w - mx - 1, bot], fill=LIT_TV)
        d.rectangle([mx, top, mx + int(w * 0.3), bot], fill=(190, 175, 150))
    elif lit == "lit":
        r = rng.random()
        colour = (LIT_WARM if r < 0.60 else
                  (LIT_NEUTRAL if r < 0.85 else LIT_COOL))
        d.rectangle([mx, top, w - mx - 1, bot], fill=colour)
        # a curtain on one side, a blind on the other: the flats must not all match
        if rng.random() < 0.45:
            d.rectangle([mx, top, mx + int(w * 0.24), bot], fill=(212, 192, 162))
        if rng.random() < 0.35:
            d.rectangle([mx, bot - int(h * 0.18), w - mx - 1, bot], fill=(96, 90, 82))
    d.rectangle([mx - 4, top - 4, w - mx + 3, bot + 3], outline=(90, 84, 76), width=4)
    d.rectangle([w // 2 - 2, top, w // 2 + 2, bot], fill=(90, 84, 76))
    return img


def _build(size, rows, cols, cell_m, states_spec, cell_fn, seed):
    """Build one atlas: the rows come from the bottom up, the bands are in runs."""
    rng = np.random.default_rng(seed)
    cw, ch = _cell_px(size, cell_m, rows, cols)
    state = _row_states(rows, rng, states_spec)
    prob = {s[0]: s[3] for s in states_spec}
    img = Image.new("RGB", (cols * cw, rows * ch), (0, 0, 0))
    for cy in range(rows):
        # the world v=0 is the bottom of the building: the image row 0 is the top
        st = state[rows - 1 - cy]
        for cx in range(cols):
            lit = None
            if st == "full":
                lit = "lit"
            elif rng.random() < prob[st]:
                lit = "lit" if rng.random() > 0.06 else "tv"
            img.paste(cell_fn((cw, ch), rng, lit), (cx * cw, cy * ch))
    return img, (cw, ch), (cols, rows)


def build_office(size=2048, seed=101):
    """The office atlas (dark spandrel, cool offices, lit bands of 2-4 floors)."""
    return _build(size, OFFICE_ROWS, OFFICE_COLS, OFFICE_CELL_M, OFFICE_ROW_STATES,
                  _office_cell, seed)


def build_resi(size=2048, seed=202):
    """The residential atlas (warm flats, wide bays, scattered lights)."""
    return _build(size, RESI_ROWS, RESI_COLS, RESI_CELL_M, RESI_ROW_STATES,
                  _resi_cell, seed)


def emission_from(albedo, lit_ratio=1.0, seed=303):
    """The emission map: only the lit windows glow, at FULL value (E1, never blooms)."""
    arr = np.asarray(albedo).astype(np.float32)
    bright = arr.max(axis=2) > 160.0
    out = arr * bright[..., None] * lit_ratio
    return np.clip(out, 0, 255).astype(np.uint8)
