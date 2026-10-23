"""The parts of a shikumen house: the 门堂 door, the pediment and the windows.

Every window and the door of a lane house is a real hole in the wall: the glass
sits at the back of the reveal, the frame and the architrave stand proud of the
brick, and the granite frame of the door carries a carved pediment.
"""
from .. import openings, shapes
from ..parts3 import add_ring_knocker

DOOR_W = 1.4
DOOR_H = 2.6
DOOR_RECESS = 0.30       # the black lacquer doors sit 30 cm inside the wall
FRAME_PROUD = 0.10       # the granite frame stands 10 cm proud of the brick
FRAME_IN = 0.14          # and reaches 14 cm into the reveal
WINDOW_RECESS = 0.15
WALL_T = 0.40            # the brick wall is 40 cm thick
ENTRY_RECESS = 1.1       # the ground floor is set back: the 门堂 entrance
WIN_W = 1.0
WIN_H = 1.7
WIN_SILL = 0.95
CASEMENT_PROUD = 0.08
CASEMENT_BACK = 0.02
KNOCKER_H = 1.10      # the ring knocker hangs at 1.10 m on each leaf


def _in_wall(fc, u, depth):
    """The city point on the wall at `u`, `depth` metres inside it."""
    p = openings.wall_point(fc, u)
    return (p[0] - fc["n"][0] * depth, p[1] - fc["n"][1] * depth)


def _door(ctx, fc, rng, u_frac=None):
    """The 门堂 door.

    A granite frame with a carved pediment, two black lacquer leaves 30 cm inside
    the wall and a brass ring knocker on each leaf.  Everything stands proud of the
    brick - nothing is coplanar with the wall.
    """
    u = fc["w"] * (u_frac if u_frac is not None else rng.uniform(0.35, 0.65))
    u0, u1 = u - DOOR_W * 0.5, u + DOOR_W * 0.5
    stone = ctx.bag.bm("stone_pale")
    wood = ctx.bag.bm("wood")
    brass = ctx.bag.bm("brass")
    # the two lacquer leaves, 30 cm inside the wall
    for side in (-1, 1):
        lu0 = u0 + 0.02 if side < 0 else u + 0.02
        lu1 = u + 0.02 if side < 0 else u1 - 0.02
        openings.wall_slab(wood, fc, lu0, lu1, 0.0, DOOR_H, DOOR_RECESS,
                           DOOR_RECESS + 0.06)
    # the brass ring knockers on the leaves
    if ctx.detail >= 3:
        for side in (-1, 1):
            ku = u + side * 0.12
            add_ring_knocker(ctx, _in_wall(fc, ku, DOOR_RECESS), fc["n"], KNOCKER_H)
    # the granite frame: two jambs, a lintel and a carved pediment
    jamb_w = 0.34
    for side in (-1, 1):
        ju0 = u0 - jamb_w if side < 0 else u1
        ju1 = u0 if side < 0 else u1 + jamb_w
        openings.wall_slab(stone, fc, ju0, ju1, 0.0, DOOR_H + 0.42, -FRAME_PROUD,
                           FRAME_IN)
    openings.wall_slab(stone, fc, u0 - jamb_w, u1 + jamb_w, DOOR_H + 0.42, DOOR_H + 0.78,
                       -FRAME_PROUD, FRAME_IN)
    if ctx.detail >= 2:
        _pediment(ctx, fc, u, DOOR_H + 0.78, stone)
    # the stone step in front of the door
    openings.wall_slab(stone, fc, u0 - 0.2, u1 + 0.2, 0.0, 0.16, -0.40, -0.10)
    return {"u0": u0, "u1": u1, "h0": 0.0, "h1": DOOR_H}


def _pediment(ctx, fc, u, h0, stone):
    """The carved pediment over the door lintel.

    A stone panel with a relief from the carved atlas (four motifs), framed by two
    jambs and a cornice and finished with a keystone.
    """
    panel_w = 1.05
    panel_h = 0.62
    slot = ctx.random_cell("carving")
    if slot is not None:
        uv = [(slot["u0"], slot["v0"]), (slot["u1"], slot["v0"]),
              (slot["u1"], slot["v1"]), (slot["u0"], slot["v1"])]
    else:
        uv = None
    base = openings.wall_point(fc, u - panel_w * 0.5)
    base = (base[0] - fc["n"][0] * (FRAME_PROUD - 0.02),
            base[1] - fc["n"][1] * (FRAME_PROUD - 0.02))
    shapes.add_wall_quad(ctx.bag.bm("carving"), base, fc["n"], panel_w, h0 + 0.02,
                         h0 + 0.02 + panel_h, uv=uv)
    # the frame of the panel and the cornice over it
    for side in (-1, 1):
        ju0 = u - panel_w * 0.5 - 0.09 if side < 0 else u + panel_w * 0.5
        ju1 = u - panel_w * 0.5 if side < 0 else u + panel_w * 0.5 + 0.09
        openings.wall_slab(stone, fc, ju0, ju1, h0, h0 + panel_h + 0.12,
                           -FRAME_PROUD + 0.01, FRAME_IN)
    openings.wall_slab(stone, fc, u - panel_w * 0.5 - 0.09, u + panel_w * 0.5 + 0.09,
                       h0 + panel_h + 0.02, h0 + panel_h + 0.14, -FRAME_PROUD + 0.01, FRAME_IN)
    # the keystone in the middle of the cornice
    openings.wall_slab(stone, fc, u - 0.09, u + 0.09, h0 + panel_h + 0.14,
                       h0 + panel_h + 0.30, -FRAME_PROUD + 0.02, FRAME_IN + 0.02)


def _window(ctx, fc, u, h0, rng):
    """A timber casement in a real reveal, with muntins and sometimes a curtain."""
    u0, u1 = u - WIN_W * 0.5, u + WIN_W * 0.5
    h1 = h0 + WIN_H
    lit = rng.random() < 0.34
    # the pane at the back of the reveal: an interior or dirty glass
    if lit:
        slot = ctx.random_cell("interior")
        uv = [(slot["u0"], slot["v0"]), (slot["u1"], slot["v0"]),
              (slot["u1"], slot["v1"]), (slot["u0"], slot["v1"])] if slot else None
        openings.add_pane(ctx, fc, u0, u1, h0, h1, WINDOW_RECESS, "interior", uv=uv)
    else:
        openings.add_pane(ctx, fc, u0, u1, h0, h1, WINDOW_RECESS, "glass")
    # the timber casement, standing proud of the brick (the sill is the masonry
    # below the opening, so the frame is three pieces and not four)
    openings.wall_slab(ctx.bag.bm("wood"), fc, u0 - 0.09, u0, h0, h1 + 0.09,
                       -CASEMENT_PROUD, -CASEMENT_BACK)
    openings.wall_slab(ctx.bag.bm("wood"), fc, u1, u1 + 0.09, h0, h1 + 0.09,
                       -CASEMENT_PROUD, -CASEMENT_BACK)
    openings.wall_slab(ctx.bag.bm("wood"), fc, u0 - 0.09, u1 + 0.09, h1, h1 + 0.09,
                       -CASEMENT_PROUD, -CASEMENT_BACK)
    # the muntin, in the reveal in front of the pane
    mu = u
    openings.wall_slab(ctx.bag.bm("wood"), fc, mu - 0.025, mu + 0.025, h0, h1,
                       WINDOW_RECESS - 0.05, WINDOW_RECESS)
    # a curtain on a third of the windows
    if rng.random() < 0.30:
        slot = ctx.random_cell("cloth")
        uv = [(slot["u0"], slot["v0"]), (slot["u1"], slot["v0"]),
              (slot["u1"], slot["v1"]), (slot["u0"], slot["v1"])] if slot else None
        side = -1 if rng.random() < 0.5 else 1
        cu0 = u0 if side < 0 else u + WIN_W * 0.5 - 0.02
        cu1 = u - WIN_W * 0.5 + 0.02 if side < 0 else u1
        openings.add_quad_in_reveal(ctx, fc, cu0, cu1, h0, h1, WINDOW_RECESS - 0.06,
                                    "cloth", uv)
    # the shutters (木百叶窗) beside the window
    if rng.random() < 0.40:
        for side in (-1, 1):
            su = u + side * (WIN_W * 0.5 + 0.16)
            openings.wall_slab(ctx.bag.bm("wood"), fc, su - 0.13, su + 0.13, h0 - 0.08,
                               h1 + 0.08, -0.07, -0.02)
    return {"u0": u0, "u1": u1, "h0": h0, "h1": h1}
