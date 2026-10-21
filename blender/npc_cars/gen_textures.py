"""Generate the NPC fleet textures (PIL + numpy, system python3 - NOT Blender).

    python3 blender/npc_cars/gen_textures.py

Everything is deterministic (fixed seeds). Output: game/assets/cars/npc/textures/.
The layout constants live in atlas.py so the Blender builders can map UVs.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas  # noqa: E402
import gen_decals  # noqa: E402
import texlib  # noqa: E402
from texlib import fit_font, font, noise_overlay, save  # noqa: E402

OUT = atlas.TEXTURE_DIR
TRIM = atlas.TRIM_SIZE
INTERIOR = atlas.INTERIOR_SIZE

# ------------------------------------------------------------------- surfaces


def trim_atlas(size=TRIM):
    """Shared trim sheet: rim alloy, plastics, grille mesh, LED strip, rubber."""
    img = Image.new("RGB", (size, size), (18, 19, 22))
    d = ImageDraw.Draw(img)

    # --- rim: dark machined alloy, circular brushing ---
    x0, y0, x1, y1 = atlas.TRIM["rim"]
    w, h = x1 - x0, y1 - y0
    rim = Image.new("RGB", (w, h), (58, 61, 66))
    rd = ImageDraw.Draw(rim)
    for i in range(120):
        t = i / 120.0
        c = int(52 + 74 * (1.0 - abs(t - 0.5) * 2.0) ** 2)
        rd.ellipse([w * 0.5 * t - 4, h * 0.5 * t - 4,
                    w - w * 0.5 * t + 4, h - h * 0.5 * t + 4],
                   outline=(c, c, c + 3), width=3)
    rd.ellipse([w * 0.06, h * 0.06, w * 0.94, h * 0.94], outline=(166, 171, 175),
               width=7)
    rd.ellipse([w * 0.30, h * 0.30, w * 0.70, h * 0.70], fill=(28, 30, 34),
               outline=(96, 100, 106), width=4)
    for i in range(10):
        a = i * math.pi / 5.0
        rd.ellipse([w * 0.5 + math.cos(a) * w * 0.34 - 9,
                    h * 0.5 + math.sin(a) * h * 0.34 - 9,
                    w * 0.5 + math.cos(a) * w * 0.34 + 9,
                    h * 0.5 + math.sin(a) * h * 0.34 + 9], fill=(18, 19, 22))
    img.paste(noise_overlay(rim, 8, 5), (x0, y0))

    # --- matte black trim with a fine grain ---
    x0, y0, x1, y1 = atlas.TRIM["trim"]
    w, h = x1 - x0, y1 - y0
    grain = texlib.fbm(size, 26, 2, 11)[:h, :w]
    base = np.zeros((h, w, 3), dtype=np.float32) + 21.0
    base += (grain[:, :, None] - 0.5) * 14.0
    img.paste(Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB"), (x0, y0))

    # --- expanded-metal grille mesh ---
    x0, y0, x1, y1 = atlas.TRIM["mesh"]
    w, h = x1 - x0, y1 - y0
    mesh = Image.new("RGB", (w, h), (8, 9, 11))
    md = ImageDraw.Draw(mesh)
    step = 18
    for i in range(-h, w + h, step):
        md.line([(i, 0), (i + h, h)], fill=(52, 55, 62), width=5)
        md.line([(i, h), (i + h, 0)], fill=(30, 32, 37), width=4)
    img.paste(mesh, (x0, y0))

    # --- LED segment strip (50% duty) ---
    x0, y0, x1, y1 = atlas.TRIM["lamp"]
    w, h = x1 - x0, y1 - y0
    lamp = Image.new("RGB", (w, h), (8, 10, 14))
    ld = ImageDraw.Draw(lamp)
    seg = 10
    for i in range(0, w, seg):
        ld.rectangle([i, 5, i + seg - 4, h - 5], fill=(232, 242, 255))
        ld.rectangle([i + seg - 4, 5, i + seg - 1, h - 5], fill=(120, 140, 170))
    img.paste(lamp, (x0, y0))

    # --- red LED strip (tail lamps, 50 % duty) ---
    x0, y0, x1, y1 = atlas.TRIM["lamp_red"]
    w, h = x1 - x0, y1 - y0
    lamp = Image.new("RGB", (w, h), (58, 5, 8))
    ld = ImageDraw.Draw(lamp)
    seg = 10
    for i in range(0, w, seg):
        ld.rectangle([i, 5, i + seg - 4, h - 5], fill=(255, 32, 48))
    img.paste(lamp, (x0, y0))

    # --- tyre sidewall ---
    x0, y0, x1, y1 = atlas.TRIM["rubber"]
    w, h = x1 - x0, y1 - y0
    rub = texlib.fbm(size, 18, 2, 21)[:h, :w]
    arr = np.zeros((h, w, 3), dtype=np.float32) + 27.0
    arr += (rub[:, :, None] - 0.5) * 12.0
    img.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB"), (x0, y0))

    # --- flat dark ---
    x0, y0, x1, y1 = atlas.TRIM["plain"]
    img.paste(Image.new("RGB", (x1 - x0, y1 - y0), (24, 25, 28)), (x0, y0))
    return img


def tyre_normal(size=1024):
    """Tread + sidewall normal map with the embossed sidewall lettering.

    u = around the circumference, v = across the section.
    """
    v = np.linspace(0.0, 1.0, size, dtype=np.float32)[None, :]
    u = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None]
    h = np.zeros((size, size), dtype=np.float32)
    tread = (v > 0.37) & (v < 0.63)
    h += tread * 1.0
    for centre in (0.405, 0.455, 0.505, 0.555):
        h -= (np.abs(v - centre) < 0.019) * 0.95
    sipe = (np.abs(((u * 66.0) % 1.0) - 0.5) < 0.10) & tread
    h -= sipe * 0.45
    shoulder = ((v > 0.345) & (v < 0.375)) | ((v > 0.625) & (v < 0.655))
    h += shoulder * (np.abs(((u * 33.0) % 1.0) - 0.5) > 0.22) * 0.12
    side = (v < 0.30) | (v > 0.70)
    h += side * (0.5 + 0.5 * np.sin(u * 900.0)) * 0.10
    h += texlib.value_noise(size, 64, 7) * 0.05
    # embossed sidewall lettering (18 mm caps, once around the circumference)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    f = fit_font("SKYRUSH CITYGRIP 235/45 R19", 46, 620, 60)
    md.text((70, int(size * 0.735)), "SKYRUSH CITYGRIP 235/45 R19", font=f, fill=255)
    m = np.asarray(mask, dtype=np.float32) / 255.0
    h += m * 0.55
    return texlib.normal_from_height(h, 2.6)


def rim_face(size=1024):
    """The alloy face of a five twin spoke rim (the pockets stay dark).

    The art is drawn in the same square the rim is projected into, so the
    spokes line up with the modelled ones: the wheel angle theta maps to the
    image angle -theta (the box projection is u = y, v = z).
    """
    img = Image.new("RGB", (size, size), (16, 17, 20))
    d = ImageDraw.Draw(img)
    cx = cy = size * 0.5
    r = size * 0.5
    # the outer lip
    d.ellipse([cx - r * 0.995, cy - r * 0.995, cx + r * 0.995, cy + r * 0.995],
              fill=(108, 113, 119))
    d.ellipse([cx - r * 0.955, cy - r * 0.955, cx + r * 0.955, cy + r * 0.955],
              fill=(16, 17, 20))
    # the twin spokes
    for i in range(5):
        base = -i * 2.0 * math.pi / 5.0
        for side in (-1, 1):
            a0 = base + side * 0.16 - 0.10
            a1 = base + side * 0.16 + 0.10
            pts = []
            for rr, aa in ((0.22, a0 - 0.06), (0.95, a0 - 0.012),
                           (0.95, a1 + 0.012), (0.22, a1 + 0.06)):
                pts.append((cx + rr * r * math.cos(aa),
                            cy - rr * r * math.sin(aa)))
            d.polygon(pts, fill=(166, 171, 175))
    # the hub cap and the bolt circle
    d.ellipse([cx - r * 0.27, cy - r * 0.27, cx + r * 0.27, cy + r * 0.27],
              fill=(150, 155, 161))
    d.ellipse([cx - r * 0.19, cy - r * 0.19, cx + r * 0.19, cy + r * 0.19],
              fill=(96, 100, 106))
    for i in range(5):
        a = -i * 2.0 * math.pi / 5.0
        bx, by = cx + r * 0.33 * math.cos(a), cy - r * 0.33 * math.sin(a)
        d.ellipse([bx - 7, by - 7, bx + 7, by + 7], fill=(38, 40, 44))
    # radial machining marks
    for i in range(360):
        a = i * math.pi / 180.0
        c = 150 + int(26 * ((i % 7) / 7.0 - 0.5))
        d.line([(cx + r * 0.30 * math.cos(a), cy - r * 0.30 * math.sin(a)),
                (cx + r * 0.95 * math.cos(a), cy - r * 0.95 * math.sin(a))],
               fill=(c, c + 4, c + 8), width=1)
    return noise_overlay(img, 10, 12)


def tyre_face(size=1024):
    """The rubber of the tyre: a dark tread with a sidewall."""
    img = Image.new("RGB", (size, size), (24, 25, 28))
    d = ImageDraw.Draw(img)
    grain = texlib.fbm(size, 26, 3, 21)
    arr = np.zeros((size, size, 3), dtype=np.float32) + 30.0
    arr += (grain[:, :, None] - 0.5) * 14.0
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, size - 1, size * 0.16], fill=(34, 35, 39))
    d.rectangle([0, size * 0.84, size - 1, size - 1], fill=(34, 35, 39))
    return img


def brake_face(size=512):
    """The brake disc: a machined grey ring with radial grooves."""
    img = Image.new("RGB", (size, size), (90, 93, 96))
    d = ImageDraw.Draw(img)
    cx = cy = size * 0.5
    r = size * 0.48
    for i in range(90):
        a = i * math.pi / 45.0
        d.line([(cx + r * 0.55 * math.cos(a), cy + r * 0.55 * math.sin(a)),
                (cx + r * 0.95 * math.cos(a), cy + r * 0.95 * math.sin(a))],
               fill=(74, 77, 80), width=2)
    d.ellipse([cx - r * 0.52, cy - r * 0.52, cx + r * 0.52, cy + r * 0.52],
              fill=(112, 116, 120))
    d.ellipse([cx - r * 0.30, cy - r * 0.30, cx + r * 0.30, cy + r * 0.30],
              fill=(58, 60, 63))
    return noise_overlay(img, 8, 13)


def caliper_face(size=512):
    """The caliper: a red anodised body over the disc."""
    img = Image.new("RGB", (size, size), (16, 17, 20))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([size * 0.22, size * 0.10, size * 0.78, size * 0.90],
                        radius=size * 0.12, fill=(138, 43, 34))
    d.rounded_rectangle([size * 0.30, size * 0.22, size * 0.70, size * 0.78],
                        radius=size * 0.08, fill=(96, 30, 24))
    return noise_overlay(img, 8, 14)


def wheel_sheet(size=1024):
    """The wheel sheet: the rim face, the tread, the brake and the caliper."""
    w, h = atlas.WHEEL_SHEET
    out = Image.new("RGB", (w, h), (18, 19, 22))
    out.paste(rim_face(size), (0, 0))
    out.paste(tyre_face(size).crop((0, 0, 768, size)), (0, size))
    out.paste(brake_face(256), (768, size))
    out.paste(caliper_face(256), (768, size + 256))
    return out


def wheel_normal(tyre_nrm, size=1024):
    """The wheel normal sheet: a flat rim on top, the tread normal below."""
    w, h = atlas.WHEEL_SHEET
    out = Image.new("RGB", (w, h), (128, 128, 255))
    out.paste(tyre_nrm.crop((0, 0, 768, size)), (0, size))
    return out


def interior_atlas(size=INTERIOR):
    """Shared interior sheet: seats, dash, headliner, plastics, screen, belts."""
    img = Image.new("RGB", (size, size), (16, 16, 18))
    x0, y0, x1, y1 = atlas.INTERIOR["seat"]
    w, h = x1 - x0, y1 - y0
    seat = Image.new("RGB", (w, h), (34, 33, 36))
    sd = ImageDraw.Draw(seat)
    for j in range(0, h, 30):
        for i in range(0, w, 30):
            sd.ellipse([i + 10, j + 10, i + 18, j + 18], fill=(20, 19, 22))
    sd.rectangle([0, 0, w - 1, h - 1], outline=(62, 60, 64), width=6)
    sd.rectangle([12, 12, w - 13, h - 13], outline=(104, 66, 66), width=4)
    for x in range(30, w - 30, 46):
        sd.line([(x, 16), (x, h - 16)], fill=(118, 74, 74), width=2)
    grain = texlib.fbm(size, 22, 2, 31)[:h, :w]
    arr = np.asarray(seat, dtype=np.float32) + (grain[:, :, None] - 0.5) * 12.0
    img.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB"), (x0, y0))

    x0, y0, x1, y1 = atlas.INTERIOR["dash"]
    w, h = x1 - x0, y1 - y0
    dash = Image.new("RGB", (w, h), (40, 41, 45))
    dd = ImageDraw.Draw(dash)
    dd.rectangle([w * 0.50, h * 0.14, w * 0.95, h * 0.60], fill=(10, 16, 24))
    dd.rectangle([w * 0.52, h * 0.17, w * 0.93, h * 0.57], fill=(18, 44, 62))
    dd.text((w * 0.56, h * 0.24), "0", font=font(int(h * 0.22)), fill=(150, 220, 255))
    dd.text((w * 0.74, h * 0.24), "km/h", font=font(int(h * 0.09)), fill=(120, 190, 230))
    for i in range(6):
        dd.rectangle([w * 0.08 + i * w * 0.058, h * 0.72, w * 0.12 + i * w * 0.058,
                      h * 0.86], fill=(24, 25, 28))
    img.paste(dash, (x0, y0))

    x0, y0, x1, y1 = atlas.INTERIOR["headliner"]
    w, h = x1 - x0, y1 - y0
    weave = texlib.fbm(size, 40, 2, 41)[:h, :w]
    arr = np.zeros((h, w, 3), dtype=np.float32) + 104.0
    arr += (weave[:, :, None] - 0.5) * 26.0
    img.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB"), (x0, y0))

    x0, y0, x1, y1 = atlas.INTERIOR["trim"]
    w, h = x1 - x0, y1 - y0
    fine = texlib.fbm(size, 30, 2, 51)[:h, :w]
    arr = np.zeros((h, w, 3), dtype=np.float32) + 26.0
    arr += (fine[:, :, None] - 0.5) * 10.0
    img.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB"), (x0, y0))

    x0, y0, x1, y1 = atlas.INTERIOR["screen"]
    w, h = x1 - x0, y1 - y0
    scr = Image.new("RGB", (w, h), (5, 9, 15))
    cd = ImageDraw.Draw(scr)
    for i in range(0, w, 8):
        cd.rectangle([i, 0, i + 3, h], fill=(10, 20, 28))
    cd.arc([w * 0.12, h * 0.30, w * 0.88, h * 1.10], 200, 340, fill=(70, 210, 255),
           width=6)
    cd.text((w * 0.30, h * 0.36), "0", font=font(int(h * 0.30)), fill=(220, 245, 255))
    img.paste(scr, (x0, y0))

    x0, y0, x1, y1 = atlas.INTERIOR["belt"]
    w, h = x1 - x0, y1 - y0
    belt = Image.new("RGB", (w, h), (26, 26, 28))
    bd = ImageDraw.Draw(belt)
    for i in range(0, w, 10):
        bd.line([(i, 0), (i + 6, h)], fill=(42, 42, 46), width=4)
    img.paste(belt, (x0, y0))
    return img


def plastic_normal(size=512):
    """Fine plastic grain for the black trim (bumper, mirrors, liners)."""
    h = texlib.fbm(size, 60, 2, 91)
    h = h + texlib.value_noise(size, 220, 92) * 0.30
    return texlib.normal_from_height(h, 0.9)


def interior_normal(size=256):
    """Leather and fabric bump for the cabin (seats, dash, headliner)."""
    h = texlib.fbm(size, 18, 3, 93)
    fine = texlib.value_noise(size, 120, 94)
    return texlib.normal_from_height(h * 0.7 + fine * 0.3, 1.4)


def paint_rough(size=256):
    """Two-scale roughness breakup for the car paint (0.24 - 0.44)."""
    coarse = texlib.fbm(size, 12, 3, 61)
    fine = texlib.fbm(size, 90, 2, 62)
    r = 0.24 + coarse * 0.14 + (fine - 0.5) * 0.07
    return Image.fromarray((np.clip(r, 0, 1) * 255).astype(np.uint8), "L").convert("RGB")


def black_plastic(size=1024):
    """Tileable black plastic grain (trim, wheel wells, bumpers).

    A fine stipple of 0.2 - 0.4 mm features, so the sheet never reads as
    wood grain when it is projected in metres on a long skirt.
    """
    coarse = texlib.fbm(size, 40, 3, 81)
    fine = texlib.value_noise(size, 260, 82)
    v = 0.10 + coarse * 0.045 + (fine - 0.5) * 0.030
    return Image.fromarray((np.clip(v, 0, 1) * 255).astype(np.uint8), "L").convert("RGB")


def plate_normal(size=1024):
    """Embossed plate characters (the height of the plate atlas as a normal map)."""
    img = Image.open(os.path.join(atlas.TEXTURE_DIR, "npc_plates.png")).convert("L")
    w, h = img.size
    arr = np.asarray(img, dtype=np.float32) / 255.0
    height = 1.0 - arr                      # the bright glyphs stand proud
    return texlib.normal_from_height(height, 1.4)


def paint_detail(size=256):
    """Near-white detail for the paint albedo (the shader multiplies base x this)."""
    coarse = texlib.fbm(size, 10, 3, 71)
    fine = texlib.fbm(size, 70, 2, 72)
    v = 0.94 + coarse * 0.05 + (fine - 0.5) * 0.03
    return Image.fromarray((np.clip(v, 0, 1) * 255).astype(np.uint8), "L").convert("RGB")


def glass_grime(size=256):
    """Rain streaks and dust for the tinted glass (multiplied over the tint)."""
    img = Image.new("L", (size, size), 255)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(77)
    for _ in range(140):
        x = int(rng.integers(0, size))
        y = int(rng.integers(0, size))
        h = int(rng.integers(30, 300))
        w = int(rng.integers(1, 5))
        d.rectangle([x, y, x + w, y + h], fill=int(rng.integers(200, 246)))
    for _ in range(320):
        x = int(rng.integers(0, size))
        y = int(rng.integers(0, size))
        r = int(rng.integers(1, 5))
        d.ellipse([x, y, x + r, y + r], fill=int(rng.integers(190, 238)))
    grain = texlib.fbm(size, 16, 2, 78)
    arr = np.asarray(img, dtype=np.float32) * (0.93 + grain * 0.07)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "L").convert("RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    print("generating NPC textures in %s" % OUT)
    trim = trim_atlas()
    save(trim, "npc_trim.png", OUT)
    tyre_nrm = tyre_normal()
    save(tyre_nrm, "npc_tyre_nrm.png", OUT)
    save(wheel_sheet(), "npc_wheel.png", OUT)
    save(wheel_normal(tyre_nrm), "npc_wheel_nrm.png", OUT)
    save(interior_atlas(), "npc_interior.png", OUT)
    save(paint_rough(), "npc_paint_rough.png", OUT)
    save(paint_detail(), "npc_paint_detail.png", OUT)
    save(black_plastic(), "npc_black_plastic.png", OUT)
    save(plastic_normal(), "npc_black_plastic_nrm.png", OUT)
    save(interior_normal(), "npc_interior_nrm.png", OUT)
    save(glass_grime(), "npc_glass_grime.png", OUT)
    save(gen_decals.plates_atlas(), "npc_plates.png", OUT)
    save(plate_normal(), "npc_plates_nrm.png", OUT)
    import spec as specs
    for name in ("police_patrol", "police_interceptor", "police_suv"):
        sp = specs.BY_NAME[name]
        door = 0.5 * (sp["doors"][0][0] + sp["doors"][0][1])
        rear = 0.5 * (sp["doors"][1][0] + sp["doors"][1][1])
        save(gen_decals.police_livery(name, door, rear, sp["L"]), "livery_%s.png" % name, OUT)
        save(gen_decals.sign_roof_number("沪-07"), "roofnum_%s.png" % name, OUT)
    save(gen_decals.taxi_livery(specs.TAXI["L"]), "livery_taxi.png", OUT)
    save(gen_decals.decal_taxi(), "decal_taxi.png", OUT)
    save(gen_decals.decal_van(), "decal_van.png", OUT)
    save(gen_decals.sign_roof(), "sign_taxi_roof.png", OUT)
    save(gen_decals.sign_roof_en(), "sign_taxi_roof_en.png", OUT)
    save(gen_decals.decal_drone(), "decal_drone.png", OUT)
    save(gen_decals.dot_matrix("申城公交 71路", (1024, 256)), "sign_bus_front.png", OUT)
    save(gen_decals.dot_matrix("71", (512, 256)), "sign_bus_side.png", OUT)
    print("done")


if __name__ == "__main__":
    main()
