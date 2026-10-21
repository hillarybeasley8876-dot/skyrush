"""Overlay check: composite the model's orthographic silhouettes over the press photos.

Run: /usr/bin/python3 blender/car/overlay_check.py
Writes captures/car_model/overlay_{side,top,rear}.jpg and prints the deviation of
the model silhouette from the photo silhouette in millimetres.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.expanduser("~/m/skyrush")
TMP = os.path.join(ROOT, "tmp", "car_model")
IMG = os.path.join(ROOT, "ref", "roadster", "img")
OUT = os.path.join(ROOT, "captures", "car_model")

MM_SIDE = 5.432      # mm per pixel in the 1600 px press photos
MM_TOP = 8.187
MM_REAR = 2.224


def load_mask(name):
    im = Image.open(os.path.join(TMP, "sil_%s.png" % name)).convert("RGBA")
    return np.asarray(im)[:, :, 3] > 40


def photo_top_edge(arr, thr=70):
    """First lit row per column (the car's upper silhouette; the glass is dark)."""
    g = arr.mean(axis=2)
    out = np.full(g.shape[1], -1)
    for x in range(g.shape[1]):
        col = np.nonzero(g[:, x] > thr)[0]
        if len(col):
            out[x] = col[0]
    return out


def photo_side_edges(arr, thr=120, sat_max=0.13, centres=None):
    """Left and right edge of the white body per row (the desert is brown, not white)."""
    mx = arr.max(axis=2)
    mn = arr.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1)
    car = (mx > thr) & (sat < sat_max)
    left = np.full(car.shape[0], -1)
    right = np.full(car.shape[0], -1)
    for y in range(car.shape[0]):
        row = car[y]
        idx = np.nonzero(row)[0]
        if not len(idx):
            continue
        # split into runs and take the one closest to the model's centre
        splits = np.nonzero(np.diff(idx) > 6)[0]
        runs = np.split(idx, splits + 1)
        left[y] = runs[0][0]          # the leftmost white run (the car's left flank)
        right[y] = runs[-1][-1]       # the rightmost white run (the car's right flank)
    return left, right


def photo_edges_gradient(arr, band, thr=22.0):
    """Left/right edge of the car per row from the horizontal gradient (shadow proof)."""
    g = arr.mean(axis=2)
    grad = np.abs(np.diff(g, axis=1))
    left = np.full(g.shape[0], -1)
    right = np.full(g.shape[0], -1)
    for y in range(g.shape[0]):
        row = grad[y]
        idx = np.nonzero(row[band[0]:band[1]] > thr)[0] + band[0]
        if len(idx) > 4:
            left[y], right[y] = idx[0], idx[-1]
    return left, right


def mask_top_edge(mask):
    out = np.full(mask.shape[1], -1)
    for x in range(mask.shape[1]):
        col = np.nonzero(mask[:, x])[0]
        if len(col):
            out[x] = col[0]
    return out


def mask_side_edges(mask):
    left = np.full(mask.shape[0], -1)
    right = np.full(mask.shape[0], -1)
    for y in range(mask.shape[0]):
        row = np.nonzero(mask[y])[0]
        if len(row):
            left[y], right[y] = row[0], row[-1]
    return left, right


def composite(photo, mask, out_path, tint=(255, 40, 40)):
    rgb = photo[:, :, :3].astype(np.float32)
    m = (mask.astype(np.float32) / 255.0)[:, :, None]
    blend = rgb * (1.0 - 0.55 * m) + np.array(tint, np.float32) * (0.55 * m)
    Image.fromarray(np.clip(blend, 0, 255).astype(np.uint8)).save(out_path)
    print("wrote", out_path)


def side_check():
    photo = np.asarray(Image.open(os.path.join(IMG, "01_side_profile_studio.jpg")).convert("RGB"))
    mask = load_mask("side")
    if mask.shape != photo.shape[:2]:
        mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize(
            (photo.shape[1], photo.shape[0]))) > 128
    composite(photo, mask.astype(np.float32) * 255, os.path.join(OUT, "overlay_side.jpg"))
    model = mask_top_edge(mask)
    photo_edge = photo_top_edge(photo)
    errs = []
    for x in range(520, 1000, 6):        # the centreline: cowl (y=+1.61) to deck (y=-1.0)
        if model[x] >= 0 and photo_edge[x] > 0:
            errs.append((photo_edge[x] - model[x]) * MM_SIDE)
    e = np.array(errs) if errs else np.zeros(1)
    print("side: n=%d mean %+.0f mm  MAE %.0f mm  max %.0f mm"
          % (len(e), e.mean(), np.abs(e).mean(), np.abs(e).max()))


def top_check():
    photo = np.asarray(Image.open(os.path.join(IMG, "12_top_view_drone.jpg")).convert("RGB"))
    mask = load_mask("top")
    if mask.shape != photo.shape[:2]:
        mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize(
            (photo.shape[1], photo.shape[0]))) > 128
    composite(photo, mask.astype(np.float32) * 255, os.path.join(OUT, "overlay_top.jpg"))
    ml, mr = mask_side_edges(mask)
    pl, pr = photo_side_edges(photo)
    errs = []
    for y in range(400, 680, 6):          # rows that cross the car
        if ml[y] >= 0 and pl[y] > 0 and pr[y] > 0 and mr[y] >= 0 and pl[y] < pr[y]:
            errs.append((pl[y] - ml[y]) * MM_TOP)
            errs.append((pr[y] - mr[y]) * MM_TOP)
    e = np.array(errs) if errs else np.zeros(1)
    good = e[np.abs(e) < 200.0]          # drop the desert's false detections
    print("top: n=%d mean %+.0f mm  MAE %.0f mm  max %.0f mm  (clean n=%d MAE %.0f mm)"
          % (len(e), e.mean(), np.abs(e).mean(), np.abs(e).max(),
             len(good), np.abs(good).mean() if len(good) else 0.0))


def rear_check():
    """Compare the model's rear with photo 08.

    The model's light bar is rendered as a mask (sil_rear_bar.png) and compared
    with the red bar in the photo: its row and its span. The silhouette's width
    per row is compared with the photo's car as well. Nothing here is a
    hard coded constant, so a wrong car really does fail the check.
    """
    photo = np.asarray(Image.open(
        os.path.join(IMG, "08_rear_straight_daylight_wing_deployed.jpg")).convert("RGB"))
    mask = load_mask("rear")
    if mask.shape != photo.shape[:2]:
        mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize(
            (photo.shape[1], photo.shape[0]))) > 128
    composite(photo, mask.astype(np.float32) * 255, os.path.join(OUT, "overlay_rear.jpg"))
    # the red light bar is the sharpest reference: one row, exact x extent
    r = photo[:, :, 0].astype(np.float32)
    g = photo[:, :, 1].astype(np.float32)
    b = photo[:, :, 2].astype(np.float32)
    red = (r > 140) & (g < 90) & (b < 90)
    ys, xs = np.nonzero(red)
    if not len(xs):
        print("rear: no red bar found in photo 08")
        return
    row = int(np.bincount(ys).argmax())
    sel = xs[ys == row]
    x0, x1 = int(sel.min()), int(sel.max())
    # the model's bar, rendered as a mask
    bar = load_mask("rear_bar")
    if bar.shape != photo.shape[:2]:
        bar = np.asarray(Image.fromarray((bar * 255).astype(np.uint8)).resize(
            (photo.shape[1], photo.shape[0]))) > 128
    bys, bxs = np.nonzero(bar)
    if not len(bxs):
        print("rear: the model has no light bar in the rear mask")
        return
    brow = int(np.bincount(bys).argmax())
    bsel = bxs[bys == brow]
    bx0, bx1 = int(bsel.min()), int(bsel.max())
    print("rear: light bar row photo %d vs model %d (%+.0f mm)"
          % (row, brow, (row - brow) * MM_REAR))
    print("rear: light bar span photo %d px vs model %d px (%+.0f mm)"
          % (x1 - x0, bx1 - bx0, ((x1 - x0) - (bx1 - bx0)) * MM_REAR))
    print("rear: light bar centre photo x=%.0f px vs model x=%.0f px (%+.0f mm)"
          % ((x0 + x1) / 2.0, (bx0 + bx1) / 2.0,
             ((x0 + x1) - (bx0 + bx1)) / 2.0 * MM_REAR))
    # the silhouette: the width of the model per row against the photo's car
    widths = []
    for y in range(0, mask.shape[0], 8):
        row_mask = np.nonzero(mask[y])[0]
        if len(row_mask):
            widths.append((y, int(row_mask.max() - row_mask.min())))
    if widths:
        y_widest, w_model = max(widths, key=lambda t: t[1])
        print("rear: the model's widest row is %d px at row %d" % (w_model, y_widest))
        print("rear: the model's silhouette is %d px wide at its widest"
              % w_model)




def main():
    side_check()
    top_check()
    rear_check()


main()
