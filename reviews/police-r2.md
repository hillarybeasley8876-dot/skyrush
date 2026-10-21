# police review round 2 — VERDICT: FAIL

Reviewer: Opus (strict reviewer / art director), 2026-10-20. Lead note P-INT1 is still NOT satisfied.
Round 2 fixed real things: the roadblock cars now stand broadside at the block (the heat-4 block closes
the carriageway), the offences are the four of §3.4 with a 10 s grace, the debuffs have one owner, the
damage/siren duplicates are gone, the light bar matches the dossier, and the code is split into modules.
But the heat-4/5 pursuit logic crashes every 0.2 s (drone line of sight), the test suite passes on
thousands of SCRIPT ERRORs and on skipped checks, and most tactics still do not happen in play: the box
never forms, the PIT does not spin, the head-on SUV spawns behind, the roadblock dissolves before the
player reaches it and has its cones/sign/strip on the wrong side, the spike strip is assembled from ten
4 m bars lying along the road, the toll closure crashes every frame. Several status claims are false.

## Scores (0-10)
- function: 3
- visual/feel: 3
- code: 4

## MUST-FIX

1. **P-INT1 (lead note, mandatory): police-initiated contact still starts a pursuit.**
   Probe D1 (sandbox, heat 0, player parked on its lane, 11 s after spawn so the grace is over; a PATROL
   unit placed 90 m behind on the same lane): `closest 4.4 m, contacts 2, state=chase heat=1
   infractions=[&"hit_police"]`. The patrol has no car-following and rear-ends the parked player, and
   `police_events.gd:48-53` (`_on_cop_hit`) counts ANY police-player contact as the player's
   `hit_police`. The lead's symptom (a pursuit at spawn without an offence) is still reproducible.
   Do: (a) `hit_police` counts only when the PLAYER is the striker: cache each body's velocity of the
   previous physics tick (velocities are equalised when the contact is reported) and require the
   player's closing speed toward the unit >= 3 m/s AND the contact point in the player's front half
   (`(point - player.pos).dot(player.forward) > 0`). (b) PATROL drives with the traffic unit's
   car-following: `IDM.acceleration(v, v0, gap, dv)` from `game/ai/common/idm.gd`, gap from a forward
   probe on layer 2 (vehicles) up to 60 m, so a patrol never runs into a stopped car (player or traffic).
   Verify: add to `test_offences.gd`: the D1 setup for 25 s → 0 contacts, state `none`; a PURSUE unit
   driven into the parked player at heat 0 → state `none`; the player driving into a parked patrol at
   40 km/h after the grace → `chase`.

2. **The drone breaks the line of sight at heat >= 4 (SCRIPT ERROR every 0.2 s).**
   `police_pursuit.gd:119` assigns `drone.seen = ok`, but `PoliceDrone` has no `seen` property: "Invalid
   assignment of property or key 'seen' ... Node3D (PoliceDrone)". `update_sight` aborts, so `seen_now`
   and `no_sight` freeze as long as a drone exists. Probe B1: heat 4, 8 s with every sight blocked →
   `no_sight=0.2 state=chase evade=0.000` (escape impossible at heat 4-5); probe A1/B3: a stale
   `no_sight` gives a phantom `cooldown` with six units within 30 m. Error counts: test_drone 17,
   test_head_on 83, test_perf 64, my captures 7-35 per run.
   Do: declare `var seen: bool = false` on `PoliceDrone` (documented) and keep its 350 m raycast (a
   tunnel roof blocks it physically; the 1.0 s flash charge blinds it too, dossier §3.2/§3.4).
   Verify: test_drone runs all 8 of its checks; new check: heat 4, `sight_block` held for 8 s →
   `search` then `cooldown`; heat 4 in the open → stays `chase` with `seen_now == true`; 0 errors.

3. **The tests pass on SCRIPT ERRORs and on checks that never ran (test integrity).**
   - `test_drone.gd:35` crashes on `drone.seen`; the coroutine aborts, `_ready` still calls `finish()`:
     "POLICE TESTS OK (4 checks, 0 failures)" while the file has 8 checks (the LOS, the spike drop and
     the two-drones-at-heat-5 checks never ran). `test_head_on.gd:34` crashes on `spot.position`
     (a Dictionary): 2 of its 8 checks never ran.
   - `test_spikes.gd:102` frees a unit with `cop.queue_free()` while the squad still holds it:
     5,108 "Invalid access to property or key 'is_wrecked' on a base object of type 'previously freed'"
     plus 1,680 `state` and 1,680 `set_lights_enabled` errors (`police_spawner.gd:89`,
     `police_squad.gd:120/137`) — and the suite reports OK.
   - Thresholds were lowered until the tests pass: `test_pit.gd` `SPIN_DEGREES := 0.5` reports
     "the player is turned by the PIT (3.9 degrees)" as a PASS (R1 asked >= 60° in 2.0 s);
     `test_head_on` "reaches the player (339.5 m, 2 hits)" passes on hits by OTHER units (probe A2: the
     SUV itself never came closer than 331 m, 0 SUV contacts); `test_perf` labels the 99.5th
     percentile "the slowest dispatcher tick" while the printed max is 6.5 ms.
   Do: in `tests/police_test.gd` register `res://tools/error_counter.gd` with `OS.add_logger` in
   `build()`; `finish()` FAILS when `errors > 0` and prints the first 5; add `t.expect(n)` and fail when
   fewer checks ran. Remove units only through a director API (`despawn_unit(unit)` → squad.remove).
   Restore the R1 thresholds; a check blocked by another unit stays a FAIL with the request named in
   the label — never weaken a check to make it green.
   Verify: all 10 suites print 0 engine errors and run exactly the checks they declare with `t.expect`.

4. **Head-on SUV (R1-6) still spawns behind the player — the same sign error in three places.**
   `police_spawner.gd:288` (`head_on_spot`), `:227` (`_oncoming_spot`) and `police_blockade.gd:145`
   (`_update_toll`) compute `to_player = player - pos` and `continue` when `to_player.dot(forward) <= 0`
   — that keeps points BEHIND the player. Probe A2: spot `-20.1 m` along the player's forward, 392 m
   away (the far straight of the loop), tangent·fwd -1.00; the SUV drove 20 s at 109 km/h and never got
   closer than 331 m. (The test's own "ahead" check repeats the inverted formula.)
   Do: ahead = `(pos - player.global_position).dot(forward) > 0`; take the point 350-450 m ahead ON THE
   ROUTE (walk the lane graph like `_route_points`), then the opposite-direction lane within 15 m of
   that route point (tangent·fwd <= -0.7). Count only the SUV's own contacts in the test.
   Verify: test_head_on (fixed): spot ahead, 350-450 m along the route, SUV contact or pass < 3 m
   within 20 s at 80 km/h counted from the SUV's collisions; `_oncoming_spot` test: ahead and oncoming.

5. **Roadblock: props on the wrong side, a 2.1 m "3 m gap", open kerb side, and the cars drive away.**
   The block's local -Z is the player's travel direction (`lane_sampler.gd:78`
   `Basis(right, UP, -tangent)`), but `police_roadblock.gd` puts the cone taper at z = -4…-32 m, the sign
   board at z = -40 m and the heat-4 spike strips at z = -7 m: all DOWNSTREAM, behind the cars. Capture
   `r2_city_block4close_t0_6.jpg` (11 m before the closed block): two white cars, nothing in front.
   - Barriers use yaw 90°, so the 2.5 m long `roadblock_barrier.glb` (Blender x 2.50 / y 0.90) lies
     ALONG the road: the kerb fill is a row of 0.9 m slabs with ~1.5 m holes, and the two gap markers
     centred on the car edges eat 0.45 m each → the clear gap is ~2.1 m for a 1.99 m Roadster.
   - `_build_barriers` skips the right-hand kerb (`length = last - width/2` is negative): with one car
     (any carriageway < 13 m) up to ~4.9 m stays open next to the gap.
   - Parked cars un-freeze when the player is within 20 m at >= 3 m/s (`_check_shoved`, no contact
     needed) and then drive off as AI units. Probe B2 (heat 3, player at 60 km/h): `car unfrozen at
     player distance 19.8 m, contact before: false`, then `car moved 29.9 m … 49 km/h`.
   - At night the block reads as two parked white cars: parked cars have `set_lights_enabled(false)`.
   Do: cones z = +4…+32 m tapering toward the gap, sign at z = +40 m facing +z (the driver), heat-4
   strips at z = +7 m; barriers yaw 0 (length across the road) edge-to-edge from each car to BOTH kerbs
   (use the absolute length); mark the gap with cones on the approach, not barriers inside it; clear
   body-to-body gap incl. props 3.0 ± 0.2 m (cars are 5.12 m across at ±12°, not `CAR_SPAN` 5.0).
   Unfreeze a parked car only inside a real `vehicle_collided` with it (closing >= 3 m/s); a shoved
   car stays a prop (no AI) and leaves with the block. Light bars of the block strobe always; the
   block cars compete for the 3 omni-light slots by distance like driving units.
   Verify (test_roadblock): every prop's local z >= 0; a 2.2 m wide BoxShape3D cast passes the gap and
   no other opening (cast every 0.5 m across, kerb to kerb) at heat 3, none passes at heat 4; player
   at 60 km/h stops 1 m before the cars → every car still frozen in place; ram at 60 km/h → shoved >= 1 m.

6. **Spike strip: the props glb is mis-assembled into a 7 m x 4 m grille of bars along the road.**
   `spike_strip.glb` is ONE 4.0 m strip (`tools/blender.sh preview`: x 0.36, y 4.00, z 0.17 m; nodes
   `SpikeStrip`, `Spikes`; there is no `Lid`). `police_spike_strip.gd:61-77` treats it as a 0.72 m case
   and lays ten copies side by side along X with their 4 m length along the travel direction. Captures
   `r2_city_strip_t1_2.jpg` (2.6 m) and `r2_city_striptop_t0_8.jpg` (9 m above): ten dark rails running
   WITH the traffic — a cattle grid, not a spike strip; the lamp is an untextured 6 cm sphere.
   Do: rotate the instance so its length lies across the road (dossier §6.3: 7 m x 0.6 m across two
   lanes): two instances end to end (3.5 m each), trigger = mesh footprint; the 0.35 s deploy unrolls
   the length from the lamp end (scale 0.05 → 1), not only the spike height; delete `CASE_LENGTH`,
   `_lids`; the lamp gets a small dark housing with the props atlas material and an emissive #FF2030
   lens (no flat untextured surface, ART.md §5). Verify: the two captures again — one continuous strip
   across the lane, spikes and the case texture readable at 2.5 m.

7. **The rolling BOX (R1-5) still never forms.** Probe C2 (heat 2, three units 30-46 m behind a 70 km/h
   player, 14 s, no pinning): `box fully formed for 0.0 s`. The BOX_FRONT unit sits straight behind the
   player (`rel x 0.0-0.1, z +4.6 m` from t = 8 s on) because its target `player + forward * 9` lies
   through the player and there is no adjacent-lane overtake; the side units hold ±2.4 m but 45-55 m
   back for 10 s because `box_speed` gives them exactly the player's speed. `test_box` passes only
   because it pins the units in place (status admits it).
   Do: front unit: target the adjacent lane (`player + right * ±3.5 + forward * 12`) at player + 8 m/s
   until rel.z < -9 m, then merge (lateral → 0) and hold 9 m ahead at player - 3 m/s; side units: player
   speed + clamp(gap * 0.4, 0, 8) m/s until within 2 m of the slot. Verify: test_box without pinning,
   start 30-45 m behind at 70 km/h: fully formed >= 3 s within 14 s (front rel.z < -5 m and |x| < 1.6 m;
   sides 1.8 < |x| < 3.6 m, -1.5 < z < 3.0 m), sides opposite, busted ×2 when boxed at 30 km/h.

8. **The PIT (R1-4) still does not spin, and the assist fires on ANY police contact.**
   `police_events.gd:53` calls `PoliceTactics.pit_assist` for every police↔player contact — rams, box
   squeezes, the head-on SUV, parked cars — not only for the unit in its PIT strike. The test accepts
   0.5° (item 3). My R1 cap of 1500 N·s was too low to rotate the 1,900 kg Roadster (Iy 3,200 kg·m²)
   against its grip; I raise it.
   Do: apply the assist only when `unit.state == PIT` and its strike timer is running (expose
   `is_striking()`), contact behind the player's centre, closing >= 3 m/s; size it as a yaw-rate target:
   torque impulse = Iy × (1.6 rad/s - |ω_y|) toward the push side, capped at 6,000 N·m·s, plus the
   existing lateral shove; increment `pit_assists` (or delete it). Keep the vehicle request.
   Verify: test_pit with the player's steering RELEASED after the contact: heading change >= 60° within
   2.0 s, `pit_assists == 1`; a RAM unit hitting the rear quarter adds no assist.

9. **Heat-5 toll closure (R1-12) is inverted and crashes every frame.** Probe C1 (fake toll POI 200 m
   ahead / behind, heat 5): toll AHEAD → 0 closures; toll BEHIND → `_close_toll` runs and hits "Invalid
   access to property or key 'width' on a base object of type 'Dictionary'" 60 times in 60 frames
   (`lane_spot_ahead` returns no `width`); each call leaves an orphan `TollClosure` node in the director
   (added before the crash, never in `blocks`, never freed). Even when it works it would put a generic
   lane block 350 m ahead, not at the plaza.
   Do: ahead test as in item 4 and on the route; close at the plaza itself (the world's
   `get_roadblock_sites()` at the toll, or the toll POI + `nearest_road_transform`), barriers + parked
   units across EVERY toll lane, once per plaza; `add_child` only after a successful setup.
   Verify: test with a fake toll POI 450 m ahead → one closure within 30 m of the plaza, 0 errors, no
   closure for a toll behind; capture `toll_closed_h5`.

10. **Drone: no spike drops, light not on `Spot`, beam and pool apart, the pool clips the car.**
    `police_air.gd:48` `on_drone_spike` only says the radio line (which `_request_spike` already said →
    two toasts); `police_director.gd:238 _on_drone_spike` (the one that calls `blockade.drop_strip`) is
    never connected → the drone never drops a strip (its test check never ran, item 3). The glb has no
    `Gimbal` node (nodes: Body, CameraLens, DroneLivery, Drone_Frame, Light_Front, Rotor_*, Spot,
    SpotLens, Strobe_*), so the SpotLight hangs from the drone root, not from the glb `Spot` empty
    (R1-9), and the beam cone hangs straight down while the light aims at the player → cone and pool do
    not line up. In the game chase view (`r2_city_dronechase_t4_0.jpg`) the energy-60 spot turns the
    white Roadster into a clipped white blob — my R1 start value was too hot.
    Do: one handler: drone signal → `blockade.drop_strip(... SPIKE_AHEAD)` → one radio line; create a
    gimbal Node3D at the glb `Spot` empty, put the SpotLight and the beam under it, aim the gimbal; the
    beam runs along the light's -Z with its length = distance to the ground hit; spot energy 16-20,
    angle_attenuation ~1.0, so no pixel of the Roadster's paint clips (max channel <= 0.92 in the
    capture) while the pool still reads brighter than the street lamps. Verify: test (spike drop lands on
    the road 100-140 m ahead), captures `drone_side` (6 m from the drone) and `drone_chase`.

11. **The hold-back (R1-14) does not hold.** Probe B3 (heat 4, eight PURSUE units converge on a 30 km/h
    player for 20 s): up to 6 units within 30 m; more than 3 within 30 m in 1,294 of 2,400 frames.
    `PoliceSquad.hold_back` counts in array order, never clears `hold_back` for units inside the radius,
    and `_tick_hold_back` steers AT the player at the player's speed. No test covers it.
    Do: sort live units by distance every tick; the nearest 3 keep their roles; the others target a
    point 35 m behind the player on the lane at the player's speed minus a brake term when closer than
    32 m. Verify: new test (the B3 setup) → never more than 3 within 30 m after the first 3 s, and the
    busted meter still fills when the player stops.

12. **Performance is over budget; the test reports a percentile as the peak.** My three `test_perf`
    runs: dispatcher mean 0.46 / 0.68 / 0.76 ms (OK), p99.5 2.55 / 2.61 / **4.24 ms (FAIL)**, max
    **6.50 / 9.43 / 41.94 ms**; wall time per physics step with 12 units +4.3 / +7.0 / +2.8 ms. The
    status claim "max 1.03-1.89 ms" does not reproduce. Budget (R1): mean <= 1.5 ms AND max <= 3.0 ms.
    Do: pool everything at director ready (12 units, 3 roadblock sets with their props, 4 strips, 2
    drones) instead of instantiate/free in the tick; full ArcadeCar physics only for the 4 nearest or
    visible units, the rest kinematic on their lanes (extend `PoliceSleep`, also while engaged); spread
    a roadblock build over frames. The test checks the max (not p99.5) and the wall-time delta (<= 2.0
    ms per physics step). Verify: three consecutive runs green.

13. **Captures (R1-16) are still not delivered.** `captures/police_sheet.jpg` shows six sandbox frames
    from the demo camera: the chase frame shows a sliver of one police car, roadblock3/4 show a car and
    cones from behind, and spikes/drone/head-on are three near-identical shots of the player's car with
    nothing police in frame. The city world loads now (my captures use `--city=true`).
    Do: on the CITY with the game chase camera where the brief/R1 asks for it, 1600x900, a 3x3 sheet
    in status: `chase_h3`, `pit_contact` (+0.5 s), `box_formed`, `roadblock_h3` (25 m before, gap
    visible), `roadblock_h4` (strip in front), `spikes_close` (2.5 m), `drone_chase`, `head_on` (SUV
    80 m ahead, oncoming), `toll_closed_h5`. Every status claim must match its image.

14. **Code rules: duplicates, dead code, orphan comments, magic numbers.**
    - Duplicates: `ENGAGE_MEMORY` (`police_car.gd:20`, `police_pursuit.gd:10`); `pursuit_lead`
      (`police_driver.gd:142`, `police_tactics.gd:84`); `PUNCTURE_SPEED` (`police_driver.gd:33`, unused)
      vs `PoliceDebuff.PUNCTURE_FACTOR`; three frustum checks (`police_spawner.gd:327 _in_view`,
      `police_squad.gd _in_view`, `police_blockade.gd:315 _visible`); the strobe in
      `police_drone.gd _update_strobe` vs `PoliceLightBar.update` (build the drone bar with
      `PoliceLightBar.build(self, model, "Strobe_")`); `start()`/`start_at()` in `police_pursuit.gd`;
      the three resets `remove_all_units`/`_clear_all`/`clear_pursuit`; the lane walk in
      `_route_points` and `lane_spot_ahead`.
    - Dead: `pit_assists` (never incremented), signal `punctured` (never connected),
      `_on_drone_spike` (never connected), `CASE_LENGTH`/`_lids`; nine orphan `##` comment lines with no
      function in `police_director.gd` (the block before `_on_infraction`).
    - Magic numbers in logic: `police_car.gd` (`rel.z > -2.0`, `rel.z > 3.0 or state_time > 14.0`,
      `get_forward() * 20.0`); `police_tactics.gd` (`rel.z - 2.0`, `4.0`, `* 0.25`);
      `police_blockade.gd` (`10.0`/`60` lane walk, `7.0`, `6.0`, `30.0`, literal heat `5`);
      `police_director.gd` (`80.0`, `6.0`, `linear_damp = 2.0`); `police_events.gd:83` (`1.0` flash
      blind); `police_drone.gd` (`0.02`, `-0.35`, `-0.4`, `0.12`, `16`, fog `3.0`);
      `police_spike_strip.gd` (`-70.0`, `0.06`, `0.16`, `6.0`, `1000.0`); `police_roadblock.gd` (`2.4`,
      `1.0`, `0.2`); `police_lightbar.gd` (`1.3`). Named, commented consts; one source each.
    - `police_director.gd` is 396 lines: split first (separate step), e.g. the test hooks into
      `police_test_hooks.gd`, then fix.

## SHOULD-FIX
1. The puncture only works because the director's `_physics_process` runs after the player's in the
   test tree: `boost.gd:74` rewrites `speed_cap` every tick and `car_dynamics.gd:90` reads it in
   `_integrate_forces`. If `main.tscn` orders the director first, the puncture/EMP do nothing. Set
   `process_physics_priority` on the director so it runs after vehicles, and make test_spikes measure
   the real top speed on the straight while punctured (<= 165 km/h), not the property. Keep the
   vehicle API request (`apply_puncture` / `apply_emp`) — writing `boost.*` stays an ownership breach.
2. Radio: the EMP toast "EMP锁定！" plays the voice `radio_hold` = "保持追踪，不要开火" (a "do not fire"
   line in a game without guns), and it is toasted twice (lock start + `_fire_emp`). Use the lock text
   once, a pulse text "EMP脉冲！", and request a matching voice from the audio unit; drop the `hold` line.
3. Disabled by flip / stuck (R1-10): no test; add one (roll a unit onto its roof → `pursuit.disabled`
   +1 after 1.5 s; a unit held still while engaged → +1 after 4 s).
4. `PoliceOffences.report` uses the wall clock (`Time.get_ticks_msec`): use the tick clock so slow-mo
   and pause do not change the cooldown.
5. Light-bar pools: in my strobe sequence beside a unit in the city (`r2_city_barseq_*`) the red/blue
   pools on the asphalt are not readable (the shaders unit had compile errors during that run, see
   cross-unit notes). Re-check after that is fixed; if still invisible raise omni energy to 6 and range
   to 16 m (budget unchanged: 3 units).
6. Scratch hygiene: scratch scripts were written into `game/ai/police/tests/dbg_*.gd` and images into
   `tmp/` root; use `tmp/police/` only (lead rule).

## Verified OK
- `tools/godot.sh check --only=res://ai/police/` → `CHECK 37 files, 0 failed, 0 engine errors, 0 warnings`.
- Offences: exactly the four kinds of §3.4, `reckless` gone, `SPAWN_GRACE` 10 s after spawn / respawn /
  player change, edge-triggered with a 1 s cooldown; patrols stay in PATROL without a pursuit
  (test_offences 16/16, no engine errors in that suite).
- Roadblock cars are now built in the block frame, broadside at 90 ± 12°; the heat-4 block closes the
  carriageway with two cars (`r2_city_block4close_t0_6.jpg`); parked cars cost no physics while frozen.
- One debuff owner (`police_debuff.gd`): puncture x0.65 for 8 s, EMP x0.7 for 3 s, N₂ stored and given
  back, restored on clear/expiry/player change; police cars immune to strips.
- Damage: `police_damage.gd` and `police_siren.gd` deleted; no `Events.takedown` from police; a wreck
  counts once via the `wrecked` signal (test_heat: two wrecks → heat 2).
- Bounty 500 x heat + 10/s + 250/disabled, `Events.stunt(&"escape", …)` (test_heat).
- Light bar = art dossier §4.8: 0.75 s loop, windows 0-70/130-200 ms red, 375-445/505-575 ms blue,
  emission 12, idle 0.3, omni 14 m / energy 4 / vol-fog 2.0, no shadows, ±0.45 m, #FF2030 / #2A5CFF.
- HUD API: group `police_director`, `heat`, `pursuit_state`, `evade`, `busted`, `engaged_units()`,
  `backup_seconds_left()`. The heat-5 radio no longer claims the sky lanes close.
- Scenes are preloaded (`PoliceFleet.CAR_SCENE`, drone, strip, props). Drone body level, rotors spin,
  EMP lock pulses red at 4 Hz. Heat table/LOS/busted numbers unchanged from R1 (correct).
- Ownership: `jobs/police/log.jsonl` shows Write/Edit only on `game/ai/police/**` and `status/police.md`.
- Static typing everywhere; every file <= 400 lines (director 396).

## Cross-unit notes (for the lead, not the police worker)
- During my later city captures the shaders unit's files failed to compile (`car_paint.gdshader:50`,
  `concrete_stained.gdshader:56`, `glass_gold.gdshader:33`, `soffit_blue.gdshader:38`: "Expected
  initialization of constant") — police cars rendered grey in `r2_city_barseq_*`.
- The vehicle requests in status (yaw damper / roll-over at 0.8 g / debuff API) are still open; the
  preset glb paths are now correct (`patrol.tres` → `police_patrol.glb`), so `PoliceFleet.spec_for`
  no longer needs its path patch.

## Evidence
Commands (from `/Users/minimax/m/skyrush`; logs kept in `tmp/review/police_test_*.log`, `police_probe_*.log`):
- `tools/godot.sh check --only=res://ai/police/` → `CHECK 37 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://ai/police/tests/test_<x>.gd` for all 10 suites: every one exits 0, but
  engine errors per suite: offences 0, heat 0, busted 0, roadblock 0, box 0, pit 0, drone **17**
  (4 of 8 checks ran), head_on **84** (5 of 8 ran), perf **64**, spikes **8,468**.
  Key lines: `PASS the player is turned by the PIT (3.9 degrees)`; `PASS the head-on unit reaches the
  player (339.5 m, 2 hits)`; `units: 13, dispatcher mean 0.458 ms, p99.5 2.553 ms, max 6.500 ms, wall
  1.122 -> 5.438 ms (+4.316)`; reruns `mean 0.684, p99.5 2.608, max 9.432, +7.046` and `mean 0.763,
  p99.5 4.244, max 41.939, +2.838` → `FAIL the slowest dispatcher tick stays inside the peak (4.244 ms)`.
- Reviewer probes (`extends Node`, run with the test host, using the unit's `tests/police_test.gd`;
  the probe scripts were deleted after the review — rebuild them as real tests):
  - A: `A1 heat=4 drones=1 before: seen_now=false no_sight=7.2 state=cooldown` (stale value, 3 s
    into a fresh heat-4 pursuit with a unit chasing); `A2 head-on spot:
    ahead=-20.1 m … dist=392.5 lane_tangent.fwd=-1.00`, `closest 331.2 m, SUV<->player contacts 0`.
  - B: `B1 heat 4 after 8 s fully blind: seen_now=false no_sight=0.2 state=chase evade=0.000`;
    `B2 car unfrozen at player distance 19.8 m, contact before: false` → `car moved 29.9 m`;
    `B3 hold-back: max 6 units within 30 m, 1294 of 2400 frames over 3`.
  - C: `C1 toll ahead: 0 blocks`; toll behind → 60x "Invalid access to property or key 'width'";
    `C2 box fully formed for 0.0 s of 14 s` (front unit `rel (0.0, +4.6)` from t = 8 s).
  - D: `D1 heat-0 patrol on the player's lane: closest 4.4 m, contacts 2, state=chase heat=1
    infractions=[&"hit_police"]`.
- Asset stats (`tools/blender.sh preview … --views front34|top`): `spike_strip.glb` x 0.36 y 4.00
  z 0.17 m, nodes `SpikeStrip, Spikes`, textured `Prop_Surface`; `roadblock_barrier.glb` x 2.50 y 0.90
  z 0.95; `police_drone.glb` nodes without `Gimbal`; Roadster 1.99 m wide; police_patrol 2.08 x 4.79 m.
- Windowed captures (city, my probe scene wrapping `res://ai/police/demo/police_demo.tscn` with review
  cameras; `tools/godot.sh shot --scene=<probe> --city=true --scenario=<s> --rcam=<cam>`), files in
  `captures/review/police/raw/`, sheets in `captures/review/police/`:
  - `r2_sheet1.jpg`: `r2_city_block3_t0_6` / `r2_city_block4_t0_6` (blocks 25 m ahead, nothing in
    front of the cars), `r2_city_strip_t0_5` (ten bars along the road), `r2_city_drone_t3_0`.
  - `r2_sheet2.jpg`: `r2_city_bar_t2_0` (unit beside, no pools), `r2_city_chase_t3_0` (game chase
    camera, no police in frame), `r2_city_dronechase_t4_0` (Roadster clipped white under the
    searchlight), `r2_city_strip_t1_2`.
  - `r2_sheet3.jpg`: `r2_city_block3top_t0_6`, `r2_city_block4close_t0_6`, `r2_city_striptop_t0_8`.
  - `r2_barseq_sheet.jpg`: eight frames 0.1 s apart beside a unit (bar dots only, no pools).
  - `r2_worker_sheet.jpg`: the worker's `captures/police_sheet.jpg` (sandbox, demo camera).
- References checked: brief `briefs/police.md`; gameplay dossier §3.2, §3.4, §6.3, §7.3; art dossier
  §4.8 (light bar, livery); ART.md §2/§3/§5/§10; CONTRACTS.md §3/§5; lead notes `reviews/police-lead.md`.
  The brief names no reference photos; the dossier numbers and the props glbs were used instead.
