"""city_road — the Road record: plan, height profile, cross-section, style.

A road is authored as plan control points [[x, z], ...] plus height *anchors*.
`build()` turns the plan into a dense Catmull-Rom, re-spaces it into uniform
2 m stations (the control points that go into city.json) and lays a
`city_profile.Profile` on it, so every anchor height is exact and the grade
never exceeds the design limit.

The anchor forms:
    ("s", s, y, g_out)        at the arc length s
    ("p", x, z, y, g_out)     at the plan position nearest to (x, z)
    ("start", y, g_out)       at the first station
    ("end", y, g_out)         at the last station
`g_out` is the grade (rise over run) of the road just after the anchor; it
defaults to 0 (the road is flat there).
"""
import math

import citylib
from city_profile import MAX_GRADE, Profile, ProfileError

CONTROL_STEP = 2.0              # metres between control points


class Road:
    """One road of the city."""

    def __init__(self, rid, name, name_en, kind, plan, anchors, lanes_fwd=2,
                 lanes_back=2, lane_width=3.75, median=1.0, shoulder=0.5,
                 sidewalk=0.0, speed_kmh=60, style=None, attach_start=None,
                 attach_end=None, no_piers=None, pier_spacing=30.0,
                 spline="catmull", notes="", max_grade=MAX_GRADE,
                 start_grade=0.0, one_way=False):
        self.id = rid
        self.name = name
        self.name_en = name_en
        self.kind = kind
        self.plan = [list(p) for p in plan]
        self.anchors = list(anchors)
        self.lanes_fwd = lanes_fwd
        self.lanes_back = lanes_back
        self.lane_width = lane_width
        self.median = median
        self.shoulder = shoulder
        self.sidewalk = sidewalk
        self.speed_kmh = speed_kmh
        self.style = style or {}
        self.attach_start = attach_start
        self.attach_end = attach_end
        self.no_piers = no_piers or []
        self.pier_spacing = pier_spacing
        self.spline = spline
        self.notes = notes
        self.max_grade = max_grade
        self.start_grade = start_grade
        self.one_way = one_way
        self.points = []
        self.dist = []
        self.profile = None

    # ---------------------------------------------------------------- build
    def build(self, step=CONTROL_STEP):
        """Re-space the plan into uniform stations and lay the profile."""
        ctrl = [[p[0], 0.0, p[1]] for p in self.plan]
        if len(ctrl) < 2:
            raise ProfileError("road %s has no plan" % self.id)
        dense = citylib.catmull_rom(ctrl, step)
        stations = citylib.resample(dense, step)
        if math.dist(stations[-1], dense[-1]) < 1e-6:
            stations[-1] = list(dense[-1])
        cum = citylib.cumulative(stations)
        self.points = stations
        self.dist = cum
        keys = self._resolve_anchors(stations, cum)
        self.profile = Profile(keys, max_grade=self.max_grade,
                               start_grade=self.start_grade)
        self.points = [[p[0], self.profile.y(s), p[2]] for p, s in zip(stations, cum)]
        return self

    def _resolve_anchors(self, stations, cum):
        """Turn the authored anchors into (s, y, g_out) keys."""
        out = []
        for anchor in self.anchors:
            kind = anchor[0]
            if kind == "s":
                out.append((float(anchor[1]), float(anchor[2]),
                            float(anchor[3]) if len(anchor) > 3 else 0.0))
            elif kind == "p":
                s = self._s_near(stations, cum, (anchor[1], anchor[2]))
                out.append((s, float(anchor[3]),
                            float(anchor[4]) if len(anchor) > 4 else 0.0))
            elif kind == "near":
                s = self._s_near(stations, cum, (anchor[1], anchor[2]))
                s = min(max(s + float(anchor[3]), 0.0), cum[-1])
                out.append((s, float(anchor[4]),
                            float(anchor[5]) if len(anchor) > 5 else 0.0))
            elif kind == "start":
                out.append((0.0, float(anchor[1]),
                            float(anchor[2]) if len(anchor) > 2 else 0.0))
            elif kind == "end":
                out.append((cum[-1], float(anchor[1]),
                            float(anchor[2]) if len(anchor) > 2 else 0.0))
            else:
                raise ProfileError("unknown anchor %r on %s" % (kind, self.id))
        out.sort(key=lambda a: a[0])
        # the first anchor fixes the start of the road
        if out and out[0][0] > 1e-6:
            raise ProfileError("road %s has no anchor at its start" % self.id)
        return out

    def _s_near(self, stations, cum, target):
        """The arc length of the station closest to the plan position."""
        best, best_s = 1e18, 0.0
        for p, s in zip(stations, cum):
            d = math.hypot(p[0] - target[0], p[2] - target[1])
            if d < best:
                best, best_s = d, s
        return best_s

    # ---------------------------------------------------------------- access
    def get(self, key, default=None):
        return getattr(self, key, default)

    def __getitem__(self, key):
        return getattr(self, key)

    def length(self):
        return self.dist[-1] if self.dist else 0.0

    def point_at(self, s):
        """The centre-line point and tangent at the distance `s`."""
        return citylib.point_at_distance(self.points, s)

    def heading_at(self, s):
        """The heading (degrees, 0 = north) of the centre-line at `s`."""
        _, tan = self.point_at(s)
        return citylib.heading_deg(tan)

    def lane_point(self, s, direction, index=0):
        """The centre of a lane at the distance `s`.

        `direction` is +1 for the forward lanes (the direction of `points`)
        and -1 for the backward lanes.  `index` counts from the median out.
        """
        p, tan = self.point_at(s)
        dx, dz = tan[0], tan[2]
        length = math.hypot(dx, dz) or 1.0
        dx, dz = dx / length, dz / length
        if self.lanes_back == 0:
            # a one-way road is centred on its own centre-line
            off = (index + 0.5 - self.lanes_fwd / 2.0) * self.lane_width
        else:
            side = 1.0 if direction >= 0 else -1.0
            off = side * (self.median * 0.5 + (index + 0.5) * self.lane_width)
        # the right of the travel direction is (-dz, dx)
        return [p[0] - dz * off, p[1], p[2] + dx * off]

    def lane_heading(self, s, direction=1):
        """The heading of a lane at the distance `s`."""
        _, tan = self.point_at(s)
        if direction < 0:
            tan = [-tan[0], tan[1], -tan[2]]
        return citylib.heading_deg(tan)

    def lane_count(self, direction):
        return self.lanes_fwd if direction >= 0 else self.lanes_back

    def to_dict(self):
        """Schema-shaped dictionary for data/city/city.json."""
        out = {
            "id": self.id,
            "name": self.name,
            "name_en": self.name_en,
            "kind": self.kind,
            "points": [[round(p[0], 2), round(p[1], 3), round(p[2], 2)]
                       for p in self.points],
            "spline": self.spline,
            "lanes_fwd": self.lanes_fwd,
            "lanes_back": self.lanes_back,
            "lane_width": self.lane_width,
            "median": self.median,
            "shoulder": self.shoulder,
            "sidewalk": self.sidewalk,
            "speed_kmh": self.speed_kmh,
            "style": self.style,
        }
        if self.attach_start:
            out["attach_start"] = self.attach_start
        if self.attach_end:
            out["attach_end"] = self.attach_end
        if self.no_piers:
            out["no_piers"] = self.no_piers
        if self.kind in ("elevated", "bridge", "ramp"):
            out["pier_spacing"] = self.pier_spacing
        if self.notes:
            out["notes"] = self.notes
        return out
