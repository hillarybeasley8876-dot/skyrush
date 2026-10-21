"""Cut the shell along the JSON panel lines, so every panel's seam IS the line
the dossier draws (review r3 #3, lead note LEAD-BODY 2).

The lead's shell is a lofted surface: its face boundaries follow the 0.08 m
section spacing, not the dossier's cut lines. A panel that is picked by face
centre alone therefore leaves its seam up to 20 cm away from the painted 4 mm
groove, and every gap shows TWICE (once at the geometric edge, once at the
painted line).

This module bisects the shell along every JSON line BEFORE the panels are
picked, so the geometric seam and the painted groove are the same line. The
cut is limited to the region of the panel it belongs to, and the T vertices
that leaves behind are dissolved again.
"""
import math

import bmesh
from mathutils import Vector

from car import paths, regions

FLANK = 0.25        # a flank face has a normal with at least this much X
TOP = 0.30          # a top face has a normal with at least this much Z
MARGIN = 0.005      # the region is 5 mm wider than the painted line
OVERSHOOT = 0.10    # the flank cut runs 100 mm past the end of its segment


def _loft():
    return paths.loft()


def _seg_plane(p0, p1):
    """The plane through a (y, z) segment; it contains the X axis."""
    dy, dz = p1[0] - p0[0], p1[1] - p0[1]
    n = Vector((0.0, -dz, dy))
    if n.length < 1e-9:
        return None
    n.normalize()
    return Vector((0.0, p0[0], p0[1])), n


def _dist_to_polyline(p, poly):
    """The distance in the (y, z) plane from p to a polyline."""
    best = 1e9
    for a, b in zip(poly[:-1], poly[1:]):
        dy, dz = b[0] - a[0], b[1] - a[1]
        l2 = dy * dy + dz * dz
        t = 0.0 if l2 < 1e-12 else max(0.0, min(1.0, ((p[0] - a[0]) * dy +
                                                       (p[1] - a[1]) * dz) / l2))
        cx, cz = a[0] + t * dy, a[1] + t * dz
        best = min(best, math.hypot(p[0] - cx, p[1] - cz))
    return best


def _flank_region(z_lo, z_hi, line=None):
    """The flank faces of a band of heights.

    With `line` (a (y, z) segment) only the faces that STRADDLE that line are
    picked: the plane of the segment is infinite, and without this test it
    would cut the flank far away from the segment as well.
    """
    p0, p1 = line if line else (None, None)

    def sign(v):
        dy, dz = p1[0] - p0[0], p1[1] - p0[1]
        return -dz * (v.y - p0[0]) + dy * (v.z - p0[1])

    def region(f):
        c = f.calc_center_median()
        if abs(f.normal.x) < FLANK:
            return False
        if not (z_lo - OVERSHOOT <= c.z <= z_hi + OVERSHOOT):
            return False
        if line is None:
            return True
        vals = [sign(v.co) for v in f.verts]
        return min(vals) < 0.0 < max(vals)
    return region


def _top_region(half_width):
    """The top faces inside a half width."""
    def region(f):
        c = f.calc_center_median()
        if f.normal.z < TOP:
            return False
        return abs(c.x) <= half_width + MARGIN
    return region


def _specs():
    """Every JSON cut line, as a plane set plus the region it belongs to."""
    d = _loft()
    sp, pl = d["side_profile"], d["panel_lines"]
    out = []
    front = [tuple(p) for p in sp["door_front_cut"]]
    rear = [tuple(p) for p in sp["door_rear_cut"]]
    for name, poly in (("door_front", front), ("door_rear", rear)):
        for i, (a, b) in enumerate(zip(poly[:-1], poly[1:])):
            z_lo = min(a[1], b[1])
            z_hi = max(a[1], b[1])
            plane = _seg_plane(a, b)
            if plane is None:
                continue
            out.append({"name": "%s_%d" % (name, i), "poly": [a, b],
                        "planes": [plane],
                        "region": _flank_region(z_lo, z_hi, (a, b)),
                        "axes": (1, 2), "kind": "flank"})
    # the sill line under the door
    lower = [front[-1], rear[-1]]
    plane = _seg_plane(lower[0], lower[1])
    if plane is not None:
        out.append({"name": "door_lower", "poly": lower, "planes": [plane],
                    "region": _flank_region(min(p[1] for p in lower) - 0.2,
                                        max(p[1] for p in lower) + 0.2, (lower[0], lower[1])),
                    "axes": (1, 2), "kind": "flank"})
    # the cowl, the vent hood and the wing's leading edge: planes of constant y
    for name, key, half in (("cowl", "cowl_y", None),
                            ("vent_hood", "vent_hood_front_y", None),
                            ("wing_edge", "wing_front_edge_y", 0.60)):
        y = pl[key]
        hw = regions.hood_half_width(y) if half is None else half
        out.append({"name": name, "poly": [(-1.0, y), (1.0, y)], "y": y,
                    "planes": [(Vector((0.0, y, 0.0)), Vector((0.0, 1.0, 0.0)))],
                    "region": _top_region(hw), "axes": (0, 1), "kind": "top"})
    # the headlamp panel's rear edge
    y = pl["headlamp_panel_rear_y"]
    out.append({"name": "headlamp_rear", "poly": [(y, 0.42), (y, 0.52)], "y": y,
                "planes": [(Vector((0.0, y, 0.0)), Vector((0.0, 1.0, 0.0)))],
                "region": _flank_region(0.36, 0.58), "axes": (1, 2), "kind": "flank"})
    return out


def cut_shell(bm):
    """Bisect the shell along every JSON line.

    Returns a dict: the spec name -> its poly, its axes and the measured
    distance between its seam and the JSON line.
    """
    seams = {}
    bm.edges.layers.int.get("seam") or bm.edges.layers.int.new("seam")
    for spec in _specs():
        found = _bisect(bm, spec)
        err = seam_error(found, spec["poly"], spec["axes"])
        seams[spec["name"]] = {"name": spec["name"], "poly": spec["poly"],
                               "axes": spec["axes"], "err": err}
        print("  cut %-16s %3d seam edges, %.1f mm off the JSON line"
              % (spec["name"], len(found), err * 1000.0))
    _fix_tjunctions(bm)
    return seams


def _bisect(bm, spec):
    """Cut the faces of `spec["region"]` along the spec's planes."""
    new = []
    for co, no in spec["planes"]:
        faces = [f for f in bm.faces if spec["region"](f)]
        if not faces:
            continue
        geom = list(faces)
        verts = set()
        edges = set()
        for f in faces:
            verts.update(f.verts)
            edges.update(f.edges)
        geom.extend(verts)
        geom.extend(edges)
        res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no,
                                      clear_inner=False, clear_outer=False)
        cut = res.get("geom_cut") or []
        new.extend([e for e in cut if isinstance(e, bmesh.types.BMEdge)])
    seams = [e for e in new if _is_seam(e, spec)]
    layer = bm.edges.layers.int.get("seam") or bm.edges.layers.int.new("seam")
    for e in seams:
        try:
            e[layer] = 1
        except ReferenceError:
            print("  cut %-16s: %d seam edges could not be marked" % (spec["name"], 1))
    return seams


def _is_seam(edge, spec):
    """True when a new edge really lies on the JSON line (and not on the
    incidental splits the infinite plane leaves behind)."""
    mid = (edge.verts[0].co + edge.verts[1].co) * 0.5
    if spec["kind"] == "flank":
        if abs(mid.x) < 0.30:
            return False
        return _dist_to_polyline((mid.y, mid.z), spec["poly"]) < 0.003
    return abs(mid.y - spec["y"]) < 0.002

def _is_tjunction(v, bm):
    """True when a vertex lies in the middle of an edge of the mesh.

    The two edges that leave v in opposite directions belong to one face, and
    the edge that connects their far ends exists in the mesh: that edge runs
    THROUGH v, which is exactly what a T junction is. A plain corner of the
    shell (three edges, two of them collinear) does NOT have that edge, so it
    is left alone.
    """
    edges = list(v.link_edges)
    for i in range(len(edges)):
        for j in range(i + 1, len(edges)):
            e1, e2 = edges[i], edges[j]
            a, b = e1.other_vert(v), e2.other_vert(v)
            d1 = a.co - v.co
            d2 = b.co - v.co
            if d1.length < 1e-9 or d2.length < 1e-9:
                continue
            if d1.normalized().dot(d2.normalized()) > -0.999:
                continue
            if bm.edges.get((a, b)) is not None:
                return True
    return False


def _fix_tjunctions(bm):
    """Dissolve the T vertices a region limited cut leaves behind.

    A T vertex is a vertex that lies in the middle of an edge of the mesh:
    the face on one side of the cut was split and the face on the other side
    was not. Dissolving it merges the two faces again, so the mesh has no
    dangling edges for the bevel modifier to trip over.
    """
    total = 0
    for _ in range(4):
        bm.verts.ensure_lookup_table()
        bad = [v for v in bm.verts if len(v.link_edges) == 3 and _is_tjunction(v, bm)]
        if not bad:
            break
        bmesh.ops.dissolve_verts(bm, verts=bad)
        total += len(bad)
    if total:
        print("  panel cuts: %d T vertices dissolved" % total)


def mark_seams(bm, seams=None):
    """The panel seams are sharp; every other edge keeps the shell's shading.

    The seams carry an int layer, so they survive the T vertex clean up.
    """
    layer = bm.edges.layers.int.get("seam") or bm.edges.layers.int.new("seam")
    for e in bm.edges:
        if e[layer]:
            e.smooth = False
            continue
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) < math.radians(2.0)


def _sample(poly, n=24):
    """Points along a polyline."""
    out = []
    for a, b in zip(poly[:-1], poly[1:]):
        for i in range(n + 1):
            t = i / float(n)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def _seg_dist(p, seg):
    """The distance from p to a 2D segment."""
    (ax, ay), (bx, by) = seg
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 < 1e-12 else max(0.0, min(1.0, ((p[0] - ax) * dx +
                                                   (p[1] - ay) * dy) / l2))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy))


def pick(seams, names):
    """The cut specs of the named lines."""
    return [seams[n] for n in names if n in seams]


def seam_error(seams, poly, axes):
    """How far the panel's seam is from the JSON line, in metres.

    Every seam edge is measured against the line it belongs to; the worst one
    is returned. The seam edges ARE the panel's boundary, so this is the
    distance between the panel's edge and the dossier's line.
    """
    worst = 0.0
    for e in seams:
        mid = (e.verts[0].co + e.verts[1].co) * 0.5
        p = (mid[axes[0]], mid[axes[1]])
        worst = max(worst, _dist_to_polyline(p, poly))
    return worst
