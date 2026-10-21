"""Count the red pixels of the tail light bar in the game look (review r3 #8).

The review's acceptance metric (round 3) is the saturated red count in the
car crop of the in-game chase capture: pixels with R > 120, R > 1.8 G and
R > 1.8 B. The round 2 metric (R > 180 and G < 90) is withdrawn: under AgX a
strong red core turns pink-white, and photo 19 shows exactly that - a
pink-white core inside a red halo.

Run:  /usr/bin/python3 blender/car/red_audit.py
"""
import os

from PIL import Image

ROOT = os.path.expanduser("~/m/skyrush")
OUT = os.path.join(ROOT, "captures")
# (file, crop box or None for the whole frame, the saturated red pixels needed)
SHOTS = [
    ("lookdev_car_car_chase84.jpg", (600, 380, 1000, 600), 1200),
    ("lookdev_car_car_far20.jpg", (560, 400, 1040, 640), 0),
    ("lookdev_car_car_far20t.jpg", (300, 300, 1300, 600), 0),
    ("lookdev_car_car_rear09.jpg", None, 0),
    ("car_glb_chase.jpg", None, 0),
    ("car_glb_far20.jpg", None, 0),
    ("car_glb_far20t.jpg", None, 0),
    ("car_glb_rear34.jpg", None, 0),
    ("car_glb_close_rear.jpg", None, 0),
]


def audit(name, box, need):
    path = os.path.join(OUT, name)
    if not os.path.exists(path):
        print("%-32s MISSING" % name)
        return
    im = Image.open(path).convert("RGB")
    w, h = im.size
    x0, y0, x1, y1 = box or (0, 0, w, h)
    px = im.load()
    strong = 0
    reddish = 0
    peak = (0, 0, 0)
    rows = 0
    for y in range(y0, y1):
        hit = 0
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if r > 180 and g < 90:
                strong += 1
            if r > 120 and r > g * 1.8 and r > b * 1.8:
                reddish += 1
                hit += 1
                if r > peak[0]:
                    peak = (r, g, b)
        if hit > 0:
            rows += 1
    lum = 0.2126 * peak[0] + 0.7152 * peak[1] + 0.0722 * peak[2]
    ok = "OK " if (need == 0 or reddish >= need) else "LOW"
    print("%s %-30s %4dx%-4d saturated red %5d (need %4d)  rows %2d  peak %s (lum %3.0f)"
          % (ok, name, x1 - x0, y1 - y0, reddish, need, rows, peak, lum))


def main():
    for name, box, need in SHOTS:
        audit(name, box, need)


if __name__ == "__main__":
    main()
