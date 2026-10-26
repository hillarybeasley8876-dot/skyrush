#!/usr/bin/env python3
"""check_joint_runoff — can a car that drives straight on at the joint of two roads run off the deck? (no Godot needed)

    python tools/city/check_joint_runoff.py <tiles dir> <lanes.json> <city.json> [--reach 40] [--spread 3] [--max-bad N] [--quiet]

Two roads that meet end to end (the joints of check_chain_links: the end of a regular lane of one road within 6 m of the start
of a regular lane of the other) need not have the same width: a road of three lanes goes on as a road of two, and its outer
lanes are linked to the other road by a short merge curve.  The car of the outer lane that drives straight on (no hands on
the wheel, the arcade car keeps its heading) leaves the deck of the first road where the second road is narrower, and when
nothing fences that corner it drives off the deck: the random drives over the viaducts lost cars there (fuzz_drive.gd,
from the Nanpu bridge onto the spiral at 140 km/h, 42 m down).

For every lane end at a joint that is on a deck (the lane end at least 3 m over the ground) the checker runs --spread + 1
straight rays from the end of the lane, along the heading of its last 4 m, offset sideways by 0, +-1.0 ... m (the width of a
car), for --reach metres, 0.5 m a step:
  * a ray is FENCED when a barrier collider (any collider that is not the road surface) stands in its way between 0.05 and
    0.55 m over the height of the lane (the box of a car);
  * a ray is ON THE ROAD when every step has a surface collider under it within 1.2 m under to 0.5 m over the lane height
    (it runs on the deck of the second road, or on the first one, to its end);
  * otherwise it is OPEN: the car leaves the road surface before a barrier stops it.
A lane end with an OPEN ray is bad.  Prints the bad lane ends and "JOINT_RUNOFF OK" or "JOINT_RUNOFF FAIL n"; exit 0 when the
number of bad lane ends is <= --max-bad (default 0).
"""
import collections
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_path_blockers as cp  # noqa: E402
import check_surface_coverage as cs  # noqa: E402

STEP = 0.5
BELOW, ABOVE = 1.2, 0.5
CAR_LO, CAR_HI = 0.05, 0.55
MIN_DECK = 3.0
JOINT_RADIUS = 6.0
JOINT_HEIGHT = 1.5
JOINT_HEADING = 40.0
OFFSET = 1.0


def heading_of(a, b):
    return math.degrees(math.atan2(b[0] - a[0], -(b[2] - a[2]))) % 360.0


def turn(a, b):
    return abs((a - b + 180.0) % 360.0 - 180.0)


def joint_lane_ends(lanes):
    """The regular lanes whose end lies at the start of a regular lane of another road (a joint)."""
    regular = [l for l in lanes if not l.get("connector") and len(l["points"]) >= 3]
    starts = collections.defaultdict(list)
    for l in regular:
        p = l["points"][0]
        starts[(int(p[0] // 8), int(p[2] // 8))].append(l)
    out = []
    for u in regular:
        e = u["points"][-1]
        hu = heading_of(u["points"][-3], e)
        cx, cz = int(e[0] // 8), int(e[2] // 8)
        found = False
        for a in range(cx - 1, cx + 2):
            for b in range(cz - 1, cz + 2):
                for v in starts.get((a, b), ()):
                    if v["road"] == u["road"]:
                        continue
                    s = v["points"][0]
                    if math.hypot(s[0] - e[0], s[2] - e[2]) > JOINT_RADIUS or abs(s[1] - e[1]) > JOINT_HEIGHT:
                        continue
                    if turn(hu, heading_of(s, v["points"][2])) > JOINT_HEADING:
                        continue
                    found = True
        if found:
            out.append(u)
    return out


def surface_at(grid, x, z, y):
    """The surface collider height at (x, z) nearest to y within [y - BELOW, y + ABOVE], or None."""
    best = None
    for t in grid.get((int(x // cs.CELL), int(z // cs.CELL)), ()):
        h = cs.height_at(t, x, z)
        if h is not None and y - BELOW <= h <= y + ABOVE and (best is None or abs(h - y) < abs(best - y)):
            best = h
    return best


def fenced_at(bgrid, btris, x, z, y):
    """True when a barrier triangle crosses the vertical segment at (x, z) from y + CAR_LO to y + CAR_HI (a 0.3 m column)."""
    half = (0.3, (CAR_HI - CAR_LO) * 0.5, 0.3)
    centre = (x, y + (CAR_LO + CAR_HI) * 0.5, z)
    for i in bgrid.get((int(x // cp.CELL), int(z // cp.CELL)), ()):
        t, _nm = btris[i]
        v = [(p[0] - centre[0], p[1] - centre[1], p[2] - centre[2]) for p in t]
        if cp.tri_box_overlap(v[0], v[1], v[2], half):
            return True
    return False


def run_ray(start, d, reach, sgrid, stris, bgrid, btris):
    """'fenced', 'road' or 'open' (with the distance where the surface ended) for one straight ray."""
    y = start[1]
    k = 1
    while k * STEP <= reach:
        x, z = start[0] + d[0] * k * STEP, start[2] + d[1] * k * STEP
        if fenced_at(bgrid, btris, x, z, y):
            return "fenced", k * STEP
        h = surface_at(sgrid, x, z, y)
        if h is None:
            return "open", k * STEP
        y = h
        k += 1
    return "road", reach


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda n, d: argv[argv.index(n) + 1] if n in argv else d  # noqa: E731
    reach, spread, max_bad = float(opt("--reach", "40")), int(opt("--spread", "3")), int(opt("--max-bad", "0"))
    for n in ("--reach", "--spread", "--max-bad"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    quiet = "--quiet" in argv
    tiles_dir, lanes_path = args[0], args[1]
    lanes = json.load(open(lanes_path, encoding="utf-8"))["lanes"]
    stris = []
    for name in sorted(os.listdir(tiles_dir)):
        if name.startswith("roads_") and name.endswith(".gltf"):
            stris += cs.load_tile_triangles(os.path.join(tiles_dir, name))
    sgrid = cs.build_grid(stris)
    btris = cp.barrier_triangles(tiles_dir)
    bgrid = cp.build_grid(btris)
    ends = [u for u in joint_lane_ends(lanes) if u["points"][-1][1] >= MIN_DECK]
    bad = []
    for u in ends:
        a, e = u["points"][-3], u["points"][-1]
        dx, dz = e[0] - a[0], e[2] - a[2]
        n = math.hypot(dx, dz) or 1.0
        d = (dx / n, dz / n)
        side = (-d[1], d[0])
        results = []
        for k in range(-spread // 2, spread // 2 + 1) if spread > 0 else [0]:
            o = k * OFFSET
            start = (e[0] + side[0] * o, e[1], e[2] + side[1] * o)
            results.append((o,) + run_ray(start, d, reach, sgrid, stris, bgrid, btris))
        opened = [r for r in results if r[1] == "open"]
        if opened:
            bad.append((u["id"], e, opened))
        if not quiet:
            print("%-40s (%.0f, %.1f, %.0f): %s" % (u["id"], e[0], e[1], e[2],
                  ", ".join("%+.0f m %s at %.1f m" % (o, kind, at) for (o, kind, at) in results)))
    for (lid, e, opened) in bad:
        print("RUNOFF %s at (%.1f, %.1f, %.1f): %s" % (lid, e[0], e[1], e[2],
              ", ".join("offset %+.0f m leaves the road %.1f m on" % (o, at) for (o, _k, at) in opened)))
    print("%d lane ends at deck joints, %d run off" % (len(ends), len(bad)))
    ok = len(bad) <= max_bad
    print("JOINT_RUNOFF %s" % ("OK" if ok else "FAIL %d" % len(bad)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
