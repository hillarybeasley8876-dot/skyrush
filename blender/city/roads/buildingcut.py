"""Lanes that run through a building of the Bund (and through the drum of the Oriental Pearl).

The Bund unit stands 24 landmark buildings along the west side of the Bund (blender/bund/data.py, a collider box each), and the
city lays its cross streets (Guangdong, Hankou, Jiujiang, Beijing East, the lattice of district D1 ...) to the centre line of
the Bund road, across the row: the dossier leaves gaps for the cross streets, but the streets of the city do not run in them. 70
lanes of the city had a point inside a box, 45 of them movements of the junctions that the buildings hide. A car on such a lane
drives into a facade: the traffic stands pressed against a wall, a rival that is sent through the junction is stopped dead.

A street that runs into a building ends at the building (a dead end, as it does in the picture: the road meets the wall), so the
lanes are cut where they meet a box:

  1. a movement through a junction with a point inside a box is dropped, with its links: the junction is inside the building;
  2. a lane of a street keeps its longest run outside the boxes (the cut end is a dead end of the kind "building"; the cut start
     has no predecessor), and is dropped when less than MIN_KEEP metres are left;
  3. a link to a cut end or from a cut start goes, and a movement that lost one of its two links goes with them, until nothing
     changes.

The surface of the street and its collider stay where they are (they are under the building).
"""
import math

from bund import data as bund

MARGIN = 0.3           # m: a lane this close to a box (or inside it) is cut. A lane that passes a facade nearer than half a car
                       # (0.95 m) is not drivable either, but a street that runs in a gap narrower than itself (Nanjing Rd in its
                       # 15 m gap: the outer lanes are 0.5 m from the walls) is the street of two race routes and stays
MIN_KEEP = 10.0        # m: a lane with less left outside the boxes is dropped
ELEVATED = 6.0         # m: a lane higher than this passes over the buildings (the viaducts)
KIND = "building"      # terminus_kind of a lane that ends at a building
# The drum of the Oriental Pearl (blender/landmarks/build_pearl.py: OPT_ColPodium, a hull of radius POD_R = 50 m and 12 m high at the
# anchor of the landmark): a street of district D7 (st_d7_ew_24) ran through it. (x, z, radius) in game space.
CIRCLES = [(637.5, -634.9, 50.0)]


def footprints():
    """The footprints of the Bund buildings: the frame of every building and its bounding circle (game space)."""
    out = []
    for s in bund.SPECS:
        yaw = bund.facade_yaw(s["z"])
        bx, by = bund.to_blender(s["front_x"], s["z"])
        c, sn = math.cos(yaw), math.sin(yaw)
        w, d = s["frontage"], s["depth"]
        # the middle of the box in game space: local (-d / 2, 0)
        mx = bx + (-d * 0.5) * c
        my = by + (-d * 0.5) * sn
        out.append({"name": s["node"], "bx": bx, "by": by, "c": c, "s": sn, "w": w, "d": d,
                    "cx": mx, "cz": -my, "r": math.hypot(d * 0.5, w * 0.5) + MARGIN})
    return out


def _inside(boxes, x, z):
    """The name of the building whose box (grown by MARGIN) holds the game point, or None."""
    for cx, cz, radius in CIRCLES:
        if math.hypot(x - cx, z - cz) < radius + MARGIN:
            return "circle"
    for f in boxes:
        if abs(x - f["cx"]) > f["r"] or abs(z - f["cz"]) > f["r"]:
            continue
        px, py = x - f["bx"], -z - f["by"]
        lx = px * f["c"] + py * f["s"]
        ly = -px * f["s"] + py * f["c"]
        if -f["d"] - MARGIN < lx < MARGIN and abs(ly) < f["w"] * 0.5 + MARGIN:
            return f["name"]
    return None


def _length(points, i, j):
    return sum(math.dist((points[k][0], points[k][2]), (points[k + 1][0], points[k + 1][2])) for k in range(i, j))


def _longest_outside_run(flags, points):
    """(first, last, length) of the longest run of points that are outside every box, or None."""
    best = None
    i = 0
    while i < len(flags):
        if flags[i]:
            i += 1
            continue
        j = i
        while j + 1 < len(flags) and not flags[j + 1]:
            j += 1
        length = _length(points, i, j)
        if best is None or length > best[2]:
            best = (i, j, length)
        i = j + 1
    return best


def apply(lanes, links):
    """Cuts the lanes at the Bund buildings, in place. Returns the statistics and the metres of lane that every road lost."""
    boxes = footprints()
    deleted = set()          # lane ids that are gone
    cut_start = set()        # the first points of the lane are gone: nothing arrives at it any more
    cut_end = set()          # the last points of the lane are gone: it does not lead anywhere any more
    had_next = {lane["id"] for lane in lanes if lane.get("next")}
    lost_metres = {}         # road id -> metres of its regular lanes that the buildings took
    touched = 0
    for lane in lanes:
        pts = lane["points"]
        if pts[0][1] > ELEVATED and pts[-1][1] > ELEVATED:
            continue
        flags = [_inside(boxes, p[0], p[2]) is not None for p in pts]
        if not any(flags):
            continue
        touched += 1
        if lane.get("connector"):
            deleted.add(lane["id"])
            continue
        whole = _length(pts, 0, len(pts) - 1)
        best = _longest_outside_run(flags, pts)
        if best is None or best[2] < MIN_KEEP:
            deleted.add(lane["id"])
            lost_metres[lane["road"]] = lost_metres.get(lane["road"], 0.0) + whole
            continue
        first, last, kept_length = best
        if first > 0:
            cut_start.add(lane["id"])
        if last < len(pts) - 1:
            cut_end.add(lane["id"])
        lost_metres[lane["road"]] = lost_metres.get(lane["road"], 0.0) + whole - kept_length
        lane["points"] = pts[first:last + 1]
    connectors = {lane["id"] for lane in lanes if lane.get("connector")}
    kept = list(links)
    while True:
        kept = [l for l in kept
                if l["from"] not in deleted and l["from"] not in cut_end
                and l["to"] not in deleted and l["to"] not in cut_start]
        arriving = {l["to"] for l in kept}
        leaving = {l["from"] for l in kept}
        lost = {cid for cid in connectors - deleted if cid not in arriving or cid not in leaving}
        if not lost:
            break
        deleted |= lost
    removed_links = len(links) - len(kept)
    links[:] = kept
    lanes[:] = [lane for lane in lanes if lane["id"] not in deleted]
    successors = {}
    for link in links:
        successors.setdefault(link["from"], []).append(link["to"])
    ended = 0
    for lane in lanes:
        nxt = [n for n in successors.get(lane["id"], []) if n not in deleted]
        lane["next"] = list(dict.fromkeys(nxt))
        if not lane["next"] and (lane["id"] in had_next or lane["id"] in cut_end):
            lane["terminus"] = True
            lane["terminus_kind"] = KIND
            ended += 1
    return ({"touched": touched, "deleted": len(deleted), "cut_start": len(cut_start), "cut_end": len(cut_end),
             "links dropped": removed_links, "dead ends": ended}, lost_metres)
