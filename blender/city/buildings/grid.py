"""Alignment helpers for the procedural facade shader (SH_facade_*).

The shader computes its window grid from the node-local position, so a wall's
horizontal parameter `u` is: u = local_z * sign(nx) when the normal is mostly along X,
otherwise u = -local_x * sign(nz).  These helpers reproduce that so that AC units,
balconies and cages can be placed exactly under the shader's windows.
"""
import math


def wall_u(x, z, normal, origin):
    """Along-wall parameter of a city point for the facade shader."""
    lx = x - origin[0]
    lz = z - origin[1]
    nx, nz = normal
    if abs(nx) > abs(nz):
        return lz * (1.0 if nx > 0 else -1.0)
    return -lx * (1.0 if nz > 0 else -1.0)


def point_on_wall(u, fc, u0, u1):
    """The city point on THIS wall at the shader-grid parameter u.

    `u0`/`u1` are the wall_u values at the wall's two ends.  The shader's u is measured
    from the tile origin, so it has to be mapped back onto the wall before use - using it
    directly puts every prop on the tile border lines.
    """
    span = u1 - u0
    if abs(span) < 1e-6:
        return (fc["a"][0], fc["a"][1])
    s = (u - u0) / span * fc["w"]
    s = max(0.0, min(fc["w"], s))   # a prop never hangs past the end of its own wall
    return (fc["a"][0] + fc["t"][0] * s, fc["a"][1] + fc["t"][1] * s)


def cell_range(u0, u1, bay_w):
    """Indices of the facade grid cells that cover the parameter range [u0, u1]."""
    lo, hi = min(u0, u1), max(u0, u1)
    return range(int(math.floor(lo / bay_w)), int(math.floor(hi / bay_w)) + 1)


def window_rect(k, bay_w, window_frac=0.55, sill_frac=0.30):
    """(u0, u1) of the window inside grid cell k, and the window height in metres."""
    inset = (1.0 - window_frac) * 0.5
    return (k * bay_w + inset * bay_w, (k + 1) * bay_w - inset * bay_w)


def window_h(floor_index, floor_h, window_frac=0.55, sill_frac=0.30):
    """(h0, h1) of the window in a floor cell."""
    base = floor_index * floor_h
    return (base + sill_frac * floor_h, base + (sill_frac + window_frac) * floor_h)
