"""Collision meshes: simplified road surfaces and thick closed barriers.

Per tile the generator emits two extra objects whose names end in -colonly, so
Godot turns them into collision-only trimeshes (CONTRACTS §2). Road surfaces are
one-sided (fine, the car is always above them); parapets and barriers are closed
volumes at least 0.5 m thick so nothing tunnels through them at 100 m/s.
"""
import bmesh

from city.roads import meshkit, profiles

SURFACE_NAME = "surface-colonly"
CONCRETE_NAME = "concrete-colonly"
STEEL_NAME = "steel-colonly"
SURFACE_DROP = 0.015     # the collider sits just under the visible asphalt
BARRIER_INSET = 0.04     # inset so the collider never z-fights the render mesh


def build_surface(road, idx, builder, lay):
    """Coarse drivable surface: one strip across the carriageway."""
    path = [road.path[i] for i in idx]
    frames = [road.frames[i] for i in idx]
    if len(path) < 2:
        return
    tmpl = [(lay["asphalt_back"], 1.0, 1.0, 1.0), (lay["asphalt_fwd"], 1.0, 1.0, 1.0)]
    bm = bmesh.new()
    meshkit.strip(bm, path, frames, tmpl, z=-SURFACE_DROP)
    builder.add_named(SURFACE_NAME, bm, surface="asphalt")


def _barrier_box(bm, centre, right, tangent, up, length, across, height):
    """A closed box along the road (a parapet or median barrier collider)."""
    hx = length * 0.5
    hy = across * 0.5
    hz = height * 0.5
    idxs = []
    for a in (-hx, hx):
        for b in (-hy, hy):
            for c in (-hz, hz):
                idxs.append(bm.verts.new(centre + tangent * a + right * b + up * c))
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in faces:
        bm.faces.new([idxs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _inset(prof, amount, drop=0.0):
    """Shrink a closed profile towards its centre and push it down."""
    cx = sum(p[0] for p in prof) / len(prof)
    cz = sum(p[1] for p in prof) / len(prof)
    out = []
    for (x, z) in prof:
        dx, dz = x - cx, z - cz
        scale = 1.0 - amount / max(abs(dx), abs(dz), 0.001)
        out.append((cx + dx * scale, cz + dz * scale + drop))
    return out


def build_barriers(road, idx, builder, lay):
    """Closed colliders for the parapets and the median barrier.

    They follow the real profile, inset by 4 cm so the render mesh always wins the
    depth test, and reach 0.6 m below the deck so a car can never tunnel through.
    """
    if not road.elevated:
        return
    path = [road.path[i] for i in idx]
    parapet = _inset(profiles.parapet_profile(), BARRIER_INSET, drop=-0.60)
    median = _inset(profiles.median_barrier_profile(lay["median_half"]), BARRIER_INSET,
                    drop=-0.60) if lay["median_half"] > 0.0 else None
    for side in ("fwd", "back"):
        mirror = side == "back"
        edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
        prof = [(edge - x if mirror else edge + x, z) for (x, z) in parapet]
        builder.add_named(CONCRETE_NAME, meshkit.sweep(bmesh.new(), prof, path))
        if median is not None:
            mprof = [(edge * 0.0 + x, z) for (x, z) in median]
            builder.add_named(CONCRETE_NAME, meshkit.sweep(bmesh.new(), mprof, path))


def build_median(road, idx, builder, lay):
    """Collider for the raised median island of a surface road."""
    if lay["median_half"] <= 0.0 or road.elevated:
        return
    path = [road.path[i] for i in idx]
    prof = [(-lay["median_half"], -0.30), (lay["median_half"], -0.30),
            (lay["median_half"], profiles.KERB_H), (-lay["median_half"], profiles.KERB_H)]
    builder.add_named(CONCRETE_NAME, meshkit.sweep(bmesh.new(), prof, path))


def build_bridge(road, idx, builder, lay):
    """The steel collider of a cable-stayed bridge: the edge girders.

    A bridge deck has no parapet, so the girder is the wall that keeps a car on
    the deck.
    """
    if not road.bridge:
        return
    path = [road.path[i] for i in idx]
    for side in ("fwd", "back"):
        mirror = side == "back"
        edge = lay["asphalt_fwd"] if side == "fwd" else lay["asphalt_back"]
        out = -1.0 if mirror else 1.0
        prof = [(edge - out * 1.20, -2.50), (edge, -2.50),
                (edge, 0.15), (edge - out * 1.20, 0.15)]
        builder.add_named(STEEL_NAME, meshkit.sweep(bmesh.new(), prof, path,
                                                    closed_profile=True), surface="steel")


def build(road, idx, builder, lay=None, excluded=None):
    """Collision geometry for a road segment.

    The drivable surface is never cut: a car must always find the road under
    its wheels, even where a junction's fill takes over the asphalt (the fill
    sits 1 cm lower, so the road's own surface still wins). The barriers are
    cut at the kerb returns: a parapet that runs straight through a junction
    would wall off the turning lanes.
    """
    lay = lay or profiles.layout(road)
    build_surface(road, idx, builder, lay)
    for sub in _split(idx, excluded or set()):
        build_barriers(road, sub, builder, lay)
        build_median(road, sub, builder, lay)
        build_bridge(road, sub, builder, lay)


def _split(idx, excluded):
    """The path indices of `idx` with the excluded ones removed."""
    out = []
    cur = []
    for i in idx:
        if i in excluded:
            if len(cur) > 1:
                out.append(cur)
            cur = []
        else:
            cur.append(i)
    if len(cur) > 1:
        out.append(cur)
    return out
