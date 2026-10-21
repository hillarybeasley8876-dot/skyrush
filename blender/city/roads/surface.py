"""Surface streets: asphalt carriageway, granite kerbs, sidewalks, median islands.

The carriageway carries the vertex colours the road shader needs (R = polished
wheel paths, G = gutters) and every marking-free surface stays a separate
material so the tile exports as a handful of draw calls.
"""
import bmesh

from lib import geo

from city.roads import meshkit, profiles

ASPHALT = "SH_wet_asphalt"
KERB = "SH_kerb"
SIDEWALK = "SH_sidewalk"
TACTILE = "Road_Tactile_Strip"
SOIL = "Road_Planter_Soil"


def _profile_at(prof, offset, mirror=False):
    """Shift a local (x, z) profile to `offset` across the road; mirrored for the left side.

    The mirrored profile is also reversed so the open profiles keep their winding.
    """
    if mirror:
        return [(offset - x, z) for (x, z) in reversed(prof)]
    return [(offset + x, z) for (x, z) in prof]


def build_asphalt(road, idx, builder, lay):
    """Asphalt for both carriageways of a surface road."""
    path = [road.path[i] for i in idx]
    frames = [road.frames[i] for i in idx]
    for side in ("back", "fwd"):
        tmpl = profiles.carriageway_template(road, lay, side)
        bm = bmesh.new()
        meshkit.strip(bm, path, frames, tmpl)
        builder.add(ASPHALT, bm)


def build_edges(road, idx, builder, lay):
    """Kerbs, sidewalks and the tactile (guide-for-blind) strip on both sides."""
    path = [road.path[i] for i in idx]
    for side in ("fwd", "back"):
        mirror = side == "back"
        edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
        km = meshkit.sweep(bmesh.new(), _profile_at(profiles.kerb_profile(), edge, mirror), path,
                            closed_profile=False)
        builder.add(KERB, km)
        if road.sidewalk > 0.0:
            sw = edge + profiles.KERB_W if not mirror else edge - profiles.KERB_W
            prof = _profile_at(profiles.sidewalk_profile(road.sidewalk), sw, mirror)
            builder.add(SIDEWALK, meshkit.sweep(bmesh.new(), prof, path, closed_profile=False))
            x0 = sw - 0.72 if mirror else sw + 0.12
            x1 = sw - 0.12 if mirror else sw + 0.72
            tp = [(x0, profiles.KERB_H + 0.006), (x1, profiles.KERB_H + 0.006)]
            builder.add(TACTILE, meshkit.sweep(bmesh.new(), tp, path, closed_profile=False))


def build_median(road, idx, builder, lay):
    """Raised planted median island on a surface road."""
    if lay["median_half"] <= 0.0 or road.median <= 0.0:
        return
    path = [road.path[i] for i in idx]
    prof = profiles.median_island_profile(lay["median_half"])
    builder.add(KERB, meshkit.sweep(bmesh.new(), prof, path))
    soil = [(-lay["median_half"] + 0.25, profiles.KERB_H - 0.01),
            (lay["median_half"] - 0.25, profiles.KERB_H - 0.01)]
    builder.add(SOIL, meshkit.sweep(bmesh.new(), soil, path, closed_profile=False))


def build(road, idx, builder, lay=None):
    """All surface-road geometry for the given path samples."""
    lay = lay or profiles.layout(road)
    build_asphalt(road, idx, builder, lay)
    build_edges(road, idx, builder, lay)
    build_median(road, idx, builder, lay)
