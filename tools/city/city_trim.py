"""city_trim — cut the lattice streets that run under a low deck.

The deck clearance rule wants 5.5 m of headroom under a deck, plus the
depth of the structure that carries it.  A street that passes under a
ramp with less room than that can neither be lowered (it is at grade)
nor be lifted (the ramp is at the height it needs), so the street is cut:
the piece under the deck is dropped and the rest of the street keeps its
two ends.

The cut follows the rule itself: a street station is a conflict when a
point of the deck lies within (street width + deck width) / 2 of it and
the gap between the two is at least 1 m and less than the headroom the
rule asks for.  The cut is widened by two stations on each side, so the
ends of the street stand clear of the deck, and the pieces shorter than
25 m are dropped.

Only the lattice streets are cut: the named streets keep their course.
"""
import copy
import math
import sys

import city_rules
import citylib

CLEARANCE = 5.5         # the headroom the rule asks for under a deck
MIN_GAP = 1.0           # below this the two roads meet at grade
MARGIN = 2              # stations cut on each side of a conflict
PAD = 2.0               # the metres the cut is widened by
MIN_PIECE = 25.0        # the shortest piece of street that is kept
STEP = 2.0              # the distance between two stations of a street
PREFIXES = ("st_d", "st_link")     # the lattice streets, not the named ones
CELL = 40.0             # the cell of the grid of deck points


def _decks(main_roads, only_decks):
    """The decks to cut under, with their width and the headroom they need."""
    out = []
    for road in main_roads:
        if road.kind not in ("elevated", "bridge", "ramp"):
            continue
        if only_decks is not None and road.id not in only_decks:
            continue
        out.append((road, citylib.road_width(road),
                    CLEARANCE + city_rules.deck_depth(road)))
    return out


def _cells(decks):
    """The points of the decks in a coarse grid of cells."""
    cells = {}
    for di, (deck, _width, _need) in enumerate(decks):
        for p in deck.points:
            key = (int(p[0] // CELL), int(p[2] // CELL))
            cells.setdefault(key, []).append((di, p))
    return cells


def _conflicts(street, decks, cells):
    """The stations of the street under a deck and the stations to cut.

    The third value is the set of the ids of the decks it runs under.
    """
    width = citylib.road_width(street)
    exact, padded, names = set(), set(), set()
    for i, p in enumerate(street.points):
        cx, cz = int(p[0] // CELL), int(p[2] // CELL)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for di, q in cells.get((cx + dx, cz + dz), ()):
                    deck, deck_width, need = decks[di]
                    gap = q[1] - p[1]
                    if not (MIN_GAP <= abs(gap) < need - 0.05):
                        continue
                    reach = (width + deck_width) / 2.0
                    d = math.hypot(q[0] - p[0], q[2] - p[2])
                    if d <= reach:
                        exact.add(i)
                        names.add(deck.id)
                    if d <= reach + PAD:
                        padded.add(i)
    return exact, padded, names


def _runs(street, padded):
    """The runs of stations of the street that are kept."""
    keep = [True] * len(street.points)
    for i in padded:
        for k in range(max(0, i - MARGIN), min(len(keep), i + MARGIN + 1)):
            keep[k] = False
    runs, run = [], []
    for k, ok in enumerate(keep):
        if ok:
            run.append(k)
        elif run:
            runs.append(run)
            run = []
    if run:
        runs.append(run)
    return [r for r in runs if (len(r) - 1) * STEP >= MIN_PIECE]


def trim_under_decks(streets, main_roads, only_decks=None):
    """Cut the lattice streets that pass under a deck with too little room.

    `only_decks` names the decks to cut under; `None` means every deck of
    the map.  A street that is cut keeps its id on its first piece; the
    next pieces get the id plus a `b` (then `bb`, ...).
    """
    decks = _decks(main_roads, only_decks)
    cells = _cells(decks)
    out = []
    for street in streets:
        if not street.id.startswith(PREFIXES):
            out.append(street)
            continue
        exact, padded, names = _conflicts(street, decks, cells)
        if not exact:
            out.append(street)
            continue
        runs = _runs(street, padded)
        orig = [list(p) for p in street.points]
        for n, run in enumerate(runs):
            piece = street if n == 0 else copy.copy(street)
            if n > 0:
                piece.id = street.id + "b" * n
            piece.plan = [[orig[k][0], orig[k][2]] for k in run]
            piece.build()
            out.append(piece)
        print("city_trim: %s cut under %s: %d conflicting station(s), "
              "pieces %s m" % (street.id, ", ".join(sorted(names)),
                               len(exact),
                               ", ".join("%d" % ((len(r) - 1) * STEP)
                                         for r in runs)),
              file=sys.stderr)
    return out
