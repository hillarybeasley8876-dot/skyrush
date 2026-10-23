# Job: a player who ends up in the river or far from any road is put back on the road

Godot GDScript, unit `game/modes/`. Read `briefs/improve/_godot-common.md` first.

## Goal
The open world has water (the Huangpu), a kill floor and edges. A player who drives into the river, falls off the map or is thrown far from every road is stuck for good: the water and the floor are solid colliders (`game/world/build/terrain_builder.gd`), the car just sits there, and the only way out is to press R. Make the game recover the player by itself: after a few seconds lost, the car is put back on the nearest road and the player is told.

## Evidence (read the code)
- Only the manual reset exists: `ArcadeCar.reset_to(xform)` (the R key / the respawn after a wreck). No code looks for a player who is lost.
- `Game.world.nearest_road_transform(pos)` (`game/world/world.gd`) gives the transform of the nearest lane (it weighs the height, so a deck 10 m above does not win over the street you are on); `Game.world.get_lane_paths()` gives the lanes.
- The modes are run by `game/modes/mode_director.gd` (`ModeDirector`, a node in the game); a session (`FreeSession`, `RaceSession`, `PursuitSession`) lives under it. The free-roam session is the open world, but a race and a pursuit also take place in the same world.

## What to build
1. A new file `game/modes/out_of_bounds.gd` (`class_name OutOfBounds`, `extends RefCounted`): `func update(delta: float, player: VehicleBase, world: WorldBase) -> bool` called once per physics tick by the mode director. It returns true on the tick on which it put the player back.
   - The player is **lost** when the 3D distance between the car and `world.nearest_road_transform(car position).origin` is more than `LOST_DISTANCE := 15.0` m. A car on a deck, in the tunnel (the tunnel goes down to y = -28 and has lanes), on a ramp or in the air over a road is not lost: the distance to its own lane is small. A car in the water (y about -3, the lanes are 15 m away or more at the quay), under the map, or flying far outside the city is lost.
   - A lost player is put back after `LOST_SECONDS := 3.0` of being continuously lost. The timer restarts when the player is found again. It does not count while `player.telemetry.flying` is true, nor while the car is airborne for less than 6 s (a long jump over the river is fine), nor on the start grid of a race (the player is frozen: `player.freeze`).
   - The put back: `player.reset_to(Transform3D)` with the transform of the nearest lane at its height plus 0.5 m, facing along the lane (the world already gives `nearest_road_transform`; use it), the linear and angular velocity zero (`reset_to` clears them; check). Show a toast once: `Events.toast.emit("已回到路面  BACK ON THE ROAD", &"info")`.
2. In `ModeDirector`: create the `OutOfBounds` object, and call `update(delta, Game.player, Game.world)` in `_physics_process` while a session exists or not (free roam counts): when `Game.player` or `Game.world` is null, or `Game.world.is_ready()` is false, do nothing.
Nothing else changes.

## Files you own
`game/modes/`. Existing tests are read-only. You add ONE new test file `game/modes/tests/test_out_of_bounds.gd`.

## The test you write FIRST (`game/modes/tests/test_out_of_bounds.gd`)
Build the world and the player like `game/modes/tests/test_modes.gd` does (the sandbox scene `res://core/sandbox/sandbox.tscn`, `PLAYER_CAR`, `MODE_DIRECTOR`), start the free mode, then:
1. **In the water**: put the player 400 m outside the road network, over the sandbox water or simply at y = -30 under the map far from every lane (`global_position = ...`, velocity zero, `gravity_scale` as the car has): after `LOST_SECONDS + 1` s the player is within 6 m of a lane (`nearest_road_transform`) and its y is above the lane minus 1 m, and exactly one toast `BACK ON THE ROAD` was emitted.
2. **Not lost on the road**: a player standing on a lane for 6 s stays where it is (distance moved under 1 m), no toast.
3. **The timer restarts**: lost for 2 s, then put on the road for 1 s, then lost again for 2 s: not put back (the sum is above 3 s but it was never continuous).
4. **Flying and grid**: a player with `telemetry.flying = true` 400 m off the road for 4 s is not put back; with `player.freeze = true` also not.
Use `has_method` / `get` guards where the new members are called so that the OLD code prints `FAIL` lines, not script errors (the test runs against the old code for the mutation check; `OutOfBounds` does not exist there: load it with `ResourceLoader.exists` / `load`, do not `preload`).
Run it BEFORE you change anything: 1 must fail (the player stays in the water); 2 passes; 3 and 4 pass trivially on the old code (they are guards for the new code).

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://modes/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://modes/tests/test_out_of_bounds.gd` prints `OUT OF BOUNDS TESTS OK` (the last line your test prints; `... FAILED` and exit 1 otherwise).
3. `python tools/mutation_check.py --test res://modes/tests/test_out_of_bounds.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/modes-bounds/tests` ends with `, 0 failed or timed out`.

## Pitfalls
- Using only the height (y) to decide: the tunnel is at y = -28 and is a road.
- A put back onto a lane of ANOTHER level (the deck over the river when the car fell from the quay): `nearest_road_transform` weighs the height; check the test numbers (lane height near the car's last height is best; if the car has no sensible height use the nearest).
- Doing the check every frame with a scan over all lanes: `nearest_road_transform` is cheap but call it at most 4 times per second.
- Putting the player back during the countdown of a race.
