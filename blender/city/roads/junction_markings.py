"""The markings and the kerb returns of a junction.

The kerb return is the arc between two arms' kerb lines: it is the only place
where a junction has a kerb, and it stands 0.15 m above the road. The crossing
is a zebra with 0.45 m bars and 0.60 m gaps, and the stop line stops the
traffic 1.5 m before it (GB 5768.3).
"""
import bmesh
from mathutils import Vector

from city.roads import markings, profiles

KERB = "SH_kerb"
SIDEWALK = "SH_sidewalk"
WHITE = "SH_road_marking_white"

ZEBRA_BAR = 0.45
ZEBRA_GAP = 0.60
ZEBRA_MAIN = 5.0        # the crossing of a main road
ZEBRA_MINOR = 4.0       # the crossing of a minor road
STOP_WIDTH = 0.30
STOP_GAP = 1.5          # the distance from the stop line to the crossing


def build_kerb(arcs, tileset):
    """The kerb return band and a short sidewalk along every corner arc.

    Every piece goes into the tile it lies on: a corner can reach over the
    border of the tile of the junction.
    """
    kerb = [(0.0, -0.25), (profiles.KERB_W, -0.25), (profiles.KERB_W, profiles.KERB_H),
            (0.0, profiles.KERB_H)]
    sw = [(profiles.KERB_W, profiles.KERB_H), (profiles.KERB_W + 3.0, profiles.KERB_H),
          (profiles.KERB_W + 3.0, -0.35), (profiles.KERB_W, -0.35)]
    for arc in arcs:
        if len(arc) < 2:
            continue
        for i in range(len(arc) - 1):
            piece = arc[i:i + 2]
            mid = (piece[0] + piece[1]) * 0.5
            tileset.builder_at(mid).add(KERB, meshkit_sweep(kerb, piece))
            tileset.builder_at(mid).add(SIDEWALK, meshkit_sweep(sw, piece))


def meshkit_sweep(profile, path):
    """Sweep a profile along a path (the kerb return of a junction)."""
    from city.roads import meshkit
    return meshkit.sweep(bmesh.new(), profile, path)


def add_quad(bm, p0, p1, across, along):
    """A flat quad from p0 to p1 extruded by `across` and `along`."""
    a = bm.verts.new(p0)
    b = bm.verts.new(p1)
    c = bm.verts.new(p1 + across)
    d = bm.verts.new(p0 + across)
    bm.faces.new((a, b, c, d))
    return bm


def build_crossings(arms, centre, tileset, z=0.0, reach=0.0):
    """The zebra crossing and the stop line of every arm."""
    for a in arms:
        road = a["road"]
        main = road.lanes_fwd + road.lanes_back >= 4
        length = ZEBRA_MAIN if main else ZEBRA_MINOR
        pos = centre + a["dir"] * (a["half"] + reach + 3.0) + Vector((0.0, 0.0, z))
        t = a["dir"]
        r = Vector((-t.y, t.x, 0.0))
        x = -a["half"] + 0.4
        while x < a["half"] - 0.5:
            for s in (-length * 0.5, length * 0.5):
                p0 = pos + r * x + t * s
                bm = bmesh.new()
                add_quad(bm, p0, p0 + r * ZEBRA_BAR, r * ZEBRA_BAR, t * length)
                tileset.builder_at(p0 + r * (ZEBRA_BAR * 0.5)).add(WHITE, bm)
            x += ZEBRA_BAR + ZEBRA_GAP
        # the stop line stops the traffic 1.5 m before the crossing
        p0 = pos - t * (length * 0.5 + STOP_GAP)
        bm = bmesh.new()
        add_quad(bm, p0, p0 + r * (a["half"] * 2.0), r * (a["half"] * 2.0), t * STOP_WIDTH)
        tileset.builder_at(p0).add(WHITE, bm)


def build_arrows(arms, centre, tileset, z=0.0):
    """GB guide arrows on the approach lanes of every arm."""
    for a in arms:
        road = a["road"]
        lay = profiles.layout(road)
        tangent = road.frames[a["index"]][0]
        right = road.frames[a["index"]][1]
        side = "fwd" if a["dir"].dot(tangent) > 0.5 else "back"
        lanes = lay["lanes"][side]
        for i, (a0, a1) in enumerate(lanes):
            across = (a0 + a1) * 0.5
            origin = (road.path[a["index"]] - a["dir"] * 9.0
                      + right * across * (1.0 if side == "fwd" else -1.0))
            kind = "right" if i == len(lanes) - 1 else "straight"
            markings.build_arrow(tileset, origin, right, a["dir"], kind)
