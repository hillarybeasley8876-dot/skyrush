"""Cross-sections for the SKYRUSH road kit.

Numbers come from ref/shanghai/SHANGHAI_DOSSIER.md §2.2 (standard elevated deck)
and GB 5768.3 (markings). Offsets are metres, positive = right of the travel
direction. `across` templates feed meshkit.strip; the colour channels drive the
road shader (R = polished wheel paths, G = gutters that collect water).
"""
PARAPET_W = 0.50      # parapet base width
PARAPET_H = 1.00      # parapet height above the deck
PLANTER_W = 0.26      # white planter trough, outer top edge of the parapet
PLANTER_H = 0.25
KERB_W = 0.30
KERB_H = 0.15
INNER_STRIP = 0.50    # asphalt between the lane block and the median barrier
DRIP = 0.25           # outer lip of the deck slab
GIRDER_DEPTH = 2.00
FLANGE = 0.60         # bottom flange as a fraction of the deck width
MEDIAN_H = 0.85       # median barrier height
PARAPET_BOTTOM = -0.15  # the visible parapet reaches this far below the deck
CAR_LIFT = 0.30      # the car rides this high above its lane
CAR_ROOF = 1.30      # and its roof is this high above its lane
LOW_PARAPET_H = 0.45   # the height of a parapet that a car passes under
LOW_PARAPET_W = 0.28   # and its width at the base
WHEEL_HALF = 0.45     # half width of a polished wheel-path band
WHEEL_POS = 0.25      # wheel path at 1/4 and 3/4 of the lane
EPS = 0.02            # colour transition width (keeps quads non-degenerate)
RAMP_MIN_HALF = 4.00  # 1-lane ramp deck half width (8 m deck)


def layout(road):
    """Every cross-section offset of a road, in metres."""
    oneway = road.lanes_back == 0
    med_half = 0.0 if oneway else road.median / 2.0
    inner = INNER_STRIP if (road.elevated and road.median > 0 and not oneway) else 0.0
    base = med_half + inner
    if oneway:
        base = -road.lanes_fwd * road.lane_width / 2.0
    lanes = {}
    outer = {}
    for side, n, sign in (("fwd", road.lanes_fwd, 1.0), ("back", road.lanes_back, -1.0)):
        ivs = []
        for i in range(n):
            a = base + i * road.lane_width
            b = a + road.lane_width
            ivs.append((min(sign * a, sign * b), max(sign * a, sign * b)))
        lanes[side] = ivs
        # a one-way road has no back carriageway: its left edge is the carriageway edge
        outer[side] = base if (n == 0 and side == "back") else sign * (base + n * road.lane_width)
    asphalt_fwd = outer["fwd"] + road.shoulder
    asphalt_back = outer["back"] - road.shoulder
    lay = {
        "oneway": oneway,
        "median_half": med_half,
        "inner_strip": inner,
        "lanes": lanes,
        "lane_outer": outer,
        "asphalt_fwd": asphalt_fwd,
        "asphalt_back": asphalt_back,
        "asphalt_inner_fwd": med_half,
        "asphalt_inner_back": -med_half,
        "lane_base": base,
    }
    if road.elevated:
        lay["edge_w"] = PARAPET_W
        lay["half_width"] = asphalt_fwd + PARAPET_W + DRIP
        lay["structure"] = "elevated"
    else:
        lay["edge_w"] = KERB_W
        lay["half_width"] = asphalt_fwd + KERB_W + road.sidewalk
        lay["structure"] = "surface"
    if road.elevated and road.kind == "ramp":
        lay["half_width"] = max(lay["half_width"], RAMP_MIN_HALF)
    lay["deck_half"] = lay["half_width"]
    lay["asphalt_half"] = max(asphalt_fwd, -asphalt_back)
    return lay


def _lane_band(tmpl, a0, a1):
    """Append one lane's cross-section entries (wheel-path colour bands) to `tmpl`."""
    lw = a1 - a0
    w1 = a0 + WHEEL_POS * lw
    w2 = a0 + (1.0 - WHEEL_POS) * lw
    for x, r in ((a0, 1.0), (w1 - WHEEL_HALF, 0.0), (w1 + WHEEL_HALF, 0.0),
                 (0.5 * (w1 + w2), 1.0), (w2 - WHEEL_HALF, 0.0), (w2 + WHEEL_HALF, 0.0),
                 (a1, 1.0)):
        tmpl.append((x, r, 1.0, 1.0))


def _gutter(tmpl, x0, x1):
    """Append a gutter band (G = 0) between x0 and x1."""
    tmpl.append((x0, 1.0, 1.0, 1.0))
    tmpl.append((x1 - EPS, 1.0, 0.0, 1.0))
    tmpl.append((x1, 1.0, 0.0, 1.0))


def carriageway_template(road, lay, side):
    """Asphalt template for one carriageway, [(across, r, g, b), ...] in increasing x.

    'fwd' runs from the median outwards, 'back' from the outer edge inwards.
    """
    tmpl = []
    if side == "fwd":
        x = lay["asphalt_inner_fwd"]
        if lay["inner_strip"] > 0.0:
            tmpl.append((x, 1.0, 1.0, 1.0))
            tmpl.append((lay["lane_base"], 1.0, 1.0, 1.0))
        for a0, a1 in lay["lanes"]["fwd"]:
            _lane_band(tmpl, a0, a1)
        x = lay["asphalt_fwd"] - road.shoulder
        tmpl.append((x, 1.0, 1.0, 1.0))
        tmpl.append((lay["asphalt_fwd"] - EPS, 1.0, 0.0, 1.0))
        tmpl.append((lay["asphalt_fwd"], 1.0, 0.0, 1.0))
    else:
        x = lay["asphalt_back"]
        tmpl.append((x, 1.0, 1.0, 1.0))
        tmpl.append((x + road.shoulder - EPS, 1.0, 0.0, 1.0))
        tmpl.append((x + road.shoulder, 1.0, 0.0, 1.0))
        for a0, a1 in reversed(lay["lanes"]["back"]):
            _lane_band(tmpl, a0, a1)
        if lay["inner_strip"] > 0.0:
            tmpl.append((-lay["lane_base"], 1.0, 1.0, 1.0))
            tmpl.append((lay["asphalt_inner_back"], 1.0, 1.0, 1.0))
    return tmpl


def kerb_profile():
    """Granite kerb, 0.30 wide x 0.15 above the road (x = 0 at the inner face).

    Open profile: the bottom and the inner face are buried in the road, so they
    are not built (the profile is walked so the visible faces point outwards).
    """
    return [(0.0, KERB_H), (KERB_W, KERB_H), (KERB_W, -0.25)]


def sidewalk_profile(width):
    """Sidewalk slab: top at the kerb height, bottom buried (open profile)."""
    return [(0.0, KERB_H), (width, KERB_H), (width, -0.35)]


def median_island_profile(half):
    """Raised median island on a surface road (granite kerb, planted top)."""
    return [(-half, -0.30), (half, -0.30), (half, KERB_H), (-half, KERB_H)]


def median_barrier_profile(half):
    """New-Jersey style median barrier on an elevated deck."""
    return [(-half, -0.15), (half, -0.15), (half, 0.33), (half * 0.26, MEDIAN_H),
            (-half * 0.26, MEDIAN_H), (-half, 0.33)]


def parapet_profile():
    """Elevated parapet: 0.50 wide at the base, 0.28 at the top, 1.00 high.

    Open profile: the base is buried in the deck slab.
    """
    return [(0.0, PARAPET_H - 0.14), (0.28, PARAPET_H), (PARAPET_W, PARAPET_H),
            (PARAPET_W, -0.15)]


def low_parapet_profile():
    """The parapet where a lane of the city runs under the edge of the deck.

    A car is 1.30 m tall above its lane, and the lane that runs under the edge
    of a deck is 0.6 m to 1.45 m below it: the full parapet would stand in the
    traffic of that lane.  The parapet gets lower there: it still fences the
    deck, and the car of the lane under the edge passes it.

    Open profile: the base is buried in the deck slab.
    """
    return [(0.0, LOW_PARAPET_H - 0.05), (0.14, LOW_PARAPET_H),
            (LOW_PARAPET_W, LOW_PARAPET_H), (LOW_PARAPET_W, PARAPET_BOTTOM)]
