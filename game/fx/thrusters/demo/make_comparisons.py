#!/usr/bin/env python3
"""Build the side-by-side comparisons of the thruster plumes against the reference photos.

    python3 game/fx/thrusters/demo/make_comparisons.py

Reads the captures in ~/m/skyrush/captures and writes captures/fx_thrusters/compare_*.jpg plus
the ground-cloud growth strip.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / "captures" / "fx_thrusters"
REF = ROOT / "ref"
TILE_W = 820
GAP = 12
BG = (18, 18, 22)

PAIRS = [
    ("compare_18_studio", REF / "roadster/img/18_thrusters_firing_studio.jpg",
     "captures/fxth_r4_hop_t3_0.jpg", "reference 18 (studio, 4 down-plumes + ground cloud)",
     "fx_thrusters: lift plumes + ground cloud, rear view"),
    ("compare_27_side", REF / "roadster/img/27_live_flight_plumes_side.jpg",
     "captures/fxth_r4_hov5_t3_0.jpg", "reference 27 (live, hover plumes, side)",
     "fx_thrusters: hover plumes at 5 m, side view"),
    ("compare_28_kickflip", REF / "roadster/img/28_live_kickflip_plumes.jpg",
     "captures/fxth_r4_roll_t3_0.jpg", "reference 28 (live kickflip, two down-plumes)",
     "fx_thrusters: yaw burst, side view"),
    ("compare_29_overhead", REF / "roadster/img/29_live_launch_plume_overhead.jpg",
     "captures/fxth_r4_boost_t3_0.jpg", "reference 29 (live launch trail, overhead)",
     "fx_thrusters: N2 boost trail, overhead view"),
    ("compare_landing", REF / "video/keyframes/t140.jpg",
     "captures/fxth_r4_land_t4_0.jpg", "reference t140 (landing cloud)",
     "fx_thrusters: landing cushion + puff, rear view"),
    ("compare_29_launch", REF / "video/keyframes/t122.jpg",
     "captures/fxth_r4_boost_t3_0.jpg", "reference t122 (launch, overhead)",
     "fx_thrusters: N2 boost trail, overhead view"),
]

## The core close-up: my render next to a crop of the banded plume in photo 18.
CORE_PAIR = (
    "compare_core",
    REF / "roadster/img/18_thrusters_firing_studio.jpg", (556, 370, 726, 700),
    "reference 18 (crop of a down-plume, rotated 90 deg so the plume points right)",
    "captures/fxth_r4_corerear_t3_0.jpg", (640, 380, 1180, 500),
    "fx_thrusters: the four rear jets, 1.5 m from the nozzles",
)

## The ground cloud growing: four frames 0, 0.5, 1.0 and 2.0 s after the plume hits the road.
STRIP = [
    ("captures/fxth_r4_strip_s10.jpg", "0.0 s"),
    ("captures/fxth_r4_strip_s15.jpg", "0.5 s"),
    ("captures/fxth_r4_strip_s10.jpg", "1.0 s"),
    ("captures/fxth_r4_strip_top.jpg", "from above"),
]


def tile(path, label, width=TILE_W):
    img = Image.open(path).convert("RGB")
    h = int(img.height * width / img.width)
    img = img.resize((width, h), Image.LANCZOS)
    out = Image.new("RGB", (width, h + 26), BG)
    out.paste(img, (0, 26))
    ImageDraw.Draw(out).text((8, 7), label, fill=(220, 220, 225))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, ref_path, shot_path, ref_label, shot_label in PAIRS:
        ref = ROOT / ref_path
        shot = ROOT / shot_path
        if not ref.exists() or not shot.exists():
            print("skip", name, "missing", ref if not ref.exists() else shot)
            continue
        a = tile(ref, ref_label)
        b = tile(shot, shot_label)
        h = max(a.height, b.height)
        canvas = Image.new("RGB", (TILE_W * 2 + GAP, h), BG)
        canvas.paste(a, (0, 0))
        canvas.paste(b, (TILE_W + GAP, 0))
        path = OUT / (name + ".jpg")
        canvas.save(path, quality=88)
        print("wrote", path)
    _core_compare()
    _strip()


def _core_compare():
    name, ref_path, crop, ref_label, shot_path, shot_crop, shot_label = CORE_PAIR
    ref_img = Image.open(ROOT / ref_path).convert("RGB").crop(crop).rotate(90, expand=True)
    shot_img = Image.open(ROOT / shot_path).convert("RGB")
    if shot_crop is not None:
        shot_img = shot_img.crop(shot_crop)
    # Scale both to the same height so the plume detail can be compared directly.
    height = 560
    a = _scaled(ref_img, height)
    b = _scaled(shot_img, height)
    canvas = Image.new("RGB", (a.width + GAP + b.width, height + 26), BG)
    canvas.paste(a, (0, 26))
    canvas.paste(b, (a.width + GAP, 26))
    d = ImageDraw.Draw(canvas)
    d.text((8, 7), ref_label, fill=(220, 220, 225))
    d.text((a.width + GAP + 8, 7), shot_label, fill=(220, 220, 225))
    path = OUT / (name + ".jpg")
    canvas.save(path, quality=90)
    print("wrote", path)


def _scaled(img, height):
    w = max(1, int(img.width * height / img.height))
    return img.resize((w, height), Image.LANCZOS)


def _labeled(img, label):
    out = Image.new("RGB", (img.width, img.height + 26), BG)
    out.paste(img, (0, 26))
    ImageDraw.Draw(out).text((8, 7), label, fill=(220, 220, 225))
    return out


def _strip():
    frames = []
    for path, label in STRIP:
        p = ROOT / path
        if not p.exists():
            print("skip strip, missing", p)
            return
        frames.append(tile(p, "ground cloud " + label, width=520))
    w = sum(f.width for f in frames) + GAP * (len(frames) - 1)
    h = max(f.height for f in frames)
    canvas = Image.new("RGB", (w, h), BG)
    x = 0
    for f in frames:
        canvas.paste(f, (x, 0))
        x += f.width + GAP
    path = OUT / "compare_cloud_strip.jpg"
    canvas.save(path, quality=88)
    print("wrote", path)


if __name__ == "__main__":
    main()
