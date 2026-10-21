"""Lane graph and minimap: game/world/data/lanes.json and minimap.json.

Roads are split into segments at the junctions they pass through. A segment's
lanes run from one kerb return to the next and keep their design lateral offset.
The junction movements and the ramp attaches are in lane_links.py, the
geometry of a movement in lane_paths.py.
"""
import math

from city.roads import junctions as jn
from city.roads import lane_links, lane_paths, profiles

SAMPLE = 2.0


def godot(p):
    """A Blender point as a Godot (x, y, z) point."""
    return (round(p.x, 2), round(p.z, 2), round(-p.y, 2))


def segments(city, road):
    """Split a road at the junctions it passes through (the junction stretches are cut).

    Every segment remembers the junction at its start and at its end: the lane
    graph needs to know which crossing a lane arrives at and which one it
    leaves.
    """
    cuts = []
    for junction in city.junctions_of(road):
        inside = jn.trim_indices(city, road, junction, road.path)
        if not inside:
            continue
        runs = []
        cur = []
        for i in sorted(inside):
            if cur and i == cur[-1] + 1:
                cur.append(i)
            else:
                if cur:
                    runs.append(cur)
                cur = [i]
        if cur:
            runs.append(cur)
        for run in runs:
            cuts.append((run[0], run[-1], junction["id"]))
    cuts.sort()
    out = []
    start = 0
    start_junction = None
    for (first, last, jid) in cuts:
        if first > start:
            out.append({"indices": list(range(start, first)),
                        "start": start_junction, "end": jid})
        start = max(start, last + 1)
        start_junction = jid
    if start < len(road.path):
        out.append({"indices": list(range(start, len(road.path))),
                    "start": start_junction, "end": None})
    if not out or all(len(s["indices"]) < 2 for s in out):
        # a short street between two junctions is all junction: it keeps the
        # middle of its path so the road is still drivable, and its lane does
        # not end on the same spot as the street it meets
        inner = list(range(1, len(road.path) - 1))
        out = [{"indices": inner if len(inner) > 1 else list(range(len(road.path))),
                "start": None, "end": None}]
    return out


def lane_points(road, seg, side, index, lay):
    """Polyline of one lane in Godot space, on the road's own path."""
    lanes = lay["lanes"][side]
    if index >= len(lanes):
        return []
    centre = (lanes[index][0] + lanes[index][1]) * 0.5
    pts = []
    for i in seg["indices"]:
        p = road.path[i]
        r = road.frames[i][1]
        q = p + r * centre
        pts.append(godot(q))
    if side == "back":
        pts.reverse()   # the back carriageway is travelled against the path order
    return lane_paths.resample(pts)


def build_lanes(city):
    """Lane graph: {lanes: [...], links: [...]}."""
    lanes = []
    links = []
    index = {}
    segs = {}
    for road in city.roads:
        lay = profiles.layout(road)
        segs[road.id] = segments(city, road)
        for si, seg in enumerate(segs[road.id]):
            for side in ("fwd", "back"):
                count = len(lay["lanes"][side])
                for i in range(count):
                    pts = lane_points(road, seg, side, i, lay)
                    if len(pts) < 2:
                        continue
                    lid = "%s_%d_%s%d" % (road.id, si, side, i)
                    lanes.append({
                        "id": lid,
                        "road": road.id,
                        "segment": si,
                        "dir": 1 if side == "fwd" else -1,
                        "index": i,
                        "leftmost": i == 0,
                        "rightmost": i == count - 1,
                        "offset": round((lay["lanes"][side][i][0]
                                         + lay["lanes"][side][i][1]) * 0.5, 2),
                        "width": road.lane_width,
                        "speed_kmh": road.speed_kmh,
                        "elevated": road.elevated,
                        "points": pts,
                        # the back carriageway is travelled against the path
                        # order, so its ends are the other way round
                        "start_junction": seg.get("start") if side == "fwd" else seg.get("end"),
                        "end_junction": seg.get("end") if side == "fwd" else seg.get("start"),
                        "next": [],
                    })
                    index[(road.id, si, side, i)] = lid
    # the movements through the junctions and the ramp attaches
    lane_links.link_junctions(city, lanes, links)
    lane_links.link_attaches(city, lanes, segs, links)
    lanes.sort(key=lambda l: l["id"])
    by_id = {lane["id"]: lane for lane in lanes}
    for link in links:
        lane = by_id.get(link["from"])
        if lane is not None and link["to"] not in lane["next"]:
            lane["next"].append(link["to"])
    _mark_termini(city, lanes)
    if lane_links.SKIPPED:
        top = sorted(lane_links.SKIPPED.items(), key=lambda kv: -kv[1])[:8]
        print("LANES %d movements skipped: %s" % (sum(lane_links.SKIPPED.values()), top))
    return {"version": 1, "lanes": lanes, "links": links, "roads": _road_stats(city, lanes)}


def _road_stats(city, lanes):
    """Per road: the length, the metres the lanes cover and the junction trims."""
    covered = {}
    for lane in lanes:
        if lane.get("connector"):
            continue
        pts = lane["points"]
        for a, b in zip(pts, pts[1:]):
            covered[lane["road"]] = covered.get(lane["road"], 0.0) + math.dist(a, b)
    out = {}
    for road in city.roads:
        length = road.length
        cov = covered.get(road.id, 0.0)
        out[road.id] = {"length": round(length, 1), "covered": round(cov, 1),
                        "trimmed": round(max(0.0, length - cov), 1)}
    return out


def _mark_termini(city, lanes):
    """Flag the lanes that end somewhere: at a junction (a T) or at the map edge.

    A road that ends at a crossing (a T) has no movement: its last lane is the
    end of the network, not a dead end in the middle of it.
    """
    junctions = city.junctions
    for lane in lanes:
        if lane["next"]:
            continue
        end = lane["points"][-1]
        best = min(junctions, key=lambda j: math.hypot(end[0] - j["x"], end[2] - j["z"]),
                   default=None)
        near = best is not None and math.hypot(end[0] - best["x"], end[2] - best["z"]) < 30.0
        lane["terminus"] = True
        if near and not _road_ends_there(city, lane, end):
            lane["terminus_kind"] = "junction"
        else:
            lane["terminus_kind"] = "map_edge"


def _road_ends_there(city, lane, end):
    """True when the lane ends at the end of its road (the edge of the network)."""
    road = city.by_id.get(lane["road"])
    if road is None or not road.path:
        return False
    for p in (road.path[0], road.path[-1]):
        if math.hypot(end[0] - p.x, end[2] + p.y) < 15.0:
            return True
    return False


def connector_points(lane_data):
    """Every point of every connector lane (the movements through a junction).

    A pier may not stand in one of them: the turning paths of a junction are
    the widest part of the drivable area.
    """
    out = []
    for lane in lane_data.get("lanes", []):
        if not lane.get("connector"):
            continue
        for p in lane.get("points", []):
            out.append((float(p[0]), -float(p[2])))   # Blender space
    return out


def build_minimap(city):
    """Minimap geometry: {roads: [{id, kind, width, points}]}."""
    out = []
    for road in city.roads:
        lay = profiles.layout(road)
        pts = [[round(p.x, 1), round(-p.y, 1)] for p in road.path]
        out.append({"id": road.id, "kind": road.kind, "name": road.name,
                    "name_en": road.name_en, "width": round(lay["asphalt_half"] * 2.0, 2),
                    "elevated": road.elevated, "points": pts})
    return {"version": 1, "roads": out}
