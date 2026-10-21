# audio review round 3 — VERDICT: FAIL

Reviewer: lead's art director (Opus). Standing order "贴图纹理什么都要细化" — for audio: every sound is
layered and physically right, the mix is balanced, nothing clicks, drones, spams or errors.
Everything below was measured. Scratch: `tmp/review/audio/r3/` (probes `probe_ev.gd`, `probe_rt.gd`,
`probe_movie.gd`, `probe_siren.gd`, `probe_bus.gd`, `probe_bus2.gd`; analysers `an_ev.py`, `an_drive.py`,
`an_probe_movie.py`, `an_bus.py`, `deadconst.py`, `writes_r3.py`). Captures: `captures/review/audio/r3/`.
You may RUN my probes (`tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/audio/r3/probe_ev.gd`);
copy what you need into your own tests, do not edit them.

Good news first: the lead note **A-INT1 is satisfied** (0 `res://audio` lines in the lead's smoke drive,
in 52 s of a 60 s main.tscn run and in two sandbox movies), the check and the 125-check test are green,
no clipping (−1.9 dBTP), CPU 5.8 %, the hiss/chuff/music/road-bed fixes of round 2 landed.
But the hero sound is gone: **in the game the Roadster has no motor whine at all.**

## Scores (0-10): function 4, visual/feel 4, code 5
- **function 4** — motor whine dead after the spawn (and after every stop); police sirens and traffic hums
  placed by the emitters are inaudible (−30 dB trim, never raised); the river bed is never created; the two
  synth voices bypass the SFX bus (the SFX volume slider and the slow-mo do not reach them); the pause
  leaks beeps and sirens; the 2nd patrol car's siren restarts every 0.5 s; "最后一圈" at the finish line.
- **visual/feel (sound) 4** — without the whine the car is a hiss + road bed; the recursive oscillators also
  random-walk ±10 dB when the rpm moves (sample peak +1.0 dBFS); horns are decaying sine chords (a
  doorbell, not a horn); wind still hissy. Music (PLR 13 dB, no holes), thruster hiss/chuff, impacts,
  voice: good. Demo UI: clean, ART colours, readable.
- **code 5** — typed, split, ≤ 400 lines, A-INT1 done right; but the tests are blind to every bug above
  (they test fresh objects and one-frame bursts), 10 dead/stale tuning constants, bare literals left in
  logic files, layout slips, untyped `call()`, ~49 scratch files left in /tmp, false status claims.

## MUST-FIX

1. **The motor whine dies at the first standstill — i.e. at every spawn — and its level random-walks.**
   `synth/ev_synth.gd:143-164`: at f0 ≤ `MOTOR_MIN_HZ` the oscillator state `_y/_p` is zeroed, and the
   seed (`if not _started`) runs once, with w = 0 when the first render happens at rest. A zero state of
   `y[n] = 2cos(w)y[n-1] − y[n-2]` stays zero forever. The car spawns frozen at 0 km/h, so the first
   render is always at rpm 0. Measured:
   - Offline (`probe_ev.gd`, RMS of 1 s at 6000 rpm, load 1): fresh voice **−15.0 dBFS**; after 0.1 s at
     rest **−45.5 dBFS** (only the fan sine is left); same after drive→stop→drive and after the idle
     throttle (3200 rpm). Your `_test_standstill` only checks the silence, never the recovery.
   - Through the real mix (`probe_movie.gd`, movie mode, Master bus): car at rest 1 s, then 150 km/h at
     full load: the 600 Hz whine line is **−61.8 dBFS (8.5 dB over the noise floor = no line)**; a control
     EvSynth created while already at 9000 rpm: **−13.4 dBFS (57.8 dB over the floor)**.
   - Gameplay (`captures/review/audio/r3/rv_nomusic.mp4`, `an_drive.py`): whine prominence at f0 = 4 × speed is **5.4 dB median**
     = the statistics of noise; `captures/review/audio/r3/spec_combo.jpg` top = my drive (no whine curve,
     only the 1.5 kHz fan line), bottom = your demo synth step (whine alive only because the demo never
     rendered at rpm 0 before it; it dies at 6.2 s after `_silence_synths()`).
   - Second defect of the same oscillator: changing w keeps (y1, y2), so the amplitude jumps by a
     phase-dependent amount at every block and drifts ∝ 1/√sin w. Rendered in 60 fps blocks at load 1
     (`an_ev.py`): sweep 3000→15000 rpm falls **6.4 dB**, 15000→3000 rises **6.5 dB** (design: flat);
     after 5 up/down cycles the 1 s holds at 9000 rpm read **−4.8, −7.8, −9.1, −4.4, −12.9 dBFS** (design
     −15.0), sample peak **+1.0 dBFS**. Re-seeding alone would expose this in every session.
   - Do: replace the recurrences by amplitude-stable oscillators. Either a quadrature rotator per
     partial (`nc = c*cw − s*sw; s = c*sw + s*cw; c = nc`, coefficients per block from f, renormalise
     `c, s` by `1/sqrt(c²+s²)` once per block, start at (1, 0)), or phase accumulators in cycles + a 4096
     sine table with linear interpolation. Never zero the state at a standstill — mute the gains instead.
   - Verify: `probe_ev.gd` cases B/C/D within ±0.5 dB of case A; every G_cycles hold within ±0.5 dB of
     the fresh voice and sample peak ≤ −6 dBFS; sweeps flat ±1 dB per 0.5 s (`an_ev.py`); `probe_movie.gd`
     phase B 600 Hz line ≥ 40 dB over the floor; a music-muted gameplay movie: `an_drive.py` median
     prominence ≥ 20 dB and a visible whine curve in the spectrogram; synth CPU still ≤ 8 %. Add the
     B/C/D and cycle checks to `audio_test_motor.gd`.

2. **The world emitters are inaudible, and the river bed is never created.**
   - `world_emitters.gd:304` attaches every siren and traffic hum at `EMITTER_START_DB = −30 dB`; nothing
     ever raises it (the only `volume_db` write is the river at :372). `probe_siren.gd` (movie, patrol car
     20 m from the player, heat 2): floor **−66.6 dBFS**, with the placed siren **−65.1 dBFS** (+1.5 dB);
     the same `siren_wail` asset on a 2D player at 0 dB: **−26.0 dBFS**. A chasing patrol car is ~40 dB
     under the player's car. Hums: same trim, also inaudible. No fade: attach/detach start/stop abruptly.
   - `river_ambience` is never attached anywhere (grep: only the LOOP_IDS entry and the volume loop at
     :367-372), so even with a `river` POI the bed cannot play.
   - Do: per-id mix constants, e.g. `SIREN_EMITTER_DB = 0.0`, `SIREN_UNIT_SIZE_M = 20.0` (0 dB at 20 m,
     −6 dB at 40 m), `HUM_EMITTER_DB = −6.0`, `HUM_UNIT_SIZE_M = 6.0`; fade in over
     `EMITTER_FADE_S = 0.3` from −40 dB to the target and fade out the same before `queue_free`; attach
     one `river_ambience` emitter at the nearest `river` POI while the player is within
     `RIVER_EMITTER_RANGE_M` (keep the world request for a polyline).
   - Verify: `probe_siren.gd` placed siren RMS ≥ −32 dBFS at 20 m; a test with a world double that
     publishes a `river` POI 50 m away → 1 river emitter playing above `SILENT_DB`; no step > 6 dB
     between two 10 ms windows when an emitter is attached or dropped.

3. **The two synth voices play on the Master bus.** `EvVoice` and `ThrusterVoice` never set `bus`
   (AudioStreamPlayer3D default = Master). `probe_bus2.gd`: `EvVoice -> Master`, `ThrusterVoice -> Master`
   (everything else SFX/Voice/MusicBed). So the player's SFX volume (Settings) does not touch the motor,
   fan, hiss, hop tone and chuff (brief §5 "respects Settings volumes"), and the takedown slow-mo
   (SFX pitch 0.7 + LPF 2 kHz) skips the car.
   - Do: `bus = &"SFX"` for both voices (set it where the director creates them).
   - Verify: `probe_bus2.gd` prints `-> SFX` for both; test: `Settings.set_volume(&"SFX", 0.0)` → the
     `SFX` bus volume is ≤ −60 dB and both voices are on it.

4. **The game pause leaks sound again (re-opens R2 #5).** SoundMapper, RaceMapper and WorldEmitters
   inherit `PROCESS_MODE_ALWAYS` from the director, so their per-frame logic runs while paused.
   `probe_rt.gd` (battery 0.10, heat 4, three patrol cars, 9 s of pause): **2 battery beeps** played,
   **2 one-shots playing un-paused**, **3 of 3 sirens playing un-paused** (`_update_sirens` sets
   `p.stream` + `play()` during the pause, which clears `stream_paused`). Your test only looks at the flags
   0.8 s after pausing.
   - Do: `process_mode = PROCESS_MODE_PAUSABLE` on SoundMapper, RaceMapper and WorldEmitters (signals
     still arrive; keep the director's ducking/bed logic ALWAYS); in WorldEmitters keep a `_paused` flag
     and re-apply `stream_paused` after every `stream =`/`play()` and in `attach_loop`. UI one-shots
     (`ui_*`) must still play in the pause menu.
   - Verify: the pause part of `probe_rt.gd` → 0 one-shots played, 0 emitters playing un-paused; plus a
     test: `play_sfx(&"ui_click")` during the pause → playing and not paused.

5. **The siren alternation stutters.** `world_emitters.gd:331-336` adds the per-car offset
   (`index × period / 2` = 3 s) to the stored phase at **every** scan, so car 1 advances 3.5 s per 0.5 s
   scan. `probe_rt.gd`, three patrol cars at 60/80/100 m, heat 4, 24 scans (12 s):
   car 0 `wwwwYYYYYYwwwwwwYYYYYYww` (4 switches), car 1 `wYwYYwYwYwwYwYwYYwYwYwwY` (**19 switches**),
   car 2 identical to car 0 (lockstep — status item 9 "every car has its own phase" is false). Every
   switch sets a new stream = the sample restarts with a cut.
   - Do: store the phase without the offset (advance it by `EMITTER_SCAN_INTERVAL_S` only), give each car
     its offset once at `attach_loop` (random or index-based), and swap wail↔yelp with a 50 ms crossfade
     (two players per car, or fade out/in) instead of a hard restart.
   - Verify: same probe → each car exactly 4 switches per 12 s, no two cars switching on the same scan;
     add it to `_test_hooks` (today it only checks `yelp_count() >= 1`).

6. **Race and collision logic slips.**
   - `race_mapper.gd:64` `if lap < total - 1: return` also fires on the last completed lap (the finish):
     `probe_rt.gd` `set_total_laps(2)` + `lap_completed(player, 2)` → **"final_lap"** (最后一圈 together
     with 终点). `race_session.gd:269-274` emits `lap` = completed laps. Do `if lap != total - 1: return`.
   - A single impact of the player starts the scrape loop: one `vehicle_collided` → scrape at **−8.5 dB**
     (`sound_mapper.gd:96` calls `_scrape_contact` on the first hit). R2 #2 asked for contacts repeating
     within 0.2 s: add `SCRAPE_REPEAT_S = 0.2` and start the scrape only on the 2nd contact of the same
     car inside it.
   - `race_mapper.gd:78-82` announces "追捕升级" when the heat goes **down** (4 → 3 → `heat_up` in the
     probe). Announce only when `level > previous`.
   - Verify (tests): lap 1 of 2 → `final_lap`, lap 2 of 2 → nothing; one impact → scrape stays at
     `SILENT_DB`; contacts every physics frame for 0.5 s → scrape playing; heat 4 → 3 → no line.

7. **The tests must catch these bugs.** Every bug above passes your 125 checks because the tests use fresh
   objects or one-frame bursts. Add (names as you like): drive voice recovers after a standstill (#1);
   level stable over rpm cycles (#1); sirens audible at 20 m — check the emitter `volume_db`/`unit_size`
   after the fade (#2); river emitter with a `river` POI (#2); both synth buses == SFX (#3); pause leaks
   (#4); per-car switch count (#5); laps/scrape/heat (#6). Also make "120 contacts" span 1 s of physics
   frames (today all 120 are emitted in one frame, so it proves nothing about the 0.15 s cooldown:
   expect 6–7 impacts). Quote the new total in status.

8. **Code rules (R2 #14 not closed).** `deadconst.py`:
   - 10 dead tuning constants: `MAX_ONESHOTS` (tests only), `SCRAPE_MAX_PLAYERS`,
     `PARTIAL_2_GAIN_LOAD_MIN/MAX`, `HISS_HP_HZ`, `HISS_LP_HZ`, `HISS_PEAK_HZ`, `HISS_PEAK_DB`,
     `HISS_TABLE_BITS`, `SLOWMO_RETURN_S`. The HISS_* ones are also **stale**: the table generator uses
     LP 5 kHz, peak 3.5 kHz +6 dB Q 1.5 (`gen_noise_table.py:27-32`), the tuning says 6 kHz / 3 kHz / +4 dB,
     and `thruster_synth.gd:8-9` repeats the wrong numbers. Delete them or make the generator the single
     source (and fix the header).
   - Bare literals in logic: `thruster_synth.gd:96` `0.1`, `:169` `30`, `:170` `1000.0` (ev_synth already
     has named constants for these), `ev_synth.gd:81` `0.1`, `music_bed.gd:186` `0.0001`,
     `chuff_voice.gd:100` `0.001`.
   - Dead debug hook `bus_setup.gd:51` `OS.has_feature("dbg_no_sfx_fx")` (a custom feature tag can never be
     set in the editor run) — delete.
   - Layout: no blank lines before `audio_director.gd:87 set_scrape`, `sound_mapper.gd:139`, `:240`
     (`# --- per frame` glued to the previous function); `music_bed.gd:101-103` declares `var _state`
     between functions under the doc comment of `set_state` — move it to the members.
   - Verify: `deadconst.py` → 0 dead constants, 0 literals in logic files other than 0/1/0.5/indexes.

9. **Lead project rule: scratch hygiene (2nd time).** `writes_r3.py`: this round wrote scratch to /tmp
   (worker rules: "never /tmp"); **49 files / 11.4 MB still there** (`/tmp/movie2.txt` 6.8 MB,
   `/tmp/drive60b.txt`, `/tmp/full1..10.txt`, `/tmp/probe_a*.txt`, `/tmp/dbg6.py`, …) plus
   `/tmp/audio_director_backup.gd`; `tools/audio/__pycache__/` is back (10:09). Delete them; scratch goes to
   `tmp/audio/` and is deleted when done; run the python tools with `PYTHONDONTWRITEBYTECODE=1`.
   - Verify: `ls /tmp` shows none of the files listed in `tmp/review/audio/r3/tmp_targets.txt`; no
     `tools/audio/__pycache__`.

## SHOULD-FIX
- **Horns sound like door chimes.** `gen_world.py:74-107`: `police_horn` and `traffic_horn` are 3–4 pure
  sines under an exponential decay (τ 0.30–0.35 s, −29 dB after 1 s). Measured (`an_assets.py`):
  `horn_traffic` 100 % of the energy in 200 Hz–1 kHz, spectral flatness 0.00; `police_horn` 97 %. A real
  horn is a sustained, buzzy diaphragm tone. Do: flat sustain while held (30 ms attack, 80 ms release),
  band-limited saw/square pair (traffic 415/523 Hz, police air horn 350/440 Hz) through a 2-pole LP
  ~3 kHz + a resonant peak ~2.5 kHz, slight 5–6 Hz vibrato and soft drive. Target ≥ 25 % above 1 kHz.
- **Wind bed still a hiss.** `wind_rush` bands 0.5/28.0/58.2/11.3/2.0 % (<200/200–1k/1–4k/4–10k/>10k),
  power centroid 2.2 kHz. R2 asked for an 80–500 Hz buffeting layer: give ≥ 5 % below 200 Hz and
  ≥ 40 % below 1 kHz.
- **Music true peaks went up.** ebur128: cruise **−0.7 dBTP**, pursuit **−0.4 dBTP**, race −1.1 dBTP
  (R2 #10: "true peak ≤ −1.5 dBTP stays"). Add a true-peak limiter at −1.5 dBTP in `mastering.py`
  (PLR 12.9–13.7 dB and the breakdown minima may stay as they are).
- **Pool priority contradicts its doc.** `oneshot_pool.gd:161-167` takes the oldest sound regardless of
  priority when nothing is stealable; `probe_rt.gd`: 16 priority-0 sounds + one priority-2 `ui_hover` →
  played, one priority-0 sound stolen. The header says "never a high-priority one": drop the incoming
  sound (return false) instead.
- **3D scrape of other cars.** `_scrape_age` is shared with the player's scrape, a repeated contact of the
  same other car never refreshes it (`sound_mapper.gd:120-124` only acts when `_scrape_3d_id == 0`), so
  it is released and re-set every 0.15 s, and its position only moves on the re-set; "nearest" is "first".
- **Typed calls.** `audio_director.gd:278` `_bed.call("cutoff_hz")` (`_bed` is typed — call it),
  `world_emitters.gd:233` `director.call("play_3d", …)` (use the parent `AudioDirectorScript`).
- **Demo.** The pass-by moves `_moving` in `_process` while the doppler tracks physics steps: move it in
  `_physics_process`. After #1 the synth step must still show the whine on every loop of the demo.
  `spectrum.gd` (46) and `audio_demo.gd` (19) still carry bare literals; `spectrum.gd` has a −120 dB floor
  next to its own `DB_FLOOR = −60`.
- **Status accuracy.** False today: item 9 "every car has its own phase", item 2 "the scrape loop only
  runs during a contact" (one impact starts it), item 14 "no bare literals, no dead constants" (10 dead),
  "the river bed near the river" (never attached), "the world emitters now add the siren" (at −30 dB).
  Only claim what a command in "How to test" prints.
- **Leaks at exit** are 98 ObjectDB instances now (R2: 76). Keep your minimal one-player probe in
  `tmp/audio/` with its output so the lead can confirm it is the headless engine, not the unit.

## Verified OK
- `tools/godot.sh check --only=res://audio/` → `CHECK 30 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://audio/tests/test_audio.gd` → `AUDIO TEST 125 checks, 0 failed`; synth CPU
  **5.76 %** of one core (ev 1.11 %, thruster 4.65 %) at load 22.3 — inside 8 %.
- **A-INT1 (lead):** `drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu` → 0 lines with
  `res://audio`; my 60 s main.tscn timeline reached t = 52 s (then a renderer FATAL, reflection-probe index
  — not audio) → 0; my two sandbox movies → 0. The unit test has the error counter around the pool and
  the emitters.
- No clipping: my 30.5 s full-mix capture I −16.9 LUFS, LRA 7.2 LU, sample and true peak **−1.9 dBFS**;
  your `captures/audio/gameplay.mp4` 31.15 s, I −17.0 LUFS, peak −1.9 dBFS. The capture is real gameplay
  (`rv_full_sheet.jpg`: 85/262/251/250/134/215 km/h, pursuit HUD).
- Thruster hiss: amplitude centroid 3.47–3.59 kHz, power 2.89–3.03 kHz, peak 3.15 kHz, attack 26 ms,
  release 123 ms; chuff 14.9 dB in 0.8–1.8 kHz, 90 Hz puff −13.9 dB. Matches DOSSIER §6.1.
- SFX bus transparent outside slow-mo (`probe_bus.gd`): `impact_light` through SFX vs the Master
  reference: correlation 0.996, 0 ms extra latency; the slow-mo adds 24 ms (pitch shifter only then).
- Music: PLR 13.3 / 13.7 / 12.9 dB, short-term minimum −22.4 / −23.5 / −23.5 LUFS (no breakdown holes).
- Beds: `road_roll` 2.5/57.6/33.6/5.3/1.0 % (≥ 50 % below 1 kHz), `boost_roar` 13.4/35.6/47.0/4.0/0 %.
- Demo: 100 steps (1 synth, 23 sfx, 12 loops on their own player, 3 music, 61 voice), `CAPTURE errors=0
  warnings=0`, meter bars in `#19E6FF` with `#F2F6FF` text, readable at 0.4× (`demo_sheet_r3.jpg`).
- Voice channels independent, P0 never times out, ducking −6 dB while any channel talks (tests).
- Ownership: every Write/Edit of this round is in `game/audio/**`, `tools/audio/**`, `status/audio.md`;
  largest file `audio_director.gd` 397 lines; static typing throughout.

## Evidence
- Check/test: `tmp/review/audio/r3/check.txt`, `test.txt`.
- A-INT1: `smoke18_out.txt`, `smoke60_out.txt` (+ `smoke60.csv`, last row t = 52.06 s).
- `tools/godot.sh movie --movie=…/captures/review/audio/r3/rv_full.avi --timeline=res://audio/capture/gameplay_timeline.json
  --skip-menu --stub=world --log=…/rv_full.csv` (and `rv_nomusic` with `--mute-music`), kept as `rv_full.mp4` / `rv_nomusic.mp4`;
  ebur128 as above; `an_drive.py <mono 48 kHz wav of rv_nomusic> rv_nomusic.csv` → whine prominence median 5.4 dB, 90th pct 8.6 dB.
- `probe_ev.gd` → `EVCASE A −15.0 / B −45.5 / C −45.5 / D −45.5 dBFS`, `EVCYCLE` holds −4.8 … −12.9 dBFS;
  `an_ev.py` → sweep up −15.6 → −22.0, down −14.9 → −8.4, cycles sample peak +1.0 dBFS.
- `probe_movie.gd` (movie via `tools/slots.py heavy`, test_host) + `an_probe_movie.py` → phase B 600 Hz
  −61.8 dBFS (8.5 dB), phase C −13.4 dBFS (57.8 dB); fan line −43.5 dBFS.
- `probe_siren.gd` → `EMITTER siren_yelp.ogg volume_db -30.0 unit_size 8.0 at 20.0 m`; floor −66.6,
  placed siren −65.1, 2D reference −26.0 dBFS.
- `probe_rt.gd` → `probe_rt_out.txt` (sirens 4/19/4 switches, scrape −8.5 dB after one impact,
  `final_lap` at lap 2 of 2, `heat_up` on 4 → 3, pool steal, pause: 2 beeps / 2 + 3 un-paused).
- `probe_bus2.gd` → `EvVoice -> Master`, `ThrusterVoice -> Master`.
- Images: `captures/review/audio/r3/spec_combo.jpg` (drive vs demo spectrogram), `demo_sheet_r3.jpg`,
  `rv_full_sheet.jpg`; demo shots `review_audio_r3_t{3,30,60,86,110}_0.jpg`; probe audio
  `probe_movie.flac`, `probe_siren.flac`, `probe_bus.flac` (all in `captures/review/audio/r3/`).

## Lead notes status
- A-INT1: **satisfied** (0 audio errors in every run listed above).
- Project rules: tests extend Node ✓; runs end by themselves ✓; scratch hygiene ✗ (MUST-FIX 9).
- Cross-unit requests still open (not blocking you): camera `doppler_tracking` (0 hits in game/vehicle),
  modes `set_total_laps()`, world `river` POI.
