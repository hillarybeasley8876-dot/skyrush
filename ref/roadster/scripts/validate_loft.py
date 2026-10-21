"""Check roadster_loft.json: internal consistency + fit against measured photo silhouettes.
usage: python3 -I validate_loft.py <loft.json> <side.jpg (gallery-02)> <top.jpg (gallery-22)>"""
import json
import sys
sys.path.append("/Users/minimax/Library/Python/3.9/lib/python/site-packages")
import numpy as np
from PIL import Image

SIDE = {"x_mid": 1300.0, "y_ground": 1168.0, "mm_px": 3.395}   # og02 calibration (WB 832 px)
TOP = {"x_mid": 1285.0, "y_mid": 849.0, "mm_px": 5.117}        # og22 calibration (L 856 px)


def interp(poly, y):
    pts = sorted(poly, key=lambda p: p[0])
    ys = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    return float(np.interp(y, ys, zs))


def internal(d):
    cl = d["side_profile"]["centreline_top"]
    plan = [[p[1], p[0]] for p in d["plan_outline_right"]]
    bad = 0
    for s in d["sections"]:
        top_c = s["K"][9][1]
        max_x = max(p[0] for p in s["K"])
        dz = top_c - interp(cl, s["y"])
        on_y = [p[1] for p in plan if abs(p[0] - s["y"]) < 1e-6]
        dx = max_x - (max(on_y) if on_y else interp(plan, s["y"]))
        flag = "" if abs(dz) <= 0.02 and abs(dx) <= 0.03 else "  <-- CHECK"
        bad += bool(flag)
        print(f"{s['id']} y={s['y']:+.2f}: centre z {top_c:.3f} vs profile dz={dz:+.3f} | max x {max_x:.3f} vs plan dx={dx:+.3f}{flag}")
    return bad


def side_fit(d, path):
    im = np.asarray(Image.open(path).convert("L"), dtype=np.int32)
    cl = d["side_profile"]["centreline_top"]
    sh = d["side_profile"]["fender_shoulder_line"]
    errs = []
    for x in range(650, 1900, 50):
        y_m = (SIDE["x_mid"] - x) * SIDE["mm_px"] / 1000
        col = np.nonzero(im[700:1250, x] > 70)[0]
        if not len(col):
            continue
        z_meas = (SIDE["y_ground"] - (700 + col.min())) * SIDE["mm_px"] / 1000
        z_model = max(interp(cl, y_m), interp(sh, y_m)) if -2.09 <= y_m <= 2.29 else None
        if z_model is not None:
            errs.append(z_model - z_meas)
    e = np.array(errs)
    print(f"side silhouette: n={len(e)} mean err {e.mean()*1000:+.0f} mm, MAE {np.abs(e).mean()*1000:.0f} mm, max {np.abs(e).max()*1000:.0f} mm")


def top_fit(d, path):
    im = np.asarray(Image.open(path).convert("RGB"), dtype=np.int32)
    mx = im.max(axis=2)
    sat = (mx - im.min(axis=2)) / np.maximum(mx, 1)
    car = (mx > 120) & (sat < 0.13)
    plan = [[p[1], p[0]] for p in d.get("plan_white_upper_right", d["plan_outline_right"])]
    errs = []
    for x in range(850, 1690, 20):
        y_m = (TOP["x_mid"] - x) * TOP["mm_px"] / 1000
        idx = np.nonzero(car[600:1100, x])[0]
        if len(idx) < 5:
            continue
        half_meas = (idx.max() - idx.min()) / 2 * TOP["mm_px"] / 1000
        errs.append(interp(plan, y_m) - half_meas)
    e = np.array(errs)
    print(f"top half-width: n={len(e)} mean err {e.mean()*1000:+.0f} mm, MAE {np.abs(e).mean()*1000:.0f} mm, max {np.abs(e).max()*1000:.0f} mm")


REAR_MEAS = [(0.834, 0.887), (0.763, 0.912), (0.692, 0.927), (0.621, 0.969), (0.586, 0.972)]  # og23 (z, half-width)


def rear_fit(d):
    errs = []
    for z, x_meas in REAR_MEAS:
        best = 0.0
        for s in d["sections"]:
            k = s["K"]
            for (x0, z0), (x1, z1) in zip(k[:-1], k[1:]):
                if min(z0, z1) <= z <= max(z0, z1) and z0 != z1:
                    best = max(best, x0 + (x1 - x0) * (z - z0) / (z1 - z0))
        errs.append(best - x_meas)
    e = np.array(errs)
    print(f"rear silhouette: n={len(e)} mean err {e.mean()*1000:+.0f} mm, MAE {np.abs(e).mean()*1000:.0f} mm, max {np.abs(e).max()*1000:.0f} mm")


def main():
    d = json.load(open(sys.argv[1]))
    bad = internal(d)
    side_fit(d, sys.argv[2])
    top_fit(d, sys.argv[3])
    rear_fit(d)
    print("sections needing a look:", bad)


if __name__ == "__main__":
    main()
