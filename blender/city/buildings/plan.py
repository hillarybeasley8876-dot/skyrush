"""Block planner: turns a city.json block polygon into building lots.

A lot is a rectangle in the block's local frame: `u` runs along the street frontage
(the longest polygon edge) and `n` points into the block.  Rows are laid out from the
frontage backwards; each style decides the row depths and what sits in them.
"""
import math


class Frame(object):
    """Local frame of a block polygon.

    `front_edge` picks the edge the frontage runs along (0 = the longest edge).
    """

    def __init__(self, poly, front_edge=None):
        self.poly = [(float(p[0]), float(p[1])) for p in poly]
        self.cx = sum(p[0] for p in self.poly) / len(self.poly)
        self.cz = sum(p[1] for p in self.poly) / len(self.poly)
        self._pick_edge(front_edge)

    def _pick_edge(self, front_edge=None):
        best = None
        n = len(self.poly)
        for i in range(n):
            a = self.poly[i]
            b = self.poly[(i + 1) % n]
            dx, dz = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dz)
            if best is None or length > best[0]:
                best = (length, a, b, dx, dz)
        if front_edge is not None:
            i = front_edge % n
            a = self.poly[i]
            b = self.poly[(i + 1) % n]
            dx, dz = b[0] - a[0], b[1] - a[1]
            best = (math.hypot(dx, dz), a, b, dx, dz)
        self.front_a = best[1]
        self.front_b = best[2]
        self.front_len = best[0]
        ux, uz = best[3] / best[0], best[4] / best[0]
        # inward normal: pointing towards the centroid
        nx, nz = -uz, ux
        mid = ((self.front_a[0] + self.front_b[0]) * 0.5, (self.front_a[1] + self.front_b[1]) * 0.5)
        if (self.cx - mid[0]) * nx + (self.cz - mid[1]) * nz < 0.0:
            nx, nz = -nx, -nz
        self.u = (ux, uz)
        self.n = (nx, nz)
        self.origin = self.front_a
        self.s_range = self._span(0)
        self.t_range = self._span(1)

    def _span(self, axis):
        vals = []
        for x, z in self.poly:
            vals.append((x - self.origin[0]) * self.u[0] + (z - self.origin[1]) * self.u[1]
                        if axis == 0 else
                        (x - self.origin[0]) * self.n[0] + (z - self.origin[1]) * self.n[1])
        return (min(vals), max(vals))

    def to_city(self, s, t):
        """Local (s along frontage, t into the block) -> city (x, z)."""
        return (self.origin[0] + self.u[0] * s + self.n[0] * t,
                self.origin[1] + self.u[1] * s + self.n[1] * t)

    def contains(self, x, z, eps=1e-6):
        """Point in polygon (even-odd rule).

        A point ON the edge counts as inside: the even-odd test is undefined there,
        and the block planner tests the corners of every lot, which sit exactly on
        the boundary - without this the first lot of every block was dropped.
        """
        n = len(self.poly)
        for i in range(n):
            ax, az = self.poly[i]
            bx, bz = self.poly[(i + 1) % n]
            dx, dz = bx - ax, bz - az
            l2 = dx * dx + dz * dz
            if l2 < 1e-12:
                continue
            t = ((x - ax) * dx + (z - az) * dz) / l2
            if t < -1e-9 or t > 1.0 + 1e-9:
                continue
            px, pz = ax + dx * t, az + dz * t
            if (x - px) ** 2 + (z - pz) ** 2 <= eps * eps:
                return True
        inside = False
        j = n - 1
        for i in range(n):
            xi, zi = self.poly[i]
            xj, zj = self.poly[j]
            if ((zi > z) != (zj > z)) and (x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi):
                inside = not inside
            j = i
        return inside


class Lot(object):
    """A rectangular building lot in city space."""

    def __init__(self, poly, u, n, kind="building", facing=0.0, seed=0, extra=None):
        self.poly = poly
        self.u = u
        self.n = n
        self.kind = kind
        self.facing = facing          # degrees, direction the front looks (outward)
        self.seed = seed
        self.extra = extra or {}

    @property
    def center(self):
        n = len(self.poly)
        return (sum(p[0] for p in self.poly) / n, sum(p[1] for p in self.poly) / n)

    @property
    def width(self):
        return math.dist(self.poly[0], self.poly[1])

    @property
    def depth(self):
        return math.dist(self.poly[1], self.poly[2])

    def poly_at(self, inset=0.0):
        """The lot polygon shrunk by `inset` metres on every side."""
        if inset <= 0.0:
            return list(self.poly)
        cx, cz = self.center
        out = []
        for x, z in self.poly:
            dx, dz = x - cx, z - cz
            d = math.hypot(dx, dz)
            if d < 1e-6:
                out.append((x, z))
            else:
                out.append((x - dx / d * inset, z - dz / d * inset))
        return out


def rectangle(frame, s0, t0, s1, t1):
    """City-space rectangle in a block frame."""
    return [frame.to_city(s0, t0), frame.to_city(s1, t0),
            frame.to_city(s1, t1), frame.to_city(s0, t1)]


def frontage_lots(frame, target, min_width, rng=None, jitter=0.2):
    """Split the frontage of a frame into lots of about `target` metres.

    Every lot is at least `min_width` wide, and the last one takes the remainder.
    The old loop (`while s < s1 - 4.0`) dropped the last 4 m of a frontage and, on a
    short parcel, dropped the whole frontage: a 10 m parcel produced no building at
    all.  With the minimum, a 10 m parcel gets one 10 m lot.
    """
    s0, s1 = frame.s_range
    total = s1 - s0
    if total < min_width:
        return []
    count = max(1, int(round(total / float(target))))
    count = min(count, int(total // min_width))
    if count < 1:
        return []
    out = []
    s = s0
    for i in range(count):
        left = count - i
        w = (s1 - s) / left
        if rng is not None and left > 1:
            lo = min_width
            hi = (s1 - s) - (left - 1) * min_width
            w = min(max(w * (1.0 + rng.uniform(-jitter, jitter)), lo), hi)
        out.append((s, s + w))
        s += w
    return out


def depth_rows(front_t, t1, depth, gap=4.0, min_depth=8.0):
    """The rows of a parcel: the front row and the rows behind it.

    A block of the map is often 150 m deep (a strip between two roads), and one
    row of buildings in it leaves 80 % of the lot as bare paving.
    """
    rows = []
    ta = front_t
    while ta < t1 - (min_depth - 0.5):
        d = min(depth, t1 - ta)
        if d < min_depth:
            break
        rows.append((ta, ta + d, 0))
        ta += d + gap
    return rows


def point_in_poly(x, z, poly):
    """Even-odd point in polygon test."""
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if ((zi > z) != (zj > z)) and (x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi):
            inside = not inside
        j = i
    return inside


def outside_water(poly, water, step=1.0):
    """True when the footprint (corners, edge samples and centre) stays out of the water."""
    if not water:
        return True
    for (x, z) in footprint_samples(poly, step):
        for w in water:
            if point_in_poly(x, z, w):
                return False
    return True


def footprint_samples(poly, step=1.0):
    """The corners of a footprint, a point every `step` metres along its edges and the centre.

    The edges are sampled densely: a long straight edge can cross a road corridor in
    the middle, and the old corner/midpoint/centre sampling missed exactly that.
    """
    out = []
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        out.append((a[0], a[1]))
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        count = max(1, int(length / step))
        for k in range(1, count):
            t = k / float(count)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    out.append((sum(p[0] for p in poly) / n, sum(p[1] for p in poly) / n))
    return out


def outside_roads(poly, segments, margin=1.0, step=1.0):
    """True when the footprint keeps `margin` metres clear of every road corridor."""
    if not segments:
        return True
    for (x, z) in footprint_samples(poly, step):
        for (ax, az, bx, bz, hw) in segments:
            dx, dz = bx - ax, bz - az
            l2 = dx * dx + dz * dz
            if l2 < 1e-9:
                d = math.hypot(x - ax, z - az)
            else:
                t = ((x - ax) * dx + (z - az) * dz) / l2
                t = max(0.0, min(1.0, t))
                d = math.hypot(x - (ax + dx * t), z - (az + dz * t))
            if d - hw < margin:
                return False
    return True


def fits(frame, s0, t0, s1, t1, margin=0.0, water=None, roads=None, road_margin=1.0):
    """True when a local rectangle lies inside the block polygon, clear of the water and
    clear of the road corridors.  The clearance is checked on the real footprint (without
    the margin), the containment on the inset one."""
    raw = [frame.to_city(s0, t0), frame.to_city(s1, t0), frame.to_city(s1, t1),
           frame.to_city(s0, t1)]
    pts = [frame.to_city(s0 + margin, t0 + margin), frame.to_city(s1 - margin, t0 + margin),
           frame.to_city(s1 - margin, t1 - margin), frame.to_city(s0 + margin, t1 - margin)]
    if not all(frame.contains(x, z) for x, z in pts):
        return False
    if water and not outside_water(raw, water):
        return False
    if roads and not outside_roads(raw, roads, road_margin):
        return False
    return True


def split_frontage(frame, width, min_width=6.0, max_width=46.0):
    """Split the frontage into lot widths, jittered so a block is never a repeat."""
    s0, s1 = frame.s_range
    total = s1 - s0
    count = max(1, int(round(total / width)))
    base = total / count
    return [(s0 + i * base, s0 + (i + 1) * base, base) for i in range(count)]


def outward_normal(frame):
    """Unit vector pointing out of the block (towards the street)."""
    return (-frame.n[0], -frame.n[1])


def recess_front(poly, front_edge, depth):
    """The footprint with its `front_edge` pushed `depth` metres into the building.

    The ground floor is built from this so the shopfronts sit in a real alcove and the
    other three sides stay closed.
    """
    a = poly[front_edge]
    b = poly[(front_edge + 1) % len(poly)]
    fc = facade(poly, front_edge)
    n = fc["n"]
    a2 = (a[0] - n[0] * depth, a[1] - n[1] * depth)
    b2 = (b[0] - n[0] * depth, b[1] - n[1] * depth)
    out = [a2, b2]
    for i in range(2, len(poly)):
        out.append(poly[(front_edge + i) % len(poly)])
    return out


def dist_to_poly(point, poly):
    """Distance from a city point to the nearest edge of a polygon (0 when inside)."""
    x, z = point
    best = 1e9
    n = len(poly)
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        dx, dz = bx - ax, bz - az
        l2 = dx * dx + dz * dz
        if l2 < 1e-9:
            d = math.hypot(x - ax, z - az)
        else:
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / l2))
            d = math.hypot(x - (ax + dx * t), z - (az + dz * t))
        if d < best:
            best = d
    return best


def facade(poly, edge=0):
    """Describe one edge of a rectangular lot: the left point, the outward normal and width.

    The tangent always agrees with `shapes.wall_tangent(normal)`: when the outward
    normal has to be flipped, the tangent and the two end points are flipped with it.
    Without that, every quad built on this facade (a sign, a shop window, a pane)
    ran backwards along the wall and sat on the neighbouring module.
    """
    a = poly[edge]
    b = poly[(edge + 1) % len(poly)]
    dx, dz = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dz)
    tx, tz = dx / length, dz / length
    nx, nz = -tz, tx
    cx = sum(p[0] for p in poly) / len(poly)
    cz = sum(p[1] for p in poly) / len(poly)
    if (cx - a[0]) * nx + (cz - a[1]) * nz > 0.0:
        nx, nz = -nx, -nz
        tx, tz = -tx, -tz
        a, b = b, a
    return {"a": a, "b": b, "w": length, "n": (nx, nz), "t": (tx, tz), "edge": edge}
