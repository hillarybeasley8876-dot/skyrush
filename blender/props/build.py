"""Registry of every prop the unit builds (see build_all.py)."""
import os

from . import barriers, charge, furniture, gas, greens, lamps, neon, signs, skylane, toll

ROOT = os.path.expanduser("~/m/skyrush")
OUT_STREET = os.path.join(ROOT, "game", "assets", "props", "street")
OUT_SITES = os.path.join(ROOT, "game", "assets", "props", "sites")

GROUPS = [
    (lamps, OUT_STREET),
    (signs, OUT_STREET),
    (greens, OUT_STREET),
    (furniture, OUT_STREET),
    (barriers, OUT_STREET),
    (neon, OUT_STREET),
    (toll, OUT_SITES),
    (gas, OUT_SITES),
    (charge, OUT_SITES),
    (skylane, OUT_SITES),
]


def all_props():
    """[(name, builder, folder), ...] for every prop in the unit."""
    out = []
    for module, folder in GROUPS:
        for name, builder in sorted(module.BUILDERS.items()):
            out.append((name, builder, folder))
    return out
