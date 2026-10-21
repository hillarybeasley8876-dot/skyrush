"""Build the side-by-side compare sheets (bund unit).

usage: python3 tmp/bund/compare.py

Every sheet puts the Godot night capture on the left and the reference photo on the
right, each with a label that says what it is - the review asked for evidence that shows
what it compares."""
import os

from PIL import Image, ImageDraw

GAME_DIR = "captures"
OUT_DIR = "captures/bund"
REF_DIR = "ref/shanghai/img/05_bund"
PANEL = (620, 800)
HEAD = 34

# (out name, game capture, reference photo, game label, reference label, ref crop)
SHEETS = [
    ("compare_12.jpg", "review_bund_r7_cmp_hsbc.jpg", "hsbc_customs_night_2026.jpg",
     "GAME: Bund 12 (HSBC) - from the river, the dome and the Customs House",
     "REFERENCE: hsbc_customs_night_2026.jpg", None),
    ("compare_13.jpg", "review_bund_r7_cmp_hsbc.jpg", "hsbc_customs_night_2026.jpg",
     "GAME: Bund 13 (Customs House) - the clock tower, right of the HSBC",
     "REFERENCE: hsbc_customs_night_2026.jpg (the clock tower)", None),
    ("compare_20.jpg", "review_bund_r7_cmp_peace.jpg", "peace_hotel_boc_night_2026.jpg",
     "GAME: Bund 20 (Sassoon House) - the green copper pyramid, left",
     "REFERENCE: peace_hotel_boc_night_2026.jpg", None),
    ("compare_23.jpg", "review_bund_r7_cmp_peace.jpg", "peace_hotel_boc_night_2026.jpg",
     "GAME: Bund 23 (Bank of China) - the green hipped roof, right",
     "REFERENCE: peace_hotel_boc_night_2026.jpg (the Bank of China)", None),
    ("compare_0.jpg", "review_bund_r7_cmp_bm.jpg", "bund_night_2026_4.jpg",
     "GAME: Bund 0 (Broadway Mansions) - the stepped Deco tower",
     "REFERENCE: bund_night_2026_4.jpg (the Bund's stepped Deco towers)", None),
    ("compare_floodwall.jpg", "review_bund_r7_cmp_flood.jpg",
     "hsbc_customs_night_2026.jpg",
     "GAME: the flood wall's river face - the blue light curtains",
     "REFERENCE: hsbc_customs_night_2026.jpg (the flood wall, bottom band)",
     (0.0, 0.72, 1.0, 1.0)),
]


def fit(img, size):
    """Contain the image in `size` on a black ground."""
    out = Image.new("RGB", size, (8, 8, 12))
    i = img.copy()
    i.thumbnail(size, Image.LANCZOS)
    out.paste(i, ((size[0] - i.width) // 2, (size[1] - i.height) // 2))
    return out


def sheet(game, ref, glabel, rlabel, crop):
    w, h = PANEL
    sheet_img = Image.new("RGB", (w * 2, PANEL[1] + HEAD), (20, 20, 24))
    d = ImageDraw.Draw(sheet_img)
    d.text((10, 10), glabel, fill=(235, 235, 235))
    d.text((w + 10, 10), rlabel, fill=(235, 235, 235))
    sheet_img.paste(fit(game, (w, h)), (0, HEAD))
    if crop:
        ref = ref.crop((int(ref.width * crop[0]), int(ref.height * crop[1]),
                        int(ref.width * crop[2]), int(ref.height * crop[3])))
    sheet_img.paste(fit(ref, (w, h)), (w, HEAD))
    return sheet_img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, game, ref, glabel, rlabel, crop in SHEETS:
        gp = os.path.join(GAME_DIR, game)
        rp = os.path.join(REF_DIR, ref)
        if not os.path.exists(gp) or not os.path.exists(rp):
            print("MISSING %s or %s - skipped %s" % (gp, rp, name))
            continue
        out = sheet(Image.open(gp), Image.open(rp), glabel, rlabel, crop)
        out.save(os.path.join(OUT_DIR, name), quality=88)
        print("wrote %s/%s" % (OUT_DIR, name))


if __name__ == "__main__":
    main()
