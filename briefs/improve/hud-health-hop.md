# Job: the HUD shows the car's health and the "HOP" hint before a roadblock or a toll plaza

Godot GDScript, unit `game/ui/hud/`. Read `briefs/improve/_godot-common.md` first. The HUD draws what the game says: read `game/ui/hud/hud.gd` (the widget tree, `_update_*` per frame, `telemetry_override` for tests), `speed_cluster.gd` (the bottom right cluster) and `mode_status_readout.gd` (a small readout added by an earlier job: your two widgets can follow its style: labels from `UI.outlined_label`, colours from `Palette`, an update only when the shown value changed).

## Goal
Two things the design promises and the HUD does not show:
1. **The health of the car.** `CarTelemetry.health_norm` (0..1) is kept up to date for every car, but nothing in the HUD draws it. After a crash the player has no idea how close the wreck is. Dossier `ref/gameplay/DOSSIER.md` section 7.3 / 8.3: health is HP out of 100.
2. **The HOP hint.** Dossier 5.7: "HUD helper: 150 m before a roadblock/toll plaza flash '跳！HOP ▲' (amber) if the player has >= 50 N2." The player can fly over a roadblock or a toll plaza with a Big Hop (it costs 50 N2), but nothing tells them when to jump.

## What to build
1. **Health bar**: a thin horizontal bar with the caption `HP` under the speed cluster's battery row or at another place that does not collide with an existing cluster (`test_hud_layout.gd` checks the boxes: keep it green and read how it checks). The fill is `health_norm`, the colour changes: green above 60 %, amber between 25 % and 60 %, red below 25 % (blinking is not needed). A number `87` next to it. It updates only when the integer percent changes. It is hidden while the car is wrecked (`health_norm <= 0`) and in the menus (follow how the other clusters hide).
2. **HOP hint** (`game/ui/hud/hop_hint.gd`, new, a `Control` child of the HUD root, centred in the upper third of the screen): shown while ALL are true: the player has at least 50 N2 (`telemetry.n2`), the car is on the ground and not flying (`not telemetry.airborne and not telemetry.flying`), and a roadblock or toll plaza is ahead: within 150 m in front of the car (angle to the car's forward axis under 35 degrees, ahead means the dot product is positive) AND on the car's level (height difference at most 4 m; the map has decks). The sites are:
   - roadblocks of the world: `Game.world.get_roadblock_sites()` (`Array[Transform3D]`), read ONCE when the world is ready and cached;
   - toll plazas: the points of interest of kind `&"toll"` from `Game.world.get_points_of_interest()` (each is a Dictionary with `kind`, `position` (Vector3 or Vector2 x/z + height, read the contract in `game/core/contracts/world_base.gd`), `label`);
   - live police roadblocks are NOT in this list (they are created while playing); ignore them.
   Text `跳！HOP ▲` with the distance underneath (`120 m`), amber (`Palette.AMBER`), pulsing slowly (a sine on the alpha, 1.5 Hz). The nearest qualifying site decides the distance. The scan runs 5 times a second, not every frame, over the cached list.
3. Do not change the other clusters, the toasts, the minimap.

## Files you own
`game/ui/hud/` (existing tests are read-only). You add ONE new test file `game/ui/hud/tests/test_health_hop.gd`.

## The test you write FIRST (`game/ui/hud/tests/test_health_hop.gd`)
Build the HUD like `game/ui/hud/tests/test_hud.gd` and `test_mode_status.gd` do (`telemetry_override`). For the HOP hint you need sites: either set a fake world on `Game.world` (a small `WorldBase` subclass defined inside the test with `get_roadblock_sites()` and `get_points_of_interest()` returning your data and `is_ready() -> true`; look at how other tests fake a world, `grep -rn "extends WorldBase" game --include=*.gd`) or give the hint a method `set_sites(Array[Vector3])` that the HUD fills from the world and the test calls directly. Checks (`PASS ...` / `FAIL ...`; end with `HUD HEALTH HOP TESTS OK (0 failures)` and quit 0, or `... FAILED` and quit 1):
1. Health 1.0 shows `100` and a full green bar; 0.5 shows `50` amber; 0.2 shows `20` red; 0.0 hides the bar.
2. The label is only rewritten when the integer percent changes (call the update 100 times with the same value: the label's text assignment count / a change counter you keep in the widget is 1).
3. HOP hint: the player at (0, 0.6, 0) facing -Z with 80 N2 on the ground, a roadblock site at (0, 0, -120): the hint is visible and shows `120`; the same site at (0, 0, +120) (behind): hidden; at (0, 10, -120) (another level): hidden; at (0, 0, -200) (too far): hidden; with 30 N2: hidden; airborne: hidden.
4. A toll POI ahead qualifies like a roadblock site.
5. The nearest of two qualifying sites decides the distance.
Run it BEFORE you change anything: all checks fail (nothing is drawn). Use `get(...)`/`find_child` guards so missing nodes print `FAIL` lines, not script errors.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ui/hud/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ui/hud/tests/test_health_hop.gd` prints `HUD HEALTH HOP TESTS OK`.
3. `python tools/mutation_check.py --test res://ui/hud/tests/test_health_hop.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/hud-health-hop/tests --allow-fail test_hud_perf` ends with `RUN_TESTS_RATCHET OK` (`test_hud_perf` checks a millisecond budget that a busy machine fails; the others, `test_hud_layout` included, must pass).

## Pitfalls
- A scan of all POIs and all sites every frame (cache them; scan 5 times a second).
- A hint for a roadblock on another level (the Yan'an street under the elevated road).
- A bar that overlaps the battery row or the N2 cluster (the layout test).
- Writing label text every frame.
