"""Waibaidu Bridge (外白渡桥) - the riveted through-truss at the Bund.

Modelled in a bridge-local frame: origin at the map anchor, +Y along the deck,
Y up. Dossier 5.5: 2 spans of 52.18 m, a curved top chord 9.144 m at mid-span,
box-section chords with lacing and rivets, a full-width granite pier, timber
sidewalks and a warm LED line along the chords. The carriageway (11.2 m clear)
comes from the roads unit.
"""
import math
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender/landmarks"))
import lmenv  # noqa: E402
from lmenv import bpy, common, geo, lmlib, lmmat, uv  # noqa: E402

# ---------------------------------------------------------------- Waibaidu (dossier 5.5)
WB_SPAN = 52.18
WB_LEN = 104.39
WB_PANEL = 4.744
WB_TRUSS_X = 6.096          # truss centre spacing 12.192 m
WB_CHORD_X = 0.3            # half thickness of a chord
WB_CHORD_Y = 0.25           # half height of a chord
WB_MEMBER = 0.13            # lacing member radius
WB_H_MID = 9.144            # truss height at mid-span
WB_H_END = 5.0              # truss height at the ends
WB_DECK_W = 11.2            # carriageway clear width
WB_SIDEWALK = 3.0
WB_WALK_X = 6.6             # inner edge of the sidewalk (outboard of the truss)
WB_PIER_TOP = -1.2          # the pier top sits below the bottom chord
WB_PIER_W = 19.0            # full width across both trusses and sidewalks



WB_SPAN = 52.18
WB_LEN = 104.39
WB_PANEL = 4.744
WB_TRUSS_X = 6.096          # truss centre spacing 12.192 m
WB_CHORD_X = 0.3            # half thickness of a chord
WB_CHORD_Y = 0.25           # half height of a chord
WB_MEMBER = 0.13            # lacing member radius
WB_H_MID = 9.144            # truss height at mid-span
WB_H_END = 5.0              # truss height at the ends
WB_DECK_W = 11.2            # carriageway clear width
WB_SIDEWALK = 3.0
WB_WALK_X = 6.6             # inner edge of the sidewalk (outboard of the truss)
WB_PIER_TOP = -1.2          # the pier top sits below the bottom chord
WB_PIER_W = 19.0            # full width across both trusses and sidewalks


def wb_top_chord(u):
    """Height of the curved top chord above the deck (u = 0 at the centre pier)."""
    return WB_H_END + (WB_H_MID - WB_H_END) * math.sin(math.pi * abs(u) / WB_SPAN)


def build_waibaidu(col, steel, granite, timber, led_mat, col_mat):
    """Riveted through-truss: 2 spans of 52.18 m, curved top chord, timber walks."""
    bm = lmlib.merge()
    spans = []
    for sgn in (-1.0, 1.0):
        span = []
        for i in range(12):
            u = -WB_SPAN + WB_PANEL * i
            span.append((sgn * u, wb_top_chord(u)))
        spans.append(span)
    for span in spans:
        for sgn in (-1.0, 1.0):
            x = sgn * WB_TRUSS_X
            # top and bottom chords: rectangular box sections
            for i in range(11):
                a, b = span[i], span[i + 1]
                bm = lmlib.merge(bm, lmlib.strut((x, a[0], a[1]), (x, b[0], b[1]),
                                                 WB_CHORD_X * 2, WB_CHORD_Y * 2))
                bm = lmlib.merge(bm, lmlib.strut((x, a[0], 0.0), (x, b[0], 0.0),
                                                 WB_CHORD_X * 2, WB_CHORD_Y * 2))
            # laced verticals and diagonals
            for i in range(12):
                p = span[i]
                bm = lmlib.merge(bm, lmlib.strut((x, p[0], 0.0), (x, p[0], p[1]), 0.3, 0.3))
                if i < 11:
                    q = span[i + 1]
                    bm = lmlib.merge(bm, lmlib.strut((x, p[0], p[1]), (x, q[0], 0.0), 0.22, 0.22))
                    # lacing bars on the vertical
                    for k in range(3):
                        t0 = k / 3.0
                        t1 = (k + 1) / 3.0
                        bm = lmlib.merge(bm, lmlib.strut(
                            (x, p[0], p[1] * t0), (x, p[0], p[1] * t1), 0.16, 0.16))
            # gusset plates at every node
            for p in span:
                bm = lmlib.merge(bm, lmlib.box((x, p[0], p[1] - 0.3), (0.5, 0.9, 0.9)))
    tr = lmlib.obj("Waibaidu_Truss", bm, col, steel)
    uv.box_uv(tr)
    # overhead X-bracing and portal frames between the two trusses
    brace = lmlib.merge()
    for span in spans:
        for i in range(0, 11, 2):
            a, b = span[i], span[i + 1]
            brace = lmlib.merge(brace, lmlib.strut(
                (-WB_TRUSS_X, a[0], a[1] - 0.4), (WB_TRUSS_X, b[0], b[1] - 0.4), 0.3, 0.3))
            brace = lmlib.merge(brace, lmlib.strut(
                (WB_TRUSS_X, a[0], a[1] - 0.4), (-WB_TRUSS_X, b[0], b[1] - 0.4), 0.3, 0.3))
        for p in span:
            brace = lmlib.merge(brace, lmlib.strut(
                (-WB_TRUSS_X, p[0], p[1] - 0.4), (WB_TRUSS_X, p[0], p[1] - 0.4), 0.35, 0.35))
    bo = lmlib.obj("Waibaidu_Overhead", brace, col, steel)
    uv.box_uv(bo)
    # granite pier across the full width, its top below the bottom chord
    pier = lmlib.box((0.0, 0.0, WB_PIER_TOP - 2.6), (WB_PIER_W, 3.6, 5.2))
    po = lmlib.obj("Waibaidu_Pier", pier, col, granite)
    uv.box_uv(po)
    bearings = lmlib.merge()
    for sgn in (-1.0, 1.0):
        bearings = lmlib.merge(bearings, lmlib.box(
            (sgn * WB_TRUSS_X, 0.0, WB_PIER_TOP + 0.35), (1.6, 2.2, 0.7)))
    lmlib.obj("Waibaidu_Bearings", bearings, col, steel)
    # timber sidewalks outboard of the trusses + railings
    walk = lmlib.merge()
    for sgn in (-1.0, 1.0):
        x0 = sgn * WB_WALK_X
        walk = lmlib.merge(walk, lmlib.box(
            (x0 + sgn * WB_SIDEWALK * 0.5, 0.0, -0.12), (WB_SIDEWALK, WB_LEN, 0.24)))
        for k in range(int(WB_LEN / 2.0) + 1):
            y = -WB_LEN * 0.5 + k * 2.0
            walk = lmlib.merge(walk, lmlib.box(
                (x0 + sgn * (WB_SIDEWALK - 0.1), y, 0.55), (0.08, 0.08, 1.2)))
        walk = lmlib.merge(walk, lmlib.box(
            (x0 + sgn * (WB_SIDEWALK - 0.1), 0.0, 1.15), (0.1, WB_LEN, 0.1)))
    wo = lmlib.obj("Waibaidu_Sidewalk", walk, col, timber)
    uv.box_uv(wo)
    # warm LED lines along the top and bottom chords
    led = lmlib.merge()
    for span in spans:
        for sgn in (-1.0, 1.0):
            x = sgn * (WB_TRUSS_X + 0.45)
            for i in range(11):
                a, b = span[i], span[i + 1]
                led = lmlib.merge(led, lmlib.tube((x, a[0], a[1]), (x, b[0], b[1]), 0.10, 0.10, 5))
            led = lmlib.merge(led, lmlib.tube((x, span[0][0], 0.35), (x, span[-1][0], 0.35),
                                              0.10, 0.10, 5))
    lo = lmlib.obj("LED_Waibaidu", led, col, led_mat)
    uv.box_uv(lo)
    # deck collider (the carriageway surface comes from the roads unit)
    colmesh = lmlib.box((0.0, 0.0, -0.15), (WB_DECK_W, WB_LEN, 0.3))
    cc = lmlib.obj("Waibaidu_ColDeck-colonly", colmesh, col, col_mat)
    uv.box_uv(cc)
    # collision walls for the two trusses and the portal frames
    walls = lmlib.merge()
    for sgn in (-1.0, 1.0):
        walls = lmlib.merge(walls, lmlib.box(
            (sgn * WB_TRUSS_X, 0.0, WB_H_MID * 0.5), (0.6, WB_LEN, WB_H_MID * 0.5)))
    for p in spans[0] + spans[1]:
        walls = lmlib.merge(walls, lmlib.box(
            (0.0, p[0], p[1] * 0.5), (WB_TRUSS_X + 0.6, 0.6, p[1] * 0.5)))
    wc = lmlib.obj("Waibaidu_ColTruss-colonly", walls, col, col_mat)
    uv.box_uv(wc)
    # 8 floods: 4 per truss, on the sidewalks, aimed at the steel
    for sgn, tag in ((-1.0, "W"), (1.0, "E")):
        for k in range(4):
            y = -WB_LEN * 0.5 + WB_LEN * (k + 0.5) / 4.0
            lmlib.empty("Flood_Waibaidu_%s%d" % (tag, k + 1),
                        (sgn * (WB_WALK_X + WB_SIDEWALK * 0.5), y, 1.3),
                        direction=(-sgn * 0.55, 0.0, 0.84), col=col, size=1.5)
