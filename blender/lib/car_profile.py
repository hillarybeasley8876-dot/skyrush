"""Side profile, plan and section rows of an NPC car (core-owned, used by lib/car_body.py).

Same semantics as npc_cars/profile.py (top surface = monotone cubic through the feature rows,
belt line, floor, plan with rounded corners, quadrilateral daylight opening), plus the station list
and the 12-row half section of the subdivision cage:

     0 bottom centre   1 floor edge    2 rocker       3 lower side   4 side max   5 shoulder
     6 belt            7 DLO bottom    8 DLO top      9 roof edge   10 roof shoulder  11 top centre
"""
import math

RAIL_H = 0.045        # roof rail: glass top to the roof edge
PILLAR_H = 0.075      # A / C pillar band: glass top to the screen edge
CABIN_RAIL = 0.028    # rail band where there is no pillar
MIN_GAP = 0.004
ROOF_CROWN = 0.03
SAIL = 0.10           # mirror sail: cowl to the front tip of the side glass


def _pchip(keys):
    """Monotone cubic Hermite (Fritsch-Carlson) through (y, z) keys sorted by y -> f(y)."""
    xs, zs = [k[0] for k in keys], [k[1] for k in keys]
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(zs[i + 1] - zs[i]) / h[i] for i in range(n - 1)]
    m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0.0:
            w1, w2 = 2.0 * h[i] + h[i - 1], h[i] + 2.0 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(y):
        if y <= xs[0]:
            return zs[0]
        if y >= xs[-1]:
            return zs[-1]
        lo = max(i for i in range(n - 1) if xs[i] <= y)
        hh = xs[lo + 1] - xs[lo]
        t = (y - xs[lo]) / hh
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * zs[lo] + (t3 - 2 * t2 + t) * hh * m[lo]
                + (-2 * t3 + 3 * t2) * zs[lo + 1] + (t3 - t2) * hh * m[lo + 1])
    return f


def _lerp(a, b, t):
    return a + (b - a) * t


def _clamp01(t):
    return min(max(t, 0.0), 1.0)


class Profile:
    def __init__(self, p):
        self.p = p
        self.nose, self.tail = p["L"] * 0.5, -p["L"] * 0.5
        keys = [(self.tail, p["tail_z"]), (p["deck_y"], p["deck_z"]),
                (p["roof_rear_y"], p["roof_z"] - p.get("roof_drop", 0.0))]
        crown = p.get("crown_y")
        if crown is not None and p["roof_rear_y"] < crown < p["roof_front_y"]:
            keys.append((crown, p["roof_z"]))
        keys += [(p["roof_front_y"], p["roof_z"]), (p["cowl_y"], p["hood_z"]), (self.nose, p["nose_z"])]
        self.top_z = _pchip(keys)
        doors = p.get("doors") or []
        # the side glass starts a little behind the cowl: the gap is the black mirror sail, and the
        # glass tip does not fall on the windscreen station (that made a hook after subdivision)
        self.front = p.get("dlo_front") or p["cowl_y"] - SAIL
        if len(doors) > 1:
            rear = doors[1][0] - 0.03
        elif doors:
            rear = doors[0][0] - 0.03
        else:
            rear = p["deck_y"] + 0.30
        self.rear = p.get("dlo_rear") or rear
        self.rail_end = p.get("dlo_rail_end") or p["roof_rear_y"]
        self.b_pillar = (doors[1][1], doors[0][0]) if len(doors) > 1 else None

    # --- profile functions (npc_cars/profile.py semantics) -------------------------------------
    def belt_z(self, y):
        p = self.p
        b = _lerp(p["belt_front"], p["belt_rear"], (self.nose - y) / p["L"])
        return min(b, self.top_z(y) - 0.06)

    def floor_z(self, y):
        d = abs(y) - (self.p["L"] * 0.5 - 0.60)
        return self.p["clear"] + (d * d * 0.5 if d > 0.0 else 0.0)

    def half_width(self, y):
        p = self.p
        hw = p["W"] * 0.5
        for r, end, sgn in ((p["rc_front"], self.nose, 1.0), (p["rc_rear"], self.tail, -1.0)):
            d = (y - (end - sgn * r)) * sgn
            if d > 0.0:
                hw = min(hw, hw - r + math.sqrt(max(0.0, r * r - d * d)))
        return hw

    def dlo_rows(self, y):
        """(z_bottom, z_top) of the daylight opening at y, or None outside it."""
        p = self.p
        if y >= self.front or y <= self.rail_end:
            return None
        if y >= p["roof_front_y"]:
            t = (self.front - y) / max(1e-6, self.front - p["roof_front_y"])
            z_top = _lerp(self.belt_z(self.front), self.top_z(p["roof_front_y"]) - RAIL_H, t)
        else:
            z_top = self.top_z(y) - RAIL_H
        if y < self.rear:
            t = (self.rear - y) / max(1e-6, self.rear - self.rail_end)
            z_bot = _lerp(self.belt_z(self.rear), self.top_z(self.rail_end) - RAIL_H, t)
        else:
            z_bot = self.belt_z(y)
        return z_bot, z_top

    # --- material regions ---------------------------------------------------------------------
    def in_dlo(self, y):
        return self.rail_end < y < self.front

    def in_b_pillar(self, y):
        return self.b_pillar is not None and self.b_pillar[0] < y < self.b_pillar[1]

    def in_sail(self, y):
        return self.front < y < self.p["cowl_y"]

    def in_top_glass(self, y):
        p = self.p
        if p.get("wrap"):
            return p["deck_y"] < y < p["cowl_y"]
        return p["roof_front_y"] < y < p["cowl_y"] or p["deck_y"] < y < p["roof_rear_y"]

    def glass_stations(self):
        p = self.p
        return [round(p[k], 6) for k in ("cowl_y", "roof_front_y", "roof_rear_y", "deck_y")]

    # --- cage ---------------------------------------------------------------------------------
    def stations(self, max_step):
        """Station list nose -> tail: every boundary is a station, gaps filled to <= max_step."""
        p = self.p
        nose, tail = self.nose - 0.05, self.tail + 0.05     # the inset caps add the last 5 cm
        must = [nose, tail, p["cowl_y"], p["roof_front_y"], p["roof_rear_y"], p["deck_y"],
                self.front, self.rear, self.rail_end] + list(self.b_pillar or ())
        extra = [p["crown_y"]] if p.get("crown_y") is not None else []
        for r, end, sgn in ((p["rc_front"], nose, -1.0), (p["rc_rear"], tail, 1.0)):
            extra += [end + sgn * r * (1.0 - math.cos(k * math.pi / 6.0)) for k in (1, 2, 3)]
        kept = sorted({round(y, 6) for y in must if tail <= y <= nose}, reverse=True)
        for y in extra:   # optional stations only where they do not crowd a boundary
            if tail < y < nose and all(abs(y - k) > 0.02 for k in kept):
                kept.append(y)
        kept.sort(reverse=True)
        out = [kept[0]]
        for y in kept[1:]:
            n = max(1, math.ceil((out[-1] - y) / max_step))
            out += [_lerp(out[-1], y, i / n) for i in range(1, n)] + [y]
        return out

    def rows(self, y):
        """The 12 (x, z) points of the half section at y (see the module docstring)."""
        p = self.p
        hw, zf, zb, zt = self.half_width(y), self.floor_z(y), self.belt_z(y), self.top_z(y)
        zs = zf + 0.16
        belt_hw = hw * 0.958
        g = _clamp01((zt - zb - 0.06) / 0.30)               # 0 over the bonnet .. 1 under the roof
        roof_hw = max(0.30, belt_hw - p["tumble"] * (0.15 + 0.85 * g))
        z_corner = zt - ROOF_CROWN

        def x_at(z):
            return _lerp(belt_hw, roof_hw, _clamp01((z - zb) / max(1e-6, z_corner - zb)))

        dlo = self.dlo_rows(y)
        if dlo is None:
            z7 = zb + MIN_GAP
            z8 = z7 + MIN_GAP
            z9 = max(z8 + MIN_GAP, zt - RAIL_H)
        else:
            z7, z8 = dlo
            pillar = CABIN_RAIL if self.rear <= y <= p["roof_front_y"] else PILLAR_H
            z9 = z8 + pillar
        z9 = min(z9, zt - ROOF_CROWN * 0.5 - MIN_GAP)
        z8 = min(z8, z9 - MIN_GAP)
        z7 = min(max(z7, zb + MIN_GAP), z8 - MIN_GAP)
        return [
            (0.0, zf), (hw - 0.14, zf), (hw - 0.035, zf + 0.045), (hw - 0.004, zs),
            (hw + p.get("bulge", 0.0), _lerp(zs, zb, 0.45)), (hw - 0.006, zb - 0.05), (belt_hw, zb),
            (x_at(z7), z7), (x_at(z8), z8), (x_at(z9), z9),
            (roof_hw * 0.55, zt - ROOF_CROWN * 0.35), (0.0, zt),
        ]

    def anchors(self, well_spec):
        """Placement points for details (lamps, plates, mirrors, wheels) in the body frame."""
        p = self.p
        yf, yr = self.nose, self.tail
        return {
            "wheels": [(s * p["track"], w.y, w.z) for w in well_spec for s in (1, -1)],
            "front_face": {"y": yf, "hw": self.half_width(yf - 0.05), "z0": self.floor_z(yf), "z1": p["nose_z"]},
            "rear_face": {"y": yr, "hw": self.half_width(yr + 0.05), "z0": self.floor_z(yr), "z1": p["tail_z"]},
            "mirror": (self.half_width(self.front) * 0.958, self.front - 0.10, self.belt_z(self.front) + 0.08),
            "roof": {"y0": p["roof_rear_y"], "y1": p["roof_front_y"], "z": p["roof_z"]},
        }
