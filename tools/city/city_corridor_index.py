"""city_corridor_index — a grid of the segments of one arterial corridor.

The corridors of the arterials are long polylines with hundreds of segments
each.  Measuring one point against every segment of every corridor is what
makes the city generator slow, so the segments of a corridor are bucketed
into square cells: a point is then only measured against the segments of the
cells around it.

The index never changes the answer, it only says which segments have to be
measured:

* a corridor whose points are all further away than `half` from the point
  cannot contain it at all;
* every segment that can be nearer to the point than `half` is always among
  the candidates, because a segment is only further away than `half` when
  its bounding box is, and a box further away than `half` is never in the
  cells around the point;
* the candidates are handed out in the order of the polyline, so the nearest
  segment is the same one the slow search would have found, and a tie is
  resolved in the same way.

The index of a corridor is built once and kept in a module level cache.  The
key is the identity of the list of points and the cache holds the list
itself, so a recycled address can never be mistaken for the old corridor.
The list is compared with the copy the index was built from, so a corridor
that is changed under us is measured again.
"""
import math

CELL = 50.0        # the size of a cell of the grid, in metres
MAX_CELLS = 64     # a segment wider than this is always measured

_CACHE = {}


def _cell(v):
    """The index of the cell a coordinate falls in."""
    return int(v // CELL)


class CorridorIndex:
    """The segments of one corridor, bucketed into square cells."""

    __slots__ = ("points", "count", "minx", "maxx", "minz", "maxz",
                 "boxes", "cells", "wide", "cacheable")

    def __init__(self, points):
        self.points = points
        self.count = len(points) - 1
        self.cells = {}
        self.wide = []
        self.boxes = []
        # a tuple cannot change under our feet, so the index of a corridor
        # of tuples stays true as long as the list of them does
        self.cacheable = all(type(p) is tuple for p in points)
        if not points:
            self.minx = self.maxx = self.minz = self.maxz = 0.0
            return
        xs = [p[0] for p in points]
        zs = [p[1] for p in points]
        self.minx, self.maxx = min(xs), max(xs)
        self.minz, self.maxz = min(zs), max(zs)
        for i in range(self.count):
            a, b = points[i], points[i + 1]
            if a[0] <= b[0]:
                bx0, bx1 = a[0], b[0]
            else:
                bx0, bx1 = b[0], a[0]
            if a[1] <= b[1]:
                bz0, bz1 = a[1], b[1]
            else:
                bz0, bz1 = b[1], a[1]
            self.boxes.append((bx0, bx1, bz0, bz1))
            i0, i1 = _cell(bx0), _cell(bx1)
            j0, j1 = _cell(bz0), _cell(bz1)
            if (i1 - i0 + 1) * (j1 - j0 + 1) > MAX_CELLS:
                self.wide.append(i)
                continue
            for ci in range(i0, i1 + 1):
                for cj in range(j0, j1 + 1):
                    self.cells.setdefault((ci, cj), []).append(i)

    def may_reach(self, point, half):
        """False when the point is further than `half` from every point."""
        x, z = point[0], point[1]
        if x < self.minx - half or x > self.maxx + half:
            return False
        if z < self.minz - half or z > self.maxz + half:
            return False
        return True

    def candidates(self, point, half):
        """The segments that can be nearer than `half`, in polyline order."""
        x, z = point[0], point[1]
        i0, i1 = _cell(x - half), _cell(x + half)
        j0, j1 = _cell(z - half), _cell(z + half)
        found = set()
        cells = self.cells
        for ci in range(i0, i1 + 1):
            for cj in range(j0, j1 + 1):
                bucket = cells.get((ci, cj))
                if bucket:
                    found.update(bucket)
        if self.wide:
            found.update(self.wide)
        if not found:
            return []
        boxes = self.boxes
        out = []
        for i in found:
            bx0, bx1, bz0, bz1 = boxes[i]
            if x < bx0:
                dx = bx0 - x
            elif x > bx1:
                dx = x - bx1
            else:
                dx = 0.0
            if z < bz0:
                dz = bz0 - z
            elif z > bz1:
                dz = z - bz1
            else:
                dz = 0.0
            if math.hypot(dx, dz) > half:
                continue
            out.append(i)
        out.sort()
        return out


def index_for(points):
    """The index of a corridor, built once and kept.

    The key is the identity of the list of points, and the list itself is
    held by the cache, so a recycled address can never be mistaken for the
    old corridor.  The list is compared with the copy the index was built
    from: the points are tuples, so they cannot change under our feet, and
    any change of the list is caught and the index is built again.
    """
    key = id(points)
    hit = _CACHE.get(key)
    if hit is not None:
        held, copy, index = hit
        if held is points and points == copy:
            return index
    index = CorridorIndex(points)
    if index.cacheable:
        if len(_CACHE) > 64:
            _CACHE.clear()
        copy = list(points) if isinstance(points, list) else tuple(points)
        _CACHE[key] = (points, copy, index)
    return index

