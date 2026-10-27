"""city_profile — the vertical geometry of a road (dossier §2.6 vertical curves).

A profile is a list of *anchors*: (arc length, height, grade out).  Between two
anchors the road runs

    transition (g_in -> g_mid) | constant grade g_mid | transition (g_mid -> g_out)

each transition being a parabola, so the grade is continuous (no kink) and the
height at every anchor is exact.  The solver picks `g_mid` and the transition
length so that

  * the peak grade never exceeds ``MAX_GRADE`` (the brief's 5 % limit), and
  * the grade never changes by more than ``KINK_RATE`` per 10 m (the brief's
    0.5 % per 10 m rule) - a transition of length L blending d_g needs
    L >= 2000 * d_g metres.

The solver reports an infeasible segment instead of hiding it, so the build
fails loudly when a road is too short for its height change.
"""
import math

MAX_GRADE = 0.0465              # design peak grade (the hard limit is 0.05)
KINK_MARGIN = 1.10              # the vertical curve is 1.1 x 2000 * d_g long
SPIRAL_GRADE = 0.038            # design peak grade of the Nanpu spiral loops
KINK_RATE = 0.005               # max grade change per 10 m (0.5 %)
PREFER_GRADE = 0.040            # the peak grade the solver aims for


class ProfileError(Exception):
    """Raised when a profile cannot be built inside the limits."""


class Segment:
    """One anchor-to-anchor stretch of a profile."""

    def __init__(self, s0, y0, s1, y1, g_in, g_mid, g_out, blend):
        self.s0 = s0
        self.y0 = y0
        self.s1 = s1
        self.y1 = y1
        self.g_in = g_in
        self.g_mid = g_mid
        self.g_out = g_out
        self.blend = blend          # length of each transition
        self.length = s1 - s0

    def y(self, s):
        b = self.blend
        u = s - self.s0
        if b <= 1e-9:
            return self.y0 + self.g_in * u
        if u <= b:
            return self.y0 + self.g_in * u + (self.g_mid - self.g_in) * u * u / (2.0 * b)
        if u >= self.length - b:
            v = s - (self.s1 - b)
            yb = self.y0 + 0.5 * (self.g_in + self.g_mid) * b \
                + self.g_mid * (self.length - 2.0 * b)
            return yb + self.g_mid * v + (self.g_out - self.g_mid) * v * v / (2.0 * b)
        yb = self.y0 + 0.5 * (self.g_in + self.g_mid) * b
        return yb + self.g_mid * (u - b)

    def grade(self, s):
        b = self.blend
        u = s - self.s0
        if b <= 1e-9:
            return self.g_in
        if u <= b:
            return self.g_in + (self.g_mid - self.g_in) * u / b
        if u >= self.length - b:
            return self.g_out + (self.g_mid - self.g_out) * (self.length - u) / b
        return self.g_mid


def solve_segment(g_in, g_out, length, rise, max_grade, kink=KINK_RATE):
    """The peak grade and the transition length of one segment.

    Returns (g_mid, blend).  Raises ProfileError when no pair fits the
    limits: the segment is too short for its height change.
    """
    if length <= 0.0:
        raise ProfileError("segment of zero length")
    flat = abs(rise) < 1e-9
    if flat and abs(g_in - g_out) < 1e-9:
        return g_in, 0.0
    best = None
    steps = 900
    for i in range(steps + 1):
        g_mid = -max_grade + 2.0 * max_grade * i / steps
        if abs(abs(g_mid) - PREFER_GRADE) < 1e-9:
            g_mid = math.copysign(PREFER_GRADE, g_mid)
        den = g_in + g_out - 2.0 * g_mid
        num = 2.0 * (rise - g_mid * length)
        if abs(den) < 1e-9:
            if abs(num) > 1e-6:
                continue
            blend = 0.0
        else:
            blend = num / den
        if blend < -1e-6 or blend > length + 1e-6:
            continue
        blend = max(0.0, blend)
        need = KINK_MARGIN * (10.0 / kink) * max(abs(g_mid - g_in), abs(g_out - g_mid))
        if blend + 1e-6 < need:
            continue
        if abs(g_mid) > max_grade + 1e-9:
            continue
        margin = min((max_grade - abs(g_mid)) / max_grade,
                      (blend - need) / need if need > 0 else 1.0)
        score = margin
        if best is None or score > best[0]:
            best = (score, g_mid, blend)
    if best is None:
        raise ProfileError(
            "no legal profile: rise %.2f m over %.1f m, grades %.3f -> %.3f"
            % (rise, length, g_in, g_out))
    return best[1], best[2]


class Profile:
    """A height profile along a road, built from anchors."""

    def __init__(self, anchors, max_grade=MAX_GRADE, kink=KINK_RATE,
                 start_grade=0.0):
        self.max_grade = max_grade
        # the steepest change of grade per 10 m: the vertical curves of a road are as long as this asks (the solver took the
        # brief's 0.5 % for every road before; a tunnel portal is allowed a shorter curve, see city_roads_east.yanan_tunnel)
        self.kink = kink
        self.anchors = [(float(a[0]), float(a[1]), float(a[2]) if len(a) > 2 else 0.0)
                        for a in anchors]
        self.anchors.sort(key=lambda a: a[0])
        self.segments = []
        self.start_grade = start_grade
        self._build(start_grade)

    # ---------------------------------------------------------------- build
    def _build(self, start_grade):
        g_in = start_grade
        for i in range(len(self.anchors) - 1):
            s0, y0, g_out = self.anchors[i]
            s1, y1, _ = self.anchors[i + 1]
            g_mid, blend = solve_segment(g_in, g_out, s1 - s0, y1 - y0,
                                         self.max_grade, self.kink)
            self.segments.append(Segment(s0, y0, s1, y1, g_in, g_mid, g_out, blend))
            g_in = g_out
        self.end_grade = g_in

    # ---------------------------------------------------------------- access
    def _segment_at(self, s):
        for seg in self.segments:
            if s <= seg.s1 + 1e-9:
                return seg
        return self.segments[-1] if self.segments else None

    def y(self, s):
        """The height at the distance `s` (the parabola, evaluated exactly)."""
        if not self.segments:
            return self.anchors[0][1] if self.anchors else 0.0
        if s <= self.segments[0].s0:
            return self.segments[0].y0
        seg = self._segment_at(s)
        return seg.y(min(max(s, seg.s0), seg.s1))

    def grade(self, s):
        """The grade (rise over run) at the distance `s`."""
        if not self.segments:
            return 0.0
        seg = self._segment_at(s)
        return seg.grade(min(max(s, seg.s0), seg.s1))

    def peak_grade(self):
        """The steepest grade of the profile (signed)."""
        worst = 0.0
        for seg in self.segments:
            for g in (seg.g_in, seg.g_mid, seg.g_out):
                if abs(g) > abs(worst):
                    worst = g
        return worst

    def peak_kink(self):
        """The largest grade change per 10 m of the profile."""
        worst = 0.0
        for seg in self.segments:
            if seg.blend <= 0.0:
                continue
            for a, b in ((seg.g_in, seg.g_mid), (seg.g_mid, seg.g_out)):
                worst = max(worst, abs(b - a) * 10.0 / seg.blend)
        return worst

    def report(self):
        """One line per segment: length, rise, peak grade, blend length."""
        out = []
        for seg in self.segments:
            out.append("s %7.1f-%7.1f  rise %6.2f  peak %5.2f%%  blend %5.1f m"
                       % (seg.s0, seg.s1, seg.y1 - seg.y0, seg.g_mid * 100.0,
                          seg.blend))
        return out
