"""city_rules_attach — how the ramps, the decks and the junctions fit together.

The rules:
  * every ramp attaches to its parent on the *edge of the carriageway it
    serves*, at the parent's height and along the parent's direction;
  * a deck that crosses a road leaves 5.5 m under it plus the depth of
    the structure above (dossier 2.1 / 1.3 / 3.2);
  * the junctions really meet their roads.
"""
import math

import citylib
from city_rules import (_angle_diff, deck_depth,
                        GORE, CLEARANCE, TUNNEL_CLEARANCE, PLAN_TOLERANCE,
                        HEIGHT_TOLERANCE, TANGENT_TOLERANCE)


def road_points(road):
    """The centre-line of a road as a list of (x, y, z)."""
    return [tuple(p) for p in road["points"]]


def plan(road):
    """The centre-line of a road as a list of (x, z)."""
    return [(p[0], p[2]) for p in road["points"]]


def _height_at(road, x, z):
    """The height of a road at the plan position (x, z)."""
    pts = road["points"]
    best, best_y = 1e18, 0.0
    for p in pts:
        d = (p[0] - x) ** 2 + (p[2] - z) ** 2
        if d < best:
            best, best_y = d, p[1]
    return best_y


def _sample_road(road, step=5.0):
    """The road's points every `step` metres."""
    out = []
    acc = 0.0
    prev = None
    for p in road["points"]:
        if prev is not None:
            acc += math.dist(prev, p)
        prev = p
        if acc >= step:
            out.append(p)
            acc = 0.0
    out.append(road["points"][-1])
    return out


def _heading(tan):
    """The heading of a 2D tangent (dx, dz) or a 3D one."""
    dx, dz = tan[0], tan[2] if len(tan) > 2 else tan[1]
    return math.degrees(math.atan2(dx, -dz)) % 360.0


def _within(city, radius, skip=()):
    """The roads whose centre-line comes within `radius` of a point."""
    index = city.setdefault("_index", None)
    if index is None:
        index = citylib.PolyIndex()
        for road in city["roads"]:
            index.add(road["id"], plan(road))
        city["_index"] = index
    return index


# ---------------------------------------------------------------- rules



def _junction_at(city, x, z, radius=40.0, roads=None):
    """The junction at the plan position, if there is one.

    With `roads` the junction must list all of them.
    """
    for j in city["junctions"]:
        if math.hypot(j["x"] - x, j["z"] - z) > radius:
            continue
        if roads and not all(r in j["roads"] for r in roads):
            continue
        return j
    return None


def _attach_gore(road, other, point):
    """True when the point is inside the attach gore of the pair."""
    for owner in (road, other):
        for key in ("attach_start", "attach_end"):
            att = owner.get(key)
            if not att:
                continue
            if att["road"] not in (road["id"], other["id"]):
                continue
            parent = road if att["road"] == road["id"] else other
            anchor, _tan = _point_at(parent, att["at"])
            if anchor and math.hypot(point[0] - anchor[0],
                                     point[2] - anchor[1]) <= GORE:
                return True
    return False


def _point_at(road, s):
    """The point at the distance `s` along a road (x, z) and its tangent."""
    pts = road["points"]
    acc = 0.0
    for a, b in zip(pts, pts[1:]):
        run = math.hypot(b[0] - a[0], b[2] - a[2])
        if acc + run >= s:
            t = (s - acc) / run if run > 1e-9 else 0.0
            return (a[0] + t * (b[0] - a[0]), a[2] + t * (b[2] - a[2])), \
                (b[0] - a[0], b[2] - a[2])
        acc += run
    a, b = pts[-2], pts[-1]
    return (b[0], b[2]), (b[0] - a[0], b[2] - a[2])


def _gore(road, other, station):
    """True when the station of the road is in the attach gore of the pair.

    A ramp leaves its parent at the parent's height and climbs away from
    the deck, so the first GORE metres of the ramp are exempt.
    """
    for key, at_start in (("attach_start", True), ("attach_end", False)):
        att = road.get(key)
        if not att or att["road"] != other["id"]:
            continue
        length = road["_length"]
        d = station if at_start else length - station
        if d <= GORE:
            return True
    return False


def _exempt(city, road, other, point, road_w, other_w):
    """The exemptions of the clearance rule: the attach gore and the
    junctions of the surface network.

    Two surface roads that meet at a declared junction cross there: the
    junction *is* the intersection, so the at-grade overlap is allowed
    wherever the two roads have a junction.  A deck over a street is only
    allowed at the junction itself.
    """
    if _attach_gore(road, other, point):
        return True
    if road["kind"] == "surface" and other["kind"] == "surface":
        return _junction_exempt(city, road, other, point, road_w, other_w)
    junction = _junction_at(city, point[0], point[2], 40.0,
                             (road["id"], other["id"]))
    if junction:
        # a deck that is still at grade crosses the street at grade
        if abs(_height_at(road, point[0], point[2])) < 1.0 or \
                abs(_height_at(other, point[0], point[2])) < 1.0:
            return True
    return False


def _junction_pair(city, road_id, other_id):
    """The junctions that list both roads."""
    for j in city["junctions"]:
        if road_id in j["roads"] and other_id in j["roads"]:
            return j
    return None


def _junction_exempt(city, road, other, point, road_w, other_w):
    """True if the point is at a junction of the two roads.

    The exemption is local: it only covers the junction itself, not the
    whole stretch where the two roads happen to run beside each other.
    """
    j = _junction_pair(city, road["id"], other["id"])
    if j is None:
        return False
    reach = road_w * 0.5 + other_w * 0.5 + 10.0
    return math.hypot(point[0] - j["x"], point[2] - j["z"]) <= reach


def check_clearance(city):
    """The decks clear the roads under them (dossier 2.1 / 1.3 / 3.2).

    A deck that crosses a road has to leave 5.5 m under it plus the depth
    of the structure above; two roads at the same level may only overlap
    at a junction.  The failures are listed one line per road pair, with
    the number of samples, the worst value and the place.
    """
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    index = _within(city, 0)
    seen = set()
    pairs = {}
    for road in city["roads"]:
        width = citylib.road_width(road)
        pts = citylib.road_points(road, 2.0)
        cum = citylib.cumulative(pts)
        road["_length"] = cum[-1]
        for i, p in enumerate(pts):
            for name, _idx, q in index.within((p[0], p[2]), width * 0.5 + 40.0):
                if name == road["id"]:
                    continue
                other = by_id[name]
                other_w = citylib.road_width(other)
                if math.hypot(p[0] - q[0], p[2] - q[1]) > width * 0.5 + other_w * 0.5:
                    continue
                oy = _height_at(other, p[0], p[2])
                gap = p[1] - oy
                if abs(gap) < 1.0:
                    # two roads at the same level: an at-grade crossing
                    need = 0.0
                else:
                    upper = road if gap > 0 else other
                    if road["kind"] == "tunnel" or other["kind"] == "tunnel":
                        need = TUNNEL_CLEARANCE
                    else:
                        need = CLEARANCE + deck_depth(upper)
                if abs(gap) >= need - 0.05:
                    continue
                if _gore(road, other, cum[i]):
                    continue
                if _exempt(city, road, other, p, width, other_w):
                    continue
                key = (road["id"], other["id"], round(p[0] / 20.0),
                       round(p[2] / 20.0))
                if key in seen:
                    continue
                seen.add(key)
                pair = (road["id"], other["id"])
                if pair not in pairs:
                    pairs[pair] = [0, gap, need, p[0], p[2]]
                pairs[pair][0] += 1
                if abs(gap) < abs(pairs[pair][1]):
                    pairs[pair][1] = gap
                    pairs[pair][2] = need
                    pairs[pair][3] = p[0]
                    pairs[pair][4] = p[2]
    for pair, (count, gap, need, x, z) in sorted(pairs.items(),
                                                 key=lambda kv: kv[1][1]):
        fails.append("%s x %s: %d samples, worst %.1f m (need %.1f) at "
                     "(%.0f, %.0f)" % (pair[0], pair[1], count, gap, need, x, z))
    return fails


def check_attaches(city):
    """The ramps attach to their parents on the centre-line (review r1 A.4).

    The plan error is the distance from the ramp's end to the parent's
    centre-line, the height error the difference to the parent's height there
    and the tangent error the angle between the two directions.  The tangent
    rule only applies to the ramps: the end to end links of two surface
    roads meet at a crossroads, where the angle is the junction's business.
    """
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    for road in city["roads"]:
        for key, idx in (("attach_start", 0), ("attach_end", -1)):
            att = road.get(key)
            if not att:
                continue
            parent = by_id.get(att["road"])
            if parent is None:
                fails.append("%s %s names the unknown road %s"
                             % (road["id"], key, att["road"]))
                continue
            cp = road["points"][idx]
            plan_err, tan, parent_y = _closest_on(parent, cp)
            height_err = abs(cp[1] - parent_y)
            ct = _direction(road, idx)
            tan_err = min(_angle_diff(_heading(ct), _heading(tan)),
                          _angle_diff(_heading(ct), _heading(tan) + 180.0))
            if plan_err > PLAN_TOLERANCE + 1e-6:
                fails.append("%s %s: %.2f m off the parent"
                             % (road["id"], key, plan_err))
            if height_err > HEIGHT_TOLERANCE + 1e-6:
                fails.append("%s %s: %.2f m height error"
                             % (road["id"], key, height_err))
            if road["kind"] == "ramp" and tan_err > TANGENT_TOLERANCE:
                fails.append("%s %s: %.1f deg tangent error"
                             % (road["id"], key, tan_err))
    return fails


def _closest_on(road, point):
    """The point of a road closest to a 3D point: the distance, the tangent
    (over 10 m) and the height there."""
    pts = road["points"]
    best, best_i = 1e18, 0
    for i, p in enumerate(pts):
        d = (p[0] - point[0]) ** 2 + (p[2] - point[2]) ** 2
        if d < best:
            best, best_i = d, i
    i = best_i
    a = pts[max(0, i - 2)]
    b = pts[min(len(pts) - 1, i + 2)]
    tan = (b[0] - a[0], b[2] - a[2])
    dist = 1e18
    for j in (i - 1, i):
        if 0 <= j < len(pts) - 1:
            dist = min(dist, citylib.point_seg_distance(
                (point[0], point[2]), (pts[j][0], pts[j][2]),
                (pts[j + 1][0], pts[j + 1][2])))
    return dist, tan, pts[i][1]


def _direction(road, idx):
    """The direction of a road at its first or last point (over 10 m)."""
    pts = road["points"]
    if idx == 0:
        a, b = pts[0], pts[min(len(pts) - 1, 2)]
    else:
        a, b = pts[max(0, len(pts) - 3)], pts[-1]
    return (b[0] - a[0], b[2] - a[2])


def check_junctions(city):
    """Every junction really joins the roads it lists."""
    fails = []
    by_id = {r["id"]: r for r in city["roads"]}
    for j in city["junctions"]:
        for rid in j["roads"]:
            road = by_id.get(rid)
            if road is None:
                fails.append("junction %s lists the unknown road %s"
                             % (j["id"], rid))
                continue
            best = 1e18
            for p in road["points"]:
                d = math.hypot(p[0] - j["x"], p[2] - j["z"])
                if d < best:
                    best = d
            if best > 40.0:
                fails.append("junction %s: %s is %.0f m away"
                             % (j["id"], rid, best))
    return fails
