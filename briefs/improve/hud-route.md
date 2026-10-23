# Job: the minimap shows the race route and the next gate

Godot GDScript, units `game/modes/` (a few lines) and `game/ui/hud/` (the minimap). Read `briefs/improve/_godot-common.md` first.

## Goal
In a race the player has no navigation aid: the minimap shows roads, points of interest and blips, but not where the route goes or where the next gate is. Show the route and the next gate on the minimap.

## Contract (already on the event bus, read the comment in `game/core/events.gd`)
`Events.mode_status(&"race", data)` now carries three more keys besides `lap`, `laps`, `position`, `racers`:
`"route"` (the route id, a String such as `"bund_sprint"`), `"next_gate"` (the index of the player's next checkpoint, -1 when the player is home) and `"gates"` (the number of checkpoints).

## What to build
1. **Modes** (`game/modes/`): the race status that `RaceSession` pushes (look at `_push_status` in `race_session.gd` and `live_status` in `race_results.gd`) gets the three keys: `route` = the id of the route that runs (`route_id` of the session), `next_gate` = `next_cp` of the player's racer (-1 when it is finished), `gates` = `gates.size()`.
2. **HUD** (`game/ui/hud/`): when a `&"race"` status arrives (the HUD already listens, see `hud_events.gd` `_on_mode_status`):
   - the minimap gets the route: `Game.world.get_route(StringName(route))` is a `RaceRoute`; its `racing_line` (a `Curve3D`) gives the points (`get_baked_points()`); turn them into a `PackedVector2Array` of world x/z, thinned to one point per 10 m, and call `minimap.set_route(points)` (new method of `minimap_panel.gd`). Do it only when the route id CHANGES (the status arrives twice a second).
   - the minimap draws the route as a bright line (cyan, thicker than the roads, drawn above the roads and the sky lanes, below the icons) with the same projection the roads use (read `_draw_layer`, `_rebuild_texture`, `project_point`);
   - the minimap draws the next gate: `route.checkpoints[next_gate].origin` (x/z) as a pulsing amber diamond marker at the gate (use the icon helper of `minimap_icons.gd`; clipped to the map like the other icons; update it when `next_gate` changes; no marker when `next_gate < 0`).
   - for every other kind of status (`&"free"`, `&"pursuit"`, `&"none"`) the route and the marker are cleared (`minimap.clear_route()`).
3. Nothing else changes: the roads, the blips, the zoom, the rotation of the map. The minimap has a performance test (`test_hud_perf.gd`): the route is drawn from a cached polyline, no allocation per frame.

## Files you own
`game/modes/` and `game/ui/hud/`. Existing tests are read-only. You add ONE new test file `game/ui/hud/tests/test_route_marker.gd`.

## The test you write FIRST (`game/ui/hud/tests/test_route_marker.gd`)
Build the HUD with a world like `game/ui/hud/tests/test_hud.gd` does, or - simpler and faster - build only the `MinimapPanel` (`res://ui/hud/minimap_panel.gd`) and call its methods directly. Checks (`PASS ...` / `FAIL ...`; end with `ROUTE MARKER TESTS OK (0 failures)` and quit 0, or `ROUTE MARKER TESTS FAILED` and quit 1):
1. `minimap.set_route(points)` with 3 or more points: the panel reports a route (expose `route_points: PackedVector2Array` and `next_gate_world: Vector2`, `has_next_gate: bool` as plain members) and `clear_route()` empties them.
2. `set_next_gate(Vector2(x, z))` / `clear_next_gate()`: `has_next_gate` follows; the projected position of the gate (`project_point`) is inside the clip when the gate is near the player and outside when it is 3 km away.
3. The HUD: emit `Events.mode_status.emit(&"race", {"lap": 1, "laps": 1, "position": 1, "racers": 6, "route": "<an id of a route the test world has>", "next_gate": 2, "gates": 8})` (the sandbox world has the route `sandbox_loop`; read how `test_hud.gd` or `test_modes.gd` get a world): after two frames the minimap has at least 20 route points, and the marker is at the origin of checkpoint 2 of that route (within 0.1 m). A later status with `next_gate = 3` moves the marker. `&"free"` clears both.
4. `next_gate = -1` clears the marker but keeps the route.
5. Modes: a race session started with `start_mode(&"race", {"route": "sandbox_loop", "laps": 2})` pushes a status with `route == "sandbox_loop"`, `gates == 8` and `next_gate == 0` at the start; after the player passes gate 0 (`Events` / the session's pass handler: see `game/modes/tests/test_modes.gd` or the rival tests for how a gate pass is simulated; if that is too heavy, call the session's `_on_gate_passed(player, 0)` directly) a status with `next_gate == 1` follows.
Run it BEFORE you change anything: every check must fail. Use `has_method` / `get` guards so that missing members give `FAIL` lines.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ui/hud/` and `--only=res://modes/` print `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ui/hud/tests/test_route_marker.gd` prints `ROUTE MARKER TESTS OK`.
3. `python tools/mutation_check.py --test res://ui/hud/tests/test_route_marker.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/hud-route/tests_hud --allow-fail test_hud_perf` and `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/hud-route/tests_modes` each end with `RUN_TESTS_RATCHET OK` / `, 0 failed or timed out`.

## Pitfalls
- Rebuilding the route polyline on every status (twice a second): only when the route id changes.
- A route of 3000 points drawn raw every frame: thin it to one point per 10 m once.
- The marker outside the map: it is clipped like the other icons (the helpers `project_point` and the clip test of the panel).
