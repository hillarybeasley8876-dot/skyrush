"""The review camera list for the Bund (bund unit).

    tools/godot.sh shot --scene=res://assets/bund/preview_bund.tscn --out=review_bund_r2 \\
        --cams=blender/bund/cams_review.json --warm=45

The cameras are the ones the lead's review used (game axes: x east, y up, z south)."""
import json
import os

CAMS = [
	{"name": "road_n", "pos": [-101, 1.3, -230], "look": [-126, 5, -330], "fov": 70},
	{"name": "road_s", "pos": [-139, 1.3, -640], "look": [-150, 10, -545], "fov": 70},
	{"name": "close5", "pos": [-124.5, 1.7, -252], "look": [-130, 6, -272], "fov": 70},
	{"name": "stone2m", "pos": [-128, 1.6, -240.5], "look": [-130.6, 1.2, -243], "fov": 60},
	{"name": "mid20", "pos": [-137, 1.6, -462], "look": [-157, 11, -490], "fov": 62},
	{"name": "far100", "pos": [-60, 6, -520], "look": [-157, 35, -569], "fov": 55},
	{"name": "prom", "pos": [-95, 4.2, -360], "look": [-120, 14, -300], "fov": 62},
	{"name": "flood", "pos": [-45, 1.6, -340], "look": [-79, 1.0, -330], "fov": 60},
	{"name": "river_mid", "pos": [60, 8, -360], "look": [-130, 26, -330], "fov": 50},
	{"name": "river_far", "pos": [230, 10, -380], "look": [-130, 28, -330], "fov": 40},
	{"name": "top", "pos": [-120, 260, -330], "look": [-120, 0, -331], "fov": 60},
	{"name": "hsbc_front", "pos": [-88, 10, -268], "look": [-130, 22, -268], "fov": 62},
	{"name": "customs_front", "pos": [-90, 14, -322], "look": [-137, 38, -328], "fov": 66},
	{"name": "peace_front", "pos": [-62, 12, -560], "look": [-157, 30, -585], "fov": 60},
	{"name": "bm_front", "pos": [-62, 12, -1030], "look": [-156, 30, -1051], "fov": 58},
	{"name": "peace_close", "pos": [-105, 26, -569], "look": [-157, 50, -569], "fov": 55},
	{"name": "boc_close", "pos": [-100, 26, -600], "look": [-154, 52, -600], "fov": 55},
	{"name": "bm_close", "pos": [-100, 30, -1051], "look": [-156, 40, -1051], "fov": 55},
	{"name": "customs_close", "pos": [-95, 30, -328], "look": [-137, 55, -328], "fov": 55},
]


def main():
	path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cams_review.json")
	with open(path, "w") as fh:
		json.dump(CAMS, fh, indent=1)
	print("wrote", path)


if __name__ == "__main__":
	main()
