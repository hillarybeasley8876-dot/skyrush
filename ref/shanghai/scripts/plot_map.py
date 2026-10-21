"""Render build/map_layout_v1.json to a labelled top-down sketch PNG (north up).

usage: python3 -E plot_map.py <layout.json> <out.png>
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

lay = json.load(open(sys.argv[1], encoding="utf-8"))
W = lay["window"]
S = 0.4  # px per metre -> 1600 x 1200 px
PAD = 40
img = Image.new("RGB", (int((W["x_max"] - W["x_min"]) * S) + 2 * PAD,
                        int((W["z_max"] - W["z_min"]) * S) + 2 * PAD), (24, 26, 34))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 15)
    small = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 12)
except OSError:
    font = small = ImageFont.load_default()

def P(p):
    return (PAD + (p[0] - W["x_min"]) * S, PAD + (p[1] - W["z_min"]) * S)

def line(pts, col, w):
    d.line([P(p) for p in pts], fill=col, width=w, joint="curve")

# grid every 500 m
for x in range(-2000, 1801, 500):
    d.line([P((x, W["z_min"])), P((x, W["z_max"]))], fill=(45, 48, 60), width=1)
    d.text(P((x + 8, W["z_min"] + 10)), f"x={x}", fill=(110, 110, 130), font=small)
for z in range(-1000, 1801, 500):
    d.line([P((W["x_min"], z)), P((W["x_max"], z))], fill=(45, 48, 60), width=1)
    d.text(P((W["x_min"] + 8, z + 6)), f"z={z}", fill=(110, 110, 130), font=small)

rv = lay["river"]
poly = rv["huangpu_west_bank_puxi"] + rv["huangpu_east_bank_pudong"][::-1]
d.polygon([P(p) for p in poly], fill=(28, 70, 120))
line(rv["suzhou_creek_centerline"], (28, 70, 120), int(70 * S))

R, D = lay["roads"], lay["design"]
line(R["yanan_tunnel"], (120, 120, 120), 3)
line(D["bund_tunnel_optional"], (90, 90, 90), 2)
for k, col, w in (("zhongshan_e2_s", (170, 170, 170), 4), ("century_ave", (200, 200, 200), 10),
                  ("lujiazui_ring_rd", (170, 170, 170), 4), ("bund_zhongshan_e1", (220, 200, 120), 6),
                  ("yanan_east_rd_surface", (170, 170, 170), 5), ("waibaidu_bridge", (200, 60, 60), 6)):
    line(R[k], col, w)
line(D["pudong_south_rd"], (170, 170, 170), 5)
line(D["g50_expressway_at_grade"], (230, 230, 230), 8)
for k in ("yanan_elevated", "ns_elevated"):
    line(R[k], (255, 140, 30), 9)
for k in ("inner_ring_elevated", "ns_elevated_north_ext"):
    line(D[k], (255, 140, 30), 9)
line([D["yanan_elevated_west_ramp"]["from"], D["yanan_elevated_west_ramp"]["to"]], (255, 190, 90), 9)
nb = D["nanpu_bridge"]
line([nb["puxi_deck_end"], nb["pudong_deck_end"]], (255, 255, 255), 8)
c = P(D["nanpu_spiral_center"])
for r in (95, 141):
    d.ellipse([c[0] - r * S, c[1] - r * S, c[0] + r * S, c[1] + r * S], outline=(255, 140, 30), width=5)

pl = D["nanpu_pudong_loop"]; c2 = P(pl["center"]); r2 = pl["radius"]
d.ellipse([c2[0] - r2 * S, c2[1] - r2 * S, c2[0] + r2 * S, c2[1] + r2 * S], outline=(255, 140, 30), width=5)
line([pl["exit_point"], [1700, 1330], [1690, 1280]], (255, 190, 90), 5)

def box(rx, rz, col, label):
    d.rectangle([P((rx[0], rz[0])), P((rx[1], rz[1]))], fill=col)
    d.text(P((rx[0], rz[1] + 8)), label, fill=col, font=small)
for name, (x0, x1, z0, z1) in D["districts"].items():
    d.rectangle([P((x0, z0)), P((x1, z1))], outline=(90, 160, 90), width=1)
    d.text(P((x0 + 6, z0 + 6)), name.split("_")[0], fill=(120, 200, 120), font=small)
tp = D["toll_plaza"]
box([tp["center"][0] - 80, tp["center"][0] + 80], [tp["center"][1] - 40, tp["center"][1] + 40], (230, 60, 200), "收费站 toll")
box(D["gas_station"]["rect_x"], D["gas_station"]["rect_z"], (255, 60, 60), "加油站 gas")
box(D["charging_station"]["rect_x"], D["charging_station"]["rect_z"], (60, 255, 160), "超充 EV")

for k, p in lay["landmarks"].items():
    q = P(p)
    d.ellipse([q[0] - 5, q[1] - 5, q[0] + 5, q[1] + 5], fill=(255, 230, 0))
    d.text((q[0] + 7, q[1] - 7), k, fill=(255, 230, 0), font=small)
for p, label in ((nb["puxi_tower"], "Nanpu tower W"), (nb["pudong_tower"], "Nanpu tower E"),
                 (D["nanpu_spiral_center"], "Nanpu spiral")):
    q = P(p)
    d.rectangle([q[0] - 5, q[1] - 5, q[0] + 5, q[1] + 5], fill=(255, 255, 255))
    d.text((q[0] + 7, q[1] + 2), label, fill=(255, 255, 255), font=small)
o = P((0, 0))
d.ellipse([o[0] - 7, o[1] - 7, o[0] + 7, o[1] + 7], outline=(255, 0, 0), width=3)
d.text((o[0] + 9, o[1] + 4), "ORIGIN (0,0) Bund/Yan'an", fill=(255, 80, 80), font=font)
d.text((PAD, 8), "SKYRUSH game map v1 - north up, X east, Z south, grid 500 m; orange = elevated", fill=(230, 230, 230), font=font)
img.save(sys.argv[2])
print(sys.argv[2], img.size)
