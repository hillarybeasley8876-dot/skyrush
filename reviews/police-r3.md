# police review round 3 — VERDICT: FAIL

Reviewer: Opus (strict reviewer / art director), 2026-10-20. Lead note P-INT1: the behaviour is fixed
(only the four §3.4 offences, 10 s grace, striker rule), but its suite `test_offences.gd` does NOT finish
with the documented command (simulated-time timeout, item 11a), so the note stays open until it does.
Round 3 fixed a lot for real: the drone no longer crashes the sight, the suites count engine errors and
declared checks, the head-on SUV comes from 350 m ahead and hits the player, the box forms on its own,
the PIT spins the player 60°, the roadblock props stand on the approach with a true 3.1 m gap. But the
pursuit does not work on the real map, and a crowd of units cannot bust anybody: PURSUE units form a push
train that shoves a BRAKING player to 64 km/h (busted meter stuck at 0.00); in the city the first unit
of a heat-3 pursuit arrives after 45 s and a roadblock never spawns (the visibility test is inverted);
the spike strip's spikes are drawn 3.5 m beside its trigger; the drone beam lays a hard-edged grey veil
over the game camera; the rotors spin like windmills; barriers are squashed to 8 % of their length;
the light bars are flat untextured slabs (the user asked for refined textures everywhere); the city
capture sheet still shows no tactic at all.

## Scores (0-10)
- function: 4
- visual/feel: 3
- code: 4

## MUST-FIX

1. **Push train: a group of PURSUE units shoves a braking player down the road — nobody can be busted.**
   `police_car.gd:288 _tick_pursue` has no car-following (only PATROL uses `PoliceFollow`/IDM), and
   `PoliceTactics.pursue_speed` (`police_tactics.gd:134-143`) targets `player_speed + clamp(d*0.3, 0, 8)`.
   Units 9-14 m back ram the unit in front, which pushes the player; the player's pushed speed then
   raises every target again (positive feedback). Reviewer probe K4 (3 PURSUE units, player 30 km/h for
   10 s, then BRAKE held 12 s, not pinned): units at 4.6 / 9.4 / 14.3 m (bumper to bumper), player
   **40 → 64 km/h while braking, busted 0.00 for 12 s**. Probe B3 (8 PURSUE units): player pushed to
   **118-129 km/h** while braking, busted 0.00. (One unit alone is fine: K1 busted in 5 s, K2 in 11 s.)
   `test_busted.gd:31` pins the player, which hides this.
   Do: (a) every driving role except a RAM/PIT strike uses `PoliceFollow.leader` + `IDM.acceleration`
   against the vehicle in front when that vehicle is NOT the player (a unit never pushes another police
   car or traffic); (b) inside `PURSUE_PRESS_DISTANCE` the target speed is `min(player_speed, v_cached)`
   where `v_cached` is the player's speed from `PoliceContact` before the contact, never above it, and
   the IDM gap to the player uses s0 = 1.0 m so a unit stops behind a stopping player.
   Verify: new `tests/test_bust_crowd.gd`: (i) the K4 setup → player < 5 km/h within 3 s of braking and
   `busted` within 6 s; (ii) the B3 setup (8 units) → busted within 8 s after the stop; (iii) zero
   police↔police `vehicle_collided` events during both runs; the player is NOT pinned.

2. **City spawning: no patrols in free roam, the first heat-3 unit after 45 s.**
   Reviewer city probe (`police_demo.tscn --city=true --rcam=chase`, spawning on, game chase camera):
   30 s of free roam → `units=0` the whole time (no patrol can ever see an offence); then
   `start_pursuit(3)` → `units=0` until t = 45 s, 3 at 50 s, 7 at 60 s. Causes:
   - `police_spawner.gd:84-89`: a failed `spawn()` resets `backup_timer` to the full backup time
     (60 s at heat 0/1, 45 s at heat 3), so ONE failed attempt means a minute without police.
   - `spawn_spot()` rejects every spot in the camera frustum (`PoliceSight.in_view` = frustum only, no
     occlusion, no distance), so every lane spot ahead is "visible"; only "behind" spots survive.
   - `close_units()` (`police_spawner.gd:411`) counts every node of the group `police`, i.e. the 12
     pooled units and 12 block cars that are parked hidden where they were released (item 10).
   Do: separate a `spawn_retry` timer (1.0 s) from the backup timer; the backup timer only runs when a
   running pursuit lost all its units; a new pursuit spawns its first unit within FIRST_SPAWN (1.2 s).
   One shared helper `PoliceSight.visible_to_player(camera, point)` = in frustum AND the ray
   camera→point+1 m is clear on layer 1 AND distance < 250 m (behind a building is NOT visible, dossier
   §6.3 "never spawn police in the player's view"). Heat 0 keeps 2 patrols within 400 m at all times.
   `close_units` counts `squad.units` only. Verify: the city probe (same setup, `tmp/police/`): free
   roam → 2 patrols within 5 s and ≥ 1 for the whole 30 s; heat 3 → 1st unit ≤ 3 s, 3 units ≤ 10 s;
   paste the log lines in status.

3. **Roadblocks never spawn in the city, and the predicted route is not the player's route.**
   - `police_blockade.gd:454-467 _visible()` returns true when the point is in the frustum OR when the
     ray from the camera is BLOCKED (`return not hit.is_empty()`), the opposite of its own doc comment.
     City probe: all 26 logged decisions returned `_visible=true`, 19 of them out of the frustum with
     the ray blocked by buildings (`in_frustum=false ray_blocked=true`); **0 roadblocks in 100 s at
     heat 3**. Use the helper of item 2.
   - `PoliceRoute.walk/route_points` (`police_route.gd:68,99`, also `police_spawner.gd:291`) always take
     `next[0]` at a junction, which in the city grid is a turn: the "350 m ahead" spot was **90-316 m**
     from the player in a straight line (route loops round a block). Take the successor whose start
     tangent is closest to the current lane's end tangent; make `"found"` false when the walk hits a dead
     end (today `walked >= distance or offset >= 0.0` is always true) and reject spots < ROADBLOCK_MIN.
   - `_roadblock_spot` (`:319`): a world site is used in either direction and its width is measured at
     the PLAYER's lane (`road_width(graph, lane, lane_s)`), not at the site. Require
     `site.basis.z · route_direction > 0.7` (contract: site -Z faces oncoming player traffic) and measure
     the width at the site's lane and offset.
   - Toll closure (R2-9 carry-over): `_close_toll` (`:232`) measures the width at `s = 0.0` of the lane
     (the lane start, not the plaza), never orients the block toward the player, never calls
     `_rebuild_block_cars()` (closure cars get no omni lights), and there is still no toll test.
   Verify: city probe heat 3 for 100 s → ≥ 3 blocks, each 350-450 m along the route, `visible_to_player`
   false at spawn, props on the approach side (log); new `test_toll.gd` (fake toll POI 450 m ahead → one
   closure within 30 m of the plaza and its cars in `block_cars`; toll behind → none; 0 errors).

4. **Spike strip: the spikes are drawn beside the trigger; the lamp never blinks.**
   `police_spike_strip.gd:188 _apply_deploy` starts the cases at `x = 0.0`, so the two 3.5 m cases span
   local x **[0.00, 7.00]** while the trigger box spans **[-3.50, +3.50]** and the lamp sits at x = 3.62
   (the joint in the middle). Measured in the city (`r3_roadblock4_*`, block strip) and in the sandbox
   (`r3psb_spikes_striptop.jpg`, strip starts at the lane centre and runs 7 m to the right). Probe F1
   (sandbox, drive through at 60 km/h): local x -3.0 / -1.5 → **punctured with no spikes under the car**;
   +4.5 / +6.0 → **driving over visible spikes, not punctured**. The lamp: line 180 uses
   `fmod(_deployed * 1000, …)`, and `_deployed` stops at 1.0, so the lens is lit forever (no 2 Hz blink).
   The housing is a 16 cm BoxMesh with the WHOLE metal atlas mapped on each face (texel density far from
   ART.md §5's 512 px/m) and the lens an untextured sphere with a literal `6.0` emission.
   Do: centre the cases on the node (`x` starts at `-STRIP_LENGTH * 0.5`; unroll from the lamp end at
   +3.5 m toward -3.5 m), lamp at x = +3.5 + 0.12; blink on an own clock (`_lamp_time += dt`); housing =
   CylinderMesh r 0.05 h 0.08 with the case material and `uv1_scale` so the metal reads at ≥ 512 px/m;
   named lens energy const. Remove the unused local `scale` in `_build_cases` (shadows `Node3D.scale`).
   Verify: `test_spikes.gd` gets the F1 sweep (punctured at x = -3.0, -1.5, +1.5, +3.0; not at ±4.5) and
   asserts the case AABB in strip-local x = [-3.5, +3.5] ± 0.05; a top capture shows the strip centred
   on the lane centre with the lamp at its right end; two frames 0.25 s apart show lamp on / off.

5. **Roadblock dressing: squashed barriers, interpenetrating cars, stacked cones.**
   - `police_roadblock.gd:212-213` scales the 2.5 m `roadblock_barrier.glb` along X to fill a run:
     probe values `scale.x = 0.736` (city heat 3), **0.083** (city heat 4: a 21 cm red/white sliver,
     `r3_roadblock4_barrier.jpg`), **0.124** (sandbox heat 4, `r3psb_roadblock4_barrier.jpg`). ART.md §8:
     no stretched textures. Never scale a prop non-uniformly: place whole barriers (they may overhang
     into the shoulder), skip runs < 0.6 m (the car body covers them) and keep the invisible wall.
   - Closed block (`:146`): `pitch = carriageway / ceil(carriageway / span)` is SMALLER than the car span
     when the width is not a multiple of 5.12 m: sandbox width 13.50 m → cars at -4.5 / 0 / +4.5 m with a
     5.12 m span = **0.62 m of body overlap** (visible in `r3psb_roadblock4_striptop.jpg`). Use
     `floor(width / span)` cars at pitch ≥ span + 0.1 m and fill the rest with whole barriers.
   - `_place_cones` at heat ≥ 4 puts **two cones at exactly (0, 0, 4)** (offset 0) and funnels the driver
     toward the middle of a CLOSED block. Heat ≥ 4: a lane-closure taper toward the kerb or a straight cone
     line at z = +4 m, 1.2 m apart; never two cones closer than 0.8 m.
   - City block width 22.13 m puts the sign at x = +10.07 m (`width/2 - 1`) INSIDE dark building
     geometry: at 1.4 m eye height only its top strip shows (`r3_roadblock4_sign.jpg`; the sandbox sign
     stands correctly, `r3psb_roadblock4_sign.jpg`). Measure the carriageway from the outer lane edges
     of the lane graph and down-ray every prop/sign spot (layer 1 hit within ±0.3 m of the road height,
     nothing above it within 3 m); a spot that fails moves inward.
   Verify: `test_roadblock.gd` asserts every barrier `transform.basis.get_scale() == Vector3.ONE`, min
   centre distance between block cars ≥ `car_span()` at heat 4 for widths 7, 10.5, 13.5, 22.1 m, and
   min pairwise cone distance ≥ 0.8 m; recapture `roadblock_h4` top view.

6. **Drone: the beam is a hard-edged grey prism that veils the game camera; the rotors windmill.**
   - Beam (`police_drone.gd:122-140, 210-218`): an unshaded additive `CylinderMesh`, 16 facets,
     `cap_top`/`cap_bottom` left **true** (probe: `cap_top=true h=40.4-49.7 top_r=9.0`), ending at the
     player's CENTRE. From the chase camera the player sits inside the 9 m cone: the whole frame gets a
     flat grey veil with a hard horizontal edge (`r3s_drone_game_t9_0.jpg`, `r3psb_drone_dronechase.jpg`);
     from outside it is a flat, pale, opaque-looking wedge (`r3psb_drone_dronewide.jpg`,
     `r3_drone_dronewide.jpg`, `r3_spikes_game_t14_0.jpg`). The mesh is also regenerated every tick
     (`cone.height = length`).
     Do: caps off; length = ray from the gimbal along -Z to layer 1 (the ground), not the player; a
     ShaderMaterial (unshaded, blend add, depth_draw never, cull disabled, 32 segments) with alpha
     ≤ 0.05 × soft edge (view-angle fade on the cone rim) × length fade (100 % at the lamp → 25 % at the
     ground) × proximity fade 2 m at geometry × camera fade (0 when the camera is within 8 m of the axis),
     plus slow 3D-noise dust; scale the node (`scale.z`) instead of rebuilding the mesh. On
     `Settings.feature("volumetric_fog")` add `light_volumetric_fog_energy` on the SpotLight and halve the
     mesh alpha.
   - Rotors: `police_drone.gd:205 rotor.rotate_z()` spins each blade about its forward axis; probe:
     `Rotor_FL basis.x = (0.724, -0.690, 0)` = blade tilted 44° out of the rotor plane. Use `rotate_y`
     (FL/RR +, FR/RL -); the `Rotor_*_blur` discs stay flat and static.
   Verify: probe prints `basis.x.y == 0 ± 0.001` for all 4 rotors after 5 s; captures `drone_chase`
   (game camera under the drone) with no edge or veil (frame mean luminance within ±5 % of the same
   frame with the beam hidden) and `drone_side` at 5 m showing a soft-edged shaft and a level rotor
   disc; the Roadster's paint keeps max channel ≤ 0.92 in the pool (R2-10).

7. **Light bars are flat untextured slabs (user: 贴图纹理什么都要细化).**
   `LightBar_Red/Blue` are 0.632 × 0.035 × 0.20 m slabs whose materials have no texture
   (`NPC_lightbar_red/blue`: no base, no normal, no emission texture); the police unit duplicates them
   per car (`police_lights.gd:73-81`) and only drives `emission_energy_multiplier`. Close-up
   `r3psb_roadblock4_lightbar.jpg` (2.6 m): one uniformly glowing red brick and a dead blue brick.
   Do (your own material copies, no asset edits): build ONE static `ImageTexture` in code (64 × 32 px
   module tile: lens background #1A0306 / #03081A, a 3 × 2 grid of round LED dots with a 2 px soft
   falloff, a 2 px reflector ring #5A5A60) and set it as `emission_texture` and `albedo_texture` on the
   copies with `uv1_triplanar = true` and `uv1_scale ≈ 19` (≈ 12 modules per 0.632 m half); roughness
   0.12, keep energy 12 × pattern and IDLE_EMISSION 0.3. Request a real lens model/texture from
   npc_cars in status. Verify: close-up capture at 2.5 m (lit red frame and lit blue frame side by side)
   shows ≥ 10 separate LED modules per half and the dark separators between them.

8. **Hold-back (R2-11 carry-over) still lets 6 units within 30 m, and still has no test.**
   Probe B3 (heat 4, 8 PURSUE units 40-110 m behind a 30 km/h player, 20 s): **max 6 within 30 m, more
   than 3 within 30 m in 222 of 2,040 frames**. `police_squad.gd:162-177 _hold_back` sorts a local
   `ranked` and then reads `_ranked[i]` (the list of `_rank()`, built before units were removed this
   tick), so the sort is wasted and removed units can be written; the brake starts at 32 m, only 2 m
   outside the 30 m rule, and ghosts overshoot it in 0.1 s steps.
   Do: one ranking per tick, used everywhere; held units aim ≥ 38 m behind and brake hard
   (`player speed - 6 m/s`) inside 31 m; ghosts obey the same point.
   Verify: new `test_hold_back.gd` = the B3 setup → never more than 3 within 30 m after the first 3 s,
   then (with item 1) busted within 8 s after the stop.

9. **Ghost units drive in straight lines through buildings (R2-12 asked "kinematic on their lanes").**
   `police_sleep.gd:28-44 roll_to` moves a far unit along the straight 3D line to `target_point`:
   through blocks, across junction corners, up and down through elevated decks; in a grid city that is a
   shortcut no real car has (dossier §6.3: catch-up is "fairness, not cheating"). The mode is held for
   `MODE_HOLD` 1.5 s, so a ghost that enters the frustum keeps sliding (wheels still, no suspension) for
   up to 1.5 s in view.
   Do: a ghost advances its `LaneFollower` at `desired_speed` along the straightest successor toward the
   player (or its hold-back point) and is placed with `graph.transform_at(lane, s, 0)` (lane height and
   heading); it switches to physics on its lane and at once when `visible_to_player` (item 2).
   Verify: a city heat-5 run of 60 s logs every ghost→physics switch with the body's distance to its lane
   centre (≤ 1.0 m) and no ghost sample with a building between it and its lane (down ray hits layer 1
   road first).

10. **Pooled cars stay in the groups `police`/`vehicles` where they were parked.**
    `police_pool.gd:85-90 _park` hides a car and clears its collision layer, but leaves it in both
    groups at the place it was released (after a bust or an escape: all around the player; the build
    parks them at the world origin). The audio unit gives sirens to the nearest members of `police`
    (`game/audio/emitter_collection.gd:300`) → sirens from invisible cars; `close_units()` counts them →
    no spawn within 30 m of the last chase (item 2). Do: `remove_from_group("police")` and
    `("vehicles")` in `_park`, add back in `take_unit`; unused block cars likewise. Verify: after
    `remove_all_units()` `get_nodes_in_group("police").size() == 0`; with one 3-car block it is 3.

11. **Test integrity.**
    a. `test_offences.gd` (the P-INT1 suite) needs ~131 s of simulated time (25 + 18.5 + 3 + 0.5 + 3 +
       0.5 + 0.5 + 35.5 + 30.5 + 14.5); the test host stops at 120 s: `tools/godot.sh test
       res://ai/police/tests/test_offences.gd` (the command in your status) → **"TEST TIMEOUT after
       120 s", exit 2**, `_check_player_contact` (the positive hit_police case) never runs. Your green
       run used `--timeout=600`. Split it (e.g. `test_offences.gd` + `test_offences_contact.gd`, each
       < 90 s simulated) or shorten the idles; both must pass with the documented command.
    b. `test_busted.gd:31` pins the player; keep it, but add the unpinned crowd test of item 1.
    c. `_check_edge_trigger` passes because `speeding` needs a patrol in sight and none is there
       ("0 reports" for 60 emits); use `toll_evaded` (no sight needed) and print the delta, not the
       total (`_check_traffic_out_of_sight` prints "(1 reports)" = the running total).
    d. `test_pit.gd _check_ram`: "a ram gives no tap" passes even when the ram never touched the player;
       assert `t.hits_of(cop) > 0` first.
    e. `test_roadblock.gd:61` accepts 300-520 m under the label "350-450 m"; use 350-450 along the
       route. `_openings` casts across `block.width` (the block's own estimate); cast across the real
       carriageway (outer lane edges + 1 m shoulder from the lane graph) so an open kerb shows.
    f. Add the tests named in items 1, 3, 4, 5, 8, 10.

12. **Performance (R2-12 carry-over) is over budget.** My three `test_perf` runs (load average 31-45):
    dispatcher mean 0.759 / 0.797 / 0.918 ms (OK), **max 6.078 / 5.420 / 10.342 ms** (budget 3.0),
    **wall +2.252 / +3.233 / +2.881 ms** per physics step (budget 2.0); 5-33 ticks > 3 ms per run. Even
    your quiet numbers (+0.99 to +1.73 ms per 120 Hz step) are 2-3.5 ms per 60 fps frame. Avoidable
    per-tick work: `spawner.assign_roles()` every tick (fresh `wanted_roles` and `live_units` arrays,
    `set_role` on every unit); three sorts with lambdas plus `live()` copies in `PoliceSquad.update`;
    `PoliceLightBar.update` writes both omni energies every tick even when unchanged; the drone beam
    mesh rebuilt every tick; `_update_toll` walks every POI every tick at heat 5; `_police_nodes()` copies
    the whole group. Do: per-module timers in `test_perf` (print the top 5), assign roles only when the
    unit set or the heat changes, reuse arrays, write light energies only on a pattern edge.
    Verify: three consecutive green runs with `uptime` printed in status (load < 12), and under load
    (> 30) mean ≤ 1.0 ms with the module breakdown.

13. **Captures (R2-13 carry-over) are still not delivered, and the demo breaks the world contract.**
    - `captures/police_sheet_3x3.jpg` (your sheet): none of the nine frames shows its tactic (a dark
      street, a kiosk, a black panel in the road, the player alone; `r3_worker_sheet.jpg`). The four
      sandbox shots are far and small; `sandbox_chase_h3` has no police in frame.
    - `police_demo.gd:100 _build_player` calls `Game.world.get_spawn_transform()` before the city is
      built (log: "[world] the API was used before the city was built", backtrace `police_demo.gd:100
      ← :58`). CONTRACTS §4: `await Game.world_ready()` before any WorldBase call. In my chase run the
      player ended at (0, -133, 0) falling at 227 km/h.
    - The demo driver steers at `director.lane` 25 m ahead and drives into walls: the drone run froze
      with the player at 5 km/h against a granite wall (`r3_drone_game_t14_0.jpg`); in my city probe
      the demo player crawled at 3-10 km/h for the whole 65 s of the heat-3 phase.
    - The `box` scenario spawns the three units already in formation (`_spawn_in_frame(BOX_FRONT, 0, -9)`
      and the sides at ±2.4 m), so `box_formed` proves nothing.
    Do: fix the demo (await `world_ready`; drive the straightest successor of the lane graph; a stuck
    detector that puts the player back on his lane; `--place` documented with a straight ≥ 600 m road;
    box units start 30-45 m behind as in `test_box`), then deliver the 3×3 CITY sheet at 1600×900:
    `chase_h3` (≥ 2 units with lit bars in frame), `pit_contact` (+0.5 s, player rotated ≥ 20°),
    `box_formed` (formed from behind), `roadblock_h3` (25 m before, the gap readable), `roadblock_h4`
    (strip centred, cones), `spikes_close` (2.5 m, LED lamp lit), `drone_chase` (game camera, no veil),
    `head_on` (SUV ~80 m ahead in the oncoming lane), `toll_closed_h5`. If the world unit's build is
    broken that day, say so and shoot the sandbox, but every frame must show its tactic.

14. **Code rules.**
    - Files over 400 lines (CONTRACTS §3; split first, as a separate step): `police_car.gd` 480,
      `police_blockade.gd` 467, `demo/police_demo.gd` 424, `police_spawner.gd` 413. E.g. car → state
      machine + `police_car_roles.gd` (`_tick_*`); blockade → + `police_toll.gd` + `police_road_width.gd`;
      spawner → + `police_spawn_spots.gd`; demo → + `police_demo_freeze.gd`.
    - Magic numbers still in logic (R2-14): `police_driver.gd:51` 8.0, `:82` 0.02, `:84` 1.6/0.22,
      `:115-116` 0.8/5.0/0.45, `:155` 25.0; `police_tactics.gd:127` 0.5, `:169` -1.0, `:171`
      `PIT_GAP_MIN - 0.6`, `:218` 4.0; `police_drone.gd:91` -0.35, `:178-179` 0.02, `:194-196`
      0.5/1.4/0.2; `police_blockade.gd:226,229` 30.0, `:411` 7.0, `:440` 6.0; `police_spike_strip.gd:132`
      0.12, `:144` 6.0, `:164` Color(0.18, 0.18, 0.20); `police_roadblock.gd:221-222` 0.9/0.95/0.45,
      `:231` 0.5, `:249` 1.0; `police_watch.gd:52` 80.0, `:128` 0.5.
    - Dead or duplicate code: consts `PoliceSleep.FORWARD_AXIS`, `PoliceSpawner.ONCOMING_SHARE`,
      `PoliceFollow.SAFE_GAP`, `PolicePool.UNIT_COUNT`; `PoliceEvents.on_player_changed()` is never called
      and the director's `_on_player_changed` never updates `events.player` (stale player after a car
      change), with a doubled doc comment at `police_events.gd:117-118`; the unused arguments of
      `PoliceDrone.spike_requested` / `_on_drone_spike`; `PolicePursuit.start_at`;
      `PoliceBlockade.spawn_strip_at` repeats `_add_strip`; `HEAD_ON_AIM := 0.0` documented as "a little in
      front"; the same light-bar paragraph in `police_lights.gd` and `police_lightbar.gd`.
    - Gameplay timing on the wall clock: `PoliceRadio.say`, `PoliceCar.notify_contact`,
      `PoliceDrone._update_aim` (EMP blink) use `Time.get_ticks_msec()`; use the tick clock.

## SHOULD-FIX
1. Drone lag: at 90 km/h the drone hangs **35.6 m** behind (probe `DRONE rel`), spec §6.3 is 20 m; the
   lerp lags v / MOVE_RATE. Lead the hover point by `player.linear_velocity / MOVE_RATE`.
2. Radio voices: `radio_emp` / `radio_emp_pulse` do not exist in the audio manifest (radio_* ids found:
   suspect, reinforce, roadblock, checkpoint, drone, heavy, escape, lost, found, all_units, airspace,
   hold, …), and `spikes` ("前方投放钉刺带") plays `radio_roadblock` ("部署路障！"). Request
   `radio_emp`, `radio_emp_pulse`, `radio_spikes` from the audio unit in status.
3. Box side units hold exactly `rel.z = +2.0 m` (`test_box`: -2.4/2.0, 2.4/2.0): `box_speed` drops to
   the player's speed at `BOX_SLOT_REACHED` 2.0 m, a dead band. Make the closing term proportional to 0.
4. Dossier §6.3 SPIKES: "charging bay repairs" — `on_charge_finished` only blinds the police; clear the
   puncture there. The μ × 0.55 grip loss and the rim sparks are missing: request them (vehicle, fx).
5. Scratch hygiene: `/tmp/dbg_bust.gd` was written outside `tmp/police/` (lead rule; the user keeps
   scratch out of /tmp); `tmp/police/` still holds `run2-7.sh`, `runall.sh`, `run_tests.sh`, `run5.out`.

## Verified OK
- `tools/godot.sh check --only=res://ai/police/` → `CHECK 45 files, 0 failed, 0 engine errors, 0 warnings`.
- With the documented command, 8 suites pass with 0 police engine errors and all declared checks run:
  heat 19/19, busted 8/8, roadblock 16/16, drone 13/13, pit 5/5, box 7/7, head_on 8/8, spikes 12/12.
  `test_offences` passes 28/28 only with `-- --timeout=600` (item 11a). `police_test.gd` now counts
  engine errors of `res://ai/police/` and fails on fewer checks than `t.expect(n)` (R2-3 fixed).
- P-INT1 behaviour: exactly the four §3.4 offences, `SPAWN_GRACE` 10 s after spawn/respawn/new car,
  `hit_police` only when the player closes ≥ 3 m/s and hits with his front half; a patrol stops behind a
  parked player (0 contacts, 25 s), a PURSUE unit touching a parked player starts nothing, the player
  ramming a parked unit at 40 km/h starts heat 1. Unknown kinds (`reckless`) are ignored.
- Drone `seen` is declared; heat 4 in the open stays `chase`, 5 s blind → `search`, 8 s → `cooldown`
  (R2-2 fixed). Drone spike drop lands 120 m ahead (one handler). Gimbal at the glb `Spot` empty, spot
  energy 18, colour #D9E8FF (R2-10 partly).
- Head-on: spot 350 m ahead on the route, lane tangent · forward = -1.00, the SUV itself reaches the
  player (4.5 m, 2 SUV contacts) (R2-4 fixed).
- Roadblock geometry: every prop at local z ≥ 0 (cones z = 4/13/22/31 m, sign z = 40 m facing +Z, strip
  z = 7 m), body-to-body gap 8.22 - 5.12 = 3.10 m in the city and the sandbox, closed at heat 4, parked
  cars stay frozen when the player stops in front of them and are shoved 1.03 m by a 60 km/h ram.
- PIT: 60.3° within 2.0 s with the steering released, one tap, none from the RAM run (R2-8 fixed).
- Box: formed 5.9 s of 14 s from 35-45 m behind without pinning, front unit -9.2 m / x -0.0, sides
  ±2.4 m; boxed at 30 km/h → busted 0.66 in 1 s (R2-7 fixed).
- Disabled by roof (1.5 s) and by standing still (4 s) are tested (R2 SHOULD-FIX 3). Offence cooldown on
  a tick clock (R2 SHOULD-FIX 4). Director priority 10 and the punctured top speed measured on the
  straight, 163 km/h (R2 SHOULD-FIX 1). EMP toasts "EMP锁定！" / "EMP脉冲！" once each (R2 SHOULD-FIX 2 text).
- One unit alone busts an unpinned player (K1 braking from 60 km/h: busted at 5 s; K2 standing: 11 s).
- Light bar = art dossier §4.8 pattern (0.75 s, red 0-70/130-200 ms, blue 375-445/505-575 ms), #FF2030 /
  #2A5CFF, emission 12, omni 16 m / 6 (R2 SHOULD-FIX 5 allowance), omni only for the 3 nearest.
- Everything is pooled (12 units, 3 blocks, 4 strips, 2 drones); `police_director.gd` is 383 lines.
- Ownership: `jobs/police/log.jsonl` shows Write/Edit only on `game/ai/police/**` and `status/police.md`.

## Cross-unit notes (for the lead, not the police worker)
- world: during my captures `res://world/build/world_builder.gd:258` failed to parse ("Invalid argument
  for link(): argument 2 should be LaneGraph"), so `world.gd` did not compile and the city did not build
  (the chase run, and my second city batch which I stopped). My last three captures are on the sandbox.
- props: the face of `police_sign_board.glb` reads "公安 POLICE" (`r3_roadblock4_sign.jpg`); ART.md §7 and
  the art dossier §4.8/§9 forbid 公安/警察/POLICE text — use e.g. "天巡 SKYPOL 前方设卡 减速慢行".
- npc_cars (the user wants refined textures everywhere): `NPC_lightbar_red/blue` have no texture at all,
  the light bar halves are 3.5 cm slabs; `NPC_drone_body`, `NPC_rim`, `NPC_gloss_black` have no albedo or
  normal map.
- vehicle: roll-over above ~0.8 g and the puncture/EMP API requests in `status/police.md` are still open.

## Evidence
Logs in `tmp/review/police_r3/` (runner scripts `run_all.sh`, `run_perf.sh`, `run_shots*.sh`; probes
`hprobe.gd`, `kprobe.gd`, `cprobe.gd`, `rprobe.gd` + `rprobe.tscn` wrapping `police_demo.tscn`).
- `check.log`: `CHECK 45 files, 0 failed, 0 engine errors, 0 warnings`.
- `test_offences.log`: 25 PASS lines, then `TEST TIMEOUT after 120 s (engine errors so far: 0)`, exit 2;
  `test_offences_long.log` (`-- --timeout=600`): `POLICE TESTS OK (28 checks, 0 failures …)`.
- `test_perf_1..3.log` (uptime 45.6 / 31.7 / 34.8): `dispatcher mean 0.759 ms, p99.5 2.762 ms, max 6.078
  ms, wall 1.020 -> 3.271 ms (+2.252)`; `mean 0.797, p99.5 3.291, max 5.420, +3.233`; `mean 0.918,
  p99.5 5.499, max 10.342, +2.881` → `POLICE TESTS FAILED (4 checks, 2 failures …)` each.
- `kprobe.log`: `K1 … t=5 … busted`, `K2 … t=11 … busted`; `kprobe2.log`: `K4 pursue-only, 3 units
  t=1 player 40 km/h busted=0.00 … [4.6 m] [9.4 m] [14.3 m]` … `t=12 player 64 km/h busted=0.00`.
- `hprobe2.log`: `B3 pursue-only: units=8 max within 30 m=6, frames over 3: 222 of 2040`; `stop t=6
  kmh=129.0 nearest=4.5 busted=0.00`; `F1 visual case extent local x=[0.00, 7.00]`; `F1 drive through at
  local x=-3.0 … punctured=true`, `x=+4.5 … punctured=false`, `x=+6.0 … punctured=false`.
- `cprobe.log` (city): `CP free end: state=none heat=0 units=0 blocks spawned=0`; `heat3 t=40 … units=0`,
  `t=45 units=1`, `t=60 units=7`; every decision `in_frustum=false ray_blocked=true _visible=true` or
  `in_frustum=true … _visible=true`; `spot_dist=101/90/199/270/316`; `CP heat3 end: … blocks spawned=0`.
- `shot_roadblock3/4.log`, `shot3_*.log`: block cars, cone, barrier scale and strip extents quoted above;
  `ROTOR Rotor_FL basis.x=(0.724137, -0.689677, 0.0)`; `BEAM cap_top=true cap_bottom=true h=49.7 top_r=9.0`;
  `DRONE rel=(35.649, 35.039, 0.066)` at 90 km/h; `shot_chase.log`: `player=(0.0, -133.0504, 0.0) kmh=227`.
- Sheets (`captures/review/police/`): `r3_sheet_roadblock.jpg` (city: rb3 game/high/gap, rb3 barrier,
  rb4 high with the beam prism, rb4 strip top), `r3_sheet_drone.jpg` (city: drone game view against a
  wall, drone side, drone wide = flat wedge, spikes game view with the veil band, rb4 barrier sliver,
  sign "公安 POLICE"), `r3_sheet_sandbox.jpg` (rb4 game/high, strip top with overlapping cars and the
  off-centre strip, barrier sliver, flat light bar close-up, spikes top), `r3_sheet_drone_sb.jpg` (drone
  side wedge, chase view under the drone with the grey veil and its hard edge, wide wedge, game camera
  veil), `r3_worker_sheet.jpg`, `r3_worker_sandbox.jpg`, `r3_sign_pair.jpg` (sandbox sign standing /
  city sign buried, text "公安 POLICE"). Raw frames in `captures/review/police/raw/r3*`.
- References: brief `briefs/police.md`; gameplay dossier §3.1-3.5, §6.3, §7.3; art dossier §4.8; ART.md
  §2/§3/§5/§7/§8/§10; CONTRACTS.md §3/§4/§5; lead notes `reviews/police-lead.md`; R2 review. The brief
  names no reference photos; the dossier numbers and the glbs (`spike_strip.glb` case x ±0.18 / z ±2.0,
  `police_patrol.glb` LightBar halves 0.632 × 0.035 × 0.20 m) were the references.
