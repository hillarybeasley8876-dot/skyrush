# police review round 1 — VERDICT: FAIL

Reviewer: Opus (art director / strict reviewer), 2026-10-20. Lead note P-INT1 is NOT satisfied.
The heat table, line of sight, evade/cooldown, busted meter and the light-bar strobe work. Most of
what makes a chase *visible* is broken: roadblock cars spawn at the world origin, the PIT spins
the player without touching it, the box never forms, the head-on SUV comes from behind, spike
strips are grey boxes that throw SCRIPT ERRORs and leave the player permanently slowed, patrols
chase innocent players. Several status claims are false (see Evidence).

## Scores (0-10)
- function: 3
- visual/feel: 3
- code: 4

## MUST-FIX

1. **P-INT1 (lead note, mandatory): pursuits start without a real offence; real offences are missed.**
   Probe evidence (scratch probe A, sandbox, `spawn_enabled` on, player parked, NO offence):
   at heat 0 the free-roam patrols switch to PURSUE (`st1`) and close in: 109 m → 70 m → 30 m → 7 m
   in 25 s. The first touch fires `hit_police` → heat 1 ("嫌疑车辆，立即靠边停车！") — the lead's bug.
   Meanwhile the player passing a patrol in sight at 185 km/h starts NOTHING (state `none`, 0
   infractions); `&"reckless"` 0.2 s after `Events.player_respawned` starts a chase at heat 1;
   during a chase at 185 km/h the director emits **236 `Events.infraction` in 2 s** (one per frame).
   Causes: `police_car.gd:181-184` (`_tick_patrol` enters PURSUE whenever `seen`, also at heat 0);
   `police_director.gd:317-322` (`_check_offences` returns when `pursuit.is_over()` — inverted, so
   it only runs during a chase, every frame); `police_heat.gd:21-22` accepts `&"reckless"`; no grace.
   Do:
   - A patrol stays in PATROL while there is no pursuit. It reacts only after the director starts one.
   - Offences = exactly the four of dossier §3.4: `toll_evaded`; `speeding` (> 160 km/h while a
     PATROL unit has line of sight ≤ 220 m — detected by the director itself); `hit_police`;
     `hit_traffic` (only bodies in group `traffic`, only while `seen_now`). Remove `reckless`. External
     `speeding`/`hit_traffic` infractions are ignored unless a unit sees the player. Walls/props never.
   - `const SPAWN_GRACE := 10.0`: no offence counts within 10 s after the player spawns, respawns
     (`Events.player_respawned`) or `Game.player` changes.
   - Emit each infraction once (edge-triggered), never per frame.
   - Public API for the modes unit: `func start_pursuit(level: int) -> void` (bypasses the grace)
     and add a status Request to modes: `modes/pursuit_session.gd:55-59` calls `set_heat` on the director,
     which does not exist (add `set_heat(level: int)` as an alias).
   Verify: new `tests/test_offences.gd` (extends Node): parked 25 s at heat 0 with 2 patrols →
   state `none`, no unit leaves PATROL; 185 km/h past a patrol 60-100 m away in sight → `chase`
   within 1 s; 185 km/h with no patrol in sight → `none`; `reckless` → `none`; `hit_traffic` 3 s
   after `player_respawned` → `none`, at 12 s while seen → `chase`; ≤ 1 infraction event per offence.

2. **Roadblock cars are spawned at the WORLD ORIGIN, ~245 m from the block.**
   `police_roadblock.gd:45` assigns `_car_transform(across, slot)` (a block-LOCAL offset,
   `across * slot + UP * 0.1`) to `car.global_transform`. Probe C: block origin (-150.2, 0.1,
   -196.0); its cars at (0.0, 0.1, -5.6 … 4.8), 242.5-250.7 m away. Captures: sandbox
   `review_police_r1_b_t7_3.jpg` and city `review_police_r1_city_t7_3.jpg` (three police cars parked
   at the map origin under the deck). The road 350 m ahead only gets the strip (heat 4) or nothing
   (heat ≤ 3, `review_police_r1_loop_t5_6.jpg` is an empty road). `test_roadblock` passes because it
   only measures centre spacing and the block node's position.
   Do: place cars with `car.transform = local` (or `global_transform = global_transform * local`).
   Verify (add to `test_roadblock.gd`): every car within 8 m of the block origin and on the road
   (down-ray hits layer 1 within 0.5 m); then the capture list of item 16.

3. **The roadblock itself does not block (layout, coverage, placement, props, physics).**
   Probe B3 (sandbox, road width 13.08 m from `road_width()`): cars stand PARALLEL to the road (car
   axis · road axis = 1.00), each covering only its 1.95 m width. Heat 2 leaves three openings:
   1.67 m + the 3.0 m gap + 2.56 m. The "closed" heat-4 block covers -6.54…-0.69 m and leaves
   **7.2 m open**; the 7 m strip is centred, so 3.0 m of road has neither cars nor spikes.
   Also: the block is centred on the PLAYER's lane (`transform_at(lane, s, 0.0)`), not on the
   carriageway; `police_blockade.gd:99-111` takes the first `roadblock_site` 250-600 m from the
   player in ANY direction (even behind, not on the route); lane spots are never checked with
   `_in_view` (blocks pop in on straight roads); parked cars are frozen kinematic and skip damage
   (`police_damage.gd` returns on `parked`) → an indestructible infinite-mass wall.
   Do:
   - Cars broadside across the carriageway of the player's direction (yaw 75-90° to the lane,
     alternate ±12° like a real 设卡), kerb to kerb. Heat ≤ 3: exactly ONE body-to-body gap of
     3.0 m ± 0.2; heat ≥ 4: no gap, a full-width strip (two strips if > 7 m) 6-8 m in front.
   - Fill the rest with the props unit's assets: `game/assets/props/street/roadblock_barrier.glb`
     between cars and kerbs, `cone.glb` ×8 in a 30 m taper, `police_sign_board.glb` 40 m before.
   - `roadblock_site` only if it lies on the predicted route 350-450 m ahead (walk the lane graph,
     site within 20 m of that segment); otherwise the lane spot. Spawn only out of view
     (frustum + occlusion ray from the camera); else retry next second.
   - Parked cars: on the first contact ≥ 3 m/s set `freeze = false` (they get shoved), take damage,
     count as disabled/takedown; they cost no physics while frozen.
   Verify: `test_roadblock.gd` with a Camera3D in the scene: distance along the route 350-450 m
   (tighten the current 300-520 m check), not in the frustum at spawn, edge-to-edge gap 3.0 ± 0.2 m
   (heat 3), coverage of the full carriageway minus that gap, 0 open metres at heat 4; ram test:
   a parked car hit at 60 km/h moves ≥ 1 m.

4. **The PIT is a force at a distance, not a collision.**
   `police_car.gd:271-275` fires `PoliceTactics.tap_player` (`police_tactics.gd:80-93`, up to
   2600 N·s on the player) when the AIR GAP between the cars is ≤ 1.6 m (`PIT_GAP_MIN - 0.6` = 0.0
   is the lower bound). Probe B1: tap 1 at **1.39 m air gap, no contact**, player yaw −0.76 rad/s —
   exactly the value `test_pit` reports as a pass. Dossier §6.3: "rams and PITs are real collisions";
   status even claims "the impulse is a real force". It is an invisible hand — unfair.
   Do: no impulse without contact. The strike steers into the rear quarter (target 25° per §6.3; if
   the vehicle roll-over limits it, request the fix — see SHOULD-FIX 1). An assist impulse is allowed
   ONLY inside a real `Events.vehicle_collided` between this unit and the player, contact point behind
   the player's rear axle, relative speed ≥ 3 m/s, ≤ 1500 N·s.
   Verify: `test_pit.gd` counts a PIT only when `police_hits > 0` came first and the player's heading
   then changes ≥ 60° within 2.0 s (a 0.7 rad/s yaw rate is a lane change, not a spin).

5. **The rolling BOX never forms.** Probe F (heat 2, BOX_FRONT + 2 BOX_SIDE 25-45 m behind,
   player 70 km/h, 14 s): fully formed **0.0 s**; the front unit never got ahead (best rel. z
   +14.8 m = still behind) and drifted off the road (x −18.9 m at 8 s, −20.9 m at 10 s); both side
   units ended on the SAME side (x +2.5 / +2.6). Causes: `PoliceTactics.box_speed` gives the front
   unit "player − 3 m/s" even while it is behind; each side unit picks its side with
   `_side_of_player()`. And `police_pursuit.gd:174` doubles the busted fill only below 15 km/h, so the
   §6.3 rule "player < 40 km/h for 2 s → busted meter fills ×2" never acts.
   Do: the front unit overtakes first (player + 8 m/s on the adjacent lane until rel. z < −9 m), then
   holds 9 m ahead at −3 m/s; the director assigns side −1/+1 to the two side units (±2.6 m, 0-2 m
   behind); break after 8 s; boxed and < 40 km/h for 2 s → busted fills at 2/3 per s.
   Verify: new `tests/test_box.gd`: formation holds ≥ 3 s within 12 s, sides opposite, busted rate
   doubles when boxed at 30 km/h.

6. **HEAD-ON SUV spawns on lanes going the player's way; test hook snaps units onto the player.**
   `police_spawner.gd:220` `var forward := -player.get_forward()` then keeps lanes with
   tangent·forward ≤ −0.7 — a double negation that selects SAME-direction lanes; it also checks
   only lane midpoints and never "ahead". Probe B2: tangent·player_fwd = +1.00, +0.77, +1.00 at
   203/293/221 m (it fell back to normal lane spots). The HEAD_ON state itself works when the SUV is
   placed facing the player (probe G: charged at 90 km/h, 2 hits).
   `spawn_unit_at()` (`police_director.gd:363-376`) starts the follower at the PLAYER's lane offset;
   a unit placed > 150 m away is snapped by `PoliceSleep._roll_along` onto the player (probe: rel.
   z +0.1 m, a 208 698 km/h teleport).
   Do: search oncoming lanes (tangent·fwd ≤ −0.7) for a point 350-450 m ahead ALONG the player's
   route (dot(to_point, fwd) > 0), drive into the player's lane at 25 m/s; after a miss, brake to
   8 m/s and turn within the road (no 100 m U-turn arcs). Initialise every follower from the given
   transform (`nearest_lane` + `closest_offset`).
   Verify: new `tests/test_head_on.gd` (spawn via the spawner at heat 4: oncoming, ahead, 350-450 m,
   contact or a pass within 3 m inside 20 s); `spawn_unit_at` at 300 m stays at 300 m.

7. **Police-station spawns are teleported to lane 0.** `police_spawner.gd:177` returns
   `"lane": 0, "s": 0.0`; the unit spawns asleep and `_roll_along` moves it to lane 0 at s≈0 —
   anywhere on the map, possibly in view. The city has 2 `police_station` POIs (data/city/city.json).
   Do: lane + offset nearest to `world.nearest_road_transform(pos)`. Verify: a test with a fake
   station POI: the unit stays within 5 m of the station road transform for 1 s after spawning.

8. **Spike strips: grey-box art, SCRIPT ERRORs, permanent player debuff, bad placement.**
   a) Art: `police_spike_strip.gd` builds a BoxMesh slab + 14 CylinderMesh cones with flat colours
      (#121316 "rubber", #8C949E "steel"), no texture, no normal/roughness map — ART.md §5 "no flat
      untextured surface" and the user's "贴图纹理什么都要细化". Captures `review_police_r1_b_t5_9.jpg`,
      `review_police_r1_city_t5_9.jpg`: a black plank with toy cones. The props unit already ships
      `game/assets/props/street/spike_strip.glb` (Case, Lid, Label, Mount0, Spike0-13, node `Spikes`;
      PBR `Prop_galv` / `Prop_alu` / `Prop_dark_steel` + police board label). Use it; keep only the
      Area3D; add a 0.35 s deploy (unroll out of the case) and keep a blinking red lamp #FF2030.
   b) Errors: `police_spike_strip.gd:114` calls `apply_puncture(8.0)` but `PoliceCar.apply_puncture()`
      (`police_car.gd:364`) takes 0 arguments → "Invalid call to function 'apply_puncture (via call)'
      … Expected 0 argument(s)" whenever a unit crosses a strip and 3× at EVERY heat-4 roadblock spawn
      (parked cars stand in the trigger). Seen in `test_perf` (my run), probe B, and 11× in one capture
      run. Dossier §3.1: cop cars are not affected by spikes → skip `team == POLICE`, delete
      `PoliceCar.apply_puncture` / `punctured` / unused `PUNCTURE_MU`.
   c) Leak: the fallback writes the vehicle's `boost.speed_cap` and restores it from the strip's own
      `_process`; `remove_all_units()` frees the strips at busted/escaped, so the cap is never restored.
      Probe B4: 250 → 162 km/h on spikes → **still 162 km/h 10 s after the pursuit ended**. Two strips
      restore a stale cap; any boost use (`boost.gd:144-196` reassigns `speed_cap`) cancels the puncture.
      Same pattern in the EMP fallback (`police_drone.gd:141-147`), which also sets `n2 = 0.0` — dumps
      the whole tank instead of §6.3 "no N₂ for 3 s".
      Do: ONE owner on the director (e.g. `police_debuff.gd`): remember the original cap once, combine
      multipliers (puncture ×0.65 for 8 s, EMP ×0.7 for 3 s), restore on expiry, on pursuit end, on
      player change/respawn and in `_exit_tree`; never zero `n2` (store it and block use for 3 s, or
      wait for the requested `apply_emp`). Keep the vehicle Requests in status.
   d) Placement: unit strips (`police_blockade.gd:61-72`) and drone strips (`police_drone.gd:125`)
      appear at `player_pos + forward × 80/120 m` in a straight line — off the road on curves, floating
      or buried on ramps/decks, popping in in plain view. Place along the lane graph (s + 80/120 m on
      the predicted route), snap with a down-ray to layer 1, drone strips fall from the drone
      (0.6 s) with radio "前方投放钉刺带", max 4 strips alive, free strips > 300 m behind.
   Verify: new `tests/test_spikes.gd`: player over a strip → cap 162 km/h; pursuit ends → cap back to
   250 km/h within 0.1 s; two strips 2 s apart → back to 250 km/h after both expire; a police car
   over a strip → 0 engine errors; drone/unit strips lie on the road surface (|dy| < 0.1 m).

9. **Drone: body pitched at the player, dead rotors, invisible searchlight, silent EMP lock.**
   `police_drone.gd:99` `look_at(player)` tilts the whole drone 40-60° nose-down
   (`review_police_r1_b_t8_8.jpg`, `review_police_r1_city_t8_8.jpg`); the `Rotor_*` meshes never spin
   and the `Rotor_*_blur` discs are unused; the SpotLight3D (energy 6, range 140 m, at (0,-0.4,0),
   not on the glb's `Spot` Empty) gives no readable pool around the Roadster in the chase views
   (`review_police_r1_b_t10_3.jpg`, `review_police_r1_city_t10_3.jpg`). The EMP lock (2.0 s) has no
   tell at all, so the pulse cannot be dodged.
   Do: body level (pitch ≤ 12° into the travel direction, bank ≤ 15° in turns); spin the rotors and
   show the blur discs; mount the light on `Spot` and aim only the light (gimbal); make the pool read
   brighter than the street lamps (start: energy 60, spot_attenuation 0.6, spot_angle 15° (≈25-30°
   full cone), angle_attenuation 0.5, light_volumetric_fog_energy 3, colour #D9E8FF) plus a soft
   additive beam cone (alpha 0.12 → 0) so it reads on presets without volumetric fog; EMP lock: spot
   turns #FF2030 and pulses at 4 Hz for the 2.0 s, toast `&"police"` "EMP锁定！".
   Verify: captures `drone_side` (6 m away, same height) and `drone_chase` (game chase cam, pool
   visible around the car), plus the EMP lock frame.

10. **Damage and takedowns are counted twice; "disabled" ignores flipped/stuck units.**
    The damage unit already damages every VehicleBase and credits police takedowns
    (`damage/damage_director.gd:134-193` → `apply_damage`; `damage/takedown_tracker.gd` kind
    `&"police"`). The police unit ALSO applies `PoliceDamage.apply` (`police_director.gd:289`) and emits
    `Events.takedown` (`police_director.gd:304`) → double HP loss, double banner / N₂ / takedown cam.
    The brief says takedowns are the damage unit's ("police can be taken down (damage unit)").
    §6.3 "disabled = HP 0, flipped, or stuck > 4 s" — flipped/stuck units are never counted, keep their
    budget slot and block the backup timer.
    Do: delete the HP and takedown logic of `police_damage.gd`; count disabled units from `wrecked`,
    from flipped (basis.y·UP < 0.3 for 1.5 s) and from stuck (< 2 m/s for 4 s while engaged); remove
    them out of view after 10 s; withdraw the takedown request to damage in status.
    Verify: a test with the damage director loaded: one hard ram → exactly one `Events.takedown`;
    a unit rolled onto its roof counts as disabled after 1.5 s and raises `pursuit.disabled`.

11. **Siren never plays and warns every 1.2 s.** `police_siren.gd:28` calls
    `audio.play_3d(&"siren_wail" / &"siren_yelp", …)`; the audio unit refuses loop ids there
    (`game/audio/oneshot_pool.gd:59-61`: "is a loop and needs attach_loop()") — and its
    `world_emitters.gd` already attaches a following siren loop to every node in group `police`.
    `police_radio.gd` also asks for `&"radio_squelch"`, which the audio library does not have.
    Do: delete `police_siren.gd` and the director's `_update_siren` (rely on the group emitters), or
    call `attach_loop(id, unit)` once per unit if the audio unit asks for it; drop the squelch or
    request it from audio in status. Verify: a 20 s heat-2 chase prints 0 `[audio]` warnings.

12. **Heat-5 toll-plaza closure is missing** (no code at all; status says "implemented").
    Do: at heat 5, when the predicted route reaches a toll plaza within 600 m, close it (parked units
    + `roadblock_barrier.glb` across every toll lane, out of view, radio "部署路障！"); request a
    close/open API from the world unit if the plaza barriers must drop. Verify: test + capture.

13. **No reward at the end of a pursuit** (deliverable 2: "pursuit end → reward toast").
    `police_pursuit.gd` `end()` only toasts "甩掉警察了！ ESCAPED". Do: bounty = 500 × heat + 10 per
    pursuit second + 250 per disabled unit (constants); escaped → `Events.stunt(&"escape", bounty,
    "甩掉警察！ +%d")` and the toast with the number; busted → "被捕了！ BUSTED −%d" (rewards lost, §3.4).
    Verify: `test_heat.gd` checks the escape stunt event and the amount.

14. **"Never more than 3 units within 30 m" is only checked at spawn** (`police_spawner.gd` `spawn` →
    `close_units`), where units appear 150-320 m away, so it never acts. Do: a dynamic hold-back —
    the 4th+ nearest live units hold ≥ 32 m from the player (speed = player speed, no role states).
    Verify: test: player parked, 8 units at heat 4 converge for 20 s → ≤ 3 within 30 m on every frame,
    and busting still works.

15. **Performance is over budget and mis-measured.** Brief: ≤ 1.5 ms/frame with 12 units.
    `test_perf.gd` reads `tick_ms`, which is lerp-smoothed (`police_director.gd:139`, factor 0.15), so
    its "peak" is not a peak, and it excludes the 12 ArcadeCars the unit drives. My numbers:
    `test_perf` mean 0.442 / "peak" 0.700 ms (status claims 0.224 / 0.312); smoothed tick max 0.75-6.68
    ms in probes; headless wall time per 120 Hz physics frame, same run, no police vs 12 awake units:
    0.531 → 3.095 ms and 0.751 → 3.633 ms (**+2.6 to +2.9 ms per physics step**, ≈ 5.5 ms per 60 fps
    frame). Hitches: `load()` + instantiate of `police_car.tscn` (with its glb) ×3 inside the physics
    tick at every roadblock, the drone glb + `MaterialLibrary.apply` at drone spawn.
    Do: `const` preload all scenes; pool units, roadblock cars, strips and drones; full ArcadeCar
    physics only for the ~4 nearest/visible units, the rest kinematic on lanes (extend `PoliceSleep`);
    `test_perf` reports the raw per-frame max (no smoothing) AND the wall-time delta vs a no-police run
    in the same test. Budget: mean ≤ 1.5 ms, max ≤ 3.0 ms over 1200 frames with 12 units at heat 5.

16. **Captures (deliverable 6) are missing or mislabelled.** `captures/police_city_t9_0.jpg` shows the
    camera inside a beige building wall (status: "the blue bar of the interceptor on the Bund road");
    the sandbox shots show 3 tiny cars 30-60 m away; no tactic is ever shown. The demo uses its own
    camera 34 m back with 6 fake orange omni "lamps". After the fixes, capture on the CITY with the
    game chase camera (`res://vehicle/camera/chase_camera.tscn`), 1600×900, and put a 3×3 contact
    sheet in status: `chase_h3` (lit bars, red/blue pools), `pit_contact` (+0.5 s spin), `box_formed`,
    `roadblock_h3` (25 m before, gap visible), `roadblock_h4` (closed, strip, barriers), `spikes_close`
    (2.5 m, textured), `drone_chase` (searchlight pool), `head_on` (SUV 80 m ahead, oncoming),
    `toll_closed_h5`. Every status claim must match its image.

17. **Code rules: magic numbers, duplicates, dead code, files at the limit, runtime writes into
    another unit.**
    - Magic numbers in logic (give each a named, commented const): `police_car.gd:208` (0.3, 8.0),
      `:226` (−2.0, 25.0, 10.0), `:229` (22.0), `:271` (`PIT_GAP_MIN - 0.6`), `:298-299` (20.0, 14.0),
      `:306` (3.0, 14.0); `police_pursuit.gd:137` (2.0), `:174` (40.0); `police_driver.gd:62,68,77,82`;
      `police_tactics.gd:54` (2.0, 0.4, 6.0), `:92` (1.6, 0.9); `police_spawner.gd:173` (120/420),
      `:186` (0.7), `:230` (300/500); `police_blockade.gd:102` (250/600).
    - Duplicated constants: `HEAD_ON_SPEED`, `PIT_STRIKE_STEER`, `ENGAGE_MEMORY`, `PUNCTURE_SPEED`,
      `PUNCTURE_TIME` are each defined in two files. Duplicated logic: `_in_view` (spawner + blockade),
      strip creation (blockade + air), strobe update (lightbar + drone), police-car instantiate/setup
      (spawner, director, roadblock). One source each.
    - Dead/wrong: `PoliceDriver.GRIP` unused, `LATERAL_GAIN := 0.0` term, `PoliceCar.PUNCTURE_MU`
      unused, the comment "grip 1.4 x g" on `MAX_LATERAL := 4.0` (that is 0.41 g).
    - `police_director.gd` is 393 lines and `police_car.gd` 390: split FIRST, in a separate step
      (e.g. offences + test hooks out of the director; role ticks out of the car), then fix.
    - Writing `boost.speed_cap` / `boost.n2` of the vehicle unit at runtime is an ownership breach;
      keep it in the single debuff owner of item 8c until the vehicle API exists.

## SHOULD-FIX
1. `PoliceDriver.MAX_LATERAL = 4.0 m/s²` (0.41 g: a 193 m turn radius at 100 km/h) makes the police
   timid in the city. Keep the vehicle Request (roll stiffness) and raise to ≥ 9 m/s² when it lands;
   until then prefer units that come from oncoming lanes/junctions over same-direction "ahead" spawns
   (70 % of spawns roll ahead in the player's direction and must U-turn).
2. Light bar: both OmniLights sit at (0, 1.3, 0); put red at x −0.45 and blue at x +0.45 so the pools
   alternate left/right. Use the ART.md colours exactly: red #FF2030 (code has #FF171F), blue #2A5CFF.
   Give the unlit lens a faint emission (0.3) so the bar is not dead grey 62 % of the loop.
3. Expose the meters for the HUD instead of letting it re-implement them (`ui/hud/hud.gd:312-320`
   duplicates busted/evade): director in group `police_director` with documented `heat`,
   `pursuit_state`, `evade`, `busted`, engaged-unit count, backup seconds left; note it in status.
4. `_update_units` despawns at > 420 m even in view: despawn only out of view.
5. The heat-5 radio line "注意，空中航道已封闭" claims the sky lanes close; nothing does. Change the text
   or implement it.
6. Scratch hygiene: the worker wrote `/tmp/dbg_bust.gd`; scratch goes to `tmp/police/` only.

## Verified OK
- `tools/godot.sh check --only=res://ai/police/` → 31 files, 0 failed, 0 engine errors, 0 warnings.
- 45 test checks green (heat 14, busted 8, roadblock 10, pit 3, drone 8, perf 2) — but see items
  2, 4, 15: three of the suites pass on broken behaviour.
- Heat table = dossier §3.4: units 3/5/7/9/12, backup 60/50/45/40/35 s, cooldown 20/35/50/70/90 s,
  time steps 60/120/200/300 s, disabled steps 2/5/9/14.
- Line of sight every 0.2 s, roof 1.6 m → player roof, 220 m ground / 350 m drone, world layer 1;
  evade after 4.0 s, hiding spot ×2, sighting resets the bar; sky lane blinds ground units only;
  flash charge blinds for 1.0 s.
- Busted meter 1/3 per s below 15 km/h with a unit ≤ 12 m, drains 1/s, never airborne/flying.
- Light-bar strobe matches art dossier §4.8: 0.75 s loop, red 0-70/130-200 ms, blue 375-445/505-575
  ms, emission 12, omni range 14 m, energy 4, vol-fog 2.0, no shadows, only the 3 nearest units.
  Red/blue pools on the wet asphalt read well (`review_police_r1_b_t2_6.jpg`, `_b_t3_6.jpg`,
  `_city_t2_6.jpg`).
- Drones: 1 at heat 4, 2 at heat 5, 35 m up, 20 m behind; the HEAD_ON state charges at 25 m/s.
- Radio toasts use `Events.toast(text, &"police")`; all `radio_*` voice ids exist in
  `game/audio/voice/voice_lines.gd`.
- Ownership: the job log shows edits only under `game/ai/police/**` and `status/police.md`.
- Static typing everywhere; no file over 400 lines (two at 390+).

## Cross-unit notes (for the lead, not the police worker)
- Police cars render plain white without the 天巡 SKYPOL navy band / yellow stripe (all captures); the
  drone shell is a bare ring frame — tracked in `reviews/npc_cars-r1.md` items 1-5.
- `modes/pursuit_session.gd` calls a `set_heat` the director does not have (item 1 adds the API).
- City captures log `INSTANCE_CUSTOM` shader compile errors (not police code).

## Evidence
Commands (from `/Users/minimax/m/skyrush`):
- `tools/godot.sh check --only=res://ai/police/` → `CHECK 31 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://ai/police/tests/test_{heat,busted,roadblock,pit,drone,perf}.gd` → all PASS;
  roadblock gaps printed as centre spacings `[4.95, 1.95]` / `[1.95, 1.95]`; pit `yaw -0.76 rad/s`;
  perf `units: 12, mean 0.442 ms, peak 0.700 ms` plus
  `SCRIPT ERROR: Invalid call to function 'apply_puncture (via call)' in base 'RigidBody3D (PoliceCar)'. Expected 0 argument(s).`
- Reviewer scratch probes (headless, `extends Node`, run through the test host with the unit's own
  `tests/police_test.gd` helper; deleted after the review — rebuild them as real tests):
  - A (sandbox, player parked at (-500, 0, -196), heat 0, spawning on): `A1 t=10s units[patrol/st1/109m]`
    … `t=25s … patrol/st1/7m`; `A2 speeding past patrol: kmh=185 seen_any=true state=none infr=[]`;
    `A3 'reckless' 0.2 s after respawn -> state=chase heat=1`; `A4 infraction events in 2 s of chase: 236`.
  - B: `B1 tap 1: air gap 1.39 m (|x| 3.32, z 7.26), contact this frame false, yaw -0.76`;
    `B2 head-on lane: tangent.fwd=1.00 … 0.77 … 1.00`; `B3 heat 2: width 13.08, car centres [-3.90,
    1.05, 3.00], car axis . road axis 1.00`; `B3 heat 4: … [-5.56, -3.61, -1.66] … strip true` (3 SCRIPT
    ERRORs at that spawn); `B4 player cap km/h: before 250, on spikes 162, 10 s after the pursuit ended 162`.
  - C: `block origin (-150.2, 0.1, -196.0)`; `car world (0.0, 0.1, -1.7) dist-to-block 245.6 m` (all six
    cars 242.5-250.7 m away).
  - F/G: `box: seconds fully formed 0.0; front unit best z 14.8 m`; head-on placed by hand facing the
    player: `closest approach 4.6 m, hits on player 2`; `spawn_unit_at` at 260 m → `z +0.1 … 208698 km/h`.
  - E (wall time per physics frame, same run): `no police 0.531 -> 12 units 3.095 (delta 2.564)`,
    `no police 0.751 -> 12 units 3.633 (delta 2.882)`; smoothed tick max 0.75-6.68 ms across runs.
- Windowed captures (my probe scene wraps `res://ai/police/demo/police_demo.tscn`, review camera):
  `tools/godot.sh shot --scene=<probe>.tscn --out=review_police_r1_b --warm=1 --times=2.6,3.6,4.6,5.9,7.3,8.8,10.3`
  (+ `--city=true` → `review_police_r1_city_*`). Files in `captures/review/police/`:
  - `review_police_r1_b_t2_6.jpg` / `_t3_6.jpg` — light bar red / blue phase, pools OK.
  - `review_police_r1_b_t5_9.jpg`, `review_police_r1_city_t5_9.jpg` — grey-box spike strip.
  - `review_police_r1_b_t7_3.jpg`, `review_police_r1_city_t7_3.jpg` — roadblock cars at the world origin.
  - `review_police_r1_loop_t5_6.jpg` — the heat-3 block position: empty road.
  - `review_police_r1_b_t8_8.jpg`, `review_police_r1_city_t8_8.jpg` — drone pitched at the player, rotors still.
  - `review_police_r1_b_t10_3.jpg`, `review_police_r1_city_t10_3.jpg` — chase view, no searchlight pool.
  - Contact sheets: `sheet_b_1.jpg`, `sheet_b_2.jpg`, `sheet_city.jpg`, `worker_sheet.jpg` (the six
    worker captures; `police_city_t9_0` = camera inside a wall).
- Brief references checked: gameplay dossier §3.1-3.5, §6.3, §7.3; art dossier §4.8 (light bar,
  livery); ART.md §3/§5; CONTRACTS.md §3/§5. The brief names no reference photos; the art dossier
  numbers were used instead.
- Ownership scan of `jobs/police/log.jsonl`: Write/Edit only on `game/ai/police/**` and
  `status/police.md`; one scratch file in `/tmp` (removed).
