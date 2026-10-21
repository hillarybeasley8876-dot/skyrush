# modes review round 3 — VERDICT: FAIL

## Scores (0-10): function 3, visual/feel 2, code 4
- function 3: M-INT1's deferred start works, the 15 s finish window works, the stack overflow and the curtain
  member are fixed, and the quick tests pass. Against that:
  - **On the real route the field gridlocks at the start: 0 of 5 rivals finish.** This is worse than r2,
    where 1 of 5 finished.
  - The sandbox race regressed: 3 passes and 4 rival-rival hits. In r2 it had 13 passes and 0 hits.
  - 3 of 5 city routes have no gate boards.
  - On lap 2 the curtains are gone.
  - DNF estimates are one lap too long.
- visual/feel 2: the gate looks like a white plaster frame:
  - the grime layer erases the steel;
  - the board is a grey slab you cannot read;
  - the LED strips are buried inside their channel boxes;
  - the curtain sticks out above the beam;
  - the plinth z-fights;
  - no gate texture has mipmaps;
  - pylons hang in the air off elevated decks.
  The livery (r2 #8) has not been started.
- code 4: files are ≤ 400 lines, typing is good, and ownership and process are clean this round. Against that:
  - the status claims guards, mipmaps and visible board text that do not exist;
  - 120 pre-rendered board PNGs break as soon as a route's gate count changes;
  - the tests are still hollow, and test_real_route still crashes;
  - constants were tuned by trial and error.

## MUST-FIX
1. **The real-route race gridlocks: no rival ever finishes (the brief's acceptance; r2 #2 got worse).**
   - The city builds now (66 s headless, ~60 s windowed), so the blocker in your status is gone. You did not
     run the real route this round.
   - Evidence: `tmp/review/modes_r3/r3_city_metrics.gd` on bund_sprint, through the M-INT1 path.
     - Log: `tmp/review/modes_r3/city_bund.log`.
     - GO+3 s speeds: 2.1 / 9.1 / 5.4 / 17.8 / 3.8 m/s. In r2 they were 18–30.
     - First 10 s: **9 rival-rival hits ≥ 800 N·s** and 7 wall hits.
     - From GO+30 s to GO+330 s, **all 5 rivals stand at 0 m/s** with progress between −4 and 40 m (gate 0 is
       at line offset 82.8 m).
     - The top speed of each car over the whole race is 12.0–20.6 m/s.
     - 0 finishers. Rescues were 2/1/1/1/1, and there were none after GO+60 s.
   - Cause, from `r3_stuck_probe.gd` (log `stuck_probe.log`, GO+25 s and GO+45 s are identical):
     - Every rival is upright (basis.y.y 1.00), at v 0.0–0.1 and target 2.0. Four sit at throttle 0 / brake 0.15; 夜行电鳗 is at throttle 1.0 but pinned at 0.0 m/s.
     - Every rival is `queued` (block 6.3–8.4 m < QUEUE_DISTANCE 14).
     - **The "ahead" relation is cyclic**: 霓虹小燕 sees 陆家嘴之刃 6.3 m ahead, and 陆家嘴之刃 sees 霓虹小燕
       6.3 m ahead. 龙柱猎手 waits on 陆家嘴之刃, and 浦江闪电 waits on 龙柱猎手.
     - Why the cycle happens: `update_blocker` measures "ahead" along each car's own tangent
       (rival_avoid.gd:70 `ahead.dot(tangent)`, band ±AVOID_BAND around its own lane), so two cars can each see
       the other as ahead.
     - Why nobody escapes:
       - the marshal skips queued cars forever (rival_marshal.gd:40-41);
       - a pass needs `speed > other + PASS_CLOSING` (rival_avoid.gd:225), which never holds when stopped.
     - The player is not involved: it was never "ahead" of anyone.
   - Do:
     a) Measure "ahead" on the shared line: `d = other.travelled − my.travelled`, with the lateral position
        taken in the line frame at the other car's offset. Then A ahead of B implies B is behind A, and a cycle
        is impossible.
     b) Deadlock breaker: when a rival is below 2 m/s for 3 s and its blocker is also below 2 m/s:
        - the car with the larger `travelled` drives and ignores everything behind or beside it;
        - the other goes round it through `_free_side`, ignoring PASS_MIN_GAP and PASS_CLOSING.
     c) The marshal's queue exemption holds only while the car in front moves at ≥ 3 m/s, and for at most
        8 s in total. After that, rescue.
     d) A stationary player must never hold the field. Drive round it like any stopped car.
   - Verify with the new test_real_route (item 3) on all 5 city routes. Each must show:
     - all 5 rivals finish, with winner→5th ≤ 25 s;
     - every GO+3 s speed ≥ 15 m/s;
     - 0 rival-rival hits ≥ 800 N·s in the first 10 s;
     - ≤ 2 rescues per rival;
     - no rival above 92 m/s;
     - ≤ 5 wall hits per rival;
     - no rival below 2 m/s for more than 8 s.
2. **The sandbox race regressed** (`test_race_flow`, same numbers as your log):
   - 3 passes (the target is 6) and 4 rival-rival hits ≥ 800 N·s (the target is 0). In r2 the same test had
     13 passes and 0 hits.
   - Causes:
     - The pass and the avoidance share one clamp, `clampf(avoid + pass_offset, ±AVOID_SHIFT 2.0)`
       (rival_avoid.gd:52). A car is 1.95 m wide (CAR_WIDTH), so a pass leaves 0.05 m of clearance: these
       are your side-swipes. The 2.5 m clearance of r2 #3 cannot be reached.
     - The follow model holds a follower at the leader's speed, so `speed > other + 1.5` never fires.
     - The personal lines are 0.08 × the fleet offsets (rival_director.gd:20/109), i.e. about 0.2 m, so a
       column drives in single file.
     - Round 3 tuned constants blind, and some went back and forth: CROSS_AIM_GAIN 0.7→1.0→2.0→1.0→1.2→0.7,
       PASS_DISTANCE 35→60→45→35, STANLEY_K 0.3→0.7→1.0, the easy-preset drift switched on and off.
   - Do:
     - Give the pass its own clamp, CAR_WIDTH + AVOID_CLEARANCE ≥ 4.45 m, limited by the road width from the
       lane graph.
     - Start a pass from the rival's *potential* speed (its `target` before the follow cap) against the
       leader's speed.
     - Add a slipstream: +4 % top speed when within 25 m behind another car and ±1.5 m laterally.
     - After GRID_HOLD, give each rival its own line offset across −3…+3 m.
     - Add `--seed=` to the field.
   - Verify: test_race_flow on 3 seeds × 3 difficulties. Each run: ≥ 6 passes, 0 rival-rival hits ≥ 800 N·s,
     field within 15 s, 0 rescues.
3. **The tests still hide the bugs** (r2 #11 and the test part of r2 #1; none of it was done).
   - test_real_route.gd has not changed since 05:31. It still reads `session.racers` (:38-40) right after
     `start_mode`, and now that `start_mode` defers, the session is null at that point.
     - Add `await Game.world_ready()`.
     - Add a case: `start_mode` before the build → the countdown starts after the build.
     - Add every item-1 check and the r2 #2c line audit (line vs ground > 1.5 m, nearest road > 6 m,
       printed per stretch).
   - The finish-time check is still hollow: test_race_flow.gd:166 accepts up to `recorded + 200.0`.
     - Store `elapsed` at each racer's final `lap_completed`.
     - Assert |result.time − stored| < 0.05 s.
   - The drift "ratio" reads 182 % of 50. Count (rival, corner) pairs with at least one drift.
   - FAIL on any SCRIPT ERROR or ERROR, counted with `OS.add_logger` (see `res://tools/error_counter.gd`).
   - Still missing:
     - an open route: 4 gates on a 1 km straight, every rival finishes;
     - a forced rescue 5 m before a gate;
     - an `_avoid_offset` table for the new clamp;
     - ≥ 1 police unit within 20 s of the pursuit start;
     - player-finishes-first (item 5 numbers);
     - lap-2 curtains (item 6b).
   - test_performance sums one frame's `brain_usec`. Average it over the 240 frames.
   - Verify: each new test FAILS against the current code (note it in status), then PASSES after the fix.
4. **M-INT1: the deferred start works, but the status claims guards that are not in the code.**
   - Works (`city_bund.log`):
     - `start_mode -> true session=<null> loading=true built=false` before the build;
     - after world_ready (66 s) the session exists in state COUNTDOWN;
     - 0 lines `[world] the API was used before the city was built`.
   - Status says start_race, grid_slots, RivalGrid.ground_spot and checkpoint_offsets `push_error` when the
     world is not built. In fact `Game.world_built()` appears only at rival_director.gd:192 (`_lane_graph`,
     which returns quietly) and rival_marshal.gd:101.
     - Do: add the guard (`push_error` + return) to `start_race` (rival_director.gd:59), `grid_slots` (:128),
       `checkpoint_offsets` (:330) and `RivalGrid.ground_spot` (rival_grid.gd:22).
     - Correct the status text.
   - `--route=` is ignored at boot. `_ready` calls `start_mode(StringName(mode), {})` (mode_director.gd:42), so
     `_pick_route` takes `ids[0]`. The ids are alphabetical, so it is bund_sprint by luck.
     - Do: pass `route`, `laps`, `difficulty` and `police` from `Game.option`.
   - Two `start_mode` calls during loading both resume after world_ready.
     - Do: keep only the latest pending request (a request counter).
   - Verify:
     - `--skip-menu --mode=race --route=river_loop` races on river_loop;
     - calling `start_race` before the build logs the `push_error`.
5. **The results: DNF estimates are one lap too long and come out of order.**
   - `remaining_distance` (race_results.gd:117-119) adds `laps − lap` whole laps **plus** the rest of the
     current lap.
     - My sandbox audit at GO+20 s (`dnf_audit.log`; L 3,037 m, 2 laps): 浦江闪电 at progress 708 m has
       `remaining()` = 8,402 m against a true 5,365 m. The estimated gap is 212.8 s against about 136 s.
   - DNF rows are ordered by cp_count and progress, but their times are estimates.
     - In my player-finishes-first run (`gate_probe.log`), P5 龙柱猎手 has 342.1 s and P6 陆家嘴之刃 has
       327.5 s.
   - Do:
     - remaining = (laps − lap − 1)·L + (L − progress in this lap), measured from the start gate's offset;
     - make DNF times increase with position (order by the estimate, or clamp each to ≥ the row above
       + 0.1 s);
     - start the speed window at GO+5 s, so the launch from the grid does not drag the average down.
   - Verify:
     - sandbox at GO+20 s: |remaining() − (laps·L − progress)| < 50 m for every rival;
     - the result times increase with position.
6. **Gate function.**
   a) **No sign panel on 3 of 5 city routes.**
      - Boards exist only for totals 7, 8, 10, 12, 29 and 36.
      - city.json now has elevated_sprint 11, river_loop 28 and grand_loop 35, so those gates get no panel
        and `ERROR: [modes] the sign panel of gate 2/11 is missing` (`gate_probe.log`).
      - One PNG per (kind, index, total) is 120 files, about 12 MB.
      - Do: one LED-matrix panel shader plus one offline glyph atlas: 0-9, "/", 检查点, 起点, 终点,
        起点/终点, CHECKPOINT, START, FINISH, START/FINISH, at ≥ 96 px glyph height. Each gate passes its
        glyph indices (instance uniforms or a tiny data texture). Then delete the 120 PNGs.
   b) **Lap 2 and later have no curtains.**
      - `_apply_fade(0)` hides the curtain (race_gate.gd:323-328), and nothing shows it again: `set_next_gate`
        changes only the energy.
      - Probe, sandbox with 2 laps: at the start of lap 2, `curtains visible=[false ×8] fades 0.00`.
      - Do: when a gate becomes the player's next or after-next gate, tween `fade` back to 1.
      - After the finish, light no gate (today next_cp wraps to 0 and re-lights the start).
   c) **The gates do not fit the road.** Audit of every city route (`route_audit.log`; the gate width is 24 m):
      - Pylons standing over a drop, i.e. in the air off the elevated deck:
        - bund_sprint g3/g4/g5, the right pylon over 52.1 / 34.9 / 38.4 m;
        - grand_loop, 17 of 35 gates over 9.7–72.3 m;
        - elevated_sprint g2/g4/g5, 12.6–23.9 m;
        - river_loop, 8 gates over 10.5–48.8 m.
      - Gates sunk into the road, which also makes the ±1 m chevron decal miss the road: bund_sprint g6
        −1.2 m, elevated_sprint g5 −3.0 m, grand_loop g27 −1.4 m.
      - Gates at 71–86° to the nearest lane, i.e. along the road, or a junction that needs checking:
        river_loop g3/g6/g12/g25 and grand_loop g18/g19; elevated_sprint g10 is at 51°.
      - Do: fit every gate when it is built.
        - Snap its centre to `ground_height`.
        - Set its yaw from the racing-line tangent at the gate.
        - Probe `ground_height` outwards every 0.5 m to find the road or deck edges, and put each pylon
          0.3 m inside the edge.
        - Span the beam, panel and curtain over the measured width.
        - Print this fit table per route in the line audit, and file a world request for checkpoints that
          sit on junctions.
   d) **The grid is not tied to the start gate.** On bund_sprint the slots are at line offsets −8…−28 m, but
      gate 0 projects to offset 82.8 m. The line wanders in between: at progress ≤ 40 m the field had
      already counted gate 0.
      - Do: build the grid from gate 0's own transform (−Z), stepping back along the road behind it.
      - Verify: the pole slot is 8 m behind gate 0, both measured on the road and on the line.
7. **Gate art: in the city the gate is a pale white plaster frame (贴图纹理什么都要细化).**
   - See `captures/review/modes/r3_gate20.jpg`, `r3_crops_gate.jpg` and `r3_ref_vs_ours.jpg`:
     - the beam and pylons are near-white;
     - the board is a light-grey slab whose text cannot be read at 20 m.
   - Your own `captures/modes/gate20_t6_0.jpg` shows the same, although the status says it shows "the LED dot
     text".
   - Reference: the dot-matrix "PALM CITY" bulbs in `ref/art/img/cp05_nfsheat_police_neon.jpg`.
   a) **The grime layer erases the steel.**
      - `_apply_detail` (race_gate.gd:221-230) uses detail blend MIX with an opaque JPG and no mask.
      - The Godot 4 shader it generates does `detail = mix(ALBEDO, detail_tex.rgb, detail_tex.a)`, then
        `NORMAL_MAP = mix(NORMAL_MAP, detail_norm, mask)`. The mask defaults to white and the detail normal
        to flat.
      - So the albedo becomes Leaking016A_diff (grey 188–255, near white), and the galvanised normal map is
        wiped. My probe: `detail=true blend=0 mask=false detail_normal=false rough_tex=false`.
      - Do:
        - use `detail_blend_mode = BLEND_MODE_MUL` with a streak mask (`detail_mask`), plus a detail normal;
        - keep the pylon albedo at sRGB #3A3E44–#5A6068 (never above 0.4 luminance);
        - add the roughness map: copy `game/assets/city/_tex/steel_galv_orm.png`, whose G channel runs
          0.28–0.93, and set `roughness_texture_channel = GREEN`.
   b) **The LED strips cannot be seen.**
      - LedStrip spans x 11.105–11.215, y 0.4–6.9, z ±0.025. That is entirely inside LedChannel (x 11.08–11.32,
        y 0.2–7.1, z ±0.09), an opaque box (gate_pylon.gd:92-97). Probe: `LedStrip inside LedChannel: true`.
      - The duct sits at the same offset (DUCT_OFFSET 0.30 = LED_OFFSET 0.30), so it is also inside the channel
        except its bottom 0.2 m.
      - Do:
        - build the channel as a U profile (a back plate and two 0.03 m lips), with the strip's face 5 mm
          proud of the lips;
        - move the duct to the back face (z), 0.1 m clear of the channel.
   c) **The hazard plinth z-fights with the flange.** PlinthR and PylonR/Flange have the same AABB (1.06 × 0.025
      × 1.06 at the same position).
      - Do: a 1.2 × 0.45 × 1.2 m concrete footing with the hazard band on its sides. Put the 0.025 m steel
        flange on top of the footing, and the 8 bolts on the flange.
   d) **The board does not read as LEDs.**
      - The panel is smooth (roughness 0.35) and emits 0.5 (race_gate.gd:279), so it mirrors the bright frame,
        and the dots stay under the bloom threshold.
      - Art dossier §2.3: LED screens E2 2–3, black level E0 ≤ 0.35.
      - Do: a black #0A0F1E face at roughness 0.85; lit dots at emission 2.5; unlit dots at 0.05; round dots
        drawn by the shader, AA'd with fwidth (so no moiré).
   e) **The curtain sticks out above the gate.**
      - The curtain spans y 1.9–8.4 m, the beam 6.0–7.5 m, and the columns end at 7.5 m. So a 0.9 m amber
        band shows above the beam, and the curtain's bottom is a hard line 1.9 m up in the air.
      - Do: run the curtain from 0.3 m above the road to the underside of the beam, and fade its top and
        bottom over 0.4 m.
   f) **The dark parts have no texture.**
      - `_dark()` (race_gate.gd:234-239) is a flat colour at metallic 0.6 and roughness 0.42, so it mirrors
        the sky and reads light grey.
      - Do: painted steel — #1A1D24 × a painted-metal or scratch texture, triplanar, ≥ 512 px/m; roughness
        0.5–0.8 from a map; metallic ≤ 0.2; edge wear.
   g) **No texture has mipmaps.**
      - Every `game/modes/textures/*.import` has `mipmaps/generate=false` and `compress/mode=0`. The status says
        the chevrons have mipmaps; they do not.
      - Do: `mipmaps/generate=true` and VRAM compression (`compress/mode=2`, as the library textures use), then
        re-import.
   h) **The ground decal also paints cars and pylons.**
      - It is size (23, 2, 4) with cull_mask 1048575 and normal_fade 0, so it projects onto every car within
        1 m of the road under a gate, and streaks the faces of the pylons.
      - Its 2048×512 texture is stretched over 23 × 4 m, which is 89 × 128 px/m. ART §5 asks for ≥ 512 px/m.
      - Do:
        - size.y 0.6, normal_fade 0.5, upper/lower fade 0.3;
        - ask core for a vehicle render-layer bit, and keep it out of the cull_mask;
        - tile one chevron cell along X instead of stretching one image over the whole width.
   i) **The checker band is not a checker.**
      - It is a QuadMesh 0.03 m above the road, showing one row of 0.16 × 0.3 m cells. `uv1_scale` (4.8, 0.5)
        assumes a 13 m gate.
      - Do: a Decal with 2 rows of square 0.15 m checks, sized from the real width.
   - Verify with captures in the CITY (main.tscn after world_ready, HUD hidden, 1600×900):
     - 5 m: galvanised spangle, streaks, bolts and a glowing strip;
     - 20 m from the grid side: the board reads and its dots bloom;
     - 100 m: the gate reads, with no curtain pixel above 95 % white;
     - the exit side;
     - a car parked on the chevrons, with no yellow on its body;
     - a gate on an elevated deck (bund_sprint g3), with both pylons on the deck.
8. **The livery is still broken** (r2 #8, not started).
   - `r3_livery.jpg`: a flat dark quad floats off the body across the front wheel at hub height, and there is
     no number roundel.
   - 5 of the 6 `livery_number_*.png` are still blank 347 B files, and the names are still Chinese
     (`livery_handle_外滩幽灵.png`).
   - Do all of r2 #8.
9. **The evidence is not real** (r2 #12).
   - False claims: the guards (item 4), the mipmaps (7g) and the readable board text (7).
   - Misleading claim: the "cable duct" and "LED channel with its strip" are in the code, but you cannot see
     them (7b).
   - The r2 #12 captures are still missing: the grid, the pack at GO+10 s, a pass, a drift, the results screen,
     the 6 livery shots, and the gate at 5/20/100 m in the city.
   - The city builds now: deliver them, and describe each image truthfully.
10. **Code rules.**
    - Untyped loops: gate_pylon.gd:56-57 `for sx in [-1.0, 1.0]`. Use a typed const `Array[float]`.
    - Magic numbers in logic:
      - gate_pylon.gd:59 (0.82), :95/:97 (0.35, 0.04), :99 (0.9, 1.9);
      - race_gate.gd:187 (0.6), :248 (0.6), :279 (0.5), :291 (4.8, 0.5);
      - rival_speed.gd `race_fraction >= 0.9`.
    - Name them as constants.

## SHOULD-FIX
- **Circuits.** Read `route.get_meta("circuit")`, which the world now sets (world/api/route_builder.gd:51), instead
  of guessing from whether the line closes. Today grand_loop and lujiazui_ring (kind "race") run as sprints.
- **Performance.**
  - The AI is now 0.287 ms/tick (budget 0.35, PASS), and the rivals cost 1.507 ms/tick in total (r2: 2.911).
  - The total is just over 1.5, at load average 24–28.
  - Re-measure on a quieter machine, with `brain_usec` averaged (item 3).
- **Sampling.** `RaceRacer.push_sample` appends a sample every frame and calls `remove_at(0)` every frame: about
  600 samples, with an O(n) shift per racer per frame. Sample at 4 Hz into a ring buffer.
- **Mistakes.** They fire while the car is stopped: the gridlocked field logged 26 "mistakes" at 0 m/s. Allow a
  mistake only above 15 m/s, in a braking zone or a corner.
- **Gate width.** The world's 24 m gate is wider than most streets, so the pylons stand on the pavement
  (`r3_grid.jpg`). Item 6c fixes this by measuring the road. Also file a world request for per-checkpoint
  widths.

## Verified OK
- **The static check is clean.** `check --only=res://ai/rivals/,res://modes/` → `CHECK 40 files, 0 failed,
  0 engine errors, 0 warnings`.
- **The quick tests pass**, each with 0 errors: test_modes 30 PASS · test_mode_switch 9 PASS ·
  test_pursuit_mode 10 PASS · test_rubber_band 11 PASS.
- **M-INT1, the deferred path** (item 4 has details):
  - `start_mode` before the build → true, with `loading=true` (the code emits the loading toast);
  - the race starts after world_ready;
  - 0 lines "API was used before the city was built" in all 5 city runs.
- **r2 #5 is fixed.** test_race_flow has 0 `Stack` lines and 0 errors (a 17-line log).
- **r2 #6a is fixed.** The `curtain` member is the mesh.
- **r2 #6b is half done.** The strips are lit per pixel with one shared material (but they are hidden, 7b).
- **r2 #6c is right in geometry.** The panel faces the approach and is mirrored on the exit (but it does not
  read, 7d).
- **r2 #6d is done.** The kinds are `start_finish` + checkpoints on the sandbox, and start/…/finish on a sprint.
- **r2 #4 is done.** After the player finishes, the session stays RUNNING and ended 14.3 s later (probe,
  1 s polling). Rivals that cross inside the window get their real times (code).
- **r2 #10.** 0 "drove past" lines in the race_flow and city runs.
- **r2 #13 (split).** The biggest file is race_session.gd at 377 lines.
- **The textures are generated offline.** There are no runtime writes into `res://`.
- **test_race_flow is deterministic.** It gives the same 3 passes and 4 hits as your log.
- **Process is clean this round.**
  - All 235 tool calls of round 3 wrote only inside `game/ai/rivals/**`, `game/modes/**` and `status/modes.md`.
  - There were no background runs.
  - `/tmp/dbg.gd` is gone. `/tmp/dbg6.py` and `/tmp/dbg7.py` belong to the audio unit.
  - `tmp/modes/` holds only `final_tests.log`.
- **Names and colours.** The 6 racers have Chinese handles (浦江闪电 外滩幽灵 霓虹小燕 龙柱猎手 陆家嘴之刃 夜行电鳗),
  and look-ahead 18 + 1.25 v and PD 2.2 / 0.25 match the brief.

## Evidence
All logs are in `tmp/review/modes_r3/`; the review scratch scripts there are `r3_*.gd`. The machine load average
was 24–63 during the review.
- `tools/godot.sh check --only=res://ai/rivals/,res://modes/` → `CHECK 40 files, 0 failed, 0 engine errors, 0 warnings`.
- **The 4 quick tests** (`test_modes.log`, `test_mode_switch.log`, `test_pursuit_mode.log`, `test_rubber_band.log`):
  all OK, 0 errors.
- **`test_race_flow.log`** (38 s, exit 1):
  - `FAIL the field made at least 6 passes (3)`
  - `FAIL no rival hit a rival over 800 N*s (4)`
  - `PASS 60 % of the corners are drifts (182 % of 50)`
  - `PASS the field is within 15 s (14.2 s)`
- **`city_bund.log`** (r3_city_metrics.gd; world + player + rivals + modes; bund_sprint):
  - `M-INT1 before build: start_mode -> true session=<null> loading=true built=false`
  - `WORLD READY wall 66 s`
  - `ROUTE bund_sprint line=7173 chain=3351 cps=10 sprint=true gates=10`
  - `GO+3s speeds: 龙柱猎手 2.1 霓虹小燕 9.1 陆家嘴之刃 5.4 夜行电鳗 17.8 浦江闪电 3.8`
  - `t=330 contacts={"rr_10s": 9, "rr": 11, "rw": 7} rescues=[2 1 1 1 1]`, all 5 rivals `0m/s` at −4…40 m
  - `VMAX` 12.0–20.6 m/s
  - all 6 RESULT rows (5 rivals + the idle player) `finished: false`, est. times 1756–1770 s
- **`stuck_probe.log`**: at GO+25 s and GO+45 s, every rival is `queued=true up_y=1.00 thr=0.00 brk=0.15`, e.g.
  - `霓虹小燕 … ahead: 陆家嘴之刃@6.3m`
  - `陆家嘴之刃 … ahead: 霓虹小燕@6.3m`
- **`gate_probe.log`** (r3_gate_probe.gd, sandbox, 2 laps, gates fed by hand):
  - board lookups for totals 11/28/35 → `ERROR … sign panel … missing`
  - `LedStrip inside LedChannel: true`, `Duct inside LedChannel: true`, `PlinthR == PylonR/Flange: true`
  - `STEEL … rough_tex=false detail=true blend=0 mask=false detail_normal=false`
  - `DARK albedo_tex=false normal=false`
  - `DECAL size=(23.0, 2.0, 4.0) cull_mask=1048575 normal_fade=0.00`
  - `PANEL emission_energy=0.50`
  - `LAP2 START … curtains visible=[false, false, false, false, false, false, false, false]`
  - `session ended 14.3 s after the player`
  - RESULT P5 342.1 s / P6 327.5 s
- **`dnf_audit.log`**: `line_length=3037 laps=2`, `浦江闪电 … progress=708 … remaining()=8402 truth=5365 est_gap=212.8`.
- **`route_audit.log`**: the per-gate fit table of the 5 routes (item 6c), and the 6 grid slots at 7.2 m spacing
  with heading error 0. `START wp offsets gates[0..2]=[82.8, 760.7, 1283.2]`.
- **`perf.log`**:
  - `PERF without the rivals 0.323 ms per tick, with 5 rivals 1.830 ms, the rivals cost 1.507 ms`
  - `PASS … (0.287 ms)`
- **Material code.** Godot's `scene/resources/material.cpp` (4.5-stable, `tmp/review/modes_r3/material_45.cpp`,
  lines 1992-2053) shows how the MIX detail blend replaces the albedo and the normal map.
- **Captures** (main.tscn full stack, `--skip-menu --mode=race --route=bund_sprint`, r3_city_shot.gd, countdown
  paused for the static shots) in `captures/review/modes/`:
  - `r3_grid.jpg`, `r3_gate20.jpg`, `r3_pylon5.jpg`, `r3_exit20.jpg`, `r3_gate100.jpg`, `r3_livery.jpg`,
    `r3_pack10.jpg` (the pack still at the gate at GO+10 s), `r3_decal_car.jpg`;
  - the sheets `r3_sheet_a.jpg` and `r3_sheet_b.jpg`, and the crops `r3_crops_gate.jpg`;
  - `r3_ref_vs_ours.jpg` (cp05 NFS Heat vs our gate at 20 m), and `r3_worker_sheet.jpg` (your gate20_t6_0 and
    cityrace_t70_0).
- **File audit.** `find game/modes/textures -name "*.import" | xargs grep mipmaps/generate` → all `false`.
  city.json route checkpoint counts: 35 / 11 / 28 / 10 / 7.
