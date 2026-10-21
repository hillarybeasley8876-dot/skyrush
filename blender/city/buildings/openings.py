"""Walls with real openings.

A facade is not a solid slab with a dark rectangle painted on it: the wall is built
as pier strips (the solid parts between the openings) and spandrel strips (the parts
above and below each opening), so every window and door is a genuine hole with a
reveal.  The glass or the door leaf sits at the back of the reveal, the frame and the
architrave stand proud of the wall.

`ctx.add_pane` records every pane so the builder can assert - with a BVH ray cast -
that nothing is buried inside the wall.
"""
import math

from mathutils import Vector

from . import shapes

WALL_T = 0.30        # the wall thickness of a masonry building
PANE_CHECK_DIST = 0.5


def wall_angle(fc):
    """The rotation of a facade's boxes (its local X runs along the wall)."""
    return math.degrees(math.atan2(fc["t"][1], fc["t"][0]))


def wall_point(fc, u):
    """The city point on the wall at the distance `u` from its start."""
    return (fc["a"][0] + fc["t"][0] * u, fc["a"][1] + fc["t"][1] * u)


def wall_box(bm, fc, u0, u1, h0, h1, wall_t):
    """A solid strip of wall between the heights h0 and h1."""
    mid = wall_point(fc, (u0 + u1) * 0.5)
    c = (mid[0] - fc["n"][0] * wall_t * 0.5, mid[1] - fc["n"][1] * wall_t * 0.5)
    shapes.add_box(bm, c, (max(u1 - u0, 0.01), wall_t), h0, h1, rot_deg=wall_angle(fc))


def wall_quad(bm, fc, u0, u1, h0, h1, uv=None):
    """A vertical quad on the wall plane (the outside face)."""
    base = wall_point(fc, u0)
    return shapes.add_wall_quad(bm, base, fc["n"], u1 - u0, h0, h1, uv=uv)


def wall_slab(bm, fc, u0, u1, h0, h1, d0, d1):
    """A box on the wall plane, spanning the depths d0..d1.

    A depth is the distance INTO the wall: 0 is the wall plane, a negative depth is
    proud of it.  This is the workhorse for the reveals, the frames and the sills.
    """
    mid = wall_point(fc, (u0 + u1) * 0.5)
    c = (mid[0] - fc["n"][0] * (d0 + d1) * 0.5, mid[1] - fc["n"][1] * (d0 + d1) * 0.5)
    shapes.add_box(bm, c, (max(u1 - u0, 0.005), max(abs(d1 - d0), 0.005)), h0, h1,
                   rot_deg=wall_angle(fc))


def add_quad_in_reveal(ctx, fc, u0, u1, h0, h1, depth, key, uv=None):
    """A quad inside the reveal (a curtain, a blind) at `depth` into the wall."""
    base = wall_point(fc, u0)
    base = (base[0] - fc["n"][0] * depth, base[1] - fc["n"][1] * depth)
    shapes.add_wall_quad(ctx.bag.bm(key), base, fc["n"], u1 - u0, h0, h1, uv=uv)


def wall_frame(bm, fc, u0, u1, h0, h1, width, d0, d1):
    """A four-piece frame around an opening (a casement, an architrave)."""
    wall_slab(bm, fc, u0 - width, u0, h0 - width, h1 + width, d0, d1)
    wall_slab(bm, fc, u1, u1 + width, h0 - width, h1 + width, d0, d1)
    wall_slab(bm, fc, u0, u1, h1, h1 + width, d0, d1)
    wall_slab(bm, fc, u0, u1, h0 - width, h0, d0, d1)



def build_facade(bm, fc, holes, h0, h1, wall_t=WALL_T):
    """The wall of one facade with real holes.

    The wall is cut in vertical strips: every strip is filled only where no opening
    covers it.  Building it as one strip per opening (the naive way) made the
    spandrel of the window below fill the window above it, because both share the
    same u range.
    """
    edges = [0.0, fc["w"]]
    for op in holes:
        edges.append(max(0.0, min(fc["w"], op["u0"])))
        edges.append(max(0.0, min(fc["w"], op["u1"])))
    edges = sorted(set(edges))
    tol = 1e-4
    for i in range(len(edges) - 1):
        ua, ub = edges[i], edges[i + 1]
        if ub - ua < 1e-6:
            continue
        cuts = []
        for op in holes:
            if op["u0"] <= ua + tol and op["u1"] >= ub - tol:
                cuts.append((max(op["h0"], h0), min(op["h1"], h1)))
        cuts.sort()
        cursor = h0
        for (c0, c1) in cuts:
            if c0 > cursor + 1e-6:
                wall_box(bm, fc, ua, ub, cursor, c0, wall_t)
            cursor = max(cursor, c1)
        if h1 > cursor + 1e-6:
            wall_box(bm, fc, ua, ub, cursor, h1, wall_t)


def add_pane(ctx, fc, u0, u1, h0, h1, depth, key, uv=None, check=True):
    """The glass (or the door leaf) at the back of an opening, and its assertion."""
    mid = wall_point(fc, (u0 + u1) * 0.5)
    p = (mid[0] - fc["n"][0] * depth, mid[1] - fc["n"][1] * depth)
    base = wall_point(fc, u0)
    base = (base[0] - fc["n"][0] * depth, base[1] - fc["n"][1] * depth)
    shapes.add_wall_quad(ctx.bag.bm(key), base, fc["n"], u1 - u0, h0, h1, uv=uv)
    if check:
        ctx.add_pane((p[0], p[1], (h0 + h1) * 0.5), fc["n"], depth)
    return p


def assert_panes_visible(faces, panes, tolerance=0.15):
    """Every pane must be the first thing a ray from in front of it hits.

    The ray starts 0.5 m in front of the pane and goes back along the wall normal.
    If the wall is solid at that point the ray hits the wall plane instead, and the
    pane is buried - which is exactly the defect this checks for.
    """
    from mathutils.bvhtree import BVHTree
    if not panes:
        return []
    tree = _bvh(faces)
    failures = []
    for (x, z, h), n, depth in panes:
        origin = Vector((x + n[0] * PANE_CHECK_DIST, -(z + n[1] * PANE_CHECK_DIST), h))
        direction = Vector((-n[0], n[1], 0.0))
        loc, _nor, _idx, dist = tree.ray_cast(origin, direction)
        if loc is None:
            failures.append("pane at (%.1f, %.1f, %.1f) hit nothing (%d faces in the bvh)"
                            % (x, z, h, len(faces)))
            continue
        # the origin is already 0.5 m in front of the pane, so a visible pane is
        # hit at 0.5 m; a pane buried in the wall is hit at the wall plane instead
        want = PANE_CHECK_DIST
        if abs(dist - want) > tolerance:
            failures.append("pane at (%.1f, %.1f, %.1f): first hit at %.2f m, expected %.2f"
                            % (x, z, h, dist, want))
    return failures


def _bvh(faces):
    """A BVH over a list of faces (they are all in the same world space)."""
    from mathutils.bvhtree import BVHTree
    if not faces:
        return None
    verts = []
    polys = []
    for f in faces:
        poly = []
        for v in f.verts:
            poly.append(len(verts))
            verts.append(v.co.copy())
        polys.append(poly)
    if not polys:
        return None
    return BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
