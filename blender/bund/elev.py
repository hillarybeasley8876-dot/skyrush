"""The elevation of a Bund building, shared by the facade builder and the wash bake.

The wash (art dossier 3.4) has to know where the openings are, so that the light never
falls inside a window, and the facade builder has to put the windows in the same place.
Both read this module, so the light map and the geometry can never drift apart.
"""
from . import data


def _front_storeys(s, mass_h):
    """The storeys of the front elevation: (z_bottom, z_top, sill, head)."""
    base_h, fh = s["base_h"], s["floor_h"]
    n = s["floors"]
    while n > 1 and base_h + n * fh > mass_h + 0.01:
        n -= 1
    out = []
    for f in range(n):
        z0 = base_h + f * fh
        z1 = base_h + (f + 1) * fh if f < n - 1 else mass_h
        win_h = min(data.WIN_H, (z1 - z0) - data.WIN_SILL - 0.30)
        sz = z0 + data.WIN_SILL
        out.append((z0, z1, sz, sz + win_h))
    return out


def front_windows(s, mass_h=None):
    """The window rectangles of the front elevation: (y_centre, half_width, z0, z1)."""
    mass_h = mass_h if mass_h is not None else s["cornice"]
    w = s["frontage"]
    bays = s["bays"]
    pitch = w / bays
    win_w = min(pitch * 0.45, data.WIN_W)
    out = []
    for (_z0, _z1, sz, hz) in _front_storeys(s, mass_h):
        for i in range(bays):
            yc = -w * 0.5 + (i + 0.5) * pitch
            out.append((yc, win_w * 0.5, sz, hz))
    return out


def shopfronts(s):
    """The ground floor openings: the portal and the shopfronts of the base course.

    Each is (y_centre, half_width, z0, z1) in the facade's local frame."""
    w = s["frontage"]
    base_h = s["base_h"]
    pw = min(5.0, w * 0.22)
    out = [(0.0, pw * 0.5, 0.0, base_h)]
    n = max(2, int((w - pw) / 4.6))
    step = (w - pw) / n
    for i in range(n):
        yc = -w * 0.5 + pw + (i + 0.5) * step
        if abs(yc) < pw:
            continue
        out.append((yc, 1.3, 0.0, base_h))
    return out


def attic_windows(s):
    """The windows of the attic storey (empty when the building has no attic)."""
    opts = s["opts"]
    if not opts.get("attic"):
        return []
    w = s["frontage"]
    z0 = s["cornice"]
    height = min(opts["attic"], max(1.5, s["height"] - s["cornice"] - 0.6))
    out = []
    n = max(3, int(w / 4.0))
    for i in range(n):
        yc = -w * 0.5 + (i + 0.5) * (w / n)
        out.append((yc, 0.62, z0 + height * 0.28, z0 + height * 0.74))
    return out


def string_courses(s, mass_h=None):
    """The z of every string course of the front elevation (the shadow lines)."""
    mass_h = mass_h if mass_h is not None else s["cornice"]
    return [z0 - 0.15 for (z0, _z1, _sz, _hz) in _front_storeys(s, mass_h) if z0 > 0.01]


def attic_top(s):
    """The top of the attic storey (the cornice when there is no attic)."""
    opts = s["opts"]
    if not opts.get("attic"):
        return s["cornice"]
    return s["cornice"] + min(opts["attic"], max(1.5, s["height"] - s["cornice"] - 0.6))


def elevation(s, mass_h=None):
    """Everything the wash bake needs to know about one facade."""
    mass_h = mass_h if mass_h is not None else s["cornice"]
    return {
        "width": s["frontage"],
        "cornice": s["cornice"],
        "cornice_h": data.CORNICE_H_BIG if s["cornice"] > data.CORNICE_BIG_ABOVE
                     else data.CORNICE_H_SMALL,
        "windows": front_windows(s, mass_h),
        "shopfronts": shopfronts(s),
        "attic": attic_windows(s),
        "strings": string_courses(s, mass_h),
        "attic_top": attic_top(s),
        "top": max(s["cornice"] + 1.6, attic_top(s)),
    }


def uplight_layout(s):
    """The ground uplights of one building: (y, z) of every lamp.

    The lamps stand 1 m off the wall, every 5 m along it, and are aimed 80 deg up
    (art dossier 3.4). The light bake and the real lights share this layout, so the
    wash always agrees with the lamps that light the near field."""
    w = s["frontage"]
    n = max(1, int(w / data.UPLIGHT_EVERY))
    out = []
    for i in range(n):
        y = -w * 0.5 + (i + 0.5) * (w / n)
        out.append((y, 0.6))
    return out
