"""The planter row of an elevated deck.

Dossier §2.4: a continuous row of white pots on both parapets, with a 2 cm
gap, ten magenta bougainvillea and five green privet in every fifteen. The
plants stand on the soil of the pot and reach over the outer face.

The pots are grouped in 64 m chunks (the world unit fades them out at 90 m)
and the planted strip on the parapet takes over from 80 m.
"""
import bmesh
import math
import random

from city.roads import meshkit, profiles, tiles

PLANTER = "Road_Planter_White"
PLANTS = "Road_Planter_Row"
BOUGAINVILLEA = "Road_Foliage_Bougainvillea"
PRIVET = "Road_Foliage_Privet"

PLANTER_PERIOD = 9.3     # 15 pots of 0.62 m: 10 magenta + 5 privet
POT_LENGTH = 0.60       # one planter pot
POT_GAP = 0.02          # the gap between two pots
POT_DEPTH = 0.25
POT_HEIGHT = 0.25
POT_CENTRE = 0.42       # the pot's centre, measured from the asphalt's edge
POT_PITCH = POT_LENGTH + POT_GAP
CARD_WIDTH = 0.46
CARD_HEIGHT_MIN = 0.45
CARD_HEIGHT_MAX = 0.60
CARD_OVERHANG = 0.20    # how far the plants reach over the outer face
CARD_ROOT = 0.03        # the plants start just below the soil
RHYTHM = 15             # 10 magenta bougainvillea, then 5 green privet
PRIVET_RUN = 5
POT_JITTER = 0.10       # the plants are not all the same size
POT_YAW = 15.0          # ... and not all square to the parapet
CHUNK = 64.0            # the pots of one LOD chunk
LOD_END = 90.0          # the pots are drawn up to this distance
LOD_BEGIN = 80.0        # the planted strip takes over from this distance
STRIP_WIDTH = 0.22      # the width of the planted band on the parapet top


def _pot_box(bm, centre, right, tangent, up, length, depth, height):
    """A planter pot: the top, the inner face, the outer face and the two ends.

    The bottom is left out (the parapet hides it): a pot is 10 triangles.
    """
    hx, hy, hz = length * 0.5, depth * 0.5, height * 0.5
    v = {}
    for ai, a in enumerate((-hx, hx)):
        for ri, r in enumerate((-hy, hy)):
            for ui, u in enumerate((-hz, hz)):
                v[(ai, ri, ui)] = bm.verts.new(centre + tangent * a + right * r + up * u)
    bm.faces.new((v[(0, 0, 0)], v[(1, 0, 0)], v[(1, 0, 1)], v[(0, 0, 1)]))   # inner face
    bm.faces.new((v[(0, 0, 1)], v[(0, 1, 1)], v[(1, 1, 1)], v[(1, 0, 1)]))   # top
    bm.faces.new((v[(0, 1, 0)], v[(1, 1, 0)], v[(1, 1, 1)], v[(0, 1, 1)]))   # outer face
    bm.faces.new((v[(0, 0, 0)], v[(0, 1, 0)], v[(0, 1, 1)], v[(0, 0, 1)]))   # end
    bm.faces.new((v[(1, 0, 0)], v[(1, 0, 1)], v[(1, 1, 1)], v[(1, 1, 0)]))   # end
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _plant_card(bm, centre, right, tangent, up, width, height, yaw=0.0):
    """One foliage card: a quad with the leaf texture's alpha.

    The card stands on the soil of the pot and leans over the outer face.
    """
    a = centre - tangent * (width * 0.5)
    b = centre + tangent * (width * 0.5)
    v0 = bm.verts.new(a)
    v1 = bm.verts.new(b)
    v2 = bm.verts.new(b + up * height)
    v3 = bm.verts.new(a + up * height)
    face = bm.faces.new((v0, v1, v2, v3))
    uv = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for loop, coord in zip(face.loops, ((0.0, 0.0), (width, 0.0), (width, height), (0.0, height))):
        loop[uv].uv = coord
    return bm


def _seed(text):
    """A stable seed from a road id (Python's hash is not stable between runs)."""
    return sum((i + 1) * ord(c) for i, c in enumerate(text))


def build_pots(road, tileset, lay, gaps=None):
    """The row of white planter pots on both parapets of an elevated road.

    Dossier §2.4: a continuous row of pots with a 2 cm gap, ten magenta
    bougainvillea and five green privet in every fifteen. The pots are grouped
    in 64 m chunks so the world unit can fade them out at 90 m, where the
    planted strip takes over. A ramp that leaves the road takes a break in the
    row: the parapet is not there either. The break is per side: only the side
    the ramp is on gives way.
    """
    if road.style.get("parapet", "planter") != "planter":
        return
    gaps = gaps or {}
    rng = random.Random(_seed(road.id))
    groups = {}
    counts = {"fwd": 0, "back": 0}
    s = 0.0
    while s <= road.length:
        p, t, r, u, _i = road.at(s)
        for side_index, side in enumerate(("fwd", "back")):
            if any(a <= s <= b for (a, b) in gaps.get(side, ())):
                continue
            mirror = side == "back"
            edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
            sign = -1.0 if mirror else 1.0
            centre = p + r * (edge + sign * POT_CENTRE) + u * (profiles.PARAPET_H + POT_HEIGHT * 0.5)
            # every parapet has its own 10 + 5 rhythm
            magenta = (counts[side] % RHYTHM) < (RHYTHM - PRIVET_RUN)
            counts[side] += 1
            chunk = int(s // CHUNK)
            key = (chunk, tiles.tile_of(centre), magenta, side_index)
            group = groups.get(key)
            if group is None:
                group = {"pots": bmesh.new(), "cards": bmesh.new(), "count": 0,
                         "centre": centre.copy()}
                groups[key] = group
            _pot_box(group["pots"], centre, r, t, u, POT_LENGTH, POT_DEPTH, POT_HEIGHT)
            # the plants stand on the soil and reach over the outer face
            height = CARD_HEIGHT_MIN + rng.random() * (CARD_HEIGHT_MAX - CARD_HEIGHT_MIN)
            scale = 1.0 + (rng.random() * 2.0 - 1.0) * POT_JITTER
            yaw = math.radians((rng.random() * 2.0 - 1.0) * POT_YAW)
            root = centre + u * (POT_HEIGHT * 0.5 - CARD_ROOT) + r * (sign * CARD_OVERHANG)
            card_t = (t * math.cos(yaw) + r * sign * math.sin(yaw)).normalized()
            _plant_card(group["cards"], root, r, card_t, u,
                        CARD_WIDTH * scale, height * scale)
            group["count"] += 1
        s += POT_PITCH
    for (chunk, tile_key, magenta, _side), group in groups.items():
        builder = tileset.builder(tile_key)
        props = {"vis_end": LOD_END}
        builder.add_named("pots_%s_%d" % (road.id, chunk), group["pots"],
                          material=PLANTER, surface="concrete", props=props,
                          origin=group["centre"])
        builder.add_named("cards_%s_%d" % (road.id, chunk), group["cards"],
                          material=BOUGAINVILLEA if magenta else PRIVET,
                          surface="concrete", props=props, origin=group["centre"])




def build_strip(road, tileset, lay, gaps=None):
    """The planted strip on the parapet: the far LOD of the planter row.

    From 80 m the row of pots reads as a continuous green and magenta band, so
    the strip carries the same texture and takes over from the pots.
    """
    if road.style.get("parapet", "planter") != "planter":
        return
    gaps = gaps or {}
    for side in ("fwd", "back"):
        mirror = side == "back"
        edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
        inner, outer = 0.28, 0.50
        x0 = edge - outer if mirror else edge + inner
        x1 = edge - inner if mirror else edge + outer
        z = profiles.PARAPET_H + 0.006
        # the band is built tile by tile so a quad never lies in two tiles
        run = []
        for i in range(len(road.path) - 1):
            s = road.dist[i]
            if any(a <= s <= b for (a, b) in gaps.get(side, ())):
                if len(run) > 1:
                    _strip_piece(road, run, tileset, x0, x1, z, mirror)
                run = []
                continue
            key = tiles.tile_of(road.path[i])
            if run and run[-1][0] != key:
                _strip_piece(road, run, tileset, x0, x1, z, mirror)
                run = []
            run.append((key, i))
        if len(run) > 1:
            _strip_piece(road, run, tileset, x0, x1, z, mirror)


def _strip_piece(road, run, tileset, x0, x1, z, mirror):
    """The planted band of one tile of a road."""
    indices = [i for (_k, i) in run]
    path = [road.path[i] for i in indices]
    frames = [road.frames[i] for i in indices]
    template = [(x0, 1.0, 1.0, 1.0), (x1, 1.0, 1.0, 1.0)]

    def uv_fn(i, k):
        return (road.dist[indices[i]], 0.0 if k == 0 else STRIP_WIDTH)

    bm = bmesh.new()
    meshkit.strip(bm, path, frames, template, z=profiles.PARAPET_H + 0.006, uv_fn=uv_fn)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tileset.builder(run[0][0]).add_named("planter_row_%s" % road.id, bm,
                                          material=PLANTS, surface="concrete",
                                          props={"vis_begin": LOD_BEGIN})


