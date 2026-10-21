"""Block parcels: the rectangles a block polygon is cut into.

The map's block polygons are 10 m raster outlines - staircases with 8 to 114 vertices
and a fill of 0.29 to 0.70 of their bounding box.  The old planner took the longest
edge of the polygon as the frontage and then asked for ONE rectangle that fits inside
the polygon: on a staircase that almost never happens, so 164 of the 556 blocks were
left with nothing but paving (18 % of the block area, the whole of Nanjing East Rd).

The polygon is now rasterised on the 10 m lattice and cut into maximal rectangles.
Every rectangle is planned on its own, with a frontage on the edge that faces a road;
a rectangle with two street frontages is split so that both get one.
"""
import math

from . import plan

CELL = 10.0             # the lattice of the map
FRONTAGE_MAX = 30.0     # an edge further than this from a road is not a street frontage
SERVICE_LANE_AREA = 20000.0   # a lot bigger than this gets a service lane and more buildings
MIN_FRONTAGE = 20.0      # a frontage shorter than this is a sliver, not a street


class Parcel(object):
    """One rectangle of a block, with the edge that faces the street.

    The edges are numbered like the corners of the rectangle: 0 = the north edge
    (z = z0), 1 = the east edge (x = x1), 2 = the south edge (z = z1), 3 = the west
    edge (x = x0).
    """

    def __init__(self, x0, z0, x1, z1, front=0, street=True):
        self.x0 = min(x0, x1)
        self.z0 = min(z0, z1)
        self.x1 = max(x0, x1)
        self.z1 = max(z0, z1)
        self.front = front
        self.street = street

    @property
    def area(self):
        return (self.x1 - self.x0) * (self.z1 - self.z0)

    @property
    def width(self):
        """The length of the frontage edge."""
        return (self.x1 - self.x0) if self.front in (0, 2) else (self.z1 - self.z0)

    @property
    def depth(self):
        """The depth behind the frontage."""
        return (self.z1 - self.z0) if self.front in (0, 2) else (self.x1 - self.x0)

    def corners(self):
        """The four corners, starting at the front edge so that edge 0 is the front."""
        base = [(self.x0, self.z0), (self.x1, self.z0), (self.x1, self.z1), (self.x0, self.z1)]
        f = self.front
        return [base[(f + i) % 4] for i in range(4)]

    def edge_mid(self, edge):
        """The middle of an edge (city space)."""
        c = [(self.x0, self.z0), (self.x1, self.z0), (self.x1, self.z1), (self.x0, self.z1)]
        a = c[edge]
        b = c[(edge + 1) % 4]
        return ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)

    def split(self, rect, front):
        """A sub-rectangle of this parcel, with its own frontage."""
        x0, z0, x1, z1 = rect
        return Parcel(x0, z0, x1, z1, front, self.street)


def snap(poly, cell=CELL):
    """The polygon snapped to the lattice of the map.

    The map's block outlines carry a jitter of up to 0.2 m, and rasterising them
    on the 10 m lattice without snapping cut the blocks into 5 m strips.
    """
    return [(round(p[0] / cell) * cell, round(p[1] / cell) * cell) for p in poly]


def _cells(poly, cell=CELL):
    """The lattice cells whose centre is inside the polygon.

    The scanline version: a block polygon has up to 114 vertices and there are 620
    blocks, so testing every cell against every edge was minutes of build time.
    """
    poly = snap(poly, cell)
    n = len(poly)
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    j0 = int(math.floor(min(zs) / cell))
    j1 = int(math.floor(max(zs) / cell))
    out = set()
    for j in range(j0, j1 + 1):
        zc = (j + 0.5) * cell
        crossings = []
        for i in range(n):
            ax, az = poly[i]
            bx, bz = poly[(i + 1) % n]
            if (az > zc) != (bz > zc):
                t = (zc - az) / (bz - az)
                crossings.append(ax + (bx - ax) * t)
        crossings.sort()
        for k in range(0, len(crossings) - 1, 2):
            xa, xb = crossings[k], crossings[k + 1]
            ia = int(math.floor(xa / cell))
            ib = int(math.floor(xb / cell))
            for i in range(ia, ib + 1):
                cx = (i + 0.5) * cell
                if xa <= cx <= xb:
                    out.add((i, j))
    return out


def _largest_rect(cells):
    """The largest axis-aligned rectangle of a set of lattice cells (or None)."""
    if not cells:
        return None
    xs = [c[0] for c in cells]
    ys = [c[1] for c in cells]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    w = x1 - x0 + 1
    h = y1 - y0 + 1
    best = (0, 0, 0, 0)
    for j in range(y0, y1 + 1):
        heights = [0] * w
        for i in range(x0, x1 + 1):
            heights[i - x0] = heights[i - x0] + 1 if (i, j) in cells else 0
        stack = []
        for i in range(w + 1):
            cur = heights[i] if i < w else 0
            start = i
            while stack and stack[-1][1] >= cur:
                sx, sh = stack.pop()
                area = sh * (i - sx)
                if area > best[0]:
                    best = (area, x0 + sx, j - sh + 1, x0 + i, j + 1)
                start = sx
            stack.append((start, cur))
    if best[0] == 0:
        return None
    return best[1], best[2], best[3], best[4]


def rectangles(poly, cell=CELL):
    """The maximal rectangles of a block polygon, in city space."""
    remaining = _cells(poly, cell)
    out = []
    while remaining:
        rect = _largest_rect(remaining)
        if rect is None:
            break
        x0, y0, x1, y1 = rect
        for i in range(x0, x1):
            for j in range(y0, y1):
                remaining.discard((i, j))
        out.append((x0 * cell, y0 * cell, x1 * cell, y1 * cell))
    return out


def _street_edges(parcel, grid):
    """The edges of a rectangle that face a road."""
    out = []
    for edge in range(4):
        mx, mz = parcel.edge_mid(edge)
        if grid.edge_distance(mx, mz) <= FRONTAGE_MAX:
            out.append(edge)
    return out


def _split_frontages(parcel, edges):
    """Split a rectangle so that every piece has exactly one street frontage."""
    if len(edges) <= 1:
        return [parcel]
    if len(edges) == 2:
        a, b = edges
        xm = (parcel.x0 + parcel.x1) * 0.5
        zm = (parcel.z0 + parcel.z1) * 0.5
        if a in (0, 2) and b in (0, 2):
            # opposite north/south frontages: cut across the depth
            return [parcel.split((parcel.x0, parcel.z0, parcel.x1, zm), a),
                    parcel.split((parcel.x0, zm, parcel.x1, parcel.z1), b)]
        if a in (1, 3) and b in (1, 3):
            return [parcel.split((parcel.x0, parcel.z0, xm, parcel.z1), a),
                    parcel.split((xm, parcel.z0, parcel.x1, parcel.z1), b)]
        # two adjacent frontages: cut along the axis of the second one
        if b in (1, 3):
            return [parcel.split((parcel.x0, parcel.z0, xm, parcel.z1), a),
                    parcel.split((xm, parcel.z0, parcel.x1, parcel.z1), b)]
        zm = (parcel.z0 + parcel.z1) * 0.5
        return [parcel.split((parcel.x0, parcel.z0, parcel.x1, zm), a),
                parcel.split((parcel.x0, zm, parcel.x1, parcel.z1), b)]
    # three or four frontages: one quadrant each
    xm = (parcel.x0 + parcel.x1) * 0.5
    zm = (parcel.z0 + parcel.z1) * 0.5
    quads = [(parcel.x0, parcel.z0, xm, zm, 0), (xm, parcel.z0, parcel.x1, zm, 1),
             (xm, zm, parcel.x1, parcel.z1, 2), (parcel.x0, zm, xm, parcel.z1, 3)]
    out = []
    for (qx0, qz0, qx1, qz1, qe) in quads:
        chosen = None
        for edge in edges:
            if edge == qe:
                chosen = edge
                break
        if chosen is None:
            chosen = qe if qe in edges else edges[0]
        out.append(parcel.split((qx0, qz0, qx1, qz1), chosen))
    return out


def _split_large(parcel, lane=6.0):
    """A very big lot is cut into several lots with a service lane between them."""
    if parcel.area <= SERVICE_LANE_AREA:
        return [parcel]
    n = max(2, int(math.ceil(parcel.area / SERVICE_LANE_AREA)))
    out = []
    if parcel.front in (0, 2):
        # the frontage runs along x: cut the frontage into n parts
        total = parcel.x1 - parcel.x0
        step = (total - lane * (n - 1)) / n
        for i in range(n):
            x0 = parcel.x0 + i * (step + lane)
            out.append(parcel.split((x0, parcel.z0, x0 + step, parcel.z1), parcel.front))
    else:
        total = parcel.z1 - parcel.z0
        step = (total - lane * (n - 1)) / n
        for i in range(n):
            z0 = parcel.z0 + i * (step + lane)
            out.append(parcel.split((parcel.x0, z0, parcel.x1, z0 + step), parcel.front))
    return out


def of_block(poly, grid):
    """The parcels of a block polygon, each with its street frontage.

    A rectangle without a street frontage (an interior one) keeps the longest edge as
    its frontage and no setback: the building fills the parcel.
    """
    out = []
    for (x0, z0, x1, z1) in rectangles(poly):
        parcel = Parcel(x0, z0, x1, z1, 0, False)
        edges = _street_edges(parcel, grid)
        if not edges:
            # no street: the longest edge is the frontage and there is no setback
            width = x1 - x0
            depth = z1 - z0
            parcel.front = 0 if width >= depth else 1
            out.extend(_split_large(parcel))
            continue
        # the frontage with the most road in front of it wins
        best = min(edges, key=lambda e: grid.edge_distance(*parcel.edge_mid(e)))
        pieces = _split_frontages(parcel, edges)
        if len(pieces) > 1 and min(p.width for p in pieces) < MIN_FRONTAGE:
            # splitting a small lot would make slivers: one frontage for the lot
            parcel.front = best
            pieces = [parcel]
        for piece in pieces:
            piece.street = True
            if len(pieces) == 1 and piece.front != best:
                piece.front = best
            out.extend(_split_large(piece))
    return out
