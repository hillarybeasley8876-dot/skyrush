# hud-route — the minimap shows the race route and the next gate

## Plan
1. Read SPEC/CONTRACTS, `game/core/events.gd` (the `mode_status` contract), the HUD unit, the
   modes unit and their tests. [done]
2. Write `game/ui/hud/tests/test_route_marker.gd` (panel, HUD, modes) and run it on the OLD code:
   every check must FAIL with a FAIL line (no script error). [done: 12 FAIL lines]
3. `game/modes/race_results.gd` + `race_session.gd`: the race status carries `route`,
   `next_gate` and `gates`. [done]
4. `game/ui/hud/minimap_panel.gd` + `minimap_icons.gd` + `minimap_route.gd` (new): the route
   polyline (cached, projected every frame) and the pulsing amber gate marker. [done]
5. `game/ui/hud/hud_events.gd` + `hud.gd`: the race status gives the minimap the route (only
   when the route id changes) and the next gate (only when it changes); any other status clears
   them. [done]
6. Run the acceptance: `gd.py check --only=res://ui/hud/` and `--only=res://modes/`, the new test,
   `tools/mutation_check.py --test res://ui/hud/tests/test_route_marker.gd --files auto`,
   `tools/run_tests.py --filter res://ui/hud/` and `--filter res://modes/`. [done]

## Done
- `game/modes/race_results.gd`: `live_status(laps, route_id, next_gate, gates)` builds the whole
  race status of the bus, `player_next_gate()` gives the gate the player has to pass next
  (-1 when the player is home or not in the race).
- `game/modes/race_session.gd`: `_push_status` pushes `route` (the id of the route that runs),
  `next_gate` (the `next_cp` of the player) and `gates` (`gates.size()`) with the status.
- `game/ui/hud/minimap_route.gd` (new, 38 lines): the racing line of the race on the map. The
  world points are projected into a cached array every frame, so a redraw allocates nothing; the
  line is 3.2 px wide in the cyan of the HUD, so it reads over the 2.4 px roads.
- `game/ui/hud/minimap_panel.gd`: the plain members `route_points`, `next_gate_world`,
  `has_next_gate` and the methods `set_route()`, `clear_route()`, `set_next_gate()`,
  `clear_next_gate()`. The line is drawn after the map texture and the vignette (above the
  roads and the sky lanes) and before the icons; the gate marker is drawn with the other icons,
  after the blips.
- `game/ui/hud/minimap_icons.gd`: `draw_gate()` draws the next gate as a pulsing amber diamond
  with a dark rim (it reads over the bright line of the route).
- `game/ui/hud/hud_events.gd`: the `&"race"` status gives the minimap the route (the racing line
  of `Game.world.get_route(route)`, thinned to one point every 10 m) and the next gate (the
  origin of `route.checkpoints[next_gate]`). The line is only rebuilt when the route id changes
  and the marker is only moved when the gate changes (the status arrives twice a second). Every
  other status (`&"free"`, `&"pursuit"`, `&"none"`) clears the route and the marker. The demo
  has no world, so it hands its own route in (`demo_route`).
- `game/ui/hud/hud.gd`: the minimap is handed to the bus handler.
- `game/ui/hud/demo/`: the demo builds a loop route with eight gates and fires it with the race
  status, so the captures show the line of the route and the next gate.
- `game/ui/hud/tests/test_route_marker.gd` (new, 236 lines): 26 checks — the panel on its own
  (the route polyline, the gate marker, the projection of a near and of a far gate), the HUD
  (the bus gives the minimap the route and the gate, the marker moves, `&"free"` clears both, a
  race without a next gate keeps the route) and the modes (the race status carries the route, the
  8 gates and the next gate of the player; the gate follows the pass of the first gate).

## In progress / next
- nothing. The job is done; the lead commits (the new files `game/ui/hud/minimap_route.gd` and
  `game/ui/hud/tests/test_route_marker.gd` are untracked, with their `.uid` files).

## How to test (exact commands)
- `python tools/gd.py test res://ui/hud/tests/test_route_marker.gd`
- `python tools/gd.py check --only=res://ui/hud/`
- `python tools/gd.py check --only=res://modes/`
- `python tools/mutation_check.py --test res://ui/hud/tests/test_route_marker.gd --files auto`
- `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/hud-route/tests_hud --allow-fail test_hud_perf`
- `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/hud-route/tests_modes`
- `python tools/gd.py shot --scene=res://ui/hud/demo/hud_demo.tscn --out=hud_route --times=4 --warm=30`

## Evidence (key output lines)
- the new test on the OLD code: `FAIL the minimap can take a route` ... `ROUTE MARKER TESTS FAILED
  (12 failures)`
- the new test now: `PASS the minimap has the line of the route (286 points)`, `PASS the marker is
  at the gate 2 of the route`, `PASS the marker moves to the next gate`, `PASS the race reports the
  route ({ "lap": 1, "laps": 2, "position": 1, "racers": 6, "route": "sandbox_loop",
  "next_gate": 0, "gates": 8 })`, `PASS the next gate follows the pass (... "next_gate": 1 ...)`,
  `ROUTE MARKER TESTS OK (0 failures)`
- `CHECK 35 files, 0 failed, 0 engine errors, 0 warnings` (hud) and `CHECK 26 files, 0 failed,
  0 engine errors, 0 warnings` (modes)
- `5 tests, 5 passed, 0 failed or timed out` + `RUN_TESTS_RATCHET OK (0 failing, all of them on
  the allow list)` (hud), `7 tests, 7 passed, 0 failed or timed out` (modes)
- `MUTATION_CHECK OK: the test fails on the old code of 759eab7a78 (12 FAIL lines, first: FAIL the
  minimap can take a route)`
- the capture (`F:/dev/skyrush-wt/skyrush-out/captures/hud_route3_t4_0.jpg`): the bright cyan line
  of the route on the minimap and the amber diamond of the next gate at the bottom right.

## Known issues
- the line of the route is the racing line of the route (the ideal line of the rivals), not the
  road of every gate: a route that leaves the road network is drawn as the line the rivals drive.
- the gate marker is only drawn when it is on the map (the panel is clipped): a gate 3 km away is
  not on the map and is not drawn.

## Requests
- none.
