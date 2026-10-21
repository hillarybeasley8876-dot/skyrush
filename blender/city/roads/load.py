"""Load the city JSON (data/city/SCHEMA.md) and turn it into Blender-space road paths.

Godot coordinates (x east, y up, z south) become Blender (x, -z, y):
X east, +Y north, Z up. The glTF exporter maps them back.
"""
import bisect
import json
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))
from lib import geo  # noqa: E402

ROOT = os.path.expanduser("~/m/skyrush")
CITY_DIR = os.path.join(ROOT, "data", "city")
ELEVATED_KINDS = ("elevated", "ramp", "bridge")
STEP = 2.0          # the lane graph samples every 2 m
GEOM_STEP = 6.0     # the meshes every 6 m (keeps a tile under 400k triangles)
JUNCTION_REACH = 40.0
MERGE_GAP = 10.0        # two junction records closer than this are one crossing


def _cumulative(path):
    out = [0.0]
    for a, b in zip(path, path[1:]):
        out.append(out[-1] + (b - a).length)
    return out


def to_blender(p):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((float(p[0]), -float(p[2]), float(p[1])))


class Road:
    """A parsed road plus its resampled centre-line path (Blender space, 2 m steps)."""

    def __init__(self, data, step=STEP):
        d = self.data = data
        self.id = d["id"]
        self.name = d.get("name", self.id)
        self.name_en = d.get("name_en", "")
        self.kind = d.get("kind", "surface")
        self.lanes_fwd = int(d.get("lanes_fwd", 0))
        self.lanes_back = int(d.get("lanes_back", 0))
        self.lane_width = float(d.get("lane_width", 3.5))
        self.median = float(d.get("median", 0.0))
        self.shoulder = float(d.get("shoulder", 0.5))
        self.sidewalk = float(d.get("sidewalk", 0.0))
        self.speed_kmh = float(d.get("speed_kmh", 60.0))
        self.style = dict(d.get("style") or {})
        self.pier_spacing = float(d.get("pier_spacing", 30.0))
        self.no_piers = [(float(a), float(b)) for a, b in d.get("no_piers", [])]
        self.attach_start = d.get("attach_start")
        self.attach_end = d.get("attach_end")
        self.elevated = self.kind in ELEVATED_KINDS
        if self.kind == "bridge" and self.sidewalk > 0.0:
            # a ground-level street the city file labels "bridge": build it as a street
            self.elevated = False
        self.bridge = self.kind == "bridge" and self.elevated
        self.city = None
        pts = [to_blender(p) for p in d["points"]]
        if d.get("spline", "catmull") == "catmull" and len(pts) > 2:
            lane = geo.catmull_rom(pts, step=step)
        else:
            lane = geo.resample(pts, step)
        # the lane graph samples every 2 m; the meshes every 4 m (the tile tri budget)
        self.lpath = lane
        self.lframes = geo.frames(lane)
        self.ldist = _cumulative(lane)
        self.path = geo.resample(lane, GEOM_STEP)
        self.frames = geo.frames(self.path)
        self.dist = _cumulative(self.path)
        self.length = self.dist[-1]
        self._fine = None

    # -- queries ---------------------------------------------------------
    def at(self, s):
        """(point, tangent, right, up, index) at distance `s` along the centre line."""
        d = self.dist
        if s <= 0.0:
            i = 0
        elif s >= self.length:
            i = len(self.path) - 1
        else:
            i = max(0, min(len(self.path) - 1, bisect.bisect_right(d, s) - 1))
        t, r, u = self.frames[i]
        return self.path[i], t, r, u, i

    def index_at(self, s):
        """Index of the path sample nearest to distance `s`."""
        d = self.dist
        if s <= 0.0:
            return 0
        if s >= self.length:
            return len(self.path) - 1
        return max(0, min(len(self.path) - 1, bisect.bisect_right(d, s) - 1))

    def nearest(self, point):
        """(distance, index) of the closest path sample to a world point."""
        best = 1e18
        idx = 0
        for i, p in enumerate(self.path):
            dd = (p - point).length_squared
            if dd < best:
                best = dd
                idx = i
        return best ** 0.5, idx

    def closest(self, point):
        """(distance, index, t) of the closest point on the path polyline.

        `nearest` only looks at the samples (every 6 m), which is too coarse
        when a pier has to clear another road's carriageway.
        """
        best = (1e18, 0, 0.0)
        for i in range(len(self.path) - 1):
            a = self.path[i]
            ab = self.path[i + 1] - a
            l2 = ab.length_squared
            t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, (point - a).dot(ab) / l2))
            d = (a + ab * t - point).length
            if d < best[0]:
                best = (d, i, t)
        return best

    def project(self, point):
        """(s, z) of the point on the path closest to `point`.

        `s` is the distance along the road and `z` its height there: the exact
        height where a road meets a junction, not the height of the nearest
        6 m sample.
        """
        _dist, idx, t = self.closest(point)
        seg = self.dist[idx + 1] - self.dist[idx]
        s = self.dist[idx] + t * seg
        z = self.path[idx].z + (self.path[idx + 1].z - self.path[idx].z) * t
        return s, z

    def first_beyond(self, s):
        """The index of the first path sample further than `s` along the road."""
        for i, d in enumerate(self.dist):
            if d > s:
                return i
        return len(self.path) - 1

    def last_before(self, s):
        """The index of the last path sample closer than `s` to the start."""
        best = 0
        for i, d in enumerate(self.dist):
            if d < s:
                best = i
        return best

    def pier_allowed(self, s):
        """False inside a declared no-pier stretch."""
        return not any(a <= s <= b for a, b in self.no_piers)

    def fine(self, step=0.5):
        """A finer resampling of the centre line: [(point, right, distance)].

        The right vectors are interpolated from the road's own frames so the
        markings stay glued to the asphalt strip.
        """
        if self._fine is not None:
            return self._fine
        out = []
        count = int(self.length / step)
        for k in range(count + 1):
            d = min(k * step, self.length)
            i = self.index_at(d)
            j = min(i + 1, len(self.path) - 1)
            seg = self.dist[j] - self.dist[i]
            t = 0.0 if seg <= 1e-6 else (d - self.dist[i]) / seg
            p = self.path[i].lerp(self.path[j], t)
            r = self.frames[i][1].lerp(self.frames[j][1], t)
            if r.length > 1e-6:
                r.normalize()
            out.append((p, r, d))
        self._fine = out
        return out

    def lane_slice(self, idx):
        """(points, right vectors, distances) of the 2 m lane path for the given indices."""
        pts = [self.lpath[i] for i in idx]
        rights = [self.lframes[i][1] for i in idx]
        dists = [self.ldist[i] for i in idx]
        return pts, rights, dists


ALIGN_SPAN = 40.0       # the metres over which a ramp is shifted onto its parent


ATTACH_SEPARATION = 15.0    # two ramps of one junction must not land on the same spot


def align_attaches(city, span=ALIGN_SPAN):
    """Shift every ramp sideways so its inner edge meets the parent's outer edge.

    The city file places a ramp's end on the parent's centre line, so without
    this the ramp's asphalt, girder and parapets cross the parent's lanes.
    The attach is found by projecting the ramp's end onto the parent, not by
    the `at` distance, which can be hundreds of metres off.
    """
    from city.roads import profiles
    used = {}
    for road in city.roads:
        if road.kind != "ramp":
            continue
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            attach = road.data.get(key)
            parent = city.by_id.get(attach["road"]) if attach else None
            if parent is None:
                continue
            _align_end(city, road, parent, at_end, span, profiles,
                        str(attach.get("side", "right")), used)


def _align_end(city, road, parent, at_end, span, profiles, side="right", used=None):
    """Move a ramp's last `span` metres so it lands on the parent's outer edge.

    The ramp's inner edge has to meet the parent's outer edge, so the ramp's
    centre line ends up one full width out from the parent's centre line.
    """
    idx = len(road.path) - 1 if at_end else 0
    end = road.path[idx]
    _dist, pidx = parent.nearest(end)
    p_pt = parent.path[pidx]
    p_r = parent.frames[pidx][1]
    p_t = parent.frames[pidx][0]
    parent_half = profiles.layout(parent)["asphalt_half"]
    ramp_half = profiles.layout(road)["asphalt_half"]
    sign = 1.0 if side == "right" else -1.0
    current = (end - p_pt).dot(p_r)
    lateral = sign * (parent_half + ramp_half) - current
    # the ramp's end is projected onto the parent: the `at` distance of the city
    # file can be hundreds of metres off, and the ramp has to meet the parent
    # where it really is
    along = 0.0
    key = (parent.id, side, round(parent.dist[pidx] + along, 1))
    if used is not None:
        n = used.get(key, 0)
        used[key] = n + 1
        along += n * ATTACH_SEPARATION
    shift = p_r * lateral + p_t * along
    if shift.length < 0.01:
        return
    for k in range(len(road.path)):
        d = (road.length - road.dist[k]) if at_end else road.dist[k]
        w = max(0.0, min(1.0, (span - d) / span))
        w = w * w * (3.0 - 2.0 * w)
        road.path[k] = road.path[k] + shift * w
    road.frames = geo.frames(road.path)
    road.dist = _cumulative(road.path)
    road.length = road.dist[-1]
    road._fine = None


class City:
    """The parsed city: roads, junctions, water and blocks."""

    def __init__(self, data, path=""):
        self.data = data
        self.path = path
        self.name = data.get("name", "city")
        self.window = data.get("window", {})
        seen_ids = set()
        self.roads = []
        for raw in data.get("roads", []):
            road = Road(raw)
            if road.id in seen_ids:
                # the city file has a duplicated road id: keep the first one
                continue
            seen_ids.add(road.id)
            self.roads.append(road)
        for road in self.roads:
            road.city = self
        self._drop_duplicate_links()
        self.junctions = list(data.get("junctions", []))
        self.water = list(data.get("water", []))
        self.blocks = list(data.get("blocks", []))
        self.by_id = {r.id: r for r in self.roads}
        align_attaches(self)
        self._merge_junctions()

    def _drop_duplicate_links(self):
        """Remove the roads that duplicate another road in the opposite direction.

        The city file has "link" roads that run along an existing street the
        other way: their kerbs, markings and lanes would be drawn twice on the
        same asphalt.
        """
        drop = set()
        for road in self.roads:
            if not (road.id.startswith("st_link") or road.id.startswith("link")):
                continue
            if len(road.path) < 2:
                continue
            for other in self.roads:
                if other is road or len(other.path) < 2:
                    continue
                # the link runs along a street that is already there
                near = min((road.path[0] - other.path[0]).length,
                           (road.path[0] - other.path[-1]).length,
                           (road.path[-1] - other.path[0]).length,
                           (road.path[-1] - other.path[-1]).length)
                if near > 30.0:
                    continue
                inside = 0
                for p in road.path:
                    if other.closest(p)[0] < 2.5:
                        inside += 1
                if inside >= 0.8 * len(road.path):
                    drop.add(road.id)
                    break
        if not drop:
            return
        self.roads = [r for r in self.roads if r.id not in drop]
        print("ROADS dropped %d duplicate link roads" % len(drop))

    def _merge_junctions(self):
        """Merge the junction records that describe the same crossing.

        The city file lists every pair of arms as its own junction, so one
        crossing can have three records a few metres apart. Every record draws
        its own kerb returns, so the carriageway ends up with three sets of
        kerb arcs lying on it. The records that are closer than the sum of
        their half widths (plus 10 m) become one junction.
        """
        merged = []
        for junction in self.junctions:
            centre = Vector((float(junction["x"]), -float(junction["z"]), 0.0))
            half = self._junction_half(junction)
            target = None
            for other in merged:
                gap = (other["_centre"] - centre).length
                if gap < other["_half"] + half + MERGE_GAP:
                    target = other
                    break
            if target is None:
                junction = dict(junction)
                junction["_centre"] = centre
                junction["_half"] = half
                merged.append(junction)
                continue
            roads = list(target.get("roads", []))
            for rid in junction.get("roads", []):
                if rid not in roads:
                    roads.append(rid)
            target["roads"] = roads
            target["_half"] = max(target["_half"], half)
            target["_centre"] = (target["_centre"] + centre) * 0.5
            target["x"] = round(target["_centre"].x, 2)
            target["z"] = round(-target["_centre"].y, 2)
        for junction in merged:
            junction.pop("_centre", None)
            junction.pop("_half", None)
        if len(merged) != len(self.junctions):
            print("JUNCTIONS merged %d records into %d" % (len(self.junctions), len(merged)))
        self.junctions = merged

    def _junction_half(self, junction):
        """The half width of a junction: the widest road that meets there."""
        half = 0.0
        for rid in junction.get("roads", []):
            road = self.by_id.get(rid)
            if road is None:
                continue
            half = max(half, road.lanes_fwd * road.lane_width * 0.5
                       + road.lanes_back * road.lane_width * 0.5 + road.median * 0.5)
        return half

    def junction_centre(self, junction):
        """Junction centre in Blender space."""
        return Vector((float(junction["x"]), -float(junction["z"]), 0.0))

    def junction_arms(self, junction):
        """Roads that meet at this junction, with their half widths."""
        arms = []
        centre = self.junction_centre(junction)
        for rid in junction.get("roads", []):
            road = self.by_id.get(rid)
            if road is None:
                continue
            dist, idx = road.nearest(centre)
            if dist > JUNCTION_REACH:
                continue
            arms.append((road, idx, dist))
        return arms

    def junctions_of(self, road):
        """Junctions whose `roads` list mentions this road."""
        return [j for j in self.junctions if road.id in j.get("roads", [])]


def load(path=None):
    """Load a city file; defaults to city.json when it exists, else test_city.json."""
    if path is None:
        real = os.path.join(CITY_DIR, "city.json")
        path = real if os.path.exists(real) else os.path.join(CITY_DIR, "test_city.json")
    with open(path) as fh:
        return City(json.load(fh), path), path
