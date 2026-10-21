"""Put the review captures next to the reference photos (numpy + PIL, no Blender).

Run:  /usr/bin/python3 blender/car/compare.py

The sheets are the ones the review asks for:
  compare_wheel.jpg  the wheel at 0.9 m next to photo 13;
  compare_rear.jpg   the in-game rear (1.2 m behind, z 0.5) next to photo 09
                     and the in-game chase view next to photo 08;
  compare_wing.jpg   the deployed wing next to photo 17 and the stowed deck
                     next to photo 16;
  compare_front.jpg  the front next to photo 03.
"""
import os

from PIL import Image

ROOT = os.path.expanduser("~/m/skyrush")
OUT = os.path.join(ROOT, "captures", "car_model")
GAME = os.path.join(ROOT, "captures")
REF = os.path.join(ROOT, "ref", "roadster", "img")

# (the capture, the photo, the sheet)
PAIRS = (
    (os.path.join(OUT, "wheel09.png"), "13_wheel_closeup_stage.jpg", "compare_wheel.jpg"),
    (os.path.join(OUT, "front34_low.png"), "03_front_3q_low.jpg", "compare_front.jpg"),
)
# (the capture, the photo, the capture, the photo, the sheet) - two rows
QUADS = (
    (os.path.join(GAME, "lookdev_car_car_rear09.jpg"),
     "09_rear_closeup_nozzles_plate.jpg",
     os.path.join(GAME, "lookdev_car_car_rear08.jpg"),
     "08_rear_straight_daylight_wing_deployed.jpg",
     "compare_rear.jpg"),
    (os.path.join(OUT, "wing_deployed.png"),
     "17_wing_deployed_closeup.jpg",
     os.path.join(OUT, "deck_stowed.png"),
     "16_rear_deck_lightbar_from_above.jpg",
     "compare_wing.jpg"),
)


def _load(path, h):
    im = Image.open(path).convert("RGB")
    return im.resize((int(im.width * h / im.height), h), Image.LANCZOS)


def hstack(a, b, out, h=760):
    ia = _load(a, h)
    ib = _load(b, h)
    sheet = Image.new("RGB", (ia.width + ib.width + 8, h), (16, 16, 18))
    sheet.paste(ia, (0, 0))
    sheet.paste(ib, (ia.width + 8, 0))
    sheet.save(os.path.join(OUT, out), quality=88)
    print("COMPARE", out)


def quad(a, pa, b, pb, out, h=620):
    """Two rows: a capture next to its photo, twice."""
    ia = _load(a, h)
    ipa = _load(os.path.join(REF, pa), h)
    ib = _load(b, h)
    ipb = _load(os.path.join(REF, pb), h)
    w = max(ia.width + ipa.width, ib.width + ipb.width) + 8
    sheet = Image.new("RGB", (w, h * 2 + 8), (16, 16, 18))
    sheet.paste(ia, (0, 0))
    sheet.paste(ipa, (ia.width + 8, 0))
    sheet.paste(ib, (0, h + 8))
    sheet.paste(ipb, (ib.width + 8, h + 8))
    sheet.save(os.path.join(OUT, out), quality=88)
    print("COMPARE", out)


def main():
    for cap, photo, name in PAIRS:
        if not os.path.exists(cap):
            print("missing", cap)
            continue
        hstack(cap, os.path.join(REF, photo), name)
    for a, pa, b, pb, name in QUADS:
        for c in (a, b):
            if not os.path.exists(c):
                print("missing", c)
                break
        else:
            quad(a, pa, b, pb, name)


if __name__ == "__main__":
    main()
