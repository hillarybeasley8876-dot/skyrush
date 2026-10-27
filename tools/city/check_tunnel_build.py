#!/usr/bin/env python3
"""check_tunnel_build — the road tiles draw and fence a tunnel the way its depth asks (no Godot needed).

    python tools/city/check_tunnel_build.py <tiles dir> <data dir> <city.json> [--quiet]

<data dir> holds the lanes.json and the road_furniture.json of the same build.  A tunnel road of city.json is split by the
depth of its road (d = -y, the same split as check_tunnel_portals.py):
  AT GRADE  d <= 0.3 m          a street: asphalt, kerbs, markings, nothing of the tunnel over it
  OPEN      0.3 m < d < 5.98 m  the trough: open to the sky, a wall on each side of each carriageway from under the road up to
                                the ground, a parapet 1.0 m over the ground on the outer walls (the ground of the game is cut
                                between the walls: a car on the street must not fall in, a car in the trough must not drive out)
  COVERED   d >= 5.98 m         the bore (tunnel.py: its crown is 5.98 m over the road): the bore is drawn only here

The trough walls of one carriageway stand at the outer and the inner side of it: its middle is OFFSET = 7.25 m from the centre
line of the road (half the median 3.75 + half the 7.0 m carriageway), the walls of the bore are at 3.75 + 0.35 m from that middle
(tunnel.py build_wall_colliders): the outer ones 11.05..11.65 m, the inner ones 2.85..3.45 m from the centre line.

Checks (each is a count; all must be 0):
  BORE_ABOVE_GROUND   a triangle of the bore materials (Road_Tunnel_*, Road_Led_Tunnel) has a vertex more than 0.05 m over
                      the ground
  BORE_NOT_COVERED    a triangle of the bore materials lies at a station of the road that is not COVERED (d < 5.5)
  TROUGH_OUTER_OPEN   a station of the trough (d >= 0.5, outside the junctions of the tunnel) where a horizontal ray from the
                      outer lane (9 m from the centre line) outwards to 14 m, at a height between 0.5 m over the road and 0.9 m
                      over the ground, meets no barrier collider
  TROUGH_INNER_OPEN   the same towards the median (5.5 m -> 2.0 m), heights from 0.5 m over the road to 0.2 m under the ground
  TROUGH_NOT_DRAWN    the outer ray meets no drawn triangle (the wall and the parapet must be seen)
  PORTAL_OPEN         where the trough meets the bore: a ray along the road at 0.2 / 0.5 / 0.85 m over the ground, 4..11 m either
                      side of the centre line, from 4 m over the bore towards the trough, meets no barrier collider within 8 m
                      (a car on the ground over the bore drives into the trough)
  HEADROOM            a lane of the tunnel (every 1 m): a barrier collider in the box 2.0 m wide, 1.0 m long, from 0.3 to 4.2 m
                      over the lane
  HEADROOM_DRAWN      the same with the drawn triangles of the tunnel structure (bore, concrete, steel, LEDs), 0.5 to 4.0 m
  FLOOR_COLLIDER      a lane of the tunnel (every 1 m, not the connectors of its junctions) has no road surface collider
                      within 0.15 m of its height
  FLOOR_ASPHALT       ... no asphalt (SH_wet_asphalt) within 0.15 m of its height (the floor is seen in the trough and at grade)
  STREET_BLOCKED      a lane of another road that comes within 60 m of the trough or of the tunnel at grade: a barrier
                      collider in the box of a car (check_path_blockers: 1.9 x 1.0 x 4.2 m, 0.3 m over the lane), every 1 m
  LIGHT_NOT_COVERED   a tunnel_light of road_furniture.json at a station that is not COVERED (d < 5.5)
Prints the stretches of each tunnel, one line per check with its count and its first places, and "TUNNEL_BUILD OK" or
"TUNNEL_BUILD FAIL n" (n = the checks that fail); exit 1 on a failure.
"""
import collections
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_path_blockers as cp  # noqa: E402
import check_surface_coverage as cs  # noqa: E402

AT_GRADE = 0.3
COVER = 5.98
NOT_COVERED = 5.5
OFFSET = 7.25
OUTER_FROM, OUTER_TO = 9.0, 14.0
INNER_FROM, INNER_TO = 5.5, 2.0
PARAPET = 0.9
JUNCTION_R = 40.0
CELL = 8.0
BORE_MATS = ("Road_Tunnel_Enamel", "Road_Tunnel_Stripe", "Road_Tunnel_Dark", "Road_Led_Tunnel")
STRUCTURE_MATS = BORE_MATS + ("SH_concrete_pier", "Road_Steel_Girder")
SURFACE_MATS = ("SH_wet_asphalt", "SH_road_marking", "SH_kerb", "SH_sidewalk", "Road_Tactile", "Road_Planter")


def classify(y):
    d = -y
    return "AT_GRADE" if d <= AT_GRADE else ("OPEN" if d < COVER else "COVERED")


def load_tiles(tiles_dir, box):
    """{material or collider name: [triangle]} for the triangles that reach into box (x0, x1, z0, z1)."""
    x0, x1, z0, z1 = box
    out = collections.defaultdict(list)
    for name in sorted(os.listdir(tiles_dir)):
        if not (name.startswith("roads_") and name.endswith(".gltf")):
            continue
        tx, tz = (int(v) for v in name[len("roads_"):-len(".gltf")].split("_"))
        if (tx + 1) * 512.0 < x0 or tx * 512.0 > x1 or (tz + 1) * 512.0 < z0 or tz * 512.0 > z1:
            # a tile holds what lies in it; a margin of a tile for the pieces that reach over its border
            if (tx + 2) * 512.0 < x0 or (tx - 1) * 512.0 > x1 or (tz + 2) * 512.0 < z0 or (tz - 1) * 512.0 > z1:
                continue
        path = os.path.join(tiles_dir, name)
        gltf = json.load(open(path, encoding="utf-8"))
        bufs = [open(os.path.join(tiles_dir, b["uri"]), "rb").read() for b in gltf["buffers"]]
        prefix = "roads_%d_%d_" % (tx, tz)
        for node in gltf.get("nodes", []):
            if "mesh" not in node:
                continue
            nm = node.get("name", "")
            mat = nm[len(prefix):] if nm.startswith(prefix) else nm
            shift = node.get("translation", (0.0, 0.0, 0.0))
            for prim in gltf["meshes"][node["mesh"]]["primitives"]:
                pos = cs.read_accessor(gltf, bufs, prim["attributes"]["POSITION"])
                ind = cs.read_accessor(gltf, bufs, prim["indices"]) if "indices" in prim else list(range(len(pos)))
                for k in range(0, len(ind) - 2, 3):
                    tri = tuple((pos[ind[k + j]][0] + shift[0], pos[ind[k + j]][1] + shift[1],
                                 pos[ind[k + j]][2] + shift[2]) for j in range(3))
                    if max(p[0] for p in tri) < x0 or min(p[0] for p in tri) > x1 \
                            or max(p[2] for p in tri) < z0 or min(p[2] for p in tri) > z1:
                        continue
                    out[mat].append(tri)
    return out


class Grid:
    def __init__(self, tris):
        self.tris = tris
        self.cells = collections.defaultdict(list)
        for i, t in enumerate(tris):
            xs, zs = [p[0] for p in t], [p[2] for p in t]
            for a in range(int(min(xs) // CELL), int(max(xs) // CELL) + 1):
                for b in range(int(min(zs) // CELL), int(max(zs) // CELL) + 1):
                    self.cells[(a, b)].append(i)

    def near(self, x0, x1, z0, z1):
        seen = set()
        for a in range(int(min(x0, x1) // CELL), int(max(x0, x1) // CELL) + 1):
            for b in range(int(min(z0, z1) // CELL), int(max(z0, z1) // CELL) + 1):
                for i in self.cells.get((a, b), ()):
                    if i not in seen:
                        seen.add(i)
                        yield self.tris[i]


def ray_hits(grid, o, d, length):
    """True when the segment o -> o + d * length meets a triangle of the grid (Moeller-Trumbore)."""
    e = (o[0] + d[0] * length, o[2] + d[2] * length)
    for t in grid.near(o[0], e[0], o[2], e[1]):
        a, b, c = t
        e1 = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        e2 = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        p = (d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2], d[0] * e2[1] - d[1] * e2[0])
        det = e1[0] * p[0] + e1[1] * p[1] + e1[2] * p[2]
        if abs(det) < 1e-12:
            continue
        inv = 1.0 / det
        s = (o[0] - a[0], o[1] - a[1], o[2] - a[2])
        u = (s[0] * p[0] + s[1] * p[1] + s[2] * p[2]) * inv
        if u < -1e-6 or u > 1.0 + 1e-6:
            continue
        q = (s[1] * e1[2] - s[2] * e1[1], s[2] * e1[0] - s[0] * e1[2], s[0] * e1[1] - s[1] * e1[0])
        v = (d[0] * q[0] + d[1] * q[1] + d[2] * q[2]) * inv
        if v < -1e-6 or u + v > 1.0 + 1e-6:
            continue
        dist = (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]) * inv
        if 0.0 <= dist <= length:
            return True
    return False


def box_hits(grid, centre, right, fwd, half):
    """True when a triangle of the grid touches the box (half widths across, up, along) at centre, turned to right/fwd."""
    cx, cy, cz = centre
    reach = max(half[0], half[2]) + 0.5
    for t in grid.near(cx - reach, cx + reach, cz - reach, cz + reach):
        if min(p[1] for p in t) > cy + half[1] or max(p[1] for p in t) < cy - half[1]:
            continue
        loc = []
        for v in t:
            dx, dy, dz = v[0] - cx, v[1] - cy, v[2] - cz
            loc.append((dx * right[0] + dz * right[1], dy, dx * fwd[0] + dz * fwd[1]))
        if cp.tri_box_overlap(loc[0], loc[1], loc[2], half):
            return True
    return False


def height_near(grid, x, z, y, tol):
    for t in grid.near(x, x, z, z):
        h = cs.height_at(t, x, z)
        if h is not None and abs(h - y) <= tol:
            return True
    return False


def stations(road):
    pts = road["points"]
    out = []
    s = 0.0
    for i, p in enumerate(pts):
        if i:
            s += math.hypot(p[0] - pts[i - 1][0], p[2] - pts[i - 1][2])
        a, b = pts[max(0, i - 1)], pts[min(len(pts) - 1, i + 1)]
        n = math.hypot(b[0] - a[0], b[2] - a[2]) or 1.0
        t = ((b[0] - a[0]) / n, (b[2] - a[2]) / n)
        out.append({"s": s, "p": p, "t": t, "r": (-t[1], t[0]), "d": -p[1], "c": classify(p[1])})
    return out


def lane_samples(points, step=1.0):
    """(point, right, forward) every `step` metres along a polyline."""
    out = []
    acc, nxt = 0.0, 0.0
    for a, b in zip(points, points[1:]):
        seg = math.dist(a, b)
        if seg < 1e-6:
            continue
        flat = math.hypot(b[0] - a[0], b[2] - a[2]) or 1.0
        f = ((b[0] - a[0]) / flat, (b[2] - a[2]) / flat)
        while nxt <= acc + seg:
            u = (nxt - acc) / seg
            out.append(((a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u), (-f[1], f[0]), f))
            nxt += step
        acc += seg
    return out


class Counts:
    def __init__(self):
        self.n = collections.Counter()
        self.where = collections.defaultdict(list)

    def add(self, key, what):
        self.n[key] += 1
        if len(self.where[key]) < 4:
            self.where[key].append(what)


def check(tiles_dir, data_dir, city):
    tunnels = [r for r in city["roads"] if r.get("kind") == "tunnel"]
    lanes = json.load(open(os.path.join(data_dir, "lanes.json"), encoding="utf-8"))["lanes"]
    furniture = json.load(open(os.path.join(data_dir, "road_furniture.json"), encoding="utf-8"))
    out = Counts()
    lines = []
    for tunnel in tunnels:
        st = stations(tunnel)
        xs = [q["p"][0] for q in st]
        zs = [q["p"][2] for q in st]
        box = (min(xs) - 80.0, max(xs) + 80.0, min(zs) - 80.0, max(zs) + 80.0)
        mats = load_tiles(tiles_dir, box)
        barrier = Grid([t for m, ts in mats.items() if "colonly" in m and "surface" not in m for t in ts])
        surface = Grid([t for m, ts in mats.items() if "surface-colonly" in m for t in ts])
        drawn = Grid([t for m, ts in mats.items() if "colonly" not in m for t in ts])
        structure = Grid([t for m, ts in mats.items() if m in STRUCTURE_MATS for t in ts])
        asphalt = Grid([t for m, ts in mats.items() if m == "SH_wet_asphalt" for t in ts])
        sgrid = collections.defaultdict(list)
        for i, q in enumerate(st):
            sgrid[(int(q["p"][0] // 20.0), int(q["p"][2] // 20.0))].append(i)

        def nearest(x, z):
            best, bi = 1e18, None
            for a in range(int(x // 20.0) - 1, int(x // 20.0) + 2):
                for b in range(int(z // 20.0) - 1, int(z // 20.0) + 2):
                    for i in sgrid.get((a, b), ()):
                        d = (st[i]["p"][0] - x) ** 2 + (st[i]["p"][2] - z) ** 2
                        if d < best:
                            best, bi = d, i
            return None if bi is None else st[bi]

        junctions = [(j["x"], j["z"]) for j in city.get("junctions", []) if tunnel["id"] in j.get("roads", [])]
        in_junction = lambda q: any(math.hypot(q["p"][0] - x, q["p"][2] - z) < JUNCTION_R for x, z in junctions)  # noqa: E731
        run = None
        for q in st:
            if run and run[0] == q["c"]:
                run[2] = q["s"]
            else:
                if run:
                    lines.append("%s %-8s s %7.1f .. %7.1f" % (tunnel["id"], run[0], run[1], run[2]))
                run = [q["c"], q["s"], q["s"]]
        lines.append("%s %-8s s %7.1f .. %7.1f" % (tunnel["id"], run[0], run[1], run[2]))

        for m in BORE_MATS:
            for t in mats.get(m, ()):
                top = max(p[1] for p in t)
                cx, cz = sum(p[0] for p in t) / 3.0, sum(p[2] for p in t) / 3.0
                if top > 0.05:
                    out.add("BORE_ABOVE_GROUND", "%s %.2f m up at (%.0f, %.0f)" % (m, top, cx, cz))
                q = nearest(cx, cz)
                if q is not None and q["d"] < NOT_COVERED:
                    out.add("BORE_NOT_COVERED", "%s at s %.0f (depth %.2f) (%.0f, %.0f)" % (m, q["s"], q["d"], cx, cz))

        for q in st:
            if q["c"] != "OPEN" or q["d"] < 0.5 or in_junction(q):
                continue
            p, r, y = q["p"], q["r"], q["p"][1]
            heights = []
            h = y + 0.5
            while h < PARAPET:
                heights.append(h)
                h += 0.4
            heights.append(PARAPET)
            for side in (1.0, -1.0):
                d = (r[0] * side, 0.0, r[1] * side)
                for h in heights:
                    o = (p[0] + d[0] * OUTER_FROM, h, p[2] + d[2] * OUTER_FROM)
                    if not ray_hits(barrier, o, d, OUTER_TO - OUTER_FROM):
                        out.add("TROUGH_OUTER_OPEN", "s %.0f side %+d at %.2f m (road %.2f) (%.0f, %.0f)"
                                % (q["s"], side, h, y, o[0], o[2]))
                        break
                for h in heights:
                    o = (p[0] + d[0] * OUTER_FROM, h, p[2] + d[2] * OUTER_FROM)
                    if not ray_hits(drawn, o, d, OUTER_TO - OUTER_FROM):
                        out.add("TROUGH_NOT_DRAWN", "s %.0f side %+d at %.2f m (road %.2f)" % (q["s"], side, h, y))
                        break
                dn = (-d[0], 0.0, -d[2])
                for h in [v for v in heights if v <= -0.2] or [y + 0.5]:
                    o = (p[0] + d[0] * INNER_FROM, h, p[2] + d[2] * INNER_FROM)
                    if not ray_hits(barrier, o, dn, INNER_FROM - INNER_TO):
                        out.add("TROUGH_INNER_OPEN", "s %.0f side %+d at %.2f m (road %.2f)" % (q["s"], side, h, y))
                        break

        for i in range(1, len(st)):
            a, b = st[i - 1], st[i]
            if {a["c"], b["c"]} != {"OPEN", "COVERED"}:
                continue
            face = b if b["c"] == "COVERED" else a
            inward = (face["t"][0], face["t"][1]) if b["c"] == "COVERED" else (-face["t"][0], -face["t"][1])
            for u in [v for v in range(-11, 12) if abs(v) >= 4]:
                for h in (0.2, 0.5, 0.85):
                    o = (face["p"][0] + face["r"][0] * u + inward[0] * 4.0, h,
                         face["p"][2] + face["r"][1] * u + inward[1] * 4.0)
                    if not ray_hits(barrier, o, (-inward[0], 0.0, -inward[1]), 8.0):
                        out.add("PORTAL_OPEN", "face s %.0f offset %+d at %.2f m (%.0f, %.0f)" % (face["s"], u, h, o[0], o[2]))
                        break

        for lane in lanes:
            if lane.get("road") != tunnel["id"]:
                continue
            for (pt, right, fwd) in lane_samples(lane["points"]):
                if box_hits(barrier, (pt[0], pt[1] + 2.25, pt[2]), right, fwd, (1.0, 1.95, 0.5)):
                    out.add("HEADROOM", "%s (%.0f, %.1f, %.0f)" % (lane["id"], pt[0], pt[1], pt[2]))
                if box_hits(structure, (pt[0], pt[1] + 2.25, pt[2]), right, fwd, (1.0, 1.75, 0.5)):
                    out.add("HEADROOM_DRAWN", "%s (%.0f, %.1f, %.0f)" % (lane["id"], pt[0], pt[1], pt[2]))
                if lane.get("connector"):
                    # the connectors of a junction run over the plate of the junction (its own builder)
                    continue
                if not height_near(surface, pt[0], pt[2], pt[1], 0.15):
                    out.add("FLOOR_COLLIDER", "%s (%.0f, %.1f, %.0f)" % (lane["id"], pt[0], pt[1], pt[2]))
                if not height_near(asphalt, pt[0], pt[2], pt[1], 0.15):
                    out.add("FLOOR_ASPHALT", "%s (%.0f, %.1f, %.0f)" % (lane["id"], pt[0], pt[1], pt[2]))

        hot = [q for q in st if q["c"] != "COVERED"]
        for lane in lanes:
            if lane.get("road") == tunnel["id"] or len(lane["points"]) < 2:
                continue
            if not any(math.hypot(pt[0] - q["p"][0], pt[2] - q["p"][2]) < 60.0
                       for pt in lane["points"][::4] + [lane["points"][-1]] for q in hot[::5]):
                continue
            for (pt, right, fwd) in lane_samples(lane["points"]):
                if box_hits(barrier, (pt[0], pt[1] + 0.3 + cp.HALF[1], pt[2]), right, fwd, cp.HALF):
                    out.add("STREET_BLOCKED", "%s (%.0f, %.1f, %.0f)" % (lane["id"], pt[0], pt[1], pt[2]))

        for item in furniture.get("props", []):
            if item.get("kind") != "tunnel_light" or item.get("road") != tunnel["id"]:
                continue
            q = nearest(item["x"], item["z"])
            if q is not None and q["d"] < NOT_COVERED:
                out.add("LIGHT_NOT_COVERED", "s %.0f (depth %.2f) (%.0f, %.0f)" % (q["s"], q["d"], item["x"], item["z"]))
    return lines, out


KEYS = ("BORE_ABOVE_GROUND", "BORE_NOT_COVERED", "TROUGH_OUTER_OPEN", "TROUGH_INNER_OPEN", "TROUGH_NOT_DRAWN", "PORTAL_OPEN",
        "HEADROOM", "HEADROOM_DRAWN", "FLOOR_COLLIDER", "FLOOR_ASPHALT", "STREET_BLOCKED", "LIGHT_NOT_COVERED")


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if len(args) != 3:
        print(__doc__)
        return 2
    city = json.load(open(args[2], encoding="utf-8"))
    lines, out = check(args[0], args[1], city)
    if "--quiet" not in argv:
        for line in lines:
            print(line)
    bad = 0
    for k in KEYS:
        n = out.n.get(k, 0)
        bad += 1 if n else 0
        print("%-18s %6d%s" % (k, n, ("  first: " + "; ".join(out.where[k])) if n else ""))
    print("TUNNEL_BUILD OK" if not bad else "TUNNEL_BUILD FAIL %d" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
