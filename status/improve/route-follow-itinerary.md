# route-follow-itinerary — every race drives the roads of its itinerary

## Plan

1. Measure the gate distance **along the itinerary** in
   `tools/city/city_marks_routes.py`: `_itinerary_stations` walks the
   samples of every stretch of the itinerary and sums the road length
   between two neighbouring samples, `_refine`/`_bisect` find the station
   of a gate on that measure.  `driven_distance(last gate, x)` no longer
   decides where a gate goes.
2. Teach the generator what the **game** drives, because the game builds
   the racing line of a leg from the shortest *lane* path between the two
   gates (`game/world/api/route_builder.gd`): `_game_graph` builds the
   lane graph of the game (every turn of a junction has a connector, a
   turn of more than 100 degrees costs the hairpin cost of the game, the
   junctions that meet each other make a connector that turns back on
   itself) and the search keeps the legs whose way stays on the
   itinerary.
3. Keep the gates where the game can drive them: the game cuts the lanes
   of a road around a junction, so a gate that stands in the cut has no
   lane to sit on (`_junction_penalty`).
4. Keep every road of the itinerary: a leg that cuts a corner leaves a
   road of the itinerary undriven (`SKIPPED` in the check), so the search
   pays for the roads of the itinerary that the race does not drive
   (`MISSED_COST`).
5. Fix the itineraries in `ROUTE_SPECS` where a transition has no way in
   the game, keeping the character of the route.
6. Run the gate: `accept_rules.py`, `check_route_loop.py` and the Godot
   test `test_route_layers.gd`.

## Done

- The gate distance is measured along the itinerary
  (`_itinerary_stations`, `_step`, `_refine`, `_bisect`); the search walks
  the itinerary and places a gate every 300 to 500 m of it
  (`_gates`, `_candidates`).
- The generator models the way the game drives (`_game_graph`,
  `_junction_costs`): the graph of the game with a connector for every
  turn, the hairpin cost of the game for a sharp turn, the twin
  junctions that make a connector turn back on itself, and the plan gap
  of a connector.  The search keeps the legs whose way the game drives
  stays on the roads of the route (`_off_route`).
- The gates stand clear of the junctions (`_junction_clear`,
  `_junction_penalty`): the kerb of a road stops where a junction takes
  over and the game cuts the lanes of the road there, so a gate in the
  cut has no lane to sit on and the race cannot reach it.
- The search pays for the roads of the itinerary that the race does not
  drive (`MISSED_COST`, `_roads_of`): a leg that cuts a corner leaves a
  road of the itinerary undriven, and the check reports it as SKIPPED.
- The itineraries whose transition has no way in the game are changed.
  The movements were read from the lanes themselves (a connector lane of
  a junction carries the road and the direction of a neighbour, not of
  the way it goes, so the movements have to be read through the
  connectors):
  - the `grand_loop` keeps the first ten roads up to the tunnel, goes by
    the Nanjing E. Rd and the Bund, and comes back by the Beijing Rd,
    the Fujian Rd and the Yan'an Rd to the G50;
  - the `river_loop` keeps the Pudong South Rd, the Century Ave, the
    tunnel, the Henan Rd, the Dongchang Rd, the Nanjing E. Rd and the
    Bund;
  - the `bund_sprint` keeps the Bund, the Nanjing E. Rd, the Henan Rd and
    the tunnel;
  - the `lujiazui_ring` drives the ring road on its own.

## How to test

    python tools/city/build_city.py --out data/city/city.json
    python tools/city/check_route_itinerary.py data/city/city.json game/world/data/lanes.json --routes grand_loop,elevated_sprint,river_loop,lujiazui_ring
    python tools/city/check_routes_drivable.py data/city/city.json game/world/data/lanes.json
    python tools/city/accept_rules.py data/city/city.json --baseline tools/city/rules_baseline.json
    python tools/city/check_route_loop.py data/city/city.json F:/dev/skyrush-out/tmp/route-follow/ref_city.json --loop-only
    python tools/gd.py test res://world/tests/test_route_layers.gd -- --timeout=420

## Evidence

The acceptance, on the build of this branch (the map of the reference
city, only the routes changed):

    build            : json size  : 2.76 MB   (1 min 6 s)
    only the routes  : ONLY_ROUTES
    check_route_itinerary : ROUTE_ITINERARY OK
        route grand_loop       36 gates, 25 itinerary roads: ok
        route elevated_sprint  23 gates, 10 itinerary roads: ok
        route river_loop       11 gates,  9 itinerary roads: ok
        route bund_sprint       6 gates,  7 itinerary roads: ok
        route lujiazui_ring     7 gates,  1 itinerary roads: ok
    check_routes_drivable : ROUTES_DRIVABLE OK
        route grand_loop       36 legs,  0 bad, driven 17.1 km, 0 reversals
        route elevated_sprint  22 legs,  0 bad, driven  9.9 km, 0 reversals
        route river_loop       10 legs,  0 bad, driven  5.1 km, 0 reversals
        route bund_sprint        5 legs,  0 bad, driven  2.6 km, 0 reversals
        route lujiazui_ring     7 legs,  0 bad, driven  2.5 km, 0 reversals
    accept_rules     : ACCEPT_RULES OK
        rule "route checkpoints on the lanes": 0 failures (base 0)
    check_route_loop : ROUTE_LOOP OK
    test_route_layers: ROUTE LAYERS TESTS OK (46 checks)

The map of the branch is the map of the reference: only the `routes` key
of `data/city/city.json` differs from
`F:/dev/skyrush-out/tmp/route-follow/ref_city.json`.

## Known issues

- The `river_loop` does not drive the Lujiazui ring road.  The game has
  no lane from the ring road to the Yincheng Rd, the road that joins it
  to the tunnel (the brief lists that link as missing), and the ring
  road meets the tunnel on its other side, so the race cannot enter the
  ring road at the Century Ave and leave it at the tunnel.  The ring
  road is raced by the `lujiazui_ring` (7 gates, the whole ring, the
  race stays on the ring) and the Century Ave is raced by the
  `grand_loop` and by the `river_loop`.
- The `grand_loop` and the `bund_sprint` drive the D1 E-W street and the
  Dongchang Rd where the reference drove the D2 E-W street: the D2 E-W
  street meets the Nanjing E. Rd in two junctions 14 m apart
  (`j_st_d2_ew_4_st_nanjing_e_rd` and `..._1`), and the connector the
  game builds between them turns back on itself, so the race that turns
  there reverses.
- `tools/city/city_marks_routes.py` is 961 lines (it was 407): the model
  of the way the game drives and the search for the gates need the
  room.  I may not add a second file, so the model could not be split
  out of the module.

## Requests

- **The map depends on the routes.**  `tools/city/city_snap.py`
  (read-only for me) calls `city_marks_routes.build_routes` on the
  half-built map and keeps the roads of every route with fewer than 10
  checkpoints away from the new link streets (`ROUTE_CHECKPOINTS = 10`).
  The roads of the routes are therefore part of the map: a road that
  joins them moves the link streets, and `blocks`, `junctions` and
  `roads` of city.json change with them (acceptance 2 fails).  The
  itineraries of this job are the ones the map was built with.
- The gate of a route stands on a lane of the road, but the game cuts
  the lanes of a road around a junction and where the buildings of the
  Bund cut them.  The generator knows the junction cuts (it knows the
  width of every road) but not the buildings, so a gate can still stand
  where the Bund's buildings took the lane.  It happens today on the
  Beijing Rd next to the Bund: the gate stands 3 m from the end of the
  inner lane, where the building of the Bund cut it, and the race
  reaches it because the game finds a lane within 8 m.  The search keeps
  the gate there because it is far enough from the junction.
