"""city_ramps — the ramp pairs between the Yan'an elevated and the streets.

The dossier 10.3: ramp pairs at Xizang Rd (x = -720, both directions) and at
Chongqing Rd (x = -1080, westbound off / eastbound on).  Every ramp leaves
and meets its parent on the *edge of the carriageway it serves* (see
city_attach), so the parent's lanes stay clear and the ramp has its own
direction.

The ramps are long enough for their height change: a 9 m descent needs
315 m at 4.6 % with the 0.5 %/10 m kink rule, so every ramp swings at least
300 m along the elevated before it turns onto the street.
"""
import math

import city_attach
import citylib
from city_geom import ramp_path, sweep_path
from city_road import Road

RAMP_STYLE = {"parapet": "planter", "lamps": "barrier",
              "soffit_led": "#5A3DFF", "trees": "none"}

RAMP_LANE = 1
MAX_GRADE = 0.0465
MIN_RAMP = 300.0            # the shortest ramp the height change allows
WEAVE_GAP = 150.0           # the gap between two ramps on one carriageway
GORE = 120.0                # the attach gore: a ramp may meet its parent there


def _closest_s(road, point):
    """The distance along the road of the point closest to `point`."""
    best, best_s = 1e18, 0.0
    for p, s in zip(road.points, road.dist):
        d = math.hypot(p[0] - point[0], p[2] - point[1])
        if d < best:
            best, best_s = d, s
    return best_s


def _s_at_x(road, x):
    """The distance along the road where the centre-line crosses the line x."""
    best, best_s = 1e18, 0.0
    for p, s in zip(road.points, road.dist):
        d = abs(p[0] - x)
        if d < best:
            best, best_s = d, s
    return best_s


def _street_lane_s(street, z, direction):
    """The distance along the street of the lane centre at the height z."""
    best, best_s = 1e18, 0.0
    for p, s in zip(street.points, street.dist):
        d = abs(p[2] - z)
        if d < best:
            best, best_s = d, s
    return best_s


def _resample(plan, step=8.0):
    """Resample a 2D polyline at a uniform spacing."""
    if len(plan) < 2:
        return [list(p) for p in plan]
    out = [list(plan[0])]
    carry = 0.0
    for a, b in zip(plan, plan[1:]):
        seg = math.dist(a, b)
        if seg < 1e-9:
            continue
        d = step - carry
        while d <= seg:
            out.append([a[0] + (b[0] - a[0]) * d / seg,
                        a[1] + (b[1] - a[1]) * d / seg])
            d += step
        carry = seg - (d - step)
    if math.dist(out[-1], plan[-1]) > 1e-6:
        out.append(list(plan[-1]))
    return out


def _ends_ok(plan, src_dir, dst_dir):
    """True if the plan leaves and arrives along the wanted directions."""
    a = (plan[1][0] - plan[0][0], plan[1][1] - plan[0][1])
    b = (plan[-1][0] - plan[-2][0], plan[-1][1] - plan[-2][1])
    for v, d in ((a, src_dir), (b, dst_dir)):
        if v[0] * d[0] + v[1] * d[1] <= 0.0:
            return False
    return True


def _ramp(rid, name, name_en, plan, y0, y1, src_road, src_at, src_dir,
          dst_road, dst_at, dst_dir, notes):
    """A ramp road with its two attaches on the carriageway edges."""
    ramp = Road(rid, name, name_en, "ramp", plan,
                [("start", y0, 0.0), ("end", y1, 0.0)],
                lanes_fwd=RAMP_LANE, lanes_back=0, lane_width=3.75, median=0.0,
                shoulder=1.5, sidewalk=0.0, speed_kmh=40, style=RAMP_STYLE,
                attach_start={"road": src_road.id, "at": round(src_at, 2),
                              "side": city_attach.side_name(src_dir)},
                attach_end={"road": dst_road.id, "at": round(dst_at, 2),
                            "side": city_attach.side_name(dst_dir)},
                max_grade=MAX_GRADE, notes=notes)
    return ramp


def _clash(plan, y0, y1, roads, skip):
    """True if the ramp runs into another road.

    A ramp that passes over a street has to keep 5.5 m plus the depth of
    its own deck above it; the ramp's own parent is skipped, because it
    leaves and joins that one.
    """
    total = sum(math.dist(a, b) for a, b in zip(plan, plan[1:])) or 1.0
    travelled = 0.0
    for a, b in zip(plan, plan[1:]):
        seg = math.dist(a, b)
        y = y0 + (y1 - y0) * (travelled + seg * 0.5) / total
        travelled += seg
        if travelled < GORE or total - travelled < GORE:
            continue
        for road in roads:
            if road.id in skip:
                continue
            if road.kind == "tunnel":
                continue
            half = citylib.road_width(road) * 0.5
            for p in road.points[::4]:
                if math.hypot(p[0] - a[0], p[2] - a[1]) > half + 4.0:
                    continue
                if abs(y - p[1]) < 5.5 + 1.6:
                    return True
    return False


def surface_ramps(yanan, streets, budget=None, all_roads=None):
    """The ramp pairs of Xizang Rd and Chongqing Rd (dossier 10.3).

    `budget` is a list of the stations already used on the Yan'an
    elevated; the ramps keep at least WEAVE_GAP metres from them.  A ramp
    that would run into another road is not built at all.
    """
    by_id = {s.id: s for s in streets}
    all_roads = list(all_roads or list(streets) + [yanan])
    out = []
    used = list(budget or [])
    specs = [
        ("st_xizang_rd", "ramp_xizang",
         ("西藏路下匝道", "西藏路上匝道",
          "西藏路西向下匝道", "西藏路西向上匝道"), True),
        ("st_chongqing_rd", "ramp_chongqing",
         ("重庆路下匝道", "重庆路上匝道"), False),
    ]
    for street_id, prefix, names, four in specs:
        street = by_id.get(street_id)
        if street is None:
            continue
        x = street.plan[0][0]
        s_cross_elev = _s_at_x(yanan, x)
        cross = yanan.point_at(s_cross_elev)[0]
        s_cross_street = _street_lane_s(street, cross[2], 1)
        rh = city_attach.ramp_half(RAMP_LANE)

        def build(s_elev, s_street, elev_dir, street_dir, from_elevated):
            """The plan of a ramp between the elevated and the street."""
            e_pt, e_hd = city_attach.attach_point(yanan, s_elev, elev_dir, rh)
            t_pt, t_hd = city_attach.attach_point(street, s_street, street_dir,
                                                  rh)
            e_dir = city_attach.dir_of(e_hd)
            t_dir = city_attach.dir_of(t_hd)
            if from_elevated:
                src_pt, src_dir, src_road = e_pt, e_dir, yanan
                dst_pt, dst_dir, dst_road = t_pt, t_dir, street
            else:
                src_pt, src_dir, src_road = t_pt, t_dir, street
                dst_pt, dst_dir, dst_road = e_pt, e_dir, yanan
            plan = ramp_path(src_pt, src_dir, dst_pt, dst_dir, 90.0, 20)
            if plan is None:
                plan = sweep_path(src_pt, src_dir, dst_pt, dst_dir, None, 0.75, 20)
            if plan is None:
                return None
            if not _ends_ok(plan, src_dir, dst_dir):
                return None
            y0 = (yanan if from_elevated else street).point_at(
                s_elev if from_elevated else s_street)[0][1]
            y1 = (street if from_elevated else yanan).point_at(
                s_street if from_elevated else s_elev)[0][1]
            return _resample(plan), y0, y1, src_road, dst_road

        def search(elev_offsets, street_offsets, elev_dir, street_dir,
                   from_elevated):
            """The first ramp of the search that fits the geometry."""
            for de in elev_offsets:
                s_elev = s_cross_elev + de
                if s_elev < 5.0 or s_elev > yanan.length() - 5.0:
                    continue
                clash = [abs(s_elev - u) for d, u in used if d == elev_dir]
                if clash and min(clash) < WEAVE_GAP:
                    continue
                for ds in street_offsets:
                    s_street = s_cross_street + ds
                    if s_street < 5.0 or s_street > street.length() - 5.0:
                        continue
                    built = build(s_elev, s_street, elev_dir, street_dir,
                                  from_elevated)
                    if not built:
                        continue
                    plan, y0, y1, src_road, dst_road = built
                    length = sum(math.dist(a, b)
                                 for a, b in zip(plan, plan[1:]))
                    rise = abs(y0 - y1)
                    need = rise / MAX_GRADE + 115.0
                    if length < max(need, MIN_RAMP):
                        continue
                    if _clash(plan, y0, y1, all_roads, (src_road.id,)):
                        continue
                    return built, s_elev, s_street
            return None

        def add(rid, name, name_en, elev_offsets, street_offsets, elev_dir,
                street_dir, from_elevated, notes):
            found = search(elev_offsets, street_offsets, elev_dir, street_dir,
                           from_elevated)
            if not found:
                return None
            (plan, y0, y1, src_road, dst_road), s_elev, s_street = found
            if from_elevated:
                src_at, src_dir = s_elev, elev_dir
                dst_at, dst_dir = s_street, street_dir
            else:
                src_at, src_dir = s_street, street_dir
                dst_at, dst_dir = s_elev, elev_dir
            ramp = _ramp(rid, name, name_en, plan, y0, y1, src_road, src_at,
                         src_dir, dst_road, dst_at, dst_dir, notes)
            out.append(ramp)
            used.append((elev_dir, s_elev))
            return ramp

        if not four:
            # the Chongqing pair (dossier 10.3: westbound off, eastbound on)
            add(prefix + "_off", names[0], "%s Off-ramp" % street.name_en,
                range(-700, 0, 40), range(200, 900, 40), -1, -1, True,
                "Westbound descent from the elevated onto the street.")
            add(prefix + "_on", names[1], "%s On-ramp" % street.name_en,
                range(100, 900, 40), range(100, 900, 40), +1, +1, False,
                "Climbs from the street onto the Yan'an elevated.")
            continue
        add(prefix + "_off", names[0], "%s Off-ramp" % street.name_en,
            range(-400, 0, 40), range(60, 400, 20), +1, +1, True,
            "Descends from the Yan'an elevated onto the street.")
        add(prefix + "_on", names[1], "%s On-ramp" % street.name_en,
            range(60, 900, 40), range(-200, 400, 20), +1, -1, False,
            "Climbs from the street onto the Yan'an elevated.")
        add(prefix + "_off_wb", names[2], "%s Westbound Off-ramp" %
            street.name_en, range(100, 900, 40), range(60, 600, 20), -1, -1, True,
            "Westbound descent onto the street.")
        add(prefix + "_on_wb", names[3], "%s Westbound On-ramp" %
            street.name_en, range(-700, 0, 40), range(60, 600, 20), -1, +1, False,
            "Westbound climb from the street.")
    return out
