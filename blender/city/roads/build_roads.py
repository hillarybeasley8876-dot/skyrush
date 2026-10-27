"""Build every road of a city into 512 m tiles plus the derived data files.

    tools/blender.sh run blender/city/roads/build_roads.py -- \
        --city data/city/test_city.json --out game/assets/city/roads [--only tx,tz]
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.expanduser("~/m/skyrush/blender"))
from lib import common  # noqa: E402

from city.roads import (attaches, collision, deck, edgewalls, furniture, junctions, lanes,  # noqa: E402
                        load, markings, materials, piers, profiles, surface, tiles, tunnel)
DATA_DIR = os.path.expanduser("~/m/skyrush/game/world/data")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--city", default=None)
    p.add_argument("--out", default=tiles.ASSETS)
    p.add_argument("--only", default=None, help="tile key, e.g. 0,0")
    p.add_argument("--data", default=DATA_DIR)
    p.add_argument("--no-textures", action="store_true")
    p.add_argument("--no-data", action="store_true")
    p.add_argument("--no-edgewalls", action="store_true",
                   help="do not add the walls on the edges of the decks that nothing else fences (edgewalls.py)")
    p.add_argument("--lanes-only", action="store_true",
                   help="build the lane graph and write only <data>/lanes.json (no tiles, about 10x faster)")
    return p.parse_args(argv)


def build_road(city, road, tileset, records, paths=()):
    """Build one road: geometry, markings, collision and (for decks) piers."""
    lay = profiles.layout(road)
    excluded = set()
    for junction in city.junctions_of(road):
        excluded |= junctions.trim_indices(city, road, junction, road.path)
    # a ramp that leaves this road cuts a gap in its parapet and planter row,
    # and the traffic of the city cuts the median where it crosses the road
    gaps = {}
    if road.elevated or lay["median_half"] > 0.0:
        gaps = attaches.parapet_gaps(city, road)
    for (key, run) in tiles.tile_runs(road):
        builder = tileset.builder(key)
        if road.elevated:
            deck.build(road, run, builder, lay, gaps)
        elif road.kind == "tunnel":
            tunnel.build(road, run, builder, lay, excluded)
        else:
            surface.build_asphalt(road, run, builder, lay)
        for sub in tiles.split_runs(run, excluded):
            if not road.elevated:
                surface.build_edges(road, sub, builder, lay)
                surface.build_median(road, sub, builder, lay)
            markings.build_lane_markings(road, lay, builder, sub)
        collision.build(road, run, builder, lay, excluded, gaps)
    if road.elevated:
        # the pots, the joints, the scuppers and the planted strip are built in
        # one pass over the road, so they are never built twice at a tile border
        deck.build_details(road, tileset, lay, gaps)
        # the outer edge of the acceleration strips is a deck edge like any
        # other: it gets a parapet like the deck's own edge
        deck.build_strip_parapets(city, road, tileset, lay)
    if road.kind == "tunnel":
        # the gantry and the face of a portal stand where the trough meets the
        # bore: the two ends of the road are junctions at grade now
        for face in tunnel.portal_faces(road):
            builder = tileset.builder_at(face["point"])
            tunnel.build_portal(road, builder, lay, face)
    if road.elevated:
        piers.build(city, road, tileset, records["piers"], paths)
    if road.kind == "ramp":
        for at_end, key in ((True, "attach_end"), (False, "attach_start")):
            if not road.data.get(key):
                continue
            idx = 0 if at_end else len(road.path) - 1
            attaches.build_gore(city, road, tileset, lay)
        # the parent road widens over the last 150 m: the acceleration lane
        deck.build_acceleration(city, road, tileset, lay)
    if road.bridge:
        deck.build_cable_anchors(road, tileset, lay)


def main():
    args = parse_args()
    start = time.time()
    common.reset()
    city, path = load.load(args.city)
    print("CITY %s  %d roads  %d junctions" % (path, len(city.roads), len(city.junctions)))
    materials.build()
    tileset = tiles.TileSet()
    records = {"piers": []}
    lane_data = lanes.build_lanes(city)
    if args.lanes_only:
        os.makedirs(args.data, exist_ok=True)
        with open(os.path.join(args.data, "lanes.json"), "w") as fh:
            json.dump(lane_data, fh, ensure_ascii=False)
        print("DATA lanes.json (lanes only)")
        print("DONE in %.1f s" % (time.time() - start))
        return
    paths = lanes.connector_points(lane_data)
    # The ramps are built last: the roof cut of an attach narrows the
    # collider of the parent's carriageway, and that collider has to be there
    # before the cut runs.
    roads = ([r for r in city.roads if r.kind != "ramp"]
             + [r for r in city.roads if r.kind == "ramp"])
    for road in roads:
        build_road(city, road, tileset, records, paths)
    for junction in city.junctions:
        junctions.build(city, junction, tileset)
    # The joints of the elevated chain: the wide deck of a road ends where the
    # narrow deck of the next one starts, and the hole between the two end
    # caps is closed with a nose and a fence before the edge walls are added
    # (the edge walls must see the fence and not build a second wall there).
    deck.build_joint_ends(city, tileset)
    only = None
    if args.only:
        parts = args.only.replace("_", ",").split(",")
        only = (int(parts[0]), int(parts[1]))
    if not args.no_edgewalls:
        print("EDGEWALLS %s" % edgewalls.add(tileset, lane_data))
    shared = materials.build(tex_dir=os.path.expanduser("~/m/skyrush/tmp/roads/tex"))
    materials.strip_shader_textures()
    print("MATERIALS %d" % len(shared))
    stats = tiles.export_tiles(tileset, only=only, out_dir=args.out)
    total = sum(s["tris"] for s in stats)
    print("TILES %d  total %d tris  max %d" %
          (len(stats), total, max([s["tris"] for s in stats] or [0])))
    if not args.no_data:
        write_data(city, records, args.data, lane_data)
    print("DONE in %.1f s" % (time.time() - start))


def write_data(city, records, data_dir, lane_data=None):
    """Write lanes.json, minimap.json and road_furniture.json."""
    os.makedirs(data_dir, exist_ok=True)
    lane_data = lane_data or lanes.build_lanes(city)
    minimap = lanes.build_minimap(city)
    items, anchors = furniture.build(city)
    for name, data in (("lanes.json", lane_data), ("minimap.json", minimap),
                       ("road_furniture.json", {"version": 1, "props": items,
                                                "cable_anchors": anchors,
                                                "piers": records["piers"]})):
        with open(os.path.join(data_dir, name), "w") as fh:
            json.dump(data, fh, ensure_ascii=False)
        print("DATA %s" % name)


main()
