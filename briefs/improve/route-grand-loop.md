# Job: the grand loop comes back to its start (a race is a circuit)

City generator (`tools/city/`), routes only. No Godot needed; one Blender command (25 s) builds the lane graph of your map.
Read `briefs/improve/_map-common.md` first.

## Goal
`grand_loop` (申城大环线) is a race, and a race is a circuit: the game drives the racing line from the last checkpoint back
to the first one (game/world/api/route_builder.gd, `_is_circuit`). Its itinerary (`ROUTE_SPECS` in
`tools/city/city_marks_routes.py`) starts heading east on the Yan'an elevated road at (-1839, 734) and ends heading north at the
north end of the Bund (-149, -854). The way back from there to the start is 5.4 km of side streets north of the Bund and across
the Waibaidu bridge, with no gate at all: `python tools/city/check_routes_drivable.py` reports
`grand_loop leg 26->0: detour: 5463 m driven for 2320 m between the gates`.

Change the itinerary of `grand_loop` so that the route comes back to its start: every leg drivable, the closing leg (last
checkpoint -> first) short, and still the same race up to the tunnel (the elevated road, the dragon interchange, the N-S elevated
road, the inner ring, the Nanpu spiral and bridge, the Pudong loop, Pudong South Rd, Century Ave and the tunnel, in this order).

## What is known (measured, not guessed)
- The start is the start of `yanan_elevated` (heading east). `yanan_elevated` begins where `g50_west` ends (-1990, 728);
  `g50_west` runs east from the west edge of the map (-2200, 728). The only way onto `g50_west` heading east from the city is the
  junction `j_g50_west_st_d9_ns_2_yanan_frontage_s` (-2200, 755): from `st_d9_ns_2` heading north, a right turn.
- From the Yan'an Rd surface road heading west (`yanan_rd_surface` direction -1, it runs from (-1700, 740) to the Bund at (0, 0)):
  `st_d9_ns_8` (direction +1, south) at (-1650, 758) -> `st_d9_ew_3` (direction -1, west) at (-1650, 800) -> `st_d9_ns_2`
  (direction -1, north) at (-2200, 800) -> `g50_west` (direction +1). `yanan_frontage_s` is one way EAST, `yanan_frontage_n` one way
  WEST and it only turns right onto `st_d9_ns` at its west end: neither of them gets you onto `g50_west` heading east.
- The tunnel now comes out in Puxi at the east end of Fujian Rd (-360, 210), at a junction with `yanan_rd_surface` and
  `st_fujian_portal`: from the tunnel heading west you can go straight on into `yanan_rd_surface` heading west.
- There is NO right turn from Nanjing E Rd heading east (`st_nanjing_e_rd` -1) onto the Bund heading south: the corner is cut by a
  building of the Bund, the lane graph has no such link (an attempt with `("bund_zhongshan_e1", -1)` after Nanjing Rd drove 3.9 km
  round the north of the Bund to get there).
- An attempt that ended `... ("bund_zhongshan_e1", -1), ("yanan_rd_surface", -1), ("st_d9_ns_8", 1), ("st_d9_ew_3", -1),
  ("st_d9_ns_2", -1), ("g50_west", 1)` made the validator fail `route grand_loop: 191 m between cp31 and cp32` (the rule
  "route checkpoints on the lanes" wants 300-500 m between checkpoints): find out why before you try that kind of tail again.
- The checkpoints are placed by `_checkpoints` every 400 driven metres along the itinerary; the itinerary may name a road whose
  crossing with the next road is not in the lane graph: `_spans` then leaves it out (it prints `has no crossing in the map, the road
  is left out` on stderr). The same lines about the elevated roads are printed on today's map too and are not your problem.

## Files you own
`tools/city/city_marks_routes.py`, the `grand_loop` entry of `ROUTE_SPECS` only (its comment too). Every other route stays exactly
as it is. Everything else is read-only.

## How to test (scratch only, never write data/city/city.json)

    python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/route-grand-loop/city.json
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --lanes-only --city F:/dev/skyrush-out/tmp/route-grand-loop/city.json --data F:/dev/skyrush-out/tmp/route-grand-loop/data
    python tools/city/check_routes_drivable.py F:/dev/skyrush-out/tmp/route-grand-loop/city.json F:/dev/skyrush-out/tmp/route-grand-loop/data/lanes.json --lanes

The first takes about 25 s, the second about 30 s; the third prints every bad leg with its lane path. `--lanes` shows the lanes a
leg drives: read them to see where the route goes.

## Acceptance (the runner executes these itself, in order)
1. The map builds: the first command above prints `json size`.
2. The lane graph builds: the second prints `DONE in`.
3. Every route is drivable: `python tools/city/check_routes_drivable.py F:/dev/skyrush-out/tmp/route-grand-loop/city.json F:/dev/skyrush-out/tmp/route-grand-loop/data/lanes.json`
   prints `ROUTES_DRIVABLE OK` (no detour, no long leg, no reversal, in any route).
4. The rules gate: `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/route-grand-loop/city.json --baseline tools/city/rules_baseline.json`
   prints `ACCEPT_RULES OK`.
5. The loop: `python tools/city/check_route_loop.py F:/dev/skyrush-out/tmp/route-grand-loop/city.json data/city/city.json`
   prints `ROUTE_LOOP OK`: grand_loop keeps its itinerary up to the tunnel, its last checkpoint is within 900 m (in plan) of its
   first, and the four other routes have exactly the checkpoints they have in data/city/city.json.

## Pitfalls
- Do not change `_checkpoints`, the spacing constants, the rules, or another route to make a check pass.
- Keep the race a race: `("grand_loop", "申城大环线", "race", [...])`.
- A tail through narrow streets is allowed where it is the only way (the D9 turn onto `g50_west`), but prefer the big roads.
