#!/usr/bin/env python3
"""render_map — draws the SKYRUSH city map and the road height profiles.

    python3 tools/city/render_map.py [data/city/city.json]

Writes captures/city_layout/map.png (2400 px, north up) and
captures/city_layout/profiles.png.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

from PIL import Image, ImageDraw, ImageFont  # noqa: E402

import citylib        # noqa: E402

OUT_DIR = os.path.join(ROOT, "captures", "city_layout")
MAP_PX = 2400

ROAD_COLOUR = {
    "surface": (92, 99, 112),
    "elevated": (255, 165, 60),
    "ramp": (255, 214, 110),
    "bridge": (96, 200, 255),
    "tunnel": (186, 110, 220),
}
ROAD_WIDTH = {"surface": 2, "elevated": 5, "ramp": 5, "bridge": 5, "tunnel": 4}
BLOCK_COLOUR = {
    "heritage": (150, 126, 96),
    "neon_street": (200, 90, 170),
    "midrise": (110, 116, 132),
    "office_tower": (86, 100, 140),
    "residential_slab": (120, 108, 118),
    "shikumen": (128, 104, 96),
    "industrial": (92, 92, 84),
    "park": (64, 122, 74),
    "plaza": (70, 74, 86),
}
WATER = (20, 52, 92)
BG = (10, 12, 18)
GRID = (30, 34, 44)
TEXT = (226, 230, 238)
LEVELS = ((9.0, "#7ad3ff"), (16.5, "#ffd166"), (23.9, "#ff8fab"), (31.0, "#b8f2a0"))


def load_font(size):
    for path in ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/System/Library/Fonts/Supplemental/Arial.ttf"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


def draw_map(city, path):
    win = city["window"]
    w = win["x_max"] - win["x_min"]
    size = MAP_PX
    scale = size / float(w)
    height = int((win["z_max"] - win["z_min"]) * scale)
    img = Image.new("RGB", (size, height), BG)
    d = ImageDraw.Draw(img)
    font = load_font(14)
    font_small = load_font(12)
    font_tiny = load_font(10)

    def px(x, z):
        return ((x - win["x_min"]) * scale, (z - win["z_min"]) * scale)

    for gx in range(int(win["x_min"] // 500 * 500), int(win["x_max"]) + 500, 500):
        for gz in range(int(win["z_min"] // 500 * 500), int(win["z_max"]) + 500, 500):
            x, y = px(gx, gz)
            d.line([(x, 0), (x, height)], fill=GRID, width=1)
            d.line([(0, y), (size, y)], fill=GRID, width=1)
            d.text((x + 3, 3), "x=%d" % gx, fill=(86, 92, 106), font=font_tiny)
            d.text((3, y + 3), "z=%d" % gz, fill=(86, 92, 106), font=font_tiny)

    # the water
    for water in city["water"]:
        if "polygon" in water:
            d.polygon([px(p[0], p[1]) for p in water["polygon"]], fill=WATER)
        if "centerline" in water:
            half = water.get("width", 70) * 0.5
            line = water["centerline"]
            left, right = [], []
            for i, p in enumerate(line):
                a = line[max(0, i - 1)]
                b = line[min(len(line) - 1, i + 1)]
                dx, dz = b[0] - a[0], b[1] - a[1]
                length = math.hypot(dx, dz) or 1.0
                nx, nz = dz / length, -dx / length
                left.append(px(p[0] + nx * half, p[1] + nz * half))
                right.append(px(p[0] - nx * half, p[1] - nz * half))
            d.polygon(left + list(reversed(right)), fill=WATER)

    # the lots
    for block in city["blocks"]:
        poly = [px(p[0], p[1]) for p in block["polygon"]]
        colour = BLOCK_COLOUR.get(block["style"], (90, 90, 90))
        d.polygon(poly, fill=colour, outline=(18, 20, 26))

    # the roads
    for road in city["roads"]:
        colour = ROAD_COLOUR.get(road["kind"], (120, 120, 120))
        pts = citylib.resample([[p[0], p[2]] for p in road["points"]], 10.0)
        if len(pts) < 2:
            continue
        line = [px(p[0], p[1]) for p in pts]
        width = ROAD_WIDTH.get(road["kind"], 2)
        d.line(line, fill=colour, width=width)
        if road["kind"] in ("elevated", "ramp", "bridge"):
            d.line([(x, y + 3) for (x, y) in line], fill=(26, 26, 34), width=width)

    # the sky lanes: dashed, with a label
    for lane in city["sky_lanes"]:
        pts = [px(p[0], p[2]) for p in lane["points"]]
        for i in range(0, len(pts) - 1, 2):
            d.line([pts[i], pts[i + 1]], fill=(0, 229, 255), width=3)
        mid = pts[len(pts) // 2]
        d.text((mid[0] + 6, mid[1] - 16), lane["label"] + "  " + lane["id"],
               fill=(0, 229, 255), font=font_small)
        pad = lane["pad"]
        x, y = px(pad["x"], pad["z"])
        head = math.radians(pad["heading_deg"])
        d.polygon([(x + 9 * math.sin(head), y - 9 * math.cos(head)),
                   (x - 6 * math.sin(head) - 5 * math.cos(head), y + 6 * math.cos(head) - 5 * math.sin(head)),
                   (x - 6 * math.sin(head) + 5 * math.cos(head), y + 6 * math.cos(head) + 5 * math.sin(head))],
                  fill=(255, 43, 214))
        d.text((x + 10, y + 4), "PAD " + lane["id"], fill=(255, 43, 214), font=font_tiny)

    # the routes
    route_colours = [(255, 90, 90), (255, 214, 0), (90, 255, 140),
                     (0, 200, 255), (255, 120, 220)]
    for i, route in enumerate(city["routes"]):
        colour = route_colours[i % len(route_colours)]
        pts = [px(cp[0], cp[2]) for cp in route["checkpoints"]]
        if len(pts) > 1:
            d.line(pts, fill=colour, width=3)
        for n, (cp, p) in enumerate(zip(route["checkpoints"], pts)):
            d.ellipse([p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5], fill=colour)
            d.text((p[0] + 6, p[1] - 14), str(n), fill=colour, font=font_tiny)
        if pts:
            d.text((pts[0][0] + 8, pts[0][1] + 6),
                   "%s (%d cp)" % (route["title"], len(route["checkpoints"])),
                   fill=colour, font=font_small)

    # the POIs
    for poi in city["pois"]:
        x, y = px(poi["x"], poi["z"])
        kind = poi["kind"]
        colour = {"landmark": (255, 220, 120), "toll": (255, 90, 90),
                  "roadblock_site": (255, 120, 60), "gas": (120, 255, 140),
                  "charge": (0, 229, 255), "police_station": (120, 160, 255),
                  "hiding_spot": (200, 200, 200)}.get(kind, (210, 210, 210))
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=colour)
        if kind not in ("landmark",):
            d.text((x + 6, y - 6), poi["label"], fill=colour, font=font_tiny)

    # the deck heights
    for road in city["roads"]:
        if road["kind"] not in ("elevated", "bridge", "ramp"):
            continue
        pts = road["points"]
        if len(pts) < 2:
            continue
        mid = pts[len(pts) // 2]
        x, y = px(mid[0], mid[2])
        d.text((x + 4, y - 18), "%.0fm" % mid[1], fill=ROAD_COLOUR[road["kind"]],
               font=font_tiny)

    # the legend
    d.rectangle([8, height - 150, 300, height - 8], fill=(14, 16, 22), outline=(58, 64, 76))
    ly = height - 140
    for kind, colour in sorted(ROAD_COLOUR.items()):
        d.line([(20, ly + 5), (48, ly + 5)], fill=colour, width=5)
        d.text((56, ly), kind, fill=TEXT, font=font_small)
        ly += 16
    d.text((20, ly + 4), "blocks:", fill=TEXT, font=font_small)
    bx = 78
    for style, colour in sorted(BLOCK_COLOUR.items()):
        d.rectangle([bx, ly + 2, bx + 16, ly + 14], fill=colour)
        d.text((bx + 20, ly + 2), style[:7], fill=TEXT, font=font_tiny)
        bx += 78
    d.text((20, height - 22), "SKYRUSH city layout - north up - 1 px = %.1f m" % (1 / scale),
           fill=TEXT, font=font_tiny)
    img.save(path)
    return img.size


def draw_profiles(city, path):
    """The height profile of every elevated road, ramp and bridge."""
    roads = [r for r in city["roads"]
             if r["kind"] in ("elevated", "ramp", "bridge", "tunnel")
             and len(r["points"]) > 1]
    width, row = 1600, 70
    height = 60 + row * len(roads)
    img = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(img)
    font = load_font(12)
    font_title = load_font(15)
    left = 250
    for i, road in enumerate(roads):
        y0 = 46 + i * row
        d.text((8, y0 - 12), "%-22s %s" % (road["id"], road["name_en"]), fill=TEXT, font=font)
        # the samples along the road (x, z arc length)
        pts = road["points"]
        cum = [0.0]
        for a, b in zip(pts, pts[1:]):
            cum.append(cum[-1] + math.hypot(b[0] - a[0], b[2] - a[2]))
        total = max(1.0, cum[-1])
        top = max(48.0, max(p[1] for p in pts) + 6.0)
        base = min(0.0, min(p[1] for p in pts) - 4.0)
        span = top - base
        # the grid and the level lines
        g = base
        while g <= top:
            y = y0 - ((g - base) / span) * (row - 26)
            d.line([(left, y), (width - 24, y)], fill=(26, 30, 38), width=1)
            if int(g) % 20 == 0:
                d.text((width - 62, y - 6), "%dm" % g, fill=(90, 96, 110),
                       font=font)
            g += 10.0
        for level, colour in LEVELS:
            y = y0 - ((level - base) / span) * (row - 26)
            for x in range(left, width - 24, 12):
                d.line([(x, y), (x + 6, y)], fill=colour, width=1)
        # the profile
        prev = None
        for p, s in zip(pts, cum):
            x = left + (s / total) * (width - 40 - left)
            y = y0 - ((p[1] - base) / span) * (row - 26)
            if prev:
                run = math.hypot(p[0] - prev[0][0], p[2] - prev[0][2])
                over = run > 0.5 and abs(p[1] - prev[0][1]) > 0.046 * run
                d.line([prev[1], (x, y)], fill=(255, 80, 80) if over else (255, 170, 70),
                       width=2)
            prev = (p, (x, y))
        d.text((left, y0 + 12), "%.0f m long, %.1f - %.1f m" % (
            total, min(p[1] for p in pts), max(p[1] for p in pts)),
            fill=(150, 156, 168), font=font)
    d.text((8, 12), "road height profiles (Y in m over the distance along the road)",
           fill=TEXT, font=font_title)
    d.text((8, 32), "red = over the 4.6 % design grade; the dashed lines are L2 9.0 / "
                    "L3 16.5 / L4 23.9 / L5 31.0", fill=(150, 156, 168), font=font)
    img.save(path)
    return img.size


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(ROOT, "data", "city", "city.json")
    city = citylib.load_json(path)
    os.makedirs(OUT_DIR, exist_ok=True)
    size = draw_map(city, os.path.join(OUT_DIR, "map.png"))
    psize = draw_profiles(city, os.path.join(OUT_DIR, "profiles.png"))
    print("map.png      %dx%d" % size)
    print("profiles.png %dx%d" % psize)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
