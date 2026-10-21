"""Build context: RNG, mesh bag and the sign slot pool shared by all style modules."""
import random

from . import cells, matsb, openings

SIGN_ATLAS = {
    "neon_v": "neon_vertical",
    "neon_h": "neon_horizontal",
    "neon_red": "fascia_red",
    "plaque": "plaques",
    "led": "led_ads",
    "interior": "interiors",
    "shop_interior": "shop_interiors",
    "cloth": "cloth",
    "prop": "props",
    "carving": "carvings",
}


class Ctx(object):
    """Everything a style module needs to write geometry."""

    def __init__(self, seed, bag, water=None):
        self.rng = random.Random(seed)
        self.bag = bag
        self.wall_key = "render"
        self.ground_h = 4.0
        self.water = water or []
        self.roads = []
        self.origin = (0.0, 0.0)     # the facade grid origin (the cell centre)
        self.cell = (0, 0)
        self.panes = []
        self._pool = {}
        self._used = set()

    def reset_pool(self):
        """Forget which signs were used (a new block gets a fresh set)."""
        self._pool = {}
        self._used = set()

    def begin_building(self, poly):
        """Start a building.

        The building's faces are tagged with the 128 m cell of its centre, so all of
        its faces end up in ONE node: the facade shader computes its window grid from
        the object-space position, and a building split over two cells would show its
        grid jumping in the middle of a wall.
        """
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        self.cell = cells.cell_of(cx, cz)
        self.origin = cells.cell_centre_city(self.cell[0], self.cell[1])
        self.panes = []
        self.bag.begin_building(self.cell)

    def end_building(self):
        """Check that every pane is really visible, then merge the building."""
        failures = openings.assert_panes_visible(self.bag.pending_faces(), self.panes)
        if failures:
            raise AssertionError("; ".join(failures[:3]))
        self.bag.end_building()
        self.panes = []

    def add_pane(self, point, normal, depth):
        """Record a pane so the builder can assert that it is not buried."""
        self.panes.append((point, normal, depth))

    def next_sign(self, key):
        """An unused atlas slot for a sign material, or None when the atlas is empty."""
        atlas = SIGN_ATLAS.get(key)
        if atlas is None:
            return None
        if atlas not in self._pool:
            slots = [s for s in matsb.sign_slots() if s.get("atlas") == atlas]
            self._pool[atlas] = slots
            self._used = set()
        pool = self._pool[atlas]
        if not pool:
            return None
        free = [s for s in pool if s["id"] not in self._used]
        if not free:
            self._used = set()
            free = pool
        slot = free[self.rng.randrange(len(free))]
        self._used.add(slot["id"])
        return slot

    def prop_uv(self, name):
        """The UV rect of a named cell of the prop sheet (the AC casing, the cage...)."""
        if "props" not in self._pool:
            self._pool["props"] = [s for s in matsb.sign_slots() if s.get("atlas") == "props"]
        for slot in self._pool["props"]:
            if slot["id"] == name:
                return (slot["u0"], slot["v0"], slot["u1"], slot["v1"])
        return None

    def random_cell(self, key):
        """A random cell of an atlas - repeats are allowed (the interiors)."""
        atlas = SIGN_ATLAS.get(key)
        if atlas is None:
            return None
        if atlas not in self._pool:
            self._pool[atlas] = [s for s in matsb.sign_slots() if s.get("atlas") == atlas]
        pool = self._pool[atlas]
        if not pool:
            return None
        return pool[self.rng.randrange(len(pool))]
