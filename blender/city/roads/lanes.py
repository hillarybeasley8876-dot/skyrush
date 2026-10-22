"""Lane graph and minimap: game/world/data/lanes.json and minimap.json.

Roads are split into segments at the junctions they pass through and at the
ramp attaches they carry. A segment's lanes run from one kerb return to the
next and keep their design lateral offset.
The junction movements and the ramp attaches are in lane_links.py, the
geometry of a movement in lane_paths.py.
"""
import math

from city.roads import junctions as jn
from city.roads import lane_links, lane_paths, profiles

SAMPLE = 2.0
CUT_GAP = 8.0     # an attach closer than this to another cut shares that cut


def godot(p):
    """A Blender point as a Godot (x, y, z) point."""
    return (round(p.x, 2), round(p.z, 2), round(-p.y, 2))


def segments(city, road):
    """Split a road at the junctions it passes through and at its ramp attaches.

    Every segment remembers the junction at its start and at its end: the lane
    graph needs to know which crossing a lane arrives at and which one it
    leaves.  A ramp attach cuts the road as well: the parent's lane has to end
    (or start) exactly where the ramp's lane does, otherwise the traffic
    cannot leave the viaduct.

    A segment keeps the number of the stretch of road it comes from: the piece
    that ends the stretch keeps it, the pieces in between are numbered after
    the stretches.  The lanes at the crossing that ends the stretch keep their
    ids that way, and with them the ids of the junction movements that name
    them; the crossing at the start of the stretch names the other pieces, so
    its movements get new ids.
    """
    holes = _junction_holes(city, road)
    cuts = _attach_cuts(city, road, holes)
    stretches = _stretches(road, holes)
    out = []
    spare = len(stretches)
    for num, (indices, start_junction, end_junction) in enumerate(stretches):
        pieces = _pieces(indices, cuts)
        for i, piece in enumerate(pieces):
            last = i == len(pieces) - 1
            number = num
            if not last:
                number = spare
                spare += 1
            out.append({"indices": piece,
                        "start": start_junction if i == 0 else None,
                        "end": end_junction if last else None,
                        "number": number})
    if not out or all(len(s["indices"]) < 2 for s in out):
        # a short street between two junctions is all junction: it keeps the
        # middle of its path so the road is still drivable, and its lane does
        # not end on the same spot as the street it meets
        inner = list(range(1, len(road.path) - 1))
        out = [{"indices": inner if len(inner) > 1 else list(range(len(road.path))),
                "start": None, "end": None, "number": 0}]
    _mark_attaches(city, road, out)
    return out


def _mark_attaches(city, road, segs):
    """Mark the segment of the road that meets every ramp attach.

    The marker tells the lane graph which ramp attaches where: the segment
    that ends at the attach, or the one closest to it when the attach lies in
    a junction and the road is cut there already.
    """
    for (pidx, ramp, at_end) in lane_links.attach_stations(city, road):
        best = None
        for seg in segs:
            if not seg["indices"]:
                continue
            last = seg["indices"][-1]
            if last <= pidx and (best is None or last > best[0]):
                best = (last, seg)
        if best is not None:
            best[1]["attach"] = (ramp.id, at_end)


def _junction_holes(city, road):
    """The stretches of a road that a junction takes: [(first, last, junction)]."""
    holes = []
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
            holes.append((run[0], run[-1], junction["id"]))
    holes.sort()
    return holes


def _stretches(road, holes):
    """The stretches of a road between its junctions: [(indices, start, end)]."""
    out = []
    start = 0
    start_junction = None
    for (first, last, jid) in holes:
        if first > start:
            out.append((list(range(start, first)), start_junction, jid))
        start = max(start, last + 1)
        start_junction = jid
    if start < len(road.path):
        out.append((list(range(start, len(road.path))), start_junction, None))
    return out


def _pieces(indices, cuts):
    """The pieces of a stretch of road, cut at the ramp attaches.

    The two pieces of a cut share the path index of the cut, so the lane of
    the first one ends exactly where the lane of the second one starts: the
    traffic drives over the cut without a gap.
    """
    inside = [c for c in cuts if indices[0] < c < indices[-1]]
    bounds = [indices[0]] + inside + [indices[-1]]
    return [list(range(bounds[i], bounds[i + 1] + 1)) for i in range(len(bounds) - 1)]


def _attach_cuts(city, road, holes):
    """The path indices where a ramp attaches to this road.

    An attach that lands on a junction, on the end of the road or too close
    to another cut reuses that cut: a cut of its own would leave a lane of a
    few metres.
    """
    out = []
    for (pidx, _ramp, _at_end) in lane_links.attach_stations(city, road):
        if _on_another_cut(road, pidx, holes):
            continue
        if out and abs(road.dist[pidx] - road.dist[out[-1]]) < CUT_GAP:
            continue
        out.append(pidx)
    return out


def _on_another_cut(road, pidx, holes):
    """True when the road is already cut there (a junction or its end)."""
    s = road.dist[pidx]
    if s < CUT_GAP or road.length - s < CUT_GAP:
        return True
    for (first, last, _jid) in holes:
        if first <= pidx <= last:
            return True
        for b in (first - 1, last + 1):
            if 0 <= b < len(road.path) and abs(road.dist[b] - s) < CUT_GAP:
                return True
    return False


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
            number = seg.get("number", si)
            for side in ("fwd", "back"):
                count = len(lay["lanes"][side])
                for i in range(count):
                    pts = lane_points(road, seg, side, i, lay)
                    if len(pts) < 2:
                        continue
                    lid = "%s_%d_%s%d" % (road.id, number, side, i)
                    lanes.append({
                        "id": lid,
                        "road": road.id,
                        "segment": number,
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
                    index[(road.id, number, side, i)] = lid
    # the movements through the junctions and the ramp attaches
    _link_cuts(city, segs, links, index)
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


def _link_cuts(city, segs, links, index):
    """The traffic of a road carries on over the cuts of its ramp attaches.

    The two halves of a cut share the path index of the cut, so the end of the
    first half and the start of the second half are the same point and the
    traffic drives over the cut without a gap.  The back carriageway is
    travelled against the path order, so there the later half comes first.
    """
    for road in city.roads:
        lay = profiles.layout(road)
        road_segs = segs[road.id]
        for si in range(len(road_segs) - 1):
            a, b = road_segs[si], road_segs[si + 1]
            if not a["indices"] or not b["indices"]:
                continue
            if a["indices"][-1] != b["indices"][0]:
                continue     # a junction: the crossing links the two halves
            for side in ("fwd", "back"):
                for i in range(len(lay["lanes"][side])):
                    first = index.get((road.id, a.get("number", si), side, i))
                    second = index.get((road.id, b.get("number", si + 1), side, i))
                    if first is None or second is None:
                        continue
                    if side == "fwd":
                        links.append({"from": first, "to": second, "turn": "straight"})
                    else:
                        links.append({"from": second, "to": first, "turn": "straight"})


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
