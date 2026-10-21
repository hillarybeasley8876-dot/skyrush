"""A spatial index of the road corridors.

The old checker bucketed a segment only by its own bounding box and then read ONE
cell, so a point next to a road whose segments lay in the neighbouring cell found no
candidates and was reported clear.  A segment is now registered in every cell its
bbox touches, expanded by its half width plus the clearance, and a query reads the
3x3 neighbourhood - so a point inside a corridor is never missed.
"""
import math

from . import citydata

GRID = 40.0


class RoadGrid(object):
    """Road segments bucketed in a grid, with the half width and a clearance."""

    def __init__(self, segments, cell=GRID, clearance=1.0):
        self.cell = cell
        self.clearance = clearance
        self.buckets = {}
        for seg in segments:
            (ax, az, bx, bz, hw) = seg
            m = hw + clearance
            x0 = int(math.floor((min(ax, bx) - m) / cell))
            x1 = int(math.floor((max(ax, bx) + m) / cell))
            z0 = int(math.floor((min(az, bz) - m) / cell))
            z1 = int(math.floor((max(az, bz) + m) / cell))
            for i in range(x0, x1 + 1):
                for j in range(z0, z1 + 1):
                    self.buckets.setdefault((i, j), []).append(seg)

    def near(self, x, z):
        """The segments that could be within the clearance of the point."""
        i0 = int(math.floor(x / self.cell))
        j0 = int(math.floor(z / self.cell))
        out = []
        seen = set()
        for i in range(i0 - 1, i0 + 2):
            for j in range(j0 - 1, j0 + 2):
                for seg in self.buckets.get((i, j), ()):
                    key = (seg[0], seg[1], seg[2], seg[3])
                    if key in seen:
                        continue
                    seen.add(key)
                    out.append(seg)
        return out

    def edge_distance(self, x, z):
        """Distance from a point to the nearest road edge (negative inside the road)."""
        best = 1e9
        for (ax, az, bx, bz, hw) in self.near(x, z):
            d = citydata.point_segment_distance(x, z, ax, az, bx, bz) - hw
            if d < best:
                best = d
        return best

    def inside(self, x, z):
        """True when the point is inside a road corridor."""
        return self.edge_distance(x, z) < 0.0
