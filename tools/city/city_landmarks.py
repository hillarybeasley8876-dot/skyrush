"""city_landmarks — the landmark anchors of the map (dossier §10.2/§5.3).

Each anchor becomes a `plaza` block (the building lot is left empty for the
landmarks unit) and a `landmark` POI.  The height of a landmark block is its
real height, so the sky-lane clearance check sees the towers.
"""
import math

import citylib

# id, x, z, footprint (w, d), district, label, height (m)
LANDMARKS = [
    ("dragon_pillar", -1299.0, 687.0, (60.0, 60.0), "D4", "龙柱", 29.4),
    # the Bund row: the centre sits behind the facade (dossier 5.3), so the
    # plaza does not reach into the road
    ("hsbc_building", -168.0, -268.0, (76.0, 70.0), "D1", "汇丰银行大楼", 50.0),
    ("customs_house", -158.0, -328.0, (42.0, 60.0), "D1", "江海关大楼", 79.2),
    ("peace_hotel_n", -178.0, -561.0, (42.0, 90.0), "D1", "和平饭店", 77.0),
    ("bank_of_china_bund", -166.0, -600.0, (24.0, 60.0), "D1", "中国银行大楼", 77.0),
    ("broadway_mansions", -176.0, -1051.0, (60.0, 40.0), "D1", "上海大厦", 90.0),
    ("waibaidu_bridge", -140.0, -966.0, (40.0, 110.0), "D1", "外白渡桥", 0.0),
    ("oriental_pearl", 637.5, -634.9, (100.0, 100.0), "D7", "东方明珠", 468.0),
    ("pearl_ring", 790.0, -520.0, (90.0, 90.0), "D7", "明珠环", 6.5),
    ("jin_mao", 1133.0, -199.8, (58.0, 58.0), "D7", "金茂大厦", 420.5),
    ("swfc", 1262.2, -136.0, (60.0, 60.0), "D7", "环球金融中心", 492.0),
    ("shanghai_tower", 1122.8, -42.5, (86.0, 86.0), "D7", "上海中心", 632.0),
    ("nanpu_tower_w", 1139.4, 1338.2, (50.0, 50.0), "D6", "南浦大桥西塔", 147.0),
    ("nanpu_tower_e", 1520.6, 1521.8, (50.0, 50.0), "D7", "南浦大桥东塔", 147.0),
]

# parks: id, x, z, (w, d), district
PARKS = [
    ("peoples_square", -900.0, -350.0, (300.0, 300.0), "D3"),
    ("shikumen_park", -780.0, 640.0, (220.0, 260.0), "D4"),
    ("lujiazui_green", 900.0, -560.0, (180.0, 220.0), "D7"),
]


def rect_block(bid, district, x, z, w, d, style, height, seed, notes=""):
    """A rectangular block polygon (counter-clockwise seen from above)."""
    x0, z0 = x - w * 0.5, z - d * 0.5
    x1, z1 = x + w * 0.5, z + d * 0.5
    poly = [[round(x0, 1), round(z0, 1)], [round(x1, 1), round(z0, 1)],
            [round(x1, 1), round(z1, 1)], [round(x0, 1), round(z1, 1)]]
    if citylib.polygon_area(poly) > 0:
        poly = list(reversed(poly))
    out = {
        "id": bid,
        "district": district,
        "polygon": poly,
        "style": style,
        "height_m": [round(height[0], 1), round(height[1], 1)],
        "setback": 3.0,
        "seed": seed,
    }
    if notes:
        out["notes"] = notes
    return out


def placed_landmarks(roads=None):
    """The landmark anchors, moved clear of the roads where they need it.

    A landmark lot holds the whole footprint of the building, so the
    anchor moves a little instead of the lot being clipped.
    """
    import citylib
    index = None
    widths = {}
    if roads:
        index = citylib.PolyIndex()
        for road in roads:
            if road.kind != "surface":
                continue
            index.add(road.id, [(p[0], p[2]) for p in road.points])
            widths[road.id] = citylib.road_width(road) * 0.5
    out = []
    for lid, x, z, (w, d), district, label, height in LANDMARKS:
        if index is not None:
            x, z = _clear_of_roads(index, widths, x, z, w, d)
        out.append((lid, x, z, (w, d), district, label, height))
    return out


def _clear_of_roads(index, widths, x, z, w, d, tries=24):
    """Move an anchor until its lot stands clear of the roads."""
    half = math.hypot(w, d) * 0.5
    for _ in range(tries):
        dist, name, idx, point = index.nearest((x, z), 400.0)
        if name is None:
            return x, z
        need = half + widths.get(name, 8.0) + 2.0
        if dist >= need:
            return x, z
        # move away from the road
        dx, dz = x - point[0], z - point[1]
        length = math.hypot(dx, dz) or 1.0
        step = need - dist + 1.0
        x += dx / length * step
        z += dz / length * step
    return x, z


def landmark_blocks(roads=None):
    """The plaza blocks of the landmarks, with their real heights."""
    out = []
    for lid, x, z, (w, d), district, label, height in placed_landmarks(roads):
        out.append(rect_block("plaza_%s" % lid, district, x, z, w, d, "plaza",
                              (height, height), 1,
                              "landmark:%s" % lid))
    return out


def park_blocks(roads=None):
    """The park blocks of the dossier (People's Square and the shikumen park)."""
    import citylib
    index = None
    widths = {}
    if roads:
        index = citylib.PolyIndex()
        for road in roads:
            if road.kind != "surface":
                continue
            index.add(road.id, [(p[0], p[2]) for p in road.points])
            widths[road.id] = citylib.road_width(road) * 0.5
    out = []
    for pid, x, z, (w, d), district in PARKS:
        if index is not None:
            x, z = _clear_of_roads(index, widths, x, z, w, d)
        out.append(rect_block("park_%s" % pid, district, x, z, w, d, "park",
                              (0.0, 0.0), 2, "park:%s" % pid))
    return out
