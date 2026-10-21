"""Walls with real openings (bund unit).

A wall panel is a plane carrying a pattern of rectangular holes. The wall is built from
solid slabs - the spandrel under the openings, the header over them and the piers between
them - the glass sits in the reveal and the bronze mullions cross the pane. Nothing is
buried inside a solid box, which is what made the side elevations read as blank walls.

Local frame of a building: +X = the facade normal (towards the river), +Y = south along
the row, +Z = up. A panel is either in the x = plane (spanning y) or the y = plane
(spanning x); `sign` says which side of the plane carries the visible face.
"""
WALL_T = 0.35          # the wall thickness = the reveal depth
GLASS_RECESS = 0.30    # the glass behind the face
MULLION = 0.06         # the bronze glazing bars


def _expected_normal(axis, sign):
    """The direction the visible face of a panel has to look."""
    if axis == "X":
        return (1.0, 0.0, 0.0) if sign > 0 else (-1.0, 0.0, 0.0)
    return (0.0, 1.0, 0.0) if sign > 0 else (0.0, -1.0, 0.0)


def _check_facing(bm, face, axis, sign):
    """The pane has to look out of the building: a pane that faces inwards is culled and
    the opening shows the grey core (review r3, MF2)."""
    n = (face.verts[1].co - face.verts[0].co).cross(face.verts[2].co - face.verts[0].co)
    if n.length < 1e-9:
        return
    n = n.normalized()
    want = _expected_normal(axis, sign)
    if n.x * want[0] + n.y * want[1] + n.z * want[2] < 0.9:
        raise RuntimeError("a pane faces inwards (axis %s sign %+.0f, normal %s)"
                           % (axis, sign, tuple(round(v, 2) for v in n)))


def _flip(axis, sign):
    """Does the visible face point the other way?

    The quad of a pane is wound in the (u, z) order of the panel, so its normal follows
    the axis: an X panel comes out towards +X, a Y panel towards -Y. The sign says which
    side of the plane carries the face, so the winding has to follow it - otherwise half
    the flank and rear glass faces into the building and back-face culling hides it."""
    return (axis == "X" and sign < 0.0) or (axis == "Y" and sign > 0.0)


def _pt(axis, plane, sign, u, z, depth):
    """A point on the panel: `depth` 0 is the visible face, positive goes into the wall."""
    if axis == "X":
        return (plane - sign * depth, u, z)
    return (u, plane - sign * depth, z)


def _slab(asm, mat, axis, plane, sign, ua, ub, za, zb, wall_t, out=0.0):
    """A solid box of the wall between u = [ua, ub] and z = [za, zb]."""
    if ub - ua < 1e-4 or zb - za < 1e-4:
        return
    x0, x1 = plane + sign * out, plane - sign * wall_t
    lo, hi = min(x0, x1), max(x0, x1)
    if axis == "X":
        asm.box(mat, ((lo + hi) * 0.5, (ua + ub) * 0.5, (za + zb) * 0.5),
                (hi - lo, ub - ua, zb - za))
    else:
        asm.box(mat, ((ua + ub) * 0.5, (lo + hi) * 0.5, (za + zb) * 0.5),
                (ub - ua, hi - lo, zb - za))


def _columns(u0, u1, holes):
    """The u boundaries of the wall's solid columns (the hole edges cut the wall)."""
    edges = [u0, u1]
    for uc, uh, _hz0, _hz1 in holes:
        edges.extend((uc - uh, uc + uh))
    edges = sorted(set(round(e, 4) for e in edges))
    return list(zip(edges[:-1], edges[1:]))


def _subtract(z0, z1, spans):
    """The parts of [z0, z1] that are not inside one of the `spans`."""
    out = [(z0, z1)]
    for a, b in spans:
        nxt = []
        for c, d in out:
            if b <= c or a >= d:
                nxt.append((c, d))
                continue
            if a > c:
                nxt.append((c, a))
            if b < d:
                nxt.append((b, d))
        out = nxt
    return out


def _bar(asm, mat, axis, plane, sign, ua, ub, za, zb):
    """A flat glazing bar (two triangles, not a box).

    The bar follows the face of the panel, so it is wound with the sign as well."""
    if axis == "X":
        x = plane
        pts = [(x, ua, za), (x, ub, za), (x, ub, zb), (x, ua, zb)]
    else:
        x = plane
        pts = [(ua, x, za), (ub, x, za), (ub, x, zb), (ua, x, zb)]
    if _flip(axis, sign):
        pts = list(reversed(pts))
    bm = asm.loose_bm(mat)
    vs = [bm.verts.new(p) for p in pts]
    face = bm.faces.new(vs)
    _check_facing(bm, face, axis, sign)


def opening_wall(asm, mat, glass, plane, axis, sign, u0, u1, z0, z1, holes,
                 wall_t=WALL_T, glass_recess=GLASS_RECESS, proud=0.0,
                 rng=None, lit_fraction=0.25, cell_base=0, mullions=True,
                 frame_mat=None, atlas=True):
    """A wall panel with rectangular openings.

    `holes` is a list of (u_centre, u_half, z_bottom, z_top). The glass of each opening
    shows one cell of the interior atlas; `rng` decides which openings are lit."""
    for ua, ub in _columns(u0, u1, holes):
        mid = (ua + ub) * 0.5
        cuts = [(hz0, hz1) for uc, uh, hz0, hz1 in holes
                if uc - uh < mid < uc + uh]
        for za, zb in _subtract(z0, z1, cuts):
            _slab(asm, mat, axis, plane, sign, ua, ub, za, zb, wall_t, proud)
    for i, (uc, uh, hz0, hz1) in enumerate(holes):
        if uh < 0.05 or hz1 - hz0 < 0.05:
            continue
        g = plane - sign * glass_recess
        pts = [_pt(axis, g, sign, uc - uh, hz0, 0.0), _pt(axis, g, sign, uc + uh, hz0, 0.0),
               _pt(axis, g, sign, uc + uh, hz1, 0.0), _pt(axis, g, sign, uc - uh, hz1, 0.0)]
        if _flip(axis, sign):
            pts = list(reversed(pts))
        lit = rng is not None and rng.random() < lit_fraction
        role = glass if lit else "glassdark"
        if atlas:
            cell = (cell_base + i) % 16
            u0t = (cell % 4) * 0.25
            v0t = (cell // 4) * 0.25
            uvs = [(u0t, v0t), (u0t + 0.25, v0t), (u0t + 0.25, v0t + 0.25), (u0t, v0t + 0.25)]
            if _flip(axis, sign):
                uvs = list(reversed(uvs))
            face = asm.quad_uv(role, pts, uvs)
            _check_facing(asm.loose_bm(role), face, axis, sign)
        else:
            face = asm.quad(role, *pts)
            _check_facing(asm.loose_bm(role), face, axis, sign)
        if mullions:
            m = MULLION
            mp = g + sign * 0.03
            for f in (1.0 / 3.0, 2.0 / 3.0):
                u = uc - uh + 2.0 * uh * f
                _bar(asm, "iron", axis, mp, sign, u - m * 0.5, u + m * 0.5, hz0, hz1)
            zt = hz0 + (hz1 - hz0) * 0.62
            _bar(asm, "iron", axis, mp, sign, uc - uh, uc + uh, zt - m * 0.5, zt + m * 0.5)
        if proud > 0.0:
            fm = frame_mat or mat
            for u in (uc - uh - proud * 0.5, uc + uh + proud * 0.5):
                _slab(asm, fm, axis, plane, sign, u - proud * 0.5, u + proud * 0.5,
                      hz0 - proud, hz1 + proud, 0.12, proud)
            _slab(asm, fm, axis, plane, sign, uc - uh - proud, uc + uh + proud,
                  hz1 + proud * 0.25, hz1 + proud * 0.75, 0.12, proud)
    return asm
