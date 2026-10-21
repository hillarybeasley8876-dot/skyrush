# fx_thrusters review round 4 — VERDICT: FAIL

Last round. My captures come from the current code (16:00–16:20, sources last changed 15:39):
`captures/rv4fx_*.jpg`. Sheets: `captures/review/fx_thrusters/r4/` — `A_18_27`, `B_29_28`,
`C_core`, `D_strip`, `E_dist_land`, `H_corecrop`, `I_worker_core`, `J_crops`. The probes I ran are
kept next to them (`curve_render_probe.gd`, `cloud_measure.py`).

## Scores (0-10): function, visual, code
- **function 5**
  - Works and is tested: 44 PASS, the check is clean, attach/detach, tiers, landing gating, the
    stub fallback and the real glb.
  - The GPU budget is missed by 5×. I measured **6.3 ms/view** at h = 0.4; round 3 was 2.97 ms.
  - The ground clouds ignore `Settings.feature("particles")`.
  - The shared growth curve was removed on a diagnosis that is false (MUST-FIX 1).
- **visual 3** — Better than r3:
  - the hop/landing bank is big and soft (`A_18_27` top right, `E_dist_land` bottom left);
  - the lift columns reach the road;
  - the lift-jet diamonds can be measured;
  - the floor is wet.

  But it still does not read as photos 27 / 28 / 29:
  - the hover cloud is popcorn: 57 separate puffs, readable from 30 m (`D_strip` top view);
  - the columns are straight-edged glass tubes (`J_crops`);
  - the boost trail is a 1.4–3 m string of puffs;
  - the rear close-up shows 4 LED-like discs and one smooth beam, with no diamonds;
  - at 100 m the plume is a sprinkle of white dots.
- **code 4.5**
  - Good: typed, files ≤ 387 lines, a clean module split, ownership respected.
  - Against it:
    - a false "Measured" claim written into code and filed to the lead (MUST-FIX 1);
    - a mislabelled evidence sheet (MUST-FIX 8);
    - new stale comments, dead parameters, a duplicated loop, and a vertex pinch that never lands
      on a vertex;
    - scratch probes written inside `game/fx/thrusters/tests/` again.

## Round-3 MUST-FIX and lead notes, now
| item | now |
|---|---|
| r3-1 ground cloud | numbers OK at ~1 s (22.0 m wide, 3.0 m tall); look **FAIL** (popcorn, keeps flying to 30–36 m) → MUST-FIX 2 |
| r3-2 boost trail | length ~13 m OK, AABB OK; width/look **FAIL** → MUST-FIX 4 |
| r3-3 column | reaches the road, fbm texture, no `sin()` OK; glass tube with hard edges **FAIL** → MUST-FIX 3 |
| r3-4 diamonds | lift jet OK (4 maxima); rear close-up **FAIL** → MUST-FIX 5 |
| r3-5 budget | **FAIL** (6.3 ms/view), unit-local lever not built → MUST-FIX 6 |
| r3-6 wet floor | OK |
| r3-7 evidence | leaks OK; claims/comments **FAIL** → MUST-FIX 8 |
| lead 1 colour | OK — white/blue-white, neon only tints nearby puffs |
| lead 2 vapour | **FAIL** — puffs readable at 2–6 m (d5), per-particle α 0.65 / 0.7 / 0.5 (`plume_assets.gd:34-38`) vs ≤ 0.35 |
| lead 3 core close-up | **FAIL** — `compare_core.jpg` itself shows no diamonds on the rear jets |
| lead 4 cloud strip | **FAIL** — the strip sheet is mislabelled (MUST-FIX 8), the look fails (MUST-FIX 2) |
| lead 5 real glb | OK |
| LEAD-SMOKE | **FAIL** — the preset growth was deleted (MUST-FIX 1) |

## MUST-FIX
1. **The growth curve was removed on a false diagnosis** (LEAD-SMOKE; dossier §6.3 "scale curve
   0.12 m → 1.4 m"; brief layer 3 "size 1.5 → 5 m").
   - `lib/plume_assets.gd:124-139` `uncap_growth()` sets `scale_curve = null`. Its comment claims
     "a CurveTexture stores its points normalised… Measured". It is called from `nozzle_fx.gd:187`,
     `ground_cloud.gd:84` and `landing_puff.gd:80`, so **no sprite grows**: the vapour is a constant
     0.4–0.6 m, the cloud 2.4–3.6 m, the trail 1.2–1.8 m.
   - The worker's own probe never read the texture: log line 21299, `Cannot call method
     'get_width' on a null value` (headless).
   - My probes say the claim is false:
     - **Texture:** a curve built like `SmokeFX._grow_curve(2.4)` reads back with RenderingServer
       as **1.0 / 1.84 / 1.985 / 2.40** (px 0/64/128/255, RGBF).
     - **Render:** `curve_render_probe.gd` draws one particle with a constant curve of 2.0
       (`max_value 2.0`) next to one without a curve. Result: `curve 2.0 sprite: 5625 px -> side
       2.0 m`, `no curve sprite : 1444 px -> side 1.01 m`. The curve value reaches the shader raw.
   - Do:
     - delete `uncap_growth()` and its 3 calls;
     - withdraw status Request 1;
     - re-tune the sizes with growth on:
       - vapour `(0.12, 0.18)` × 8 → 1.0–1.4 m;
       - lift cloud `(1.5, 2.2)` × 2.4 → 3.6–5.3 m;
       - rear trail `(0.8, 1.2)` × 3.5 → 2.8–4.2 m;
       - landing puff unchanged × 2.5.
   - Verify — a d5 shot and a top shot show the sprites growing with distance from the nozzle /
     impact. Add a test that asserts `scale_curve != null` on all four emitters.
2. **The ground cloud is popcorn and never stops** (lead notes 2 and 4; photo 18; video
   118.5–120.0, `D_strip.jpg`).
   - Measured (FX minus `--demo-fx=core`, threshold +12):
     - strip cam `0,2.2,30`: 11.7 m wide at ~0.5 s, **22.0 m / 3.0 m tall at ~1.0 s**, 38 m at
       1.5 s, ≥ 48 m (frame edge) at 2.0 s;
     - top cam at ~2.25 s: coverage 74 / 73 / 54 % within 3 / 6 / 10 m, but 28–32 % out to
       18 m, and **57 separate blobs** in the 8–20 m annulus.
   - Video 119–120: one dome-shaped billowing mass, ~20 m wide and 4–5 m tall, that stays.
   - Causes (`ground_cloud.gd`):
     - `RADIAL 8–16 m/s` with `CLOUD_DAMPING 0.8`. Godot damping is a *linear* deceleration, so a
       16 m/s puff only loses 0.8 m/s per second and is still flying after its 3.5 s life;
     - no upward velocity (brief: up 1–3 m/s);
     - α 0.7 per puff, so every sprite edge reads;
     - no growth (MUST-FIX 1).
   - Do:
     - radial 5–11 m/s and damping 4.5 (stops at v²/2d = 2.8–13.4 m);
     - emit like `landing_puff.gd:91-104`: ring emission, direction UP at 1–3 m/s,
       `radial_velocity` 5–11;
     - `CLOUD_BIRTH` α 0.3, with 3–4 overlapping layers from the grown sprites;
     - keep the half-sprite lift.
   - Verify:
     - the same strip/top pair: ≥ 18 m wide and ≥ 2.5 m tall at 1.0 s, **≤ 26 m wide at 2.0 s**;
     - top coverage ≥ 70 % within 6 m and **≤ 12 separate blobs** in the 8–20 m annulus;
     - a sheet next to video 118.5 / 119.0 / 120.0.
3. **The vapour columns are glass tubes with hard edges** (lead note 2; photos 27, 28; `J_crops.jpg`,
   `C_core.jpg` d5).
   - Hover side and d5: thin, straight, translucent cones. The chase roll shows the yaw columns as
     two straight "glass planks".
   - `rv4fx_dist_d5.jpg` row 700: L drops from 122 to 47 between x = 1036 and 1051 (15 px). Row 800
     drops 60 levels. The r3 limit was ≤ 40.
   - Causes:
     - `lib/jet_column.gd` has only `RADIAL_SEGMENTS 12`. At the silhouette vertex the
       interpolated facing is still up to sin 15° = 0.26, so `smoothstep(0.0, 0.35, facing)`
       (`jet_column.gdshader:64`) leaves **~84 % alpha at the geometric edge**;
     - the noise only scales alpha by `0.7 + 0.3 * body`, so the tube stays smooth;
     - `COLUMN_ALPHA 1.0` (r3 asked 0.6–0.75);
     - `billow_m` is never set, so it stays at the 2.5 m default (r3 asked 1.2–1.5 m).
   - Do:
     - 32 radial × 24 rings;
     - `a = smoothstep(0.08, 0.6, facing) * mix(0.25, 1.0, body) * alpha_max`, with `alpha_max`
       0.75 and `billow_m` 1.3;
     - displace the wall radially in `vertex()` with the same scrolling noise
       (`textureLod(noise_tex, uv1, 0.0)`, ±30 % of the radius), so the silhouette billows;
     - a radius profile `mix(throat, 1.0, sqrt(v))`, lift tip radius 0.45 m: 0.4–0.8 m wide at
       3–5 m (dossier §6.1), ~1 m at the road (photo 27).
   - Verify:
     - d5 and hover side: no 15-px step > 40 levels across any column edge;
     - a d5 crop next to a crop of photo 27 / 28: soft, turbulent, dense column, no straight edge;
     - chase t = 13.0: the yaw jet is a soft ~1 m jet.
4. **The boost trail is a string of puffs, half the width** (photo 29; r3 MUST-FIX 2).
   - `rv4fx_cyc_over_t10_4.jpg` (cycle, 1 s into the boost): ~13 m long (OK), but 53–113 px wide
     at ~38 px/m, i.e. **1.4–3.0 m, not widening**, built from discrete blobs (`B_29_28.jpg`).
   - The held boost (`rv4fx_boost_t3_0.jpg`) breaks into blobs at 6–10 m.
   - Photo 29: one dense white cone, 4–5 m wide at the far end, no gaps.
   - The status claims "one continuous cone" (MUST-FIX 2 of the status) — false.
   - Cause: no growth (MUST-FIX 1) plus α 0.5 sprites of a constant 1.2–1.8 m.
   - Do: growth on (`REAR_SIZE (0.8, 1.2)` × 3.5); `TRAIL_BIRTH` α 0.35 with double the overlap.
   - Verify — the same two shots next to photo 29:
     - the cone starts at the nozzles;
     - it is 4–5 m wide at 12 m;
     - no gap darker than 50 % of the trail's mean along its axis.
5. **No shock diamonds on the rear jets; the nozzles read as LED lamps** (lead note 3; brief
   "shock diamonds visible up close").
   - `rv4fx_corerear_t3_0.jpg` (1.5 m, all FX; `H_corecrop.jpg`):
     - the four nozzles are glowing pale discs;
     - the jets merge into one smooth beam that brightens to a flat L 199–211 plateau from
       x ≈ 1300 to the frame edge;
     - no banding.
   - The worker's own `compare_core.jpg` shows the same (`I_worker_core.jpg`). The status only
     measured the lift jet; the R1 profile r3 asked for is missing.
   - Causes:
     - the `ThroatGlow` disc (`nozzle_fx.gd:43-46`, 0.032 m, energy 1.2) faces the camera;
     - the rear OmniLight sits at the mean nozzle position, inside the bezels
       (`thruster_rig.gd:185`), and lights the cups;
     - the four 5 m rear columns, 0.24 m apart with a 0.32 m tip radius, overlap into one slab.
   - Do:
     - recess the disc 0.03 m and shrink it to 0.02 m radius, so it reads as a lit hole (photo 18:
       dark gold throats);
     - push the rear light 0.4 m out along the mean jet;
     - rear column tip radius 0.2 m, starting after the 4th diamond (0.4 m) at α ≤ 0.3 near its
       start;
     - pinch/diamonds only if they can be seen (see SHOULD-FIX 5).
   - Verify — the R1 profile in `core_rear`, all FX on: 4 maxima, peak/trough ≥ 1.4, falling
     towards 1.0 / 0.7 / 0.45 / 0.25. Mine on the lift jet (x = 805): peaks 173 / 172 / 151 / 109,
     troughs 93 / 80 / 67, i.e. **1.0 / 0.99 / 0.87 / 0.63**, a falloff that is too flat. Redo
     `compare_core.jpg`.
6. **GPU budget: 6.3 ms/view against 1.2** (brief; r3 MUST-FIX 5).
   - My bench, h = 0.4:
     - `on=74.60 off=24.06 per_view=6.318 ms`, then `on=76.53 off=26.22 per_view=6.289 ms`;
     - load 14.7–16.0, `particles_alive=1510`.
   - h = 1.6: `per_view=2.921 ms`.
   - Breakdown (cumulative, load 21.7): vapour alone **6.31 ms**; the rest is inside the noise
     (6.8–8.8).
   - Why it is so high:
     - the rear vapour (30 m/s, damping 100) stops 30²/200 = 4.5 m behind the nozzles, i.e.
       6.6 m behind the car centre — **exactly where the chase camera sits**;
     - sprites at the lens fill the screen;
     - `DISTANCE_FADE_PIXEL_ALPHA` (`plume_assets.gd:101`) hides them but still rasterises them.
   - The status calls the near-camera shrink a "cheap variant in core". It is not a core change:
     the billboards are this unit's own `StandardMaterial3D`s.
   - Do:
     - replace `_make_billboard()` with a unit-owned `shaders/vapour_billboard.gdshader`:
       particle billboard, atlas frame from `INSTANCE_CUSTOM`, and
       `VERTEX *= smoothstep(1.0, 2.5, length((MODELVIEW_MATRIX * vec4(0,0,0,1)).xyz))`;
     - stop the rear vapour short of the camera (rear damping 150 → 3 m);
     - then re-bench: 3 runs at h = 0.4 and h = 1.6, with load.
   - If the median at h = 0.4 is still > 1.2 ms, refile Request 2 with the new numbers.
     **Lead decision needed:** on this machine one full screen of alpha sprites costs ~1.2 ms per
     view, so a cloud that matches video 119 cannot fit 1.2 ms. My recommendation is 3.0 ms/view
     at h = 0.4, once the shrink is in.
7. **The quality preset does not scale the clouds** (brief: "respect `Settings.feature("particles")`
   (scale emission amounts)").
   - `ThrusterRig.set_particle_quality()` (`thruster_rig.gd:269-272`) only scales the nozzles. The
     lift cloud (280), the rear trail (110) and the landing puff (64) stay at full count on `low`
     (0.4) — and they are the biggest sprites.
   - `tests/test_thrusters.gd:289-291` cements this: the cloud amounts are added unscaled.
   - Do: give `GroundCloud` and `LandingPuff` a `set_particle_quality(q)` (`amount =
     maxi(1, round(base * q))`), call it from the rig, and fix the test so it expects scaled clouds.
   - Verify: the test passes with `--quality=low`, and `particle_capacity()` drops by 60 % for the
     clouds as well.
8. **False evidence, false claims, stale comments** (r3 MUST-FIX 7; lead note 4).
   - `demo/make_comparisons.py:52-55` builds `compare_cloud_strip.jpg` from:
     - `fxth_r4_strip_s10.jpg` (the ~1.0 s frame), labelled **"0.0 s"** and used again as
       **"1.0 s"**;
     - `s15` (1.5 s), labelled **"0.5 s"**;
     - no 2.0 s frame at all.

     The lead's 4-frame strip (0 / 0.5 / 1.0 / 2.0 s) therefore does not exist. My
     `--warm=15` run gives real frames every 0.25 s (`D_strip.jpg`).
   - False or stale:

     | where | says | true |
     |---|---|---|
     | `plume_assets.gd:124-134` | CurveTexture normalises, "Measured" | false (MUST-FIX 1) |
     | status Request 1 | the shared size curve never grows | false; withdraw it |
     | status MUST-FIX 2 | `REAR_SIZE` 0.9–1.3 m, "one continuous cone" | code 1.2–1.8 m; a string of puffs |
     | `ground_cloud.gd:4-6` | 14 m × 2.2 m at 1 s, 23 m at 1.5 s | measured 22 m × 3.0 m, 38 m |
     | `ground_cloud.gd:28-31` | "damping 1.2 … 20 m wide"; "5.5 only travels 3.4 m" | the constant is 0.8; linear damping gives v²/2d = 13 m for 12 m/s at 5.5 |
     | `ground_cloud.gd:79`, `:108-109` | "dossier 6–12 m/s", "only the burst speed is retuned" | 8–16 m/s; damping, size, lifetime and α are retuned too |
     | `nozzle_fx.gd:64-66` | 1.4 m sprites "cost 30 ms per view" | not reproduced; no measurement with growth on |
   - Do:
     - fix the strip script;
     - capture a true 0 / 0.5 / 1.0 / 2.0 s strip (`--warm=15`, 8 identical cams = 0.25 s steps);
     - fix every row above;
     - quote command output for every number in the status.
   - Verify: every label in every `compare_*.jpg` names the file and time it really shows.

## SHOULD-FIX
1. **Duplicated logic:**
   - `thruster_rig.gd:235-253` `_update_rear_exit()` repeats `_group_jet()` (`:307-322`). Use
     `_group_jet(NozzleTable.REAR, NOZZLE_AHEAD)`.
   - `TIER_*` is defined twice (`thruster_system.gd:16-18`, `thruster_rig.gd:25-27`). Keep one.
2. **Magic numbers:**
   - `thruster_rig.gd:241` and `:313`: `0.05`;
   - `thruster_rig.gd:341`: `Vector3(0.0, 0.25, 0.0)`;
   - `nozzle_fx.gd:274-275`: the fallbacks `3.0` / `0.35`;
   - shader literals (`jet_core` `0.10`, `0.03`, `0.72`, `0.56`, `9.0`, `46.0`, `10.0`, `6.0`;
     `jet_column` `0.7`/`0.3`, `0.75`/`0.25`, `1.7`, `0.37`) → named uniforms or consts.
3. **Dead parameters and test-only code:**
   - `uncap_growth(_grow)`;
   - `update_clouds(_delta, …, _car_basis)`;
   - the `*_GROW` constants, which now only size the AABB;
   - `NozzleTable.is_down_firing()`, used only by the tests.
4. **Tiers:** the brief says "others get core + reduced vapour". `thruster_system.gd:101-107` gives
   the 4th and later cars core only. Follow the brief or get the lead's OK in the status.
5. **The diamond pinch is dead:** `jet_core.gdshader:71-72` pinches per vertex, but
   `lib/jet_mesh.gd` has `RING_COUNT 6`. The vertex rows are 0.15 m apart on the 0.9 m cone and
   0.10 m on the 0.6 m cone, against `ring_width` 0.025, so almost no diamond lands on a row. This
   is the same per-vertex sampling error as the r3 column. Use ≥ 36 rings, or drop the pinch.
6. **Vapour against the brief:**
   - 130 / 0.9 s = 144 per second per nozzle (brief 300–600 per second);
   - the colour never moves to #D8DEE6.

   Revisit after MUST-FIX 1 / 6.
7. **`demo/bench8.gd`:**
   - the `throat` layer has no branch (`ThroatGlow` is never collected), so its breakdown row is
     meaningless;
   - `name.begins_with("Light")` also catches the car's `LightBar_Rear` / `Light_*` nodes;
   - my `--breakdown=1` run printed GDScript backtraces at `bench8.gd:106/108`.
8. **Scratch, again** (r3 SHOULD-FIX 7):
   - `probe_leak.gd`, `nozzle_fx_probe.gd`, `probe_props.gd` and `probe_curve.gd` were written
     into `game/fx/thrusters/tests/` (log lines 17699–21437) and deleted later;
   - `/tmp/jet_column_backup.gdshader` (log 19033) is still on disk.

   Scratch belongs in `tmp/fx_thrusters/`, never in `/tmp`.
9. **60 vs 120 fps:** `--demo-fps` was added, but no capture shows the plume at both rates (r3
   SHOULD-FIX 6).
10. **Demo stage:** the side and strip views show the ground's hard edge against a flat navy
    backdrop. Use a ≥ 400 m floor or distance fog (lead note 1: a dark studio).

## Verified OK
- **Check:** `CHECK 17 files, 0 failed, 0 engine errors, 0 warnings`.
- **Tests:** 44 `PASS`, `TESTS PASS`. The only other line is
  `ERROR: 1 RID allocations of type '…DummyShader…' were leaked at exit`. `tools/godot.sh test
  res://fx/tests/test_fx.gd` (another unit) prints the identical line, so it is not counted.
- **Ownership** (log scan of round 4, `log.jsonl` lines 16340–22243): the 21 Write/Edit calls and
  every python patch touched only `game/fx/thrusters/**` and `status/fx_thrusters.md`. Core is
  untouched and there were no background runs.
- **Colour:** no orange, fire or sparks. The vapour is white / blue-white; the neon tints only the
  puffs near the tubes (lead note 1).
- **Cars:** the real glb is used (lead note 5). The stub fallback works (`rv4fx_stub_t3_0.jpg`):
  10 plumes at the dossier positions.
- **Landing puff:** a soft fog burst at +0.15 s that clears by +0.8 s (`E_dist_land.jpg`); the
  gating is tested.
- **Lift-jet diamonds:** at the close-up, 4 maxima with peak/trough 1.86 / 2.15 / 2.25 (MUST-FIX 5
  covers the falloff and the rear jets).
- **Ground cloud at ~1.0 s:** 22.0 m wide, 3.0–3.1 m tall beside the car — the brief's size, until
  it over-spreads (MUST-FIX 2).
- **Demo floor:** `SH_wet_asphalt`, dark, with puddles mirroring the neon.
- **r3 SHOULD-FIX 1 / 2 / 5:** a demoted rig stops its clouds; the lift raycast follows the jet;
  the diamonds are placed in metres.
- **Integration:** the vehicle writes `StringName` keys and the rig reads `String` keys. My probe
  shows the lookup works in 4.7 (`get(String) on StringName key -> 0.75`).

## Evidence
All commands were run from `/Users/minimax/m/skyrush`, with `S=res://fx/thrusters/demo/thruster_demo.tscn`,
`C=0,2.2,30:0,2,0:50` and `T=0,32,0.1:0,0,0:50`. Every shot printed `CAPTURE errors=0` at 60–83 fps.

**Check and tests**
- `tools/godot.sh check --only=res://fx/thrusters/` → `CHECK 17 files, 0 failed, 0 engine errors,
  0 warnings`.
- `tools/godot.sh test res://fx/thrusters/tests/test_thrusters.gd` → 44 PASS, `TESTS PASS`, plus
  the DummyShader line.

**Shots** — `tools/godot.sh shot --scene=$S`, followed by one of:
- `--out=rv4fx_hov5 --demo-phase=hover5 --demo-cam=side --times=3.0` (also `hop/rear`,
  `core_rear/core_rear`, `core/nozzle`, `boost/overhead` → `rv4fx_hop`, `_corerear`, `_lift`,
  `_boost`)
- `--out=rv4fx_cyc_over --demo-cam=overhead --warm=1 --times=10.4` (the cycle, 1 s into the boost)
- `--out=rv4fx_strip --demo-phase=hop --warm=15 --cams="s05:$C;s075:$C;s10:$C;s125:$C;s15:$C;s175:$C;s20:$C;top:$T"`
  → t ≈ 0.5 / 0.75 / … / 2.0 s, top at 2.25 s
- `--out=rv4fx_nofx --demo-phase=hop --demo-fx=core --warm=30 --cams="s:$C;top:$T"` — the
  particle-free baseline
- `--out=rv4fx_dist --demo-phase=hover5 --warm=180 --cams="d5:3.2,5.2,4.2:0,3.6,0:55;d20:14,10,20:0,3.6,0:55;d100:68,22,72:0,3,0:55"`
- `--out=rv4fx_land --demo-cam=rear --warm=1 --times=3.75,4.0,4.4`
- `--out=rv4fx_stub --demo-car=stub --demo-phase=hover5 --demo-cam=side --times=3.0`
- `--out=rv4fx_chase --warm=1 --times=2.6,10.4,13.0`

**Bench** — `python3 tools/slots.py heavy 4 -- /opt/homebrew/bin/godot --path game --windowed --resolution 1920x1080 --always-on-top -s res://fx/thrusters/demo/bench8.gd -- --h=<h> [--breakdown=1]`
- h = 0.4 → `per_view=6.318`, then `6.289` ms.
- h = 1.6 → `2.921` ms.
- breakdown at h = 0.4 → vapour `6.314`, +columns `7.678`, +core `6.981`, +throat `8.816`,
  +lift_cloud `7.643`, +rear_cloud `6.813`, +lights `7.662`.

**Probes**
- `curve_render_probe.gd`, run windowed (`slots.py heavy 4 --timeout 90 -- godot --path game --windowed
  --resolution 400x300 -s <abs path>`) → `curve 2.0 sprite: 5625 px -> side 2.0 m`,
  `no curve sprite : 1444 px -> side 1.01 m`.
- The texture readback (`RenderingServer.texture_2d_get`) → 1.0 / 1.8394 / 1.9852 / 2.3999.

**Measurements**
- `cloud_measure.py` (numpy, FX minus no-FX > 12): widths 11.7 / 16.4 / 22.0 / 28.9 / 38.1 /
  45.1 / 47.9 m at 0.5–2.0 s; cloud tops 2.7–2.9 / 3.0–3.1 / 3.2–3.6 / 4.1–5.4 m at 0.5 / 1.0 /
  1.5 / 2.0 s; top coverage 74.2 / 72.9 / 54.0 %.
- The rings and blobs are measured on the same pair.
- Lift diamonds: `rv4fx_lift_t3_0.jpg`, x = 805, rows 230–400. Rear: `rv4fx_corerear_t3_0.jpg`,
  max over rows 380–500.

**In game** — `tools/godot.sh drive --timeline=<abs>/tl_fx.json --shots=3.4,3.8,7.4,8.2 --out=rv4fx_game2 --skip-menu`
→ `speed=1681` (km/h) at t = 2.5, and repeated `SCRIPT ERROR … Array[CarSurface]` from other
units. The plumes cannot be judged in game right now; this is not counted against this unit.
Without `--skip-menu` the drive never leaves the title screen (`G_game.jpg`).

## ART §10 checklist
| # | check | result |
|---|---|---|
| 1 | value | **FAIL**: the bank is the brightest mass in the hop shots, but the jets themselves are faint glass lines |
| 2 | palette | OK |
| 3 | detail at 5 / 20 / 100 m | **FAIL**: glass tubes and readable puffs at 5 m; a popcorn field at 20 m; white dots at 100 m |
| 4 | tiling | OK: the wet floor (faint crack lines remain) |
| 5 | scale | 1 s cloud OK; 2 s cloud 2× too wide; trail half as wide; column borderline thin |
| 6 | emissives | **FAIL**: the rear throats read as 4 lamps; the rear columns merge into a slab |
| 8 | edges | **FAIL**: hard column silhouettes (75 levels over 15 px) |
| 9 | floating | the hover-cloud puffs hang 3–5 m up in the chase view (`rv4fx_chase_t10_4`) |
| 10 | store screenshot | the hop rear / landing frame is close; hover, boost and close-ups: no |
