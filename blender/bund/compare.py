"""Compose the Bund review sheets: the Godot render next to the reference photo (bund unit).

    python3 blender/bund/compare.py [capture prefix]

The renders come from the Godot preview scene (captures/<prefix>_<view>.jpg), so the
sheets show the real game look, not a Blender render. Labels are ASCII (the bundled font
has no CJK glyphs) and they say what each side shows - the round-2 review asked for
evidence that says what it compares.
"""
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.expanduser("~/m/skyrush")
OUT = os.path.join(ROOT, "captures", "bund")
REF = os.path.join(ROOT, "ref", "shanghai", "img", "05_bund")
SHOT = os.path.join(ROOT, "captures")
H, W = 760, 620

# (sheet name, capture suffix, reference photo, game caption, reference caption)
SHEETS = [
	("compare_12", "cmp_hsbc", "hsbc_customs_night_2026.jpg",
	 "GAME: Bund 12 (HSBC) - the ribbed dome on its drum, from the river",
	 "REFERENCE: hsbc_customs_night_2026.jpg - the HSBC's dome, left"),
	("compare_13", "cmp_hsbc", "hsbc_customs_night_2026.jpg",
	 "GAME: Bund 13 (Customs House) - the clock tower, right of the HSBC",
	 "REFERENCE: hsbc_customs_night_2026.jpg - the Customs House's clock tower, right"),
	("compare_20", "cmp_peace", "peace_hotel_boc_night_2026.jpg",
	 "GAME: Bund 20 (Sassoon House) - the green copper pyramid, left",
	 "REFERENCE: peace_hotel_boc_night_2026.jpg - the Peace Hotel's green pyramid, left"),
	("compare_23", "cmp_peace", "peace_hotel_boc_night_2026.jpg",
	 "GAME: Bund 23 (Bank of China) - the green hipped roof, right",
	 "REFERENCE: peace_hotel_boc_night_2026.jpg - the Bank of China, right"),
	("compare_0", "cmp_bm", "bund_day_panorama_2015.jpg",
	 "GAME: Bund 0 (Broadway Mansions) - the stepped Deco tower",
	 "REFERENCE: the whole Bund row - no photo in ref/ isolates this tower"),
	("compare_floodwall", "cmp_flood", "hsbc_customs_night_2026.jpg",
	 "GAME: the flood wall's river face - the blue light curtains",
	 "REFERENCE: hsbc_customs_night_2026.jpg - the flood wall's curtains, bottom band"),
	("compare_row", "cmp_prom", "bund_night_2023.jpg",
	 "GAME: the Bund from the promenade, looking north",
	 "REFERENCE: bund_night_2023.jpg - the Bund from the promenade, looking north"),
]


def fit(path, w, h):
	"""Fill a w x h panel with the image (centre crop, no letterbox)."""
	img = Image.open(path).convert("RGB")
	scale = max(w / img.width, h / img.height)
	img = img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))))
	left = (img.width - w) // 2
	top = (img.height - h) // 2
	return img.crop((left, top, left + w, top + h))


def main():
	prefix = sys.argv[1] if len(sys.argv) > 1 else "review_bund_r14"
	os.makedirs(OUT, exist_ok=True)
	for name, view, ref, caption, ref_caption in SHEETS:
		shot_path = os.path.join(SHOT, "%s_%s.jpg" % (prefix, view))
		ref_path = os.path.join(REF, ref)
		if not os.path.exists(shot_path):
			print("skip (no capture):", shot_path)
			continue
		sheet = Image.new("RGB", (W * 2 + 12, H + 40), (10, 10, 14))
		sheet.paste(fit(shot_path, W, H), (0, 34))
		sheet.paste(fit(ref_path, W, H), (W + 12, 34))
		draw = ImageDraw.Draw(sheet)
		draw.text((10, 10), caption, fill=(232, 232, 238))
		draw.text((W + 22, 10), ref_caption, fill=(232, 232, 238))
		path = os.path.join(OUT, "%s.jpg" % name)
		sheet.save(path, quality=86)
		print("wrote", path)


if __name__ == "__main__":
	main()
