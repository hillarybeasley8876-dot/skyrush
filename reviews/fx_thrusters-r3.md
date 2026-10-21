# fx_thrusters review round 3 — VERDICT: FAIL

My captures were made from the current code (12:35–12:50): `captures/rvw3_*.jpg`. The sheets are
in `captures/review/fx_thrusters/r3/`: `A_18_27`, `B_29_28`, `C_core`, `D_strip`, `E_dist_top`,
`F_land_chase`, `I_crops`.

## Scores (0-10): function, visual, code
- **function 5**
  - Works and is tested (44 PASS): attach / detach / re-attach, the tiers, the smoothing, the
    landing gating, the stub fallback, particle collision, one random sprite frame per particle.
  - Broken:
    - the brief's budget case (all 10 nozzles + both clouds) costs **2.6–3.0 ms/view**; the
      budget is 1.2;
    - the test still leaks at exit (2 `ERROR:` lines);
    - a demoted rig keeps its clouds emitting (SHOULD-FIX 1).
- **visual 2** — The plume does not read as the phenomenon in photos 18 / 27 / 28 / 29 or the
  landing clouds:
  - the ground cloud is a sparse scatter of 1–1.5 m chips (2–5 % coverage from above);
  - the vapour columns look like clear glass bottles with hard rims, plus 0.3–0.5 m "gravel",
    in dull grey;
  - the boost trail is a 1 m wisp;
  - the shock diamonds cannot be seen in the rear close-up;
  - nothing reads at 20 m or at 100 m.

  Right so far: the palette (no pink, no orange) and the landing puff (`F_land_chase.jpg`,
  +0.15 s and +0.4 s).
- **code 5** — Typed, files ≤ 368 lines, a clean module split. Against it:
  - 7 false or stale comments;
  - dead code in `lib/plume_assets.gd`;
  - noise evaluated per vertex on a 12 × 8 tube (a design error);
  - magic numbers left;
  - status claims that the logs contradict (MUST-FIX 7).

## Round-2 MUST-FIX status
| r2 | item | now |
|---|---|---|
| 1 | every particle drew frame 0 | OK: random frame, anim_speed 0, tested |
| 2 | moon-rock sprite | OK: the lead's atlas |
| 3 | ground cloud | **FAIL** → MUST-FIX 1 |
| 4 | rear launch cloud | emits, and backwards (tested), but the look **FAILS** → MUST-FIX 2 |
| 5 | beaded vapour | **FAIL** → MUST-FIX 3 |
| 6 | shock diamonds | **FAIL** → MUST-FIX 4 |
| 7 | landing ring | OK |
| 8 / 9 / 10 | detach leak / attach error / collision | OK (tests; the error counter reads 0) |
| 11 | GPU budget | **FAIL** → MUST-FIX 5 |
| 12 | evidence and claims | **FAIL** → MUST-FIX 7 |

**Lead notes:** 1 OK, 2 **FAIL**, 3 **FAIL**, 4 **FAIL**, 5 OK.

**LEAD-SMOKE:** the presets are used, but their look-defining values were cut:
- ground-cloud sprites are about 5× smaller than the preset, and there are 4.4× fewer of them;
- vapour sprites are 0.28–0.49 m.

That loses the result of the lead's look-dev: `captures/lead_smoke7_*.jpg` shows a 10–12 m
billowing cloud. Do not shrink the look to buy budget again; MUST-FIX 5 says how to buy it.

## MUST-FIX
1. **The ground cloud is a scatter of chips, not a cloud** (lead note 4; brief layer 3; photo 18;
   video t = 118–120).
   - Measured with FX on minus `--demo-fx=core` (the particles alone):
     - strip cam `0,2.2,30 → 0,2,0`, fov 50, hop h = 1.6:
       - ~1.0 s: 10.8 m wide, 1.1 m tall, 0.2 % of the frame, mean +29/255;
       - ~2.0 s: 18.5 m wide, 1.4 m tall.
     - top cam `0,32,0.1` — coverage within 3 / 6 / 10 m of the car: **5 / 4 / 2 %**.
   - Video 119.0 (`D_strip.jpg`, bottom row): a solid wall about 20 m wide and 2.5 m tall that
     hides the car.
   - Cause, in `ground_cloud.gd`:
     - `CLOUD_SIZE (0.6, 0.9)` × `CLOUD_GROW 1.7` = 1.0–1.5 m sprites. The preset gives
       2.0–3.2 × 2.4 = 4.8–7.7 m; the brief says 1.5 → 5 m.
     - `CLOUD_AMOUNT 50` alive; the preset has 220.
     - The header comment ("about 20 m wide and 2.5 m tall") is false.
   - Do — lift cloud:
     - `size (2.0, 3.2)`, `grow 2.4`, `lifetime 3.5`;
     - speed 6–12 m/s, **damping 5.5** (stops at v²/2d ≈ 13 m, so ~20 m wide at 1 s);
     - gravity 0.4, #E6EAEE at α 0.6;
     - amount: start from the preset's 220 and cut only as far as the coverage targets allow,
       never below 90;
     - keep the flat fan and the half-sprite lift.
   - Verify:
     - My strip and top commands (Evidence), plus the same pair with `--demo-fx=core`, differenced
       the same way:
       - at ~1.0 s: ≥ 16 m wide and ≥ 2.2 m tall;
       - top coverage: ≥ 70 % within 6 m, ≥ 40 % within 10 m.
     - A sheet next to video 118.0 / 118.5 / 119.0 / 120.0: one continuous soft bank, with no
       single sprite readable from 30 m.

2. **The boost trail is a wisp** (brief "Rear launch"; photo 29).
   - `rvw3_boost_over_t3_0.jpg` (`B_29_28.jpg`): at most 1 m wide, faint, broken into two blobs at
     ~6 m and ~10 m. Photo 29: one dense white cone, 12–13 m long, 4–5 m wide at the far end.
   - Cause: `REAR_SIZE (0.6, 0.9)` × `REAR_GROW 2.5` = 1.5–2.25 m sprites, and 55 alive over 1.1 s
     (50 per second).
   - Do:
     - size `(0.8, 1.2)` × grow 3.5 → 2.8–4.2 m;
     - keep lifetime 1.1 s;
     - ≥ 110 alive, α 0.55, #E6EAEE.
   - Also fix the culling box: the trail reaches ~12.5 m, but `SmokeFX.setup()` sizes
     `visibility_aabb` to ±9.95 m around the emitter. Set
     `AABB(Vector3(-6, -3, -17), Vector3(12, 8, 18))` (emitter frame, −Z = jet), or the trail pops
     out when the car leaves the frame.
   - Verify — overhead with the cycle at t = 10.4 (`--demo-cam=overhead --times=10.4`, the car
     moving, 1 s into the boost), and the held `boost` overhead, both next to photo 29:
     - the trail starts at the nozzles;
     - it is 12–13 m long and 4–5 m wide at the far end;
     - it has no gaps.
3. **The vapour column reads as glass bottles plus gravel** (lead note 2; photos 27, 28;
   `I_crops.jpg`, `E_dist_top.jpg` d5).
   - Evidence:
     - **d5:** the JetColumn tubes are smooth, clear cones with flat-cut rims.
     - **Lift close-up:** the column starts as a flat-topped cylinder right under the core
       (α = 1 at v = 0).
     - **core_rear:** at x = 1400 the top silhouette of the beam jumps from L 36 to 179 within 15 px.
     - **Hover side:**
       - along the column L is 75–110, RGB (66,74,87)–(103,110,118): dull grey;
       - the brightness alternates every ~40 px (beads);
       - the column ends ~3 m below the car. At hover throttle 0.5 it is 5.0 × 0.5 = 2.5 m long,
         because `_apply_column()` scales the length with `_value`, so it never reaches the road.
         Photo 27 reaches it from ~6 m.
     - **Particles:**
       - 0.28–0.49 m chips: `VAPOUR_SIZE (0.08, 0.14)` × `VAPOUR_GROW 3.5`. The comment at
         `nozzle_fx.gd:49` claims 0.12 → 1.4 m.
       - 80 alive over 0.9 s = 89 per second; the brief asks for 300–600.
       - They pile up as gravel on the road (hop crop) and string out as pearls on the yaw jets
         (chase-roll crop).
   - Causes, in `shaders/jet_column.gdshader`:
     - the noise is evaluated per vertex on 12 × 8 vertices, at frequencies 9 / 19 around and
       7 / 5 along. There are fewer samples than noise cells, so the noise collapses into smooth
       facets;
     - `sin(UV.x * 37.0 + UV.y * 21.0 - TIME * 2.7)` adds barber-pole stripes;
     - `ambient_light_disabled` plus albedo × 0.45–1.0 makes it grey.
   - Do — column:
     - **Noise:** sample a seamless noise texture per fragment, for example a `NoiseTexture2D`
       (`seamless = true`, 256², FastNoiseLite fbm, 5 octaves) or a generated
       `textures/vapour_noise.png`.
       - Two layers, scrolling along the jet at 1.0× and 0.6× the jet speed.
       - UV.y scaled so one billow is 1.2–1.5 m long; UV.x × 2 around the tube.
       - α = smoothstep(0.25, 0.7, n1 · n2 · 2).
     - Delete the `sin()` stripes.
     - **Softness:**
       - α ×= smoothstep(0.0, 0.12, v) at the start;
       - α ×= smoothstep(0.05, 0.6, facing) at the silhouette;
       - α ×= (1 − v)^1.5 towards the end;
       - add a depth-texture soft fade (0.4 m, like proximity fade) where the column meets the
         road.
     - **Length:** lift column 6 m long. Scale the length by `lerpf(0.8, 1.0, _value)` and put the
       throttle into α instead: a choked nozzle keeps its exit speed and only the density changes.
       Lift vapour speed 35 m/s (dossier §6.3: 35² / 200 = 6.1 m, "reaches the ground from hover
       height").
     - **Brightness:** allow ambient light, albedo #F2F6FA, `alpha_max` 0.6–0.75 near the nozzle
       (dossier: body opacity 60–80 %).
   - Do — particles:
     - `VAPOUR_SIZE (0.12, 0.18)`, `VAPOUR_GROW 8` → 1.0–1.4 m (dossier 0.12 → 1.4 m);
     - ≥ 120 alive per lift or rear nozzle, 40 per yaw nozzle. Bigger sprites need far fewer
       particles for the same coverage.
     - If the per-vertex variant looks flat at 1–1.4 m, compare it with the lead's material in the
       d5 shot and report the cost of each.
   - Verify — d5 (`3.2,5.2,4.2 → 0,3.6,0`, fov 55, hover) and hover side, next to photos 27 / 28:
     - no hard edge anywhere: the largest luminance step across the silhouette or the column start
       is ≤ 40 levels over 15 px;
     - no individually readable sprite;
     - at hover (lift 0.5, h = 6) the column runs unbroken from the nozzle to the road and is
       0.4–0.8 m wide 3 m below the car;
     - brightness in hover side: L ≥ 170 within 1 m of the car and ≥ 120 at 3 m; along the axis,
       no swing larger than ±10 levels with a period under 60 px;
     - chase roll (t = 13.0): the yaw jet is one continuous ~1 m jet, not a string of dots.

4. **No shock diamonds in the rear close-up** (lead note 3; r2 MUST-FIX 6).
   - Evidence:
     - `rvw3_core_rear_t3_0.jpg` (1.5 m from the rear nozzles, all FX; `C_core.jpg` top left):
       - the max-luminance profile along the rear jets reads 239 / 225 / 224 / 240 / 233 / 215 /
         218 over the first 120 px, then a flat plateau of L 176–192 (std 12) to the frame edge —
         no bands;
       - the four cores bloom into one blob and the columns into one smooth beam.
     - With all FX on, the lift close-up (`rvw3_diam_fx`) shows 4 beads, but they read as dots
       rather than as a jet with bands.
     - The status's 1.15–1.52 was measured on a lift jet with the vapour hidden. The R1 profile r2
       asked for is missing.
   - Cause, `shaders/jet_core.gdshader:93-97`:
     - the peaks reach ≈ 3.7 HDR (0.28 × 11 + an axial 0.68), far above the glow threshold, so the
       blooms of neighbouring diamonds (~60 px apart at 1.5 m) merge;
     - the axial core term `core * energy * core_gain * fade` adds 0.68 HDR uniformly and fills
       the troughs.
   - Do:
     - Between the diamonds, 0.15–0.2 HDR. The first diamond ≈ 1.5 HDR in total — the brief's
       "emission ≈ 1.5, just enough bloom" (e.g. `bright = base * (1.0 + rings * 6.0)`).
     - Multiply the axial term by `rings`, so it lights the diamonds and not the gaps.
     - `ring_width` 0.025.
     - If the 4 throat discs (#9FD8FF, energy 3) still bloom over the first diamond, set
       `THROAT_ENERGY_MAX` to 2.
   - Verify, with ALL FX on:
     - `--demo-phase=core_rear --demo-cam=core_rear`: print the luminance profile along the R1
       axis. It must show 4 maxima, falling ≈ 1.0 / 0.7 / 0.45 / 0.25, each with peak/trough ≥ 1.4.
     - The same on the lift jet (`--demo-phase=core --demo-cam=nozzle`).
     - Redo `compare_core.jpg` next to the photo-18 crop (520,330)–(1060,650), like my `C_core.jpg`
       top row.
5. **The GPU budget is not met in the brief's case** (brief: ≤ 1.2 ms "with all 10 nozzles at full
   + 2 ground clouds" — that is the bench at h = 0.4).
   - My `bench8.gd` runs, at load 80–116:
     - h = 0.4 → `on=45.81 off=22.04 delta=23.77 per_view=2.971 ms`;
     - h = 1.6 → `per_view=1.137 ms`.
   - Your own h = 0.4 run gave 2.619 ms. The status calls the h = 1.6 run "the budget at the noise
     level" — the budget case is h = 0.4.
   - Do, after MUST-FIX 1–3 (do not shrink the look again):
     - Print a cost breakdown at h = 0.4, as per-view deltas: vapour only, + columns,
       + lift cloud, + rear cloud.
     - Levers:
       - fewer, larger cloud particles at lower α;
       - the per-vertex billboard variant for the clouds (big soft sprites lose little);
       - no overdraw next to the camera: in the bench the chase camera sits inside the static
         rear trail. A ShaderMaterial copy of the billboard whose `vertex()` shrinks particles to
         0 between 2.5 m and 1.0 m from the camera
         (`smoothstep(1.0, 2.5, length((MODELVIEW_MATRIX * vec4(0,0,0,1)).xyz))`).
     - If h = 0.4 is still > 1.2 ms after that, write a **Request** in the status with the
       breakdown table: the lead decides between a cheap SmokeFX variant in core and a budget
       change. Do not edit core.
   - Verify: 3 runs each at h = 0.4 and h = 1.6, each with its `uptime` load. The median at
     h = 0.4 is ≤ 1.2 ms/view, or the request is filed with the numbers.

6. **The demo stage still tiles and is not wet** (r2 SHOULD-FIX 5, untouched; ART §5 and §10 #4;
   the user's "贴图纹理什么都要细化").
   - Every capture shows the 4.17 m repeat of `asphalt_02` (`uv1_scale 48` on 200 m): parallel
     crack lines in `rvw3_boost_over`, `rvw3_strip_top` and `E_dist_top.jpg`.
   - There are no puddles and no variation in wetness. The brief asks for "a wet dark ground"; ART
     §5 asks for roughness 0.35 dry → 0.05 in puddles, plus macro variation.
   - Do: use the shared wet road on `Ground/Mesh`: `MaterialLibrary.lookup("SH_wet_asphalt")`
     (`game/shaders/road_wet.gdshader`: world-space UV, anti-tiling double sample, macro variation,
     puddles, ripples).
     - It reads vertex colour R (wheel polish) and G (gutter water). The BoxMesh has no vertex
       colours, so check the road is not flooded.
     - If it is, build the ground as a 200 × 200 m mesh with vertex colour (0, 0, 0, 1).
   - Verify — in the top cam (`0,32,0.1`) and the overhead:
     - no repeating pattern;
     - patchy puddles mirror the cyan and magenta neon;
     - the asphalt reads dark (#1A1B1F–#2A2A2A).

7. **Evidence, claims, leaks and comments** (r2 MUST-FIX 12 and SHOULD-FIX 6).
   - The status says "no `ERROR:` line". The test prints:
     - `ERROR: 1 resources still in use at exit`;
     - `ERROR: 1 RID allocations of type '…DummyShader…' were leaked at exit`;
     - `WARNING: 4 ObjectDB instances were leaked`.

     The core smoke test prints none of these, so they come from this unit. Likely causes: the
     `static var` resource caches in `lib/jet_mesh.gd`, `lib/jet_column.gd` and
     `lib/plume_assets.gd`, and `quit()` running in the same frame as `queue_free()`. The comment in
     `_finish()` ("Everything is freed") is false.
   - The status says "every capture … regenerated after the last code change". `ground_cloud.gd`
     changed at 12:24:17 (log step 16303: REAR_AMOUNT 40 → 55, REAR_SIZE). Every `r3_*` capture
     except `r3_boost_over` (12:25:08), and all seven `compare_*.jpg` (12:22:27–28), are older.
   - "Particles alive: 1190 per full car": the bench prints `particles_alive=905`
     (80 × 10 + 50 + 55).
   - "A low carpet ~15 m across" and "the 12 m launch trail of photo 29": see MUST-FIX 1 and 2.
   - False or stale comments:

     | where | what it says | what is true |
     |---|---|---|
     | `nozzle_fx.gd:35` | RING_POS in metres | the shader uses fractions of the cone length |
     | `nozzle_fx.gd:49` | 0.12 → 1.4 m | 0.28–0.49 m |
     | `lib/jet_column.gd:5-7` | 0.35 m over 3 m | 0.5 m over 5 m |
     | `shaders/jet_column.gdshader:9` | 16 × 12 segments | 12 × 8 |
     | `ground_cloud.gd:4-5` | 20 m × 2.5 m | see MUST-FIX 1 |
     | `ground_cloud.gd:13` | a car budget of 270 | stale |
     | `demo/thruster_demo.gd:45-46` | max_fps prevents "beading" | the vapour runs at `fixed_fps = 60` |
   - Do:
     - free everything and await 2 frames before `quit()`; drop or release the static caches;
     - fix every comment above;
     - regenerate every capture with one foreground script after the last code change, with a
       unit prefix: `fxth_r4_*` (`captures/r3_*` also holds other units' files);
     - quote command output for every claim.
   - Verify:
     - the test log has no `ERROR:` and no `WARNING:` line;
     - every status capture is newer than the newest file in `game/fx/thrusters/`.
   - Not counted against you: the capture runs print `ERROR: 1 shaders of type ParticlesShaderRD
     were never freed` at exit, but the lead's `core/fx/smoke_demo.tscn` prints the same line.
## SHOULD-FIX
1. **A demoted rig keeps its clouds emitting.** `thruster_rig.gd:226` returns before
   `update_clouds()` when `tier > TIER_FULL`. A rig demoted while its lift or rear cloud is on keeps
   emitting at the last hit point forever. Set both clouds to `emitting = false` when the tier
   drops.
2. **The lift-cloud raycast always points world-down** (`thruster_rig.gd:188`), even when the car
   is rolled or upside down (demo `P_ROLL`, real barrel rolls). The cloud then appears under the car
   while the jets fire sideways or up. Cast along the mean jet direction of the firing lift nozzles,
   and skip the cast when its y > −0.5.
3. **Dead code in `lib/plume_assets.gd`:** `colour_ramp()`, `size_curve()`, `VAPOUR_MID`,
   `VAPOUR_END`, `CLOUD_MID`, `CLOUD_END` and `CLOUD_FADE` have no callers. Delete them.
4. **Magic numbers are still inline**, although the status says they are named constants:
   - `nozzle_fx.gd`:
     - `* 0.08` (scroll speed), `* 0.95` (speed), `0.25` (emission gain), `0.006` (throat offset);
     - `radial_segments = 12`;
     - the repeated `_cfg.get(..., default)` defaults.
   - `landing_puff.gd`: `cull_mask = 1048575`, `PUFF_LIFETIME + 0.1`, `LIFT_SPEED * 0.8`,
     `upper_fade` / `lower_fade` 0.2.
5. **Diamond positions.** The brief puts the diamonds at 0.06 / 0.15 / 0.24 / 0.33 m from the exit.
   `RING_POS` is a fraction of the cone length, so on the 0.6 m lift jet they sit at
   0.04 / 0.11 / 0.18 / 0.25 m, and they slide inwards as the throttle shortens the cone. Pass the
   cone length to the shader and place the diamonds in metres.
6. **Demo:**
   - `--demo-phase=landing` emits `landed` on the first frame, so the status's
     `--times=3.75,4.0,4.4` shots contain no landing puff. Use the cycle (as in my F sheet), or
     re-emit when the held phase starts.
   - There is still no `--demo-fps` option (r2 MUST-FIX 5, verify): add it and show the plume at
     60 vs 120 fps.
   - Hover at 6.0 m puts the lift nozzles at 6.15 m, just outside `GROUND_REACH 6.0`, so the
     photo-27 shot never shows the ground contact. Add a hover shot at 5 m.
7. **Scratch inside the unit.** `game/fx/thrusters/tests/props_tmp.gd` was written there (log step
   13466) and deleted later. Scratch belongs in `tmp/fx_thrusters/`.
   - Step 16242 also ran `rm -f /tmp/*.log`, which deletes every `.log` in `/tmp`, including other
     processes' logs. Delete only the files you created, by name.

## Verified OK
- **Check:** `tools/godot.sh check --only=res://fx/thrusters/` → `CHECK 17 files, 0 failed,
  0 engine errors, 0 warnings`.
- **Tests:** 44 PASS, `TESTS PASS` (leaks aside, MUST-FIX 7).
- **Ownership** (log scan of all 243 round-3 tool calls, `log.jsonl` lines 10315–16341):
  - Write / Edit / python patches touched only `game/fx/thrusters/**` and `status/fx_thrusters.md`;
  - the shared atlas was only read; `game/core/fx/**` and `game/assets/textures/fx/**` are
    unchanged since the lead's commits;
  - no background runs;
  - `tmp/fx_thrusters/` and the `/tmp` logs were cleaned.
- **Old puff atlas:** `soft_puff*.png` is deleted, and `gen_textures.py` now makes only the ring
  decal.
- **The lead's lessons are kept:** `billboard_keep_scale`, a random frame, the preset turbulence
  (≤ 0.012), proximity fade 0.35, the half-sprite lift.
- **Colours and lights:**
  - no orange anywhere; core #EAF4FF; throat #9FD8FF ≤ energy 3;
  - 2 omni lights per car, #CFE3FF, range 2 m, energy 0.5–1;
  - the plumes are not pink (lead note 1).
- **Landing puff:**
  - a flat ring that bursts outwards; the decal follows the yaw;
  - gating: a crash gives nothing; clean / wobble above 4 m/s and a sky-lane exit give a puff;
  - lifetime 0.9 s, as in the gameplay dossier §5.5;
  - it reads soft and right at +0.15 s and +0.4 s.
- **Cars:** the stub fallback works (`rvw3_stub_t3_0.jpg`), and the real glb is used (lead note 5).
- **Integration:**
  - `fx/fx_director.gd` instances `thruster_system.tscn`, and the vehicle writes
    `telemetry.thrusters` (`vehicle/modules/car_readout.gd`).
  - In my in-game capture the player car neither moved nor hopped, so no plume showed. That is not
    counted against this unit; re-check once the vehicle unit confirms.

## Evidence
All commands were run from `/Users/minimax/m/skyrush`. Shots use `S=res://fx/thrusters/demo/thruster_demo.tscn`
and `C=0,2.2,30:0,2,0:50`.

**Tests**
- `tools/godot.sh test res://fx/thrusters/tests/test_thrusters.gd` → 44 `PASS`, `TESTS PASS`,
  followed by the 2 `ERROR:` lines and 1 `WARNING:` line quoted in MUST-FIX 7.

**Captures** — every run printed `CAPTURE errors=0`, at 59–68 fps:
- `tools/godot.sh shot --scene=$S`, followed by one of:
  - `--out=rvw3_hop_rear --demo-phase=hop --demo-cam=rear --times=3.0`
  - `--out=rvw3_hover_side --demo-phase=hover --demo-cam=side --times=3.0`
  - `--out=rvw3_boost_over --demo-phase=boost --demo-cam=overhead --times=3.0`
  - `--out=rvw3_core_rear --demo-phase=core_rear --demo-cam=core_rear --times=3.0`
  - `--out=rvw3_diam_fx --demo-phase=core --demo-cam=nozzle --times=3.0`
    (`rvw3_diam_core`: the same plus `--demo-fx=core`)
  - `--out=rvw3_strip --demo-phase=hop --warm=30 --cams="s10:$C;s15:$C;s20:$C;s25:$C;top:0,32,0.1:0,0,0:50"`
    → t ≈ 1.0 / 1.5 / 2.0 / 2.5 s. `rvw3_nofx_*` is the same plus `--demo-fx=core`, for the
    particle-only difference (threshold +12/255).
  - `--out=rvw3_dist --demo-phase=hover --warm=180 --cams="d5:3.2,5.2,4.2:0,3.6,0:55;d20:14,10,20:0,3.6,0:55;d100:68,22,72:0,3,0:55"`
  - `--out=rvw3_land --demo-cam=rear --warm=1 --times=3.75,4.0,4.4` (the cycle; touchdown at 3.6)
  - `--out=rvw3_stub --demo-car=stub --demo-phase=hover --demo-cam=side --times=3.0`
  - `--out=rvw3_chase --warm=1 --times=2.6,10.4,13.0`
- In game: `tools/godot.sh shot --out=rvw3_game --env-only --pulse=hop@2.0,nitro@4.0 --press=accelerate --times=2.25,2.6,3.3,4.6`
  → the car is static in all 4 frames.

**Bench** — `python3 tools/slots.py heavy 4 -- /opt/homebrew/bin/godot --path game --windowed --resolution 1920x1080 --always-on-top -s res://fx/thrusters/demo/bench8.gd -- --h=<h>`
- h = 0.4 → `on=45.81 off=22.04 delta=23.77 per_view=2.971 ms`, `particles_alive=905`, load 116 → 104.
- h = 1.6 → `on=30.96 off=21.86 delta=9.10 per_view=1.137 ms`, load 104 → 80.

**Measurements** (numpy on the JPEGs)
- core_rear profile: rows 380–480, column max over x = 860–1600.
- Column brightness in hover side: x ≈ 662, rows 280–540.
- Coverage on the top cam at 30.2 px/m; car box excluded.

**Sheets** (`captures/review/fx_thrusters/r3/`)
- `A_18_27`: photo 18 | hop rear; photo 27 | hover side.
- `B_29_28`: photo 29 | boost overhead; photo 28 | chase hop.
- `C_core`: rear core 1.5 m | photo-18 crop; lift close-up, all FX | core only.
- `D_strip`: strip vs video 118.0–120.0.
- `E_dist_top`: d5 / d20 / d100 / top.
- `F_land_chase`: landing +0.15 / +0.4 / +0.8 s, video 140, chase boost and roll.
- `G_lead_smoke7`: the lead's look-dev target.
- `H_game`: the in-game shots.
- `I_crops`: jet/road contact, the column tubes, the column start, the yaw vapour.

**ART §10 checklist**

| # | check | result |
|---|---|---|
| 1 | value | **FAIL**: the plumes are dim grey, not the brightest accent (ART §2.4) |
| 2 | palette | OK: no pink or orange |
| 3 | detail at 5 / 20 / 100 m | **FAIL**: glass tubes and chips at 5 m; barely visible at 20 m; invisible at 100 m |
| 4 | tiling | **FAIL**: the demo floor |
| 5 | scale | **FAIL**: cloud 1.1–1.4 m tall instead of 2.5; trail ≤ 1 m wide instead of 4–5 |
| 6 | emissives | **FAIL**: the rear cores bloom into one slab |
| 8 | edges | **FAIL**: hard column rims |
| 9 | floating | particle chips hang in the air beside the car (hop crop) |
| 10 | store screenshot | no |
