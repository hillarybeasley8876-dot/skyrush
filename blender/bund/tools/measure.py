"""Measure the luma of the Bund captures the way the lead measured them (bund-r2 MF1).

usage: python3 tmp/bund/measure.py captures/review_bund_r7_*.jpg

For every capture it finds the skyline (the first row that is not the sky gradient) and
prints the median luma and the median R-B of the facade pixels below it - the numbers the
review quotes for the reference photos.
"""
import sys

from PIL import Image
import numpy as np

SKY_TOL = 26.0          # how far a pixel may differ from the sky gradient and stay sky
MIN_LUMA = 26.0         # ignore the very dark pixels (the window reveals)
REGIONS = {
    # the frame region that holds the row: x0, x1, y0, y1
    "river_mid": (0.05, 0.98, 0.20, 0.64),
    "across": (0.02, 0.99, 0.20, 0.60),
    "hsbc_front": (0.02, 0.60, 0.20, 0.95),
    "road_n": (0.05, 0.95, 0.20, 0.80),
    "customs_close": (0.30, 0.70, 0.20, 0.70),
    "peace_close": (0.20, 0.80, 0.05, 0.60),
    "boc_close": (0.45, 0.90, 0.02, 0.50),
    "hsbc_dome": (0.30, 0.70, 0.15, 0.60),
}


def facade_pixels(a, x0, x1, y0, y1):
    """The pixels of the buildings below the skyline, column by column."""
    h, w = a.shape[:2]
    cx0, cx1 = int(x0 * w), int(x1 * w)
    cy0, cy1 = int(y0 * h), int(y1 * h)
    sel = []
    for x in range(cx0, cx1):
        col = a[cy0:cy1, x].astype(np.float32)
        sky = col[0:6].mean(axis=0)             # the sky gradient at the top of the column
        diff = np.abs(col - sky).sum(axis=1)
        below = np.nonzero(diff > SKY_TOL)[0]
        if not len(below):
            continue
        top = below[0]
        sel.extend(col[top:])
    return np.array(sel) if sel else np.zeros((0, 3))


def measure(path, name):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im)
    x0, x1, y0, y1 = REGIONS.get(name, (0.0, 1.0, 0.0, 1.0))
    px = facade_pixels(a, x0, x1, y0, y1)
    if not len(px):
        print("%-16s no facade pixels" % name)
        return
    luma = px[:, 0] * 0.2126 + px[:, 1] * 0.7152 + px[:, 2] * 0.0722
    m = luma > MIN_LUMA
    if not m.any():
        print("%-16s no lit pixels" % name)
        return
    l = luma[m]
    rb = px[m][:, 0] - px[m][:, 2]
    print("%-16s n=%6d  luma p50=%5.1f  p75=%5.1f  R-B p50=%5.1f  p75=%5.1f"
          % (name, m.sum(), np.percentile(l, 50), np.percentile(l, 75),
             np.percentile(rb, 50), np.percentile(rb, 75)))


def main(paths):
    names = sorted(REGIONS, key=len, reverse=True)
    for p in paths:
        stem = p.rsplit(".", 1)[0]
        name = next((n for n in names if stem.endswith("_" + n)), stem)
        measure(p, name)


if __name__ == "__main__":
    main(sys.argv[1:])
