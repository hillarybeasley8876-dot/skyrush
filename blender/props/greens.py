"""Green props for the SKYRUSH props unit: London plane trees, deck planters,
noise walls and the metro entrance.

Dossier §2.4 (planters, noise walls), §9 (plane trees, metro entrance).

The plane tree is a real tree: a three-order branch skeleton (trunk, five limbs,
twenty branches) with 200 leaf-cluster cards filling a 10 m ellipsoid between
7 m and 14 m, the card normals bent outward from the canopy centre.
"""
import math
import random

import bmesh

from . import atlas, kit, materials as M

BARK = "bark"


def _branch_skeleton(p, variant, rng):
    """Trunk, five limbs and twenty branches; returns the limb tips."""
    lean = (0.0, 0.32, -0.26)[variant]
    spread = (1.0, 0.88, 1.12)[variant]
    p.cyl("Trunk", (lean * 0.5, 0.0, 3.20), 0.30, 6.40, M.surface(), segments=12,
          r2=0.18, surface=BARK)
    p.cyl("Root", (0.0, 0.0, 0.18), 0.44, 0.36, M.surface(), segments=12, r2=0.32,
          surface=BARK)
    # the grime of the first 0.6 m of the trunk (the ground traps the dirt)
    p.cyl("TrunkFoot", (lean * 0.5, 0.0, 0.30), 0.315, 0.60, M.surface(), segments=12,
          r2=0.30, surface=BARK, tint=(0.42, 0.42, 0.40))
    limbs = []
    for i in range(5):
        a = math.tau * i / 5.0 + variant * 0.4
        base_z = 5.10 + 0.28 * i
        tip = (lean + math.cos(a) * 2.3 * spread, math.sin(a) * 2.3 * spread,
               8.10 + 0.30 * i)
        p.tube("Limb%d" % (i + 1), (lean * 0.5, 0.0, base_z), tip, 0.115, M.surface(),
               segments=6, surface=BARK)
        limbs.append((tip, a))
    for li, (tip, a) in enumerate(limbs):
        for j in range(4):
            aa = a + (j - 1.5) * 0.55
            btip = (tip[0] + math.cos(aa) * 2.1 * spread, tip[1] + math.sin(aa) * 2.1 * spread,
                    tip[2] + 1.35 + rng.uniform(-0.2, 0.3))
            p.tube("Branch%d_%d" % (li + 1, j + 1), tip, btip, 0.048, M.surface(),
                   segments=5, surface=BARK)
    return limbs


def _canopy(p, variant, rng, cards=320):
    """The leaf mass: cards filling a 10 m ellipsoid between 7 m and 14 m.

    One card shows a whole quadrant of the foliage atlas, so the leaves keep
    their real size (a plane leaf is 12-18 cm) whatever the size of the card.
    """
    bm = bmesh.new()
    spread = (1.0, 0.88, 1.12)[variant]
    cx, cz = 0.0, 10.4
    for i in range(cards):
        a = rng.uniform(0.0, math.tau)
        rr = 4.9 * spread * (0.42 + 0.58 * rng.random() ** 0.35)
        zz = cz + 3.3 * math.copysign(abs(rng.uniform(-1.0, 1.0)) ** 1.3, rng.uniform(-1.0, 1.0))
        centre = (cx + math.cos(a) * rr, math.sin(a) * rr, zz)
        outward = (math.cos(a) * 0.8, math.sin(a) * 0.8, rng.uniform(-0.35, 0.45))
        size = rng.uniform(1.8, 2.8)
        # the whole quadrant, shifted inside it so the cards do not repeat
        u0 = rng.uniform(0.0, 0.25)
        v0 = rng.uniform(0.0, 0.25)
        rect = atlas.foliage_uv("plane", u0, v0, u0 + 0.75, v0 + 0.75)
        kit.add_card(bm, centre, outward, size, size * rng.uniform(0.7, 1.0), rect)
    p.mesh("Canopy", bm, M.foliage(), box_map=False)


def _plane_tree(variant):
    p = kit.Prop("PlaneTree%d" % (variant + 1))
    rng = random.Random(4100 + variant)
    _branch_skeleton(p, variant, rng)
    _canopy(p, variant, rng, cards=320)
    return p.finalize("PlaneTree%d" % (variant + 1))


def plane_tree_1():
    return _plane_tree(0)


def plane_tree_2():
    return _plane_tree(1)


def plane_tree_3():
    return _plane_tree(2)


# ------------------------------------------------------------------ planter
def _planter(quad):
    """White planter box 0.60 x 0.25 x 0.25 m with soil and a plant.

    The plant is a mass of 0.4-0.6 m cluster cards that cascade over the lip
    of the box: the cards show a third of a foliage quadrant, so the bracts and
    the leaves keep their real size (a bougainvillea bract is 3-5 cm).
    """
    p = kit.Prop("PlanterPot")
    p.box("Pot", (0.0, 0.0, 0.125), (0.60, 0.25, 0.25), M.surface(), bevel=0.015,
          surface="pot_white")
    p.box("Soil", (0.0, 0.0, 0.245), (0.54, 0.19, 0.03), M.surface(), surface="soil")
    p.tube("Pipe", (-0.28, 0.10, 0.27), (0.28, 0.10, 0.27), 0.012, M.surface(),
           segments=6, surface="black_plastic")
    rng = random.Random(77)
    bm = bmesh.new()
    # eight cards tilted 30-70 degrees outward: they cover the top of the box
    # and cascade over the long faces (dossier §2.4: parapet flower boxes)
    for i in range(10):
        x = -0.24 + (i % 5) * 0.12
        y = -0.085 if (i // 5) == 0 else 0.085
        lean = math.radians(30.0 + rng.uniform(0.0, 40.0))
        outward = (math.sin(lean) * (x / 0.30), math.sin(lean) * (y / 0.10) * 0.5,
                   math.cos(lean))
        height = 0.30 + rng.uniform(-0.02, 0.05)
        centre = (x, y, height)
        u0 = rng.uniform(0.0, 0.5)
        v0 = rng.uniform(0.0, 0.5)
        rect = atlas.foliage_uv(quad, u0, v0, u0 + 0.40, v0 + 0.40)
        size = rng.uniform(0.46, 0.60)
        kit.add_card(bm, centre, outward, size, size * rng.uniform(0.85, 1.05), rect)
    p.mesh("Plant", bm, M.foliage(), box_map=False)
    return p.finalize("PlanterPot")


def planter_pot_bougainvillea():
    """Deck planter with magenta bougainvillea (dossier §2.4)."""
    p = _planter("bougainvillea")
    p.name = "PlanterPotBougainvillea"
    return p


def planter_pot_privet():
    """Deck planter with golden privet (dossier §2.4)."""
    p = _planter("privet")
    p.name = "PlanterPotPrivet"
    return p


# ------------------------------------------------------------------ noise wall
def noise_wall():
    """3.5 m transparent noise-barrier panel on grey steel posts (dossier §2.4)."""
    p = kit.Prop("NoiseWall")
    for sx in (-1.0, 1.0):
        p.box("Post", (sx, 0.0, 1.75), (0.10, 0.16, 3.5), M.surface(), bevel=0.01,
              surface="galv")
        p.box("PostFoot", (sx, 0.0, 0.08), (0.34, 0.34, 0.16), M.surface(),
              surface="concrete")
    p.box("Panel", (0.0, 0.0, 1.85), (1.90, 0.03, 3.20), M.glass())
    for z in (0.35, 3.30):
        p.box("Rail", (0.0, 0.0, z), (2.00, 0.07, 0.07), M.surface(), bevel=0.01,
              surface="galv")
    return p.finalize("NoiseWall")


# ------------------------------------------------------------------ metro
def metro_entrance():
    """Glass and stainless canopy over the stairs plus a parody metro totem."""
    p = kit.Prop("MetroEntrance")
    p.box("Well", (0.0, 0.0, -1.30), (5.20, 3.60, 0.06), M.surface(), surface="plastic")
    for i in range(6):
        p.box("Step%d" % i, (0.0, 1.60 - i * 0.30, -0.12 - i * 0.17), (3.20, 0.30, 0.17),
              M.surface(), surface="concrete")
    p.box("Kerb", (0.0, 0.0, 0.03), (5.60, 4.00, 0.06), M.surface(), surface="pavement")
    for sx in (-2.40, 2.40):
        for sy in (-1.70, 1.70):
            p.cyl("Post", (sx, sy, 1.30), 0.055, 2.60, M.surface(), segments=8,
                  surface="alu")
    p.box("Roof", (0.0, 0.0, 2.62), (5.60, 3.80, 0.10), M.surface(), bevel=0.03,
          surface="alu")
    p.box("Fascia", (0.0, -1.88, 2.60), (5.60, 0.08, 0.30), M.surface(), bevel=0.02,
          surface="alu")
    for sx in (-2.40, 2.40):
        p.tube("Rail", (sx, -1.60, 1.05), (sx, 1.60, 1.05), 0.035, M.surface(),
               segments=8, surface="alu")
        p.tube("RailPost", (sx, -1.60, 0.05), (sx, -1.60, 1.05), 0.03, M.surface(),
               segments=6, surface="alu")
        p.tube("RailPost2", (sx, 1.60, 0.05), (sx, 1.60, 1.05), 0.03, M.surface(),
               segments=6, surface="alu")
    p.box("Totem", (3.10, -0.60, 1.55), (1.00, 0.14, 3.10), M.surface(), bevel=0.02,
          surface="alu")
    p.quad("TotemFace", 0.96, 2.90, M.sign(), (3.10, -0.675, 1.55), board="metro_totem")
    p.box("TotemFoot", (3.10, -0.60, 0.06), (1.20, 0.36, 0.12), M.surface(),
          surface="concrete")
    return p.finalize("MetroEntrance")


BUILDERS = {
    "plane_tree_1": plane_tree_1,
    "plane_tree_2": plane_tree_2,
    "plane_tree_3": plane_tree_3,
    "planter_pot_bougainvillea": planter_pot_bougainvillea,
    "planter_pot_privet": planter_pot_privet,
    "noise_wall": noise_wall,
    "metro_entrance": metro_entrance,
}
