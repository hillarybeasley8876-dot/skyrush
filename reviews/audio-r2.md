# audio review round 2 — VERDICT: FAIL

Reviewer: lead's art director (Opus). Standing order "贴图纹理什么都要细化" — for audio: every sound is
layered and physically right, the mix is balanced, nothing clicks, drones, spams or errors.
Everything below was measured or reproduced. Scratch: `tmp/review/audio/` (probes `probe_synth.gd`,
`probe_runtime.gd`, `probe_pause.gd`, analysers `an_synth.py`, `an_assets.py`), captures:
`captures/review/audio/r2/`.

The lead note **A-INT1 is NOT satisfied** (the worker never opened `reviews/audio-lead.md`: 0 mentions
in jobs/audio/log.jsonl). Round 1 fixes that landed well: the car is audible, the gameplay capture is
real, the CPU is in budget, the voice queue/radio FX/loudness and the asset QA table are good.

## Scores (0-10)
- **function: 4** — the lead's integration bug is untouched (≈8,000 audio engine errors in a 23 s
  sandbox drive), traffic hums leak on despawn, the battery beep fires every frame, one grinding car
  fires 121 impacts/s, the car keeps droning while the game is paused, 12 of 35 demo SFX steps are
  silent, horns/scrape are never played, heat never reaches the sirens.
- **visual/feel (sound quality): 4** — the mix balance is now right (whine is the dominant tonal line,
  I −14.9 LUFS, TP −1.7 dBTP), but the hero voices regressed: thruster envelope 5× too fast, hiss
  band stops at ~4.5 kHz (the "3.3 kHz centroid" comes from imaging artefacts), the chuff is a low
  rumble, the motor whine is an integer-harmonic buzz with DC, the fan whistle sits at −9.5 dB
  instead of −18 dB under the motor, and every music loop has a 25–30 dB hole in its breakdown.
- **code: 4** — typed, split, ≤ 400 lines; but a typed-array misuse and cast-before-validity bugs,
  a test function and a check that never run, 86 bare literals in logic, 7 dead tuning constants,
  duplicated LOOP_IDS and stop logic, and false status claims (see SHOULD-FIX "status accuracy").

## MUST-FIX

1. **Lead note A-INT1 (mandatory): the audio unit floods the engine log in every gameplay session.**
   - 60 s main.tscn run (my timeline `tmp/review/audio/smoke60.json`; it reached game time 12.6 s
     before a renderer crash in another unit): **773×** `oneshot_pool.gd:131` "Attempted to use 'has'
     an object of type 'AudioStreamPlayer' into a TypedArray, which does not inherit from
     'AudioStreamPlayer3D'", **252×** `oneshot_pool.gd:105` "Invalid access to property or key
     'playing' on a base object of type 'Nil'", **3×** "Signal 'tree_exiting' is already connected to
     … world_emitters.gd::_on_target_exiting".
   - Sandbox movie (`--stub=world`, 22 s): **7,046×** the `has` error, **992×** the Nil error,
     **11×** "Error calling from signal 'tree_exiting' to callable … _on_target_exiting: Cannot convert
     argument 1 from Object to Object", 2× "already connected".
   - Causes: `_prune()` casts every node `as AudioStreamPlayer` (null for a 3D player);
     `_steal_in()` calls `pool.has(node)` on a typed `Array[AudioStreamPlayer3D]` with 2D nodes (and
     vice versa); `attach_loop()` connects `target.tree_exiting` (world_emitters.gd:45) and nothing ever
     disconnects it, so a dropped emitter (`queue_free` at :147) is later passed as a freed argument, and
     a car that re-enters range gets a second connection; `e["target"] as Node3D` /
     `e["player"] as AudioStreamPlayer3D` run **before** `is_instance_valid()` (:63, :82–83, :142–144,
     :175–176) — the pattern behind the lead's "Trying to cast a freed object" at :83 (not hit in my
     two runs, but reachable: any caller that frees a handle returned by `attach_loop()` leaves a freed
     player in `_emitters`, cast on every physics frame).
   - Do: store `"is_3d": bool` in every pool entry; `_prune()` uses a helper
     `_is_playing(node: Node) -> bool` that branches on `node is AudioStreamPlayer3D`;
     `_steal_in(want_3d: bool, priority: int)` filters on the flag, never `Array.has()` across types.
     In world_emitters keep the bound `Callable` in the entry, disconnect it in every removal path
     (`stop_loop`, out-of-range drop, `stop_all`, `_on_target_exiting`), and read entry values as
     `Object`/Variant, check `is_instance_valid()` first, cast after.
   - Verify: `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu` and a
     60 s timeline in main.tscn → `grep -c "res://audio"` on the output = **0**; same for
     `tools/godot.sh movie --movie=/abs/x.avi --timeline=res://audio/capture/gameplay_timeline.json
     --skip-menu --stub=world`. Add to the unit test an error counter
     (`preload("res://tools/error_counter.gd")`, `OS.add_logger`) around 10× `play_3d` + 10× `play_2d` +
     `active_count()` + attach/drop/re-attach/free of an emitter target → 0 errors.

2. **Collision audio is not rate-limited, and the scrape loop is never played.** Traffic emits
   `vehicle_collided` on every physics tick while in contact (traffic_car.gd:399); sound_mapper.gd:100–112
   plays a one-shot for each. Probe: one car grinding for 1 s → **121 `impact_light`** one-shots
   (`probe_pause.gd`). `scrape_loop` has 0 runtime references (R1 #15 asked for it).
   - Do: per-vehicle cooldown `IMPACT_COOLDOWN_S = 0.15` keyed by `get_instance_id()`; ignore impulses
     below `IMPACT_MIN_IMPULSE_NS` (≈ 1,500 N·s); contacts repeating within 0.2 s on the player start
     `scrape_loop` on a dedicated player (level ∝ impulse, pitch ∝ speed, fade out 0.15 s after the
     last contact); non-player cars: at most one scrape emitter (nearest).
   - Verify (test): 120 events in 1 s from one non-player car → ≤ 7 impacts; 120 events on the player →
     1 impact + scrape playing; scrape silent ≤ 0.3 s after the last event.

3. **Every despawned traffic car leaves its hum playing forever.** `_on_target_exiting()`
   (world_emitters.gd:73–76) removes the entry but never stops/frees the AudioStreamPlayer3D. Probe: after
   `queue_free()` of a traffic target, `WorldEmitters` still has **1 playing `traffic_ev_hum`**. Traffic
   despawns constantly (traffic_director.gd:216, :357), so dead hums pile up at old positions.
   - Do: stop + `queue_free()` the player in `_on_target_exiting` (and disconnect, item 1).
   - Verify (test): free the target, await 2 frames → 0 playing hum players, child count back to the
     baseline.

4. **The battery-low beep fires every frame.** sound_mapper.gd:306–312 calls
   `_sfx(&"battery_low", -8.0)` from `_process` whenever `battery <= 0.16`. Probe: **60 beeps in 0.5 s**;
   each restart steals the 2D pool (16 players), so every other 2D one-shot is cut while the battery is
   low.
   - Do: edge trigger with hysteresis (`BATTERY_LOW_ON = 0.15`, re-arm above `BATTERY_LOW_OFF = 0.20`),
     beep every `BATTERY_BEEP_INTERVAL_S = 4.0` while low, voice via the queue (30 s gap already).
   - Verify (test): battery 0.10 for 1 s → exactly 1 beep; for 5 s → 2 beeps.

5. **Pausing the game leaves the car droning.** The director is `PROCESS_MODE_ALWAYS` and children
   inherit it; `_on_paused()` only pauses the music. Probe (`Game.set_paused(true)`): EV voice playing,
   `stream_paused=false`, rpm 9,000; road bed playing at +2.0 dB, wind at −8.0 dB; emitters and the
   pool keep running too.
   - Do: on `game_paused(true)` stream-pause the synth voices, road/wind/roar/squeal, the emitters and
     the pool, and put the music in the `menu` state (LPF 1.2 kHz, −10 dB) instead of stopping it; on
     resume restore the previous state. Voice lines may finish.
   - Verify (test): after `Game.set_paused(true)` + 3 frames all gameplay players report
     `stream_paused == true`; the bed filter cutoff ≤ 2 kHz; resume restores the state.

6. **Thruster hiss: the envelope runs 5× too fast and the band stops at ~4.5 kHz.**
   - The envelope is advanced twice: every mix sample (thruster_synth.gd:187–188) **and** again on
     every hiss tick (:211–212), both with coefficients computed for the quarter rate. Offline render
     (0.6 s full perimeter thrust, then cut): attack −20 → −1 dB in **7 ms**; release −6 dB after
     **18 ms**, −20 dB after **69 ms**. DOSSIER §6.1/§6.3.5: sharp **30 ms** attack, **120 ms** release.
     Round 1 measured 30/120 ms — this is a regression from the CPU rewrite.
   - The chain runs at 12 kHz with 2× RBJ LP 4 kHz (bilinear warping near the 6 kHz Nyquist) and is
     linearly interpolated back up. Render R+P (48 kHz, Welch 8192): band means re peak 4–5 kHz −17.9 dB,
     **5–6 kHz −45.7 dB**, 6–8 kHz −30.9 dB, but **8–10 kHz −23.3 dB** and 14–16 kHz −30.6 dB = images of
     the 12 kHz resampling. Spectral peak **1,395 Hz**. Below 6 kHz the amplitude centroid is
     **2,086 Hz** (power **1,905 Hz**); the test's "3,312 Hz" is only reached because the images are
     counted. DOSSIER §6.3.5: "band 600 Hz–8 kHz, peak ~3 kHz"; brief: centroid 2–4 kHz.
   - Do: drop the decimation. Pre-filter the noise table once in `_init()` at the full mix rate
     (HP 600 Hz 2-pole, 2× LP 6 kHz, peaking EQ +4 dB at 3 kHz Q 0.8 — I simulated this response:
     power centroid 3.17 kHz, peak 2.8 kHz, 6–8 kHz −11 dB re 2–4 kHz), use a 2^18-sample table
     (5.5 s, no audible repetition) with a random start offset, read it every sample (linear
     interpolation for the ±5 % pitch). This is cheaper than now and has no images. One envelope
     update per mix sample, coefficients from `THRUSTER_ATTACK_S`/`RELEASE_S` and the mix rate.
   - Verify (test, 48 kHz render): **power** centroid 2.8–3.5 kHz and amplitude centroid 2–4 kHz
     (brief); spectral peak 2.5–3.5 kHz;
     6–8 kHz mean within −15 dB of the 2–4 kHz mean; 8–10 kHz and 14–16 kHz means each ≤ the 6–8 kHz
     mean; energy < 200 Hz ≤ 2 %; attack 10 → 90 % in 25–40 ms; release to −8.7 dB in 100–140 ms.

7. **The pneumatic "chuff" is a low rumble with a broken time base.**
   - `chuff_age += 1.0 / float(HISS_DIV * _rate)` (thruster_synth.gd:232) runs once per hiss tick
     (4 mix samples), so the age advances **16× too slowly**: the "2 ms attack" is 32 ms.
     `CHUFF_DECAY = 0.999` per 12 kHz tick = τ 83 ms, the burst lasts ≈ 575 ms (spec: 40 ms decay,
     60–90 ms burst). The "burst around 1.2 kHz" is a one-pole **low-pass** at ≈ 430 Hz (coefficient
     0.2 at 12 kHz). The 90 Hz puff uses phase `chuff_age * CHUFF_PUFF_HZ / _rate` (:240) — a few
     millionths of a cycle — so it is **silent**.
   - Measured 30–230 ms after the cut: power centroid 923 Hz, **25.8 % below 200 Hz** (DOSSIER: "no
     combustion rumble"), 70–110 Hz share 1.3 %; the post-cut envelope falls smoothly (−3, −3, −7, −9,
     −12 dB per 10 ms) — no audible burst. The test's "−8.7 dB" mostly measures the hiss release.
   - Do (R1 #5 spec): RBJ band-pass 1.2 kHz Q 1.0 on the noise, attack 2 ms, decay from
     `CHUFF_DECAY_S = 0.040` (`exp(-1/(τ·rate))`), total ≤ 90 ms; puff = sine at 90 Hz with phase
     `age * CHUFF_PUFF_HZ` (cycles), 50 ms, −12 dB; add an export `chuff_enabled` for the test.
   - Verify (test): render cut-off with and without the chuff; in 0–90 ms the 0.8–1.8 kHz band of the
     difference is ≥ 6 dB above the plain release; a 70–110 Hz component exists at −12 ± 3 dB re the
     burst; 150 ms after the cut the chuff contributes ≤ −40 dB.

8. **The motor whine is a buzzy integer-harmonic wave with DC; the fan whistle is far too loud.**
   - `_build_sine_table()` (ev_synth.gd:71–75) bakes `0.66 sin θ + 0.24 sin 2.76θ + 0.10 sin 5.41θ`
     into one 4,096-sample cycle. Non-integer partials cannot live in a single-cycle table: at the wrap
     the 2.76 partial jumps from −0.24 to 0. Render at 12,000 rpm (f0 800 Hz): partials at 2,208 and
     4,328 Hz **absent (−193/−213 dB)**; instead integer harmonics 2,400 Hz **−10 dB**, 1,600/4,000 Hz
     −18 dB; **DC −24 dB** re f0; max sample step 4× (12,000 rpm) to 11× (6,000 rpm) the median = a click
     every cycle. `motor_load` only scales the level (load 0 → 1: −25.5 → −18.6 dBFS, identical
     spectrum) — status claims "the timbre changes with the load" (false).
   - The fan uses the **same** buzzy table (`_sin_lut(pf) * fn`, :130), at 0.10 against the whine's
     0.30 × (0.45 + 0.55·load): at max downforce the 3 kHz fan is **−9.5 dB** re the whine f0 at full
     load and **−2.6 dB** when coasting, with harmonics at 9 kHz (−13 dB), 15 kHz (−21 dB), 18 kHz
     (−24 dB). R1 #6 / status: "−18 dB under the motor". `FAN_LEVEL_DB = -18.0` exists but is unused.
   - Do: a pure 4,096-entry sine table with linear interpolation; three phasors f0, 2.76·f0, 5.41·f0
     (each partial muted above 0.45 × mix rate); partial gains move with load (2.76: 0.12 → 0.30,
     5.41: 0.04 → 0.14, constants in tuning); the fan = its own pure sine at
     `whine level × db_to_linear(FAN_LEVEL_DB) × suction`.
   - Verify (test, 12,000 rpm): peaks at 800, 2,208 ± 20 and 4,328 ± 40 Hz; 2,400 Hz ≤ −30 dB re f0;
     DC ≤ −60 dB; load 0 → 1 raises the 2,208 Hz partial ≥ 6 dB relative to f0; fan at max downforce
     −18 ± 2 dB re f0 at load 1, its 9 kHz harmonic ≤ −40 dB; CPU check still ≤ 8 %.

9. **The demo plays 12 of its 35 SFX steps as silence, and the city bed bleeds under every step.**
   - `_next_step()` sends every sfx id through `play_sfx()` (audio_demo.gd:99); the pool rejects
     loops. My shot run logged 12× "[audio] … is a loop and needs attach_loop()" (wind_rush, road_roll,
     river_ambience, rain_layer, city_ambience, traffic_ev_hum, siren_yelp, siren_wail,
     thruster_hiss_loop, scrape_loop, tyre_squeal, boost_roar_loop). Status item 8 says "every loop
     gets its own player" (false). `set_music_enabled(false)` leaves the MusicBed's city ambience and
     rain playing, so the "quiet" floor is the ambience (worker demo.mp4: 1.5 s steps −37 … −18 dBFS).
   - The synth step overwrites the director's gains (`whine_gain = 0.16`, `fan_gain = 0.06`,
     `hiss_gain = 1.3`, :151–158) and never restores them — the demo does not demonstrate the shipped mix.
   - Do: loop ids → `_start_loop(id)` for 3 s; the siren and the traffic hum also as a moving
     AudioStreamPlayer3D passing the listener at 30 m/s (give the demo its own Camera3D with
     `doppler_tracking = PHYSICS_STEP` — it lives in game/audio/demo, so you own it); add
     `set_ambience_enabled(false)` to the bed for the demo; keep the shipped gains.
   - Verify: `tools/godot.sh shot --scene=res://audio/demo/audio_demo.tscn --out=audio_demo --times=3,22`
     prints 0 "is a loop" warnings; re-record demo.mp4 and list per-step RMS in status (every loop step
     ≥ 10 dB above the silent gap before it; the gaps ≤ −60 dBFS with the ambience off).

10. **Music: every breakdown is a 25–30 dB hole, and the masters are still too dense.**
    - Short-term loudness every 3 s: cruise −14 … **−48 LUFS at 45 s** (−35 at 48 s); pursuit **−43 at
      36 s**; race **−46 at 39 s**. RMS per 4 s: cruise 44 s −39 dB, pursuit 32 s −44 dB, race 36 s
      −44 dB, against −13/−14 dB elsewhere. In game (cruise bed ≈ −24 LUFS) the music simply vanishes
      for ~5 s every loop. R1 #11 asked for "drums out, pad filter sweep, riser" — the pad is gone too.
    - PLR (true peak − integrated, ffmpeg ebur128): cruise −4.3 dBTP / −14.0 LUFS = **9.7**, pursuit
      **9.4**, race −5.7 dBTP = **8.3 dB**; R1 #1(a) asked ≥ 10 dB.
    - Do: keep pad + bass (filtered) + arp through the breakdown, aim −6 … −10 LU under the full
      sections; reduce the bus saturation / limiter so PLR ≥ 10 dB (true peak ≤ −1.5 dBTP stays).
    - Verify: ebur128 short-term series every 3 s in status: minimum ≥ −24 LUFS for every track;
      analyze.py prints PLR per track, all ≥ 10.0 dB.

11. **World and game hooks that are missing or wrong.**
    - Heat never reaches the emitters: nothing calls `set_heat()` (audio_director.gd:229); probe
      `heat_changed(4)` → `WorldEmitters.heat = 0`. Sirens are attached to every `police` car in range
      regardless of heat (world_emitters.gd:96; probe: a patrol car at heat 0 → 1 siren playing).
      `_yelp_on` is one flag for all police cars (:170–189), so with 2+ cars only the first switches.
      Heat ≥ 3 should alternate wail/yelp (R1 #7b), today it is yelp only.
    - The traffic hum pitch never follows the car's speed (status item 7 claims it does; no code sets
      `pitch_scale` after `attach_loop`).
    - Never played at runtime: `horn_traffic`, `horn_traffic_double` (the traffic unit already emits
      `TrafficCar.horn_requested(car)` for you, traffic_car.gd:22/:287–289 — connect it per car when you
      attach the hum), `police_horn` (play it as a 3D one-shot on police cars within 30 m every 6–10 s
      at heat ≥ 2), `radio_squelch` (before and after every radio line).
    - `_on_lap_completed()` (sound_mapper.gd:239–246) says "最后一圈" on **every** lap; `lap` is
      ignored and `total` is a dead local. Announce only when `lap == laps - 1` (ask the modes unit
      for the lap count in status if it is not exposed; until then say nothing).
    - `_last_n2_tier := 0` (:42) and the car spawns with N₂ 100, so "氮气就绪" + a chime fire on the
      first frame of every session and after every respawn. Initialise the tier from the telemetry
      when the player reference changes.
    - `_on_heat_changed()` queues "警察来了" again on every heat step ≥ 2 (:251–252); play it only on
      0 → ≥ 1.
    - Verify (test): heat 0 → 0 sirens; heat 2 → wail; heat 4 → both cars alternate; two police cars
      both switch; hum `pitch_scale` changes with the target speed; `horn_requested` → 1 horn;
      lap 1 of 3 → no line, lap 2 of 3 → `final_lap`; spawn with N₂ 100 → no `boost_ready`.

12. **Voice queue: the two channels share one "current line", so ducking breaks.**
    `_current_id` / `_current_kind` (voice_queue.gd:25–26, 113–117) belong to whichever channel started
    last; a radio line finishing while the announcer still talks emits `line_finished` and the director
    sets `_duck_target = 0` (probe: "radio finished, announcer still playing=true, duck target now =
    0.0") — the music jumps back up under a voice. `_pump_queue()` also drops P0 lines after 2 s (:124;
    P0 = never cut) and re-queues a busy head item, blocking a line for the other, free channel
    (:129–131).
    - Do: per-channel state (id, kind, busy); duck while **any** channel plays; P0 never times out;
      pump each channel's own queue.
    - Verify (test): radio + announcer together, end the radio → duck target stays 1.0 until the
      announcer ends; a P0 line queued for 3 s still plays; a radio line in the queue starts at once
      when only the announcer is busy.

13. **The test has dead and vacuous checks** (81 checks run; status item 16 says 94).
    - `_test_doppler_setup()` (test_audio.gd:149) is never called — none of its 13 checks (8 pool players + 5 emitter checks) run.
    - The crossfade check (`_finish()`) runs after `_director.free()`; `_bed` is a freed child, so the
      "does not dip by more than 3 dB" line is never printed.
    - `_ok(_spoken.has(&"countdown_3") or _voices != null, …)` is always true.
    - `_test_chuff`'s "no chuff right after the ignition" compares 100–200 ms with 250–400 ms after
      ignition — both long after it; "motor whine tracks rpm" checks the arithmetic of
      `whine_frequency()`, not the rendered spectrum.
    - Do: call every test function; run the crossfade check before freeing; replace the tautology and
      the vacuous checks with the measurements in items 1–12 (they are the regression net for this
      round). Print the final count and make status quote it.
    - Verify: `tools/godot.sh test res://audio/tests/test_audio.gd` prints the doppler, crossfade and
      every new check by name; 0 failed.

14. **Bare literals, dead code, duplication** (R1 #17, status item 17 says "every tunable number lives
    in audio_tuning.gd").
    - 86 bare literals in function bodies outside the RBJ formulas, including the exact R1 examples
      that are still there: audio_director.gd:296 `0.92 + 0.2 * slip`, :302 `1.0 + 0.08 * …`, :295/:301
      `_delta * 8.0` / `* 10.0`, :299–300 `0.15`, `- 6.0 + 6.0 *`; thruster_synth.gd 21 (:141 0.02,
      :226 `0.8 + 0.2 * tri`, :231 0.001, :234 0.002, :240 0.05, :248 0.0005, :305 0.25 …);
      ev_synth.gd 11 (:75, :113 `0.45 + 0.55`, `/ 2500.0`); music_bed.gd 8 (−60.0, 20000.0, −18.0);
      sound_mapper.gd 8 (:215 −4.0, :218 −3.0, :301 `-8.0, 1.3`, :310 0.16, :312 −8.0);
      world_emitters.gd 6 (:153 −30.0, :217 `- 8.0`, 9999.0).
    - Dead: tuning constants `LIMITER_THRESHOLD_DB`, `ROAD_GAIN`, `WIND_GAIN`, `FAN_LEVEL_DB`,
      `CHUFF_DURATION_S`, `ONESHOT_MAX_AGE_S`, `EMITTER_FADE_DISTANCE_M`; export `hop_gain`
      (thruster_synth.gd:31 — :226 uses `Tuning.HOP_TONE_GAIN` instead); local `total` (sound_mapper.gd:243).
    - Duplicated: `LOOP_IDS` in audio_tuning.gd:103–107 **and** sfx_library.gd:15–19;
      `stop_all_sounds()` (audio_director.gd:212–225) = `_exit_tree()` (:331–345).
    - Do: move every number to audio_tuning.gd with its unit (or wire the dead constant that was meant
      for it, e.g. `FAN_LEVEL_DB`), delete what stays unused, keep one `LOOP_IDS`, have `_exit_tree()`
      call `stop_all_sounds()`.
    - Verify: a scan of function bodies finds no literal other than 0, 1, 0.5 and array indexes.

## SHOULD-FIX
- **Status accuracy.** Claims that are false today: item 16 "94 checks" (81 run), item 6 "fan 18 dB
  under the motor" (−9.5 / −2.6 dB), item 7 "the hum pitch follows their speed" (no code), item 8
  "every loop gets its own player" (12 rejected), item 17 "no magic numbers" (86), SHOULD "the motor
  timbre changes with the load" (level only), item 5 "a 2 ms attack, 40 ms decay, 90 Hz puff" (32 ms,
  τ 83 ms, puff silent). Status must only claim what a command in "How to test" prints.
- **Re-record the 30 s capture after the fixes.** `captures/audio/gameplay.avi` is 29.2 s (brief: 30 s;
  timeline ends at 28.5) and was recorded at 03:06, before the 03:10 SFX rebuild. End the timeline at
  ≥ 30.5 s.
- **Leaks at exit.** `--verbose` test run: 76 leaked instances — 17 `AudioStreamOggVorbis`, 17
  `OggPacketSequence`, 20 `AudioStreamPlaybackOggVorbis`, 20 `OggPacketSequencePlayback`, 2
  `AudioStreamGeneratorPlayback` (core smoke test: 0). `CACHE_MODE_IGNORE` hid the "still in use"
  message, not the leak; it also makes every voice line re-read its OGG from disk on the main thread
  (voice_queue.gd:88). Cache the 61 voice streams in SfxLibrary and free/stop the test's players.
- **Beds are hissy.** wind_rush: power centroid 3.9 kHz, 0.4 % below 200 Hz, 29 % in 4–10 kHz;
  road_roll: 41.7 % in 1–4 kHz, centroid 2.0 kHz (power). Real tyre roar sits at 300 Hz–1.2 kHz: give
  road_roll ≥ 50 % of its energy below 1 kHz, and the wind an 80–500 Hz buffeting layer with 0.3–2 Hz
  gusts under the hiss. boost_roar_loop has 23 % in 200 Hz–1 kHz (R1 asked a 120–600 Hz body):
  +4–6 dB on the body layer.
- **Hop charge tone** is still a bare sine (220 → 880 Hz); after item 6 frees CPU, use a band-limited
  detuned saw pair through a resonant LP that opens with the charge (R1 SHOULD).
- **Crossfade swell.** For a track present in both states (menu ↔ cruise) the cos/sin blend gives
  +3 dB at mid-fade (music_bed.gd:141); interpolate linearly when from and to are the same track.
- **Null safety.** `_on_near_miss` (`other`), `_on_takedown` (`victim`), `_on_vehicle_wrecked`
  (non-player branch) dereference without `is_instance_valid()`, despite the "every handler is
  defensive" header.
- **Slow-motion.** Listen to `Events.slowmo_request` and pitch/LPF the SFX bus (≈ 0.7 pitch, LPF 2 kHz)
  for the 2.7 s takedown cam (SPEC pillar 5 "crashes have weight").
- **Demo meter.** The meter is a single grey text line (font 20, `Color(0.55, 0.6, 0.7)`); in a 0.4×
  contact sheet it is unreadable (`captures/review/audio/r2/demo_sheet_r2.jpg`). Add peak/RMS bars and a
  2–4 kHz bar (ART.md §3 UI: cyan `#19E6FF`, text `#F2F6FF`, warning `#FFCC00` above −3 dBFS).
- **sfx_ids() order.** `out.sort()` on StringNames is not alphabetical (the demo order is scrambled);
  use `sort_custom(func(a, b): return String(a) < String(b))`.
- **Housekeeping (lead rule: scratch in tmp/<unit>/, deleted when done).** Delete the 4 orphan uid files
  `game/audio/tests/_dbg.gd.uid`, `_probe2.gd.uid`, `_probe3.gd.uid`, `_probe4.gd.uid`;
  `tools/audio/__pycache__/` (set `PYTHONDONTWRITEBYTECODE=1` in build.sh); the 24 build WAVs left in
  `tmp/audio/` (build.sh should delete them; the voice MP3 cache may stay); `/tmp/oggprops.gd`,
  `/tmp/probe7.gd` (scratch outside tmp/audio/).
- **Doppler is still off game-wide** (no Camera3D sets `doppler_tracking`). Keep the camera request; when
  it lands, run the GODOT.md §9 check (440 Hz at 50 m/s → 515 ± 5 / 384 ± 5 Hz) windowed.

## Verified OK
- `tools/godot.sh check --only=res://audio/` → `CHECK 18 files, 0 failed, 0 engine errors, 0 warnings`.
- Test is `extends Node` and runs via test_host: `AUDIO TEST 81 checks, 0 failed`; every stream loads.
- Synth CPU `6.97 %` of one core (ev 2.39 %, thruster 4.57 %) at load average ≈ 21 — inside 8 %.
- The car is the star of the mix: in both spectrograms the whine is the strongest tonal line in
  150–1,100 Hz while accelerating (`worker_gameplay_combo.jpg`, `rv_combo.jpg`); car without music,
  cruise 19–25 s: −17.0 … −18.6 LUFS short-term (target −20 … −16).
- No clipping: worker capture I −14.9 LUFS, LRA 5.1 LU, sample peak −1.9 dBFS, TP −1.7 dBTP; my capture
  I −14.3 LUFS, LRA 9.0 LU, sample peak −1.9 dBFS, TP −1.8 dBTP.
- The gameplay capture is real gameplay (contact sheet: car moving, nitro, wall hit, landing).
- `analyze.py`: `ANALYZE 99 files, 0 flagged`; announcer −16.0 LUFS (spread 0.7 LU), radio −18.0 LUFS
  (0.0 LU), radio −31.5 dB below 250 Hz and −36.6 dB above 3.5 kHz; music seams continuous.
- Sound design that now works: tyre_squeal tonal (99.2 % in 1–4 kHz, flatness 0.01, peak 1,066 Hz);
  land_whoomp 92 % below 200 Hz; boost_ignite thump 74 % below 200 Hz (peak 64 Hz); impact_heavy
  layered (26/27/32/15 % in <200/200–1k/1–4k/4–10k Hz); traffic_ev_hum 64 % below 200 Hz.
- Rear vs perimeter level +2.6 dB; group sums normalised (rear/4, perimeter/6, √); hiss below 200 Hz
  ≤ 0.5 %.
- Voice: 61 lines (45 announcer + 16 radio), every brief line present with subtitles; P0/P1/P2 queue
  works for one channel; repeat throttle 4 s / 30 s.
- 2D pool bookkeeping exact (16 vs 16), cap 24, loop ids rejected; synths are not reparented;
  `AudioEffectHardLimiter` −1 dB; ducking −6 dB; Settings volumes untouched.
- Ownership: every Write/Edit and file-writing Bash command of round 2 targets `game/audio/**`,
  `tools/audio/**`, `status/audio.md`, `tmp/audio/` or `/tmp`; all files ≤ 400 lines (largest
  `tools/audio/common.py` 397, `audio_director.gd` 346); static typing throughout.

## Evidence
- `tools/godot.sh check --only=res://audio/` → `CHECK 18 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://audio/tests/test_audio.gd` → `AUDIO TEST 81 checks, 0 failed`,
  `WARNING: 76 ObjectDB instances were leaked at exit`; `--verbose` rerun lists the 76 audio objects
  (`tmp/review/audio/test_verbose.txt`).
- Lead A-INT1 reproduction: `tools/godot.sh drive --timeline=/Users/minimax/m/skyrush/tmp/review/audio/smoke60.json
  --skip-menu` (main.tscn, 60 s timeline; reached t = 12.6 s, then `FATAL: Index p_index = -1 is out of
  bounds (… size() = 64)` in the renderer — reflection probe limit, not audio) → 773× / 252× / 3× audio
  errors as in MUST-FIX 1 (`tmp/review/audio/smoke60_out.txt`).
- My capture: `tools/godot.sh movie --movie=/Users/minimax/m/skyrush/captures/review/audio/r2/rv_drive.avi
  --timeline=/Users/minimax/m/skyrush/tmp/review/audio/rv_drive.json --skip-menu --stub=world` → 23.2 s,
  7,046 + 992 + 11 + 2 audio errors (`tmp/review/audio/rv_drive_out.txt`); `rv_drive.mp4`,
  `rv_combo.jpg` (6-frame sheet + 0–6 kHz spectrogram).
- Worker capture: `ffmpeg -i captures/audio/gameplay.avi -map 0:a -af ebur128=peak=true+sample` →
  I −14.9 LUFS, LRA 5.1 LU, sample peak −1.9 dBFS, TP −1.7 dBTP; `worker_gameplay_combo.jpg`.
  Short-term per second: with music 3 s −12.7 … 23 s −18.9; without music (drive_nomusic.avi)
  19–25 s −17.0 … −18.6 LUFS.
- Demo shots: `python3 tools/slots.py heavy 4 -- godot … -s res://tools/capture.gd -- --scene=res://audio/demo/audio_demo.tscn
  --out=review_audio_r2 --times=3,22,33,44,62` → `CAPTURE errors=0 warnings=12` (the 12 loop
  rejections); sheet `captures/review/audio/r2/demo_sheet_r2.jpg`.
- Synth probe (`tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/audio/probe_synth.gd`, analysed
  with `an_synth.py`): ev_12000 top peaks 800 (0 dB) 2,400 (−10) 1,600 (−18) 4,000 (−18) 0 Hz (−24);
  partial 2.76× −193 dB; thruster attack 7 ms, release −6 dB @ 18 ms / −20 dB @ 69 ms / −40 dB @
  263 ms; tail centroid 923 Hz, 25.8 % < 200 Hz; R+P below 6 kHz amplitude centroid 2,086 Hz, power
  1,905 Hz, peak 1,395 Hz, 8–10 kHz −23.3 dB vs 5–6 kHz −45.7 dB; fan −9.5 dB (load 1) / −2.6 dB
  (load 0) re f0.
- Runtime probe (`probe_runtime.gd`): siren at heat 0 = 1; hum still playing after its car was freed
  = 1; 60 battery beeps in 0.5 s; `heat_changed(4)` → emitters.heat 0; duck target 0.0 while the
  announcer still plays; the pool calls logged 40 typed-array `has` errors and 10 Nil `.playing` errors.
- Pause/impact probe (`probe_pause.gd`): 121 `impact_light` in 1 s of contact; paused: EV playing,
  `stream_paused=false`, rpm 9,000; road +2.0 dB, wind −8.0 dB still playing.
- Assets (`an_assets.py`, bands <200 / 200–1k / 1–4k / 4–10k / >10k %): wind_rush 0.4/11.7/52.2/29.3/6.4;
  road_roll 12.2/17.3/41.7/11.9/2.3; boost_roar 7.7/23.4/63.3/5.5/0.0. Music short-term LUFS every
  3 s and RMS per 4 s as in MUST-FIX 10; ebur128 true peak cruise −4.3, pursuit −4.6, race −5.7 dBTP
  at −14.0 LUFS.
- Worker log scan (`tmp/review/audio/writes.py`, `bashscan2.py`): no writes outside owned paths;
  0 occurrences of `audio-lead` / `A-INT1`.

## Lead notes status
- A-INT1: **open** (MUST-FIX 1; zero engine errors from `res://audio` in a 60 s main.tscn run is part
  of acceptance).
- Project rules: tests extend Node ✓; runs end by themselves ✓; scratch hygiene ✗ (SHOULD-FIX
  housekeeping).
