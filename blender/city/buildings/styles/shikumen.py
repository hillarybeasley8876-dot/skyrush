"""Shikumen (石库门) row houses: 2-3 storey lane houses in 弄堂 blocks.

Grey-blue brick with red band courses, a stone door frame with a carved pediment,
black lacquer double doors, wooden windows with a real reveal, a tiled roof with a
ridge course and a dormer (老虎窗), and laundry poles across the lane.

Every window and the door are real holes in the wall: the wall is built as pier and
spandrel strips around the openings, the glass sits at the back of the reveal and
the frame stands proud of the brick.
"""
import math

from .. import openings, plan, shapes
from ..parts2 import add_dormer, add_eave_board, add_ridge_course, edge_boxes
from ..parts3 import add_ac_unit, add_drain_pipe, add_laundry_pole, add_potted_plant
from ..parts3 import add_ring_knocker, add_satellite_dish, add_wall_lamp

FLOOR_GROUND = 3.4
FLOOR_UP = 3.2
HOUSE_DEPTH = 12.0
LANE_WIDTH = 3.5
MIN_WIDTH = 3.6          # a house is never a sliver
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


def _eaves(storeys):
    return FLOOR_GROUND + FLOOR_UP * (storeys - 1)


def _recess_poly(poly, front_edge, depth):
    """The footprint with the front edge pushed `depth` metres into the house."""
    a = poly[front_edge]
    b = poly[(front_edge + 1) % len(poly)]
    fc = plan.facade(poly, front_edge)
    n = fc["n"]
    a2 = (a[0] - n[0] * depth, a[1] - n[1] * depth)
    b2 = (b[0] - n[0] * depth, b[1] - n[1] * depth)
    out = [a2, b2]
    for i in range(2, len(poly)):
        out.append(poly[(front_edge + 2 + i - 2) % len(poly)])
    return out


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


def _house(ctx, poly, front_edge, storeys, rng, rec, guard=None, skip_upper=()):
    """One shikumen house: walls with real openings, a tiled roof and a dormer."""
    ctx.begin_building(poly)
    eaves = _eaves(storeys)
    ground_poly = _recess_poly(poly, front_edge, ENTRY_RECESS)
    brick = ctx.bag.bm("brick")
    # --- the ground floor: the recessed footprint, with the door in its front wall
    gfc = plan.facade(ground_poly, front_edge)
    # the neighbour guard: no two houses in a row get the same door and window layout
    door_frac = 0.35
    if guard is not None:
        door_frac = guard.choose(lambda: round(rng.uniform(0.30, 0.70), 2), salt="door")
    door = _door(ctx, gfc, rng, door_frac)
    for edge in range(4):
        fc = plan.facade(ground_poly, edge)
        holes = [door] if edge == front_edge else []
        openings.build_facade(brick, fc, holes, 0.0, FLOOR_GROUND, WALL_T)
    # --- the upper floors: the full footprint, with the windows in the front wall
    up_fc = plan.facade(poly, front_edge)
    nwin = 2 if up_fc["w"] > 3.4 else 1
    if guard is not None:
        nwin = guard.choose(lambda: 2 if up_fc["w"] > 3.2 else 1, salt="nwin")
    holes = []
    for f in range(1, storeys):
        h0 = FLOOR_GROUND + FLOOR_UP * (f - 1) + WIN_SILL
        for i in range(nwin):
            u = up_fc["w"] * (i + 0.5) / nwin
            holes.append(_window(ctx, up_fc, u, h0, rng))
    for edge in range(4):
        if edge in skip_upper:
            # the party wall with the neighbour: the row has the same height
            continue
        fc = plan.facade(poly, edge)
        holes_e = holes if edge == front_edge else []
        openings.build_facade(brick, fc, holes_e, FLOOR_GROUND, eaves, WALL_T)
    # the slab over the 门堂 alcove
    a = poly[front_edge]
    b = poly[(front_edge + 1) % 4]
    n = up_fc["n"]
    porch = [(a[0], a[1]), (b[0], b[1]),
             (b[0] - n[0] * ENTRY_RECESS, b[1] - n[1] * ENTRY_RECESS),
             (a[0] - n[0] * ENTRY_RECESS, a[1] - n[1] * ENTRY_RECESS)]
    shapes.add_prism(ctx.bag.bm("render"), porch, FLOOR_GROUND - 0.30, FLOOR_GROUND,
                     cap_bottom=False)
    # the red band courses at every floor line
    for h in (FLOOR_GROUND, FLOOR_GROUND + FLOOR_UP):
        if h + 0.55 < eaves:
            edge_boxes(ctx.bag.bm("brick_red"), poly, h + 0.05, h + 0.50, 0.10, offset=0.03)
    # --- the roof: a gable with a ridge course, an eave board and a gutter
    if rng.random() < 0.16:
        shapes.add_prism(ctx.bag.bm("roof"), poly, eaves, eaves + 0.12)
        edge_boxes(ctx.bag.bm("render"), poly, eaves + 0.12, eaves + 0.95, 0.22, offset=0.02)
        rec["height"] = eaves + 0.95
    else:
        pitch = rng.uniform(1.1, 1.9)
        shapes.add_gable_roof(ctx.bag.bm("roof"), poly, eaves, eaves + pitch,
                              ridge_edge=front_edge, overhang=0.4)
        add_ridge_course(ctx, poly, eaves + pitch, front_edge)
        add_eave_board(ctx, poly, eaves, front_edge)
        rec["height"] = eaves + pitch
        # a dormer (老虎窗) in the street slope
        if rng.random() < 0.55:
            add_dormer(ctx, up_fc, eaves, eaves + pitch)
    # --- the street clutter
    # a warm lamp beside the door, with its pool of light on the step
    lamp_u = door["u1"] + 0.28
    if lamp_u < gfc["w"] - 0.2:
        add_wall_lamp(ctx, openings.wall_point(gfc, lamp_u), gfc["n"], 2.45)
        pool = openings.wall_point(gfc, lamp_u)
        pool = (pool[0] - gfc["n"][0] * 0.55, pool[1] - gfc["n"][1] * 0.55)
        shapes.add_ground_quad(ctx.bag.bm("emissive_warm"),
                               [(pool[0] - 0.45, pool[1] - 0.45), (pool[0] + 0.45, pool[1] - 0.45),
                                (pool[0] + 0.45, pool[1] + 0.45), (pool[0] - 0.45, pool[1] + 0.45)],
                               0.16)
    # the laundry pole hangs under a window, not over the door
    if rng.random() < 0.55 and nwin:
        u = up_fc["w"] * (0.5 / nwin) + (up_fc["w"] * 0.5 / nwin if nwin == 1 else 0.0)
        p = openings.wall_point(up_fc, u)
        add_laundry_pole(ctx, p, up_fc["n"], rng.uniform(1.6, 2.4),
                         FLOOR_GROUND + 0.30, rng.randint(3, 6))
    if rng.random() < 0.22:
        p = openings.wall_point(up_fc, up_fc["w"] * 0.08)
        add_drain_pipe(ctx, p, up_fc["n"], 0.0, eaves)
    # one to three potted plants on the step
    for _ in range(rng.randint(1, 3)):
        pu = door["u0"] - rng.uniform(0.1, 0.5)
        if pu < 0.2 or pu > gfc["w"] - 0.2:
            continue
        add_potted_plant(ctx, openings.wall_point(gfc, pu), gfc["n"], rng.uniform(0.3, 0.5))
    # an AC unit under a side window and a satellite dish on the roof edge
    if rng.random() < 0.55:
        side = plan.facade(poly, 1 if rng.random() < 0.5 else 3)
        su = side["w"] * rng.uniform(0.25, 0.75)
        add_ac_unit(ctx, openings.wall_point(side, su), side["n"],
                    FLOOR_GROUND + rng.uniform(0.2, 1.2), 0.75)
    if rng.random() < 0.20:
        add_satellite_dish(ctx, openings.wall_point(up_fc, up_fc["w"] * 0.85), up_fc["n"],
                           eaves - 0.4)
    rec["style"] = "shikumen"
    ctx.end_building()
    return rec


def poly_of(frame, s0, t0, s1, t1):
    """The city polygon of a rectangle in the block frame."""
    return plan.rectangle(frame, s0, t0, s1, t1)


def _lane(ctx, frame, lane_t, lane_t2, s0, s1):
    """The 弄堂 lane: paving, a kerb and the drain channel in the middle."""
    step = 2.0
    s = s0
    while s < s1 - 0.3:
        w = min(step, s1 - s)
        tile = plan.rectangle(frame, s, lane_t, s + w, lane_t2)
        shapes.add_ground_quad(ctx.bag.bm("paving"), tile, 0.06)
        s += w
    # the kerb along both sides of the lane
    for t in (lane_t, lane_t2):
        edge = plan.rectangle(frame, s0, t - 0.12, s1, t + 0.12)
        shapes.add_prism(ctx.bag.bm("stone_pale"), edge, 0.0, 0.14, cap_bottom=False)


def _lane_laundry(ctx, frame, s, lane_t, lane_t2, rng):
    """Laundry across the lane: a bamboo pole from one house to the other."""
    h = rng.uniform(3.4, 4.2)
    p0 = frame.to_city(s, lane_t + 0.15)
    p1 = frame.to_city(s, lane_t2 - 0.15)
    mid = ((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5)
    length = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    ang = math.degrees(math.atan2(p1[1] - p0[1], p1[0] - p0[0]))
    shapes.add_box(ctx.bag.bm("metal_galv"), mid, (length, 0.05), h, h + 0.05, rot_deg=ang)
    # the garments hang in the plane of the pole
    normal = frame.u
    count = rng.randint(3, 6)
    for i in range(count):
        t = lane_t + 0.3 + (lane_t2 - lane_t - 0.6) * (i / max(1, count - 1))
        base = frame.to_city(s, t)
        gw = rng.uniform(0.45, 0.65)
        gh = rng.uniform(0.7, 1.1)
        slot = ctx.random_cell("cloth")
        uv = [(slot["u0"], slot["v0"]), (slot["u1"], slot["v0"]),
              (slot["u1"], slot["v1"]), (slot["u0"], slot["v1"])] if slot else None
        shapes.add_wall_quad(ctx.bag.bm("cloth"), base, normal, gw, h - gh, h, uv=uv)


def _gate(ctx, frame, lane_t, s_start, s_end, front_t, over_lane=False):
    """A 弄堂 gate: two granite piers, a carved lintel and the lane name on a plaque.

    A third of the gates carry a 过街楼: a room over the mouth of the lane, with a
    lit window and a small balcony.
    """
    gate_h = 4.2
    granite = ctx.bag.bm("granite")
    for t_edge in (lane_t - 0.35, lane_t + LANE_WIDTH + 0.35):
        pier = plan.rectangle(frame, s_start - 0.45, t_edge - 0.45, s_start + 0.45,
                              t_edge + 0.45)
        shapes.add_prism(granite, pier, 0.0, gate_h, cap_bottom=False)
    beam = plan.rectangle(frame, s_start - 0.4, lane_t - 0.45, s_start + 0.4,
                           lane_t + LANE_WIDTH + 0.45)
    shapes.add_prism(ctx.bag.bm("brick_red"), beam, 3.15, gate_h)
    # the carved lintel on the street face of the gate
    lintel = plan.rectangle(frame, s_start - 0.42, lane_t - 0.52, s_start + 0.42,
                             lane_t - 0.40)
    shapes.add_prism(granite, lintel, 3.30, 4.05, cap_bottom=False)
    slot = ctx.random_cell("carving")
    if slot is not None:
        uv = [(slot["u0"], slot["v0"]), (slot["u1"], slot["v0"]),
              (slot["u1"], slot["v1"]), (slot["u0"], slot["v1"])]
        base = frame.to_city(s_start - 0.34, lane_t - 0.53)
        normal = (-frame.n[0], -frame.n[1])
        shapes.add_wall_quad(ctx.bag.bm("carving"), base, normal, 0.68, 3.36, 3.98, uv=uv)
    # the plaque faces down the lane towards the street
    normal = (-frame.u[0], -frame.u[1])
    base = (frame.origin[0] + frame.u[0] * (s_start - 0.46) + frame.n[0] * (lane_t + LANE_WIDTH * 0.5),
            frame.origin[1] + frame.u[1] * (s_start - 0.46) + frame.n[1] * (lane_t + LANE_WIDTH * 0.5))
    slot = ctx.next_sign("plaque")
    if slot is not None:
        uv = [(slot["u0"], slot["v0"]), (slot["u1"], slot["v0"]),
              (slot["u1"], slot["v1"]), (slot["u0"], slot["v1"])]
        shapes.add_wall_quad(ctx.bag.bm("plaque"), base, normal, 1.15, 3.30, 3.90, uv=uv)
    if over_lane:
        _over_lane(ctx, frame, lane_t, s_start)


def _over_lane(ctx, frame, lane_t, s_start):
    """The 过街楼: a room over the mouth of the lane."""
    poly = plan.rectangle(frame, s_start - 0.85, lane_t - 0.9, s_start + 0.85,
                           lane_t + LANE_WIDTH + 0.9)
    shapes.add_prism(ctx.bag.bm("render"), poly, 4.20, 6.40)
    # the window on the street face, with a lit room behind it
    fc = plan.facade(poly, 3)
    slot = ctx.random_cell("interior")
    uv = [(slot["u0"], slot["v0"]), (slot["u1"], slot["v0"]),
          (slot["u1"], slot["v1"]), (slot["u0"], slot["v1"])] if slot else None
    openings.add_pane(ctx, fc, fc["w"] * 0.28, fc["w"] * 0.72, 4.78, 5.98, 0.10,
                      "interior", uv=uv)
    # the small balcony in front of the window
    t = shapes.wall_tangent(fc["n"])
    c = (fc["a"][0] + t[0] * fc["w"] * 0.5 + fc["n"][0] * 0.35,
         fc["a"][1] + t[1] * fc["w"] * 0.5 + fc["n"][1] * 0.35)
    ang = math.degrees(math.atan2(fc["t"][1], fc["t"][0]))
    # the balcony sits under the window: a rail in front of it would hide the pane
    shapes.add_box(ctx.bag.bm("metal_dark"), c, (fc["w"] * 0.6, 0.08), 4.28, 4.62,
                   rot_deg=ang)


def generate(ctx, block, frame, rng, records):
    """Lay out a shikumen block: a street row of houses, a lane, and a back row."""
    s0, s1 = frame.s_range
    t0, t1 = frame.t_range
    setback = float(block.get("setback", 2.0))
    front_t = t0 + setback
    widths = plan.frontage_lots(frame, 4.2, MIN_WIDTH, rng, 0.15)
    # a parcel that is too shallow for a house is left to the ground cover
    depth = min(HOUSE_DEPTH, t1 - front_t)
    if depth < 8.0:
        return
    rows = []
    if t1 - front_t >= 2 * depth + LANE_WIDTH:
        rows.append((front_t, front_t + depth, 0))
        # the back row opens onto the lane, not onto the back of the block
        rows.append((front_t + depth + LANE_WIDTH, front_t + 2 * depth + LANE_WIDTH, 0))
    else:
        rows.append((front_t, front_t + depth, 0))
    from ..variety import NeighbourGuard
    guard = getattr(ctx, "guard", None) or NeighbourGuard()
    for ri, (ta, tb, front_edge) in enumerate(rows):
        # a row of houses has the same height: the party walls are then shared
        row_storeys = 3 if rng.random() < 0.35 else 2
        for wi, (wa, wb) in enumerate(widths):
            if not plan.fits(frame, wa, ta, wb, tb, margin=0.4, water=ctx.water,
                             roads=ctx.roads):
                continue
            # every eighth plot is left open for a lane gate (弄堂口)
            if ri == 0 and wi % 8 == 7 and len(rows) > 1:
                ctx.begin_building(poly_of(frame, wa, ta, wb, tb))
                _gate(ctx, frame, front_t + depth, wa - 0.4, wb + 0.4, front_t,
                      over_lane=(wi % 3 == 1))
                ctx.end_building()
                continue
            poly = plan.rectangle(frame, wa, ta, wb, tb)
            storeys = row_storeys
            # the inner houses share their side walls with the neighbours
            skip = ()
            if len(widths) > 2 and 0 < wi < len(widths) - 1:
                skip = (1, 3)
            rec = {"style": "shikumen", "seed": rng.randrange(1, 9999), "floors": storeys}
            _house(ctx, poly, front_edge, storeys, rng, rec, guard, skip_upper=skip)
            rec["poly"] = [[round(x, 2), round(z, 2)] for x, z in poly]
            rec["id"] = "%s_%d" % (block["id"], len(records))
            records.append(rec)
    # the lane between the two rows
    if len(rows) > 1 and widths:
        ctx.begin_building(poly_of(frame, s0, front_t, s1, front_t + 1.0))
        lane_t = front_t + depth
        lane_t2 = lane_t + LANE_WIDTH
        _lane(ctx, frame, lane_t, lane_t2, s0, s1)
        _gate(ctx, frame, lane_t, widths[-1][1] + 0.4, widths[-1][1] + 0.4, front_t,
              over_lane=True)
        # the laundry across the lane: a third of the house pairs
        for wi, (wa, wb) in enumerate(widths):
            if wi % 3 != 2:
                continue
            _lane_laundry(ctx, frame, (wa + wb) * 0.5, lane_t, lane_t2, rng)
        ctx.end_building()
