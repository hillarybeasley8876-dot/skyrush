"""The asphalt fill of a junction and its collision.

The fill is a fan over the arms' kerb lines: every ring point carries the
height of the road it belongs to, so the fill meets the roads without a step.
Every piece is clipped to the tile it lies on, so a junction that straddles a
tile border does not leave half of its asphalt in the wrong tile.
"""
import math

import bmesh

from city.roads import levels, meshkit, tiles

ASPHALT = "SH_wet_asphalt"
COLLIDER_NAME = "surface-colonly"
FILL_DROP = 0.01        # the junction fill sits 1 cm under the carriageway
COLLIDER_MARGIN = 2.5   # the junction's collision is wider than its asphalt


def build_fill(fill, tileset):
    """The asphalt polygon of the junction and its collision (the same polygon)."""
    if fill is None:
        return
    hub, ring = fill
    for i in range(len(ring)):
        _add_piece(tileset, hub, ring[i], ring[(i + 1) % len(ring)],
                   ASPHALT, None, FILL_DROP)
    # the collision is a little wider than the asphalt: a movement that cuts
    # the corner must not drop through the seam
    wide = levels.offset_ring(ring, COLLIDER_MARGIN)
    for i in range(len(wide)):
        _add_piece(tileset, hub, wide[i], wide[(i + 1) % len(wide)],
                   None, COLLIDER_NAME, FILL_DROP + 0.015)


def _add_piece(tileset, hub, a, b, material, named, drop):
    """Add one fan triangle of a junction's fill, clipped to its tiles."""
    tri = ((hub.x, hub.y), (a.x, a.y), (b.x, b.y))
    xs = [p[0] for p in tri]
    ys = [p[1] for p in tri]
    tx0 = int(math.floor(min(xs) / tiles.TILE))
    tx1 = int(math.floor(max(xs) / tiles.TILE))
    tz0 = int(math.floor(-max(ys) / tiles.TILE))
    tz1 = int(math.floor(-min(ys) / tiles.TILE))
    for tx in range(tx0, tx1 + 1):
        for tz in range(tz0, tz1 + 1):
            piece = meshkit.clip_rect(tri, tx * tiles.TILE, (tx + 1) * tiles.TILE,
                                      -(tz + 1) * tiles.TILE, -tz * tiles.TILE)
            if len(piece) < 3:
                continue
            for (px, py) in piece:
                if not (tx * tiles.TILE - 0.5 <= px <= (tx + 1) * tiles.TILE + 0.5
                        and -(tz + 1) * tiles.TILE - 0.5 <= py <= -tz * tiles.TILE + 0.5):
                    print("CLIP LEAK tile %d_%d piece %.1f %.1f" % (tx, tz, px, py))
            bm = bmesh.new()
            for (px, py) in piece:
                u, v = meshkit.barycentric(tri, (px, py))
                z = hub.z + (a.z - hub.z) * u + (b.z - hub.z) * v
                bm.verts.new((px, py, z - drop))
            bm.faces.new(bm.verts)
            meshkit.face_up(bm)
            builder = tileset.builder((tx, tz))
            if material is not None:
                builder.add(material, bm)
            else:
                builder.add_named(named, bm, surface="asphalt")
