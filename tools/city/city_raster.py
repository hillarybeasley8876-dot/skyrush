"""city_raster — the 10 m grid the building lots are cut from.

The grid marks the cells that the water, the roads, the elevated decks
and the reserved sites own, so what is left is the land that can be
built on.
"""
import math

import citylib

CELL = 10.0                     # the raster cell size in metres


class Raster:
    """A 10 m grid over the map window."""

    def __init__(self, window):
        self.x0 = window["x_min"]
        self.z0 = window["z_min"]
        self.nx = int((window["x_max"] - window["x_min"]) / CELL)
        self.nz = int((window["z_max"] - window["z_min"]) / CELL)
        self.free = bytearray(self.nx * self.nz)
        self.owner = {}

    def idx(self, i, j):
        return j * self.nx + i

    def cell_of(self, x, z):
        return (int((x - self.x0) // CELL), int((z - self.z0) // CELL))

    def centre(self, i, j):
        return (self.x0 + (i + 0.5) * CELL, self.z0 + (j + 0.5) * CELL)

    def inside(self, i, j):
        return 0 <= i < self.nx and 0 <= j < self.nz

    def paint_poly(self, poly, value=0):
        """Mark every cell whose centre is inside the polygon."""
        xs = [p[0] for p in poly]
        zs = [p[1] for p in poly]
        i0, j0 = self.cell_of(min(xs), min(zs))
        i1, j1 = self.cell_of(max(xs), max(zs))
        for j in range(max(0, j0), min(self.nz, j1 + 1)):
            for i in range(max(0, i0), min(self.nx, i1 + 1)):
                if citylib.point_in_polygon(self.centre(i, j), poly):
                    self.free[self.idx(i, j)] = value
                    continue
                # the corners of the cell must stay out of the water too
                corners = [(self.x0 + i * CELL, self.z0 + j * CELL),
                           (self.x0 + (i + 1) * CELL, self.z0 + j * CELL),
                           (self.x0 + (i + 1) * CELL,
                            self.z0 + (j + 1) * CELL),
                           (self.x0 + i * CELL, self.z0 + (j + 1) * CELL)]
                if any(citylib.point_in_polygon(c, poly) for c in corners):
                    self.free[self.idx(i, j)] = value

    def paint_disc(self, centre, radius, value=0):
        i0, j0 = self.cell_of(centre[0] - radius, centre[1] - radius)
        i1, j1 = self.cell_of(centre[0] + radius, centre[1] + radius)
        for j in range(max(0, j0), min(self.nz, j1 + 1)):
            for i in range(max(0, i0), min(self.nx, i1 + 1)):
                if math.dist(self.centre(i, j), centre) <= radius:
                    self.free[self.idx(i, j)] = value
