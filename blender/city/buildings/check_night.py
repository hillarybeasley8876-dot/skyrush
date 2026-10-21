"""Check the night lighting of the far LOD (ART.md 11, B-NIGHT1).

    python3 blender/city/buildings/check_night.py [--out tmp/buildings]

It builds the two window atlases in memory and measures:
  * the share of the windows that are lit (the offices 20-30 %, the flats 15-25 %);
  * the band structure: the atlas must light whole floors, not a polka dot, so there
    has to be a run of 2-4 fully lit rows;
  * the colour mix: the offices cool white, the flats warm.

It writes the two atlases as PNGs so they can be looked at.
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from city.buildings.texgen import atlas_windows as A  # noqa: E402

# the share of the cell that is a window (the rest is the spandrel and the frame)
OFFICE_WINDOW = (1.0 - 2 * 0.12) * (1.0 - 2 * 0.22)
RESI_WINDOW = (1.0 - 2 * 0.18) * (0.80 - 0.18)
LIT_THRESHOLD = 160.0
OFFICE_BAND = (0.20, 0.30)
RESI_BAND = (0.15, 0.25)


def analyse(name, img, cell_px, grid, window_share, target, want_band=True):
    """The lit share and the band structure of one atlas."""
    arr = np.asarray(img)
    bright = arr.max(axis=2) > LIT_THRESHOLD
    rows = grid[1]
    per_row = []
    for r in range(rows):
        band = bright[r * cell_px[1]:(r + 1) * cell_px[1]]
        per_row.append(band.mean() / window_share)
    lit = bright.mean() / window_share
    # the longest run of fully lit rows
    run = 0
    best = 0
    for value in per_row:
        if value > 0.8:
            run += 1
            best = max(best, run)
        else:
            run = 0
    ok = target[0] <= lit <= target[1]
    # the offices light whole bands of floors, the flats are scattered
    band_ok = best >= 2 if want_band else best < 2
    print("%-7s lit %5.1f %% (target %d-%d %s)  longest band %d floors  %s" %
          (name, 100.0 * lit, target[0] * 100, target[1] * 100,
           "OK" if ok else "FAIL", best, "OK" if band_ok else "FAIL"))
    print("        per floor: " + " ".join("%.0f" % (100 * v) for v in per_row))
    return ok and band_ok


def colour_mix(name, img):
    """The share of the lit cells that are cool white / warm."""
    arr = np.asarray(img).astype(int)
    lit = arr.max(axis=2) > LIT_THRESHOLD
    pixels = arr[lit]
    if len(pixels) == 0:
        print("%-7s no lit cells" % name)
        return
    cool = ((pixels[:, 2] > pixels[:, 0] + 10)).mean()
    warm = ((pixels[:, 0] > pixels[:, 2] + 10)).mean()
    print("%-7s of the lit pixels: %.0f %% cool, %.0f %% warm" % (name, 100 * cool, 100 * warm))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.expanduser("~/m/skyrush/tmp/buildings"))
    opts = ap.parse_args()
    os.makedirs(opts.out, exist_ok=True)
    ok = True
    img, cell, grid = A.build_office()
    ok = analyse("office", img, cell, grid, OFFICE_WINDOW, OFFICE_BAND) and ok
    colour_mix("office", img)
    img.save(os.path.join(opts.out, "atlas_office.png"))
    img, cell, grid = A.build_resi()
    ok = analyse("resi", img, cell, grid, RESI_WINDOW, RESI_BAND, want_band=False) and ok
    colour_mix("resi", img)
    img.save(os.path.join(opts.out, "atlas_resi.png"))
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
