# audio review round 4 — VERDICT: FAIL

Reviewer: lead's art director (Opus). Standing order "贴图纹理什么都要细化". For audio that means every sound
is layered and physically right, the mix is balanced, and nothing clicks, drones, spams or errors.
Everything below was measured. Scratch: `tmp/review/audio/r4/` (probes `probe_zip.gd`, `probe_xfade.gd` and copies
of the r3 probes; analysers `an_split.py`, `an_tonal.py`, `an_diff.py`, `an_repeat.py`, `an_voicegain.py`,
`an_assets.py`, `an_demo.py`, `an_mix.py`, `deadconst.py`). Captures: `captures/review/audio/r4/`. Run the
python with `/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I` (numpy).

Good news first: **all 9 MUST-FIX of round 3 are closed and verified**. The motor whine survives standstills, it is
level-stable and it is back in the game. The emitters are audible and fade. Both synths are on SFX. The pause is
tight. The sirens switch 4/4/4 times and never together. The laps, heat and scrape logic is right. There are 159
checks, 0 dead constants and 0 bare literals, and /tmp is clean. Lead note A-INT1 holds (0 audio errors in every
run). There is no clipping (−1.8 dBTP), the CPU is 6.7 %, and the check is clean.
Three defects remain. The first is a mix problem: now that the whine is back, it is the only thing you hear.

## Scores (0-10): function 7, visual/feel 4, code 7
- **function 7**: the acceptance list is met. Two new defects: a click on every throttle press/release, and a
  20 dB hole in every siren switch.
- **visual/feel (sound) 4**: at speed the car is ~95 % three pure sines. The road, wind and tyre beds sit 13–15 dB
  under it, there is no low end, the wind law of the dossier is not followed, and the voice lines play under the car.
- **code 7**: clean, typed, split, tested. But there is one false status claim (music_bed `_state`), stale comments, two
  weak tests, and scratch left behind.

## MUST-FIX

1. **The mix: the Roadster now sounds like a sine-wave test tone. The road, the wind and the voice lines are under it.**
   (brief goal "fast, heavy and alive"; gameplay DOSSIER §2.3 "wind ∝ v², sound sells speed", §8.5 "wind −20 → −4 dB
   with speed"; r1 #3(d) "road and wind clearly audible from 60 km/h")
   - Measured on my music-muted capture (`rv_nomusic_mono.wav`, gameplay_timeline, `an_split.py` / `an_tonal.py`):
     at a steady 250 km/h (14.5–18.5 s), **93.5–96.9 % of the car's power is the three sine partials**. The 1000 Hz
     fundamental alone is 86.4 % (−0.6 dB re total), 2.76× is −11.1 dB and 5.41× is −17.7 dB. All broadband layers
     together (road, wind, city bed) are 3.6 %: −27.2 … −30.7 dBFS against a whine of ≈ −17.5 dBFS. Below 200 Hz it
     reads −41 … −47 dBFS, so the car has no weight. Accelerating at 141–230 km/h it is 96–98 % tonal.
     main.tscn with music on (`rv_world_mono.wav`) is 90–97 % tonal. `spec_combo_r4.jpg` shows three bright lines on
     an empty floor.
   - Causes:
     - (a) The beds are mastered ~12 dB too low. `road_roll.ogg` and `wind_rush.ogg` are −29.8 dBFS RMS (peaks
       −16 dBFS), while the synth step of the demo is −16.2 dBFS. At 0 dB in the demo the road is −32.4 and the wind
       −32.3 dBFS.
     - (b) The laws in `loop_players.gd:148-151` are road 20·log(v/300) − 2 dB and wind 40·log(v/300) − 4 dB. In the
       game that puts the wind at ≈ −64 dBFS at 60 km/h and ≈ −39 dBFS at 250 km/h, and the road at ≈ −48 and −35 dBFS.
     - (c) The whine is at full level from 42 km/h on (`RPM_FULL` 2500 rpm), so it never grows with speed.
     - (d) road_roll and wind_rush are **2.00 s loops**. At 250 km/h they repeat every 1.64–1.75 s, and
       `an_repeat.py 14.2 18.8` already finds the 1.75 s road period while it is still buried. Raised, it is
       audible tiling.
   - Voice and music sit under the car. In game the announcer plays 4.0 dB under its file and the radio 6.1 dB under
     (`an_voicegain.py` on my demo movie). Against the cruising car (−16.8 LUFS mono) the **announcer is 3.2 LU under
     and the police radio 7.3 LU under**, and the 1 kHz and 2.76 kHz partials sit right in the speech band. The cruise
     music is −22.8 / −23.7 LUFS against the car's −13.8 / −14.5 LUFS, i.e. 9 LU under (`an_diff.py`, stereo).
   - Do:
     - (i) Normalise every loop bed in the generators to −18 dBFS RMS ±1 dB and re-derive the trims.
     - (ii) Wind: −20 dB at 0 km/h → −4 dB at 300 km/h, e.g. `−20 + 16·(v/300)^1.5`. Road: −18 dB at 20 km/h →
       −3 dB at 300 km/h. Put the numbers in `audio_tuning.gd`.
     - (iii) Give `road_roll` a rumble layer (a 40–160 Hz brown-noise band with a slow 2–6 Hz swell) so that ≥ 12 % of
       its power is below 200 Hz (now 2.5 %).
     - (iv) Re-render road_roll and wind_rush as ≥ 8 s seamless loops, or as two decorrelated layers of 5.3 s and 7.9 s.
     - (v) Lower the drive voice ~4 dB at cruise (`EV_OUTPUT_GAIN_DB` −2 → −6) and let it rise with rpm instead of
       saturating at 2500 rpm, e.g. level × (0.6 + 0.4·rpm/15000).
     - (vi) While a voice line plays, duck the SFX bus by 4 dB with the music-duck ramp (new `SFX_DUCK_DB`), and drop
       the −2 dB radio trim.
     - (vii) Keep the 30 s full mix at −16 … −12 LUFS (stereo) and ≤ −1 dBTP.
   - Verify: capture with `tools/godot.sh movie --movie=$HOME/m/skyrush/captures/audio/nomusic.avi
     --timeline=res://audio/capture/gameplay_timeline.json --skip-menu --stub=world --mute-music --log=<csv>`, then
     convert with `ffmpeg -i x.avi -vn -ac 1 -ar 48000 -c:a pcm_s16le x.wav`. Then:
     - `an_split.py x.wav <csv>` at 14.5–18.5 s: tonal 40–70 %, broadband ≥ −23 dBFS, <200 Hz ≥ −35 dBFS.
       At 22.5–28.5 s: tonal ≤ 80 %.
     - `an_tonal.py x.wav 15.0 18.5 1000`: f0 ≤ −3 dB re total.
     - `an_assets.py`: road_roll ≥ 12 % below 200 Hz, both beds ≥ 8 s long.
     - `an_repeat.py x.wav 14.2 18.8`: no lag with corr > 0.1.
     - On the full mix, `an_diff.py`: music 4–7 LU under the car.
     - An announcer line over the 250 km/h cruise is ≥ +3 LU above the car. Measure it in a capture with a line, or
       mix the file at the in-game gain (−4.0 dB) into the cruise segment.
     - ebur128: I −16 … −12 LUFS, TP ≤ −1 dBTP.

2. **Every throttle press and release clicks in the drive voice.** `ev_synth.gd:146-151` computes the four partial
   gains once per block and holds them. A keyboard throttle moves `motor_load` 0 ↔ 1 within one frame
   (`vehicle/modules/drive.gd:46`), so in one sample the fundamental steps +6.9 dB (WHINE_LEVEL 0.45 → 1.0) and the
   partials step 8–11 dB. The `f > MOTOR_MIN_HZ` and Nyquist gates and `active` do the same.
   `probe_zip.gd` (offline, 800-sample blocks) at 3600 rpm (60 km/h): the press puts a jump of 0.0445 into the
   waveform, **7.7× the largest step of the steady voice**, and the release 5.2×. At 9000 rpm the release is 4.4×.
   The Big Hop tone is also hard-gated at release (`thruster_synth.gd`, `if hop > Tuning.HOP_ACTIVE_EPSILON`).
   - Do: keep the previous block's gains and ramp them per sample across the block
     (`g = g_prev + (g_new − g_prev) * float(i) / float(frames)`), or smooth each gain per sample with a one-pole
     `EV_GAIN_SMOOTH_S = 0.005`. Ramp the hop tone out over 20 ms when `hop_charge` falls to 0.
   - Verify: `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/audio/r4/probe_zip.gd` must show press and
     release steps ≤ 1.2× the steady max step at 3600, 9000 and 15000 rpm. Copy the check into `audio_test_motor.gd`.
     The synth CPU must stay ≤ 8 %.

3. **The siren crossfade cuts a 20 dB hole into every wail↔yelp switch** (a defect of the r3 #5 fix).
   `emitter_voice.gd:112-117` interpolates both players linearly **in dB** between the voice level and SILENT_DB
   (−60). The 50 ms crossfade is two frames at 60 fps (mode 0.33 and 0.67), and in those frames the samples sit at
   −20 / −40 dB, so the siren nearly vanishes.
   `probe_xfade.gd` (movie mode, patrol car 60 m away, heat 4, switches at 3.0 / 6.0 / 9.0 s): at each switch the
   5 ms level drops **18.6–20.2 dB** under its median for **30–35 ms**. Between switches it varies by 0.9 dB.
   Every patrol car beyond 40 m at heat ≥ 3 stutters every 3 s.
   - Do: use an equal-power crossfade in linear gain: `g_main = cos(mode * PI / 2)`, `g_standby = sin(mode * PI / 2)`,
     `volume_db = level + linear_to_db(maxf(g, db_to_linear(Tuning.SILENT_DB)))`. Lengthen `SIREN_CROSSFADE_S` to
     0.15 s so that one frame's volume step stays ≤ 3 dB.
   - Verify: run `probe_xfade.gd` (the command is in its header). Within ±0.3 s of a switch, no 5 ms window may fall
     more than 3 dB under the median. Add a unit check that the summed power of the two players stays within 1 dB of
     the voice level at mode 0.25, 0.5 and 0.75.

## SHOULD-FIX
- **The car drones when it is stuck.** `player_voices.gd:33` sets `rpm = max(speed·60, throttle·3200)`. In main.tscn
  (`rv_world`, 9.5–17.5 s) the car was pinned against a wall at 0 km/h with the throttle held, and it whined at
  213 Hz, −17 dBFS, 96 % tonal, for 8 s. Let the idle-throttle floor decay to 0 over ~1 s while the speed stays below
  2 km/h, or follow the wheel spin.
- **World emitters against the car.** The siren at 20 m is −30.4 dBFS, 13 dB under the cruising car. A traffic hum at
  15 m computes to ≈ −48 dBFS (asset −31.8 dBFS RMS, −6 dB trim, 6 m sphere), which is inaudible. After MUST-FIX 1:
  the siren at 20 m should be within 6 dB of the car, and a passing traffic car ≥ −36 dBFS at 10 m.
- **Whine detail (细化).** The voice is three pure sines. Add slow pitch jitter (±0.3 %, 2–5 Hz), a load-dependent
  gear-mesh line and a faint PWM band (8–10 kHz, −36 dB), and keep the fundamental ≤ 60 % of the voice power. The tyre
  squeal's fundamental (1066 Hz × 0.92–1.12) lands on the 1000 Hz whine at 250 km/h, so the two beat. Move it to
  1.6–2.2 kHz.
- **Code.** Status item 8 is false: `music_bed.gd:103-105` still declares `var _state` between functions, under the
  doc comment of `set_state`, which now sits at :118 without its doc. Move `_state` to the members and give the doc
  back. Stale comments: `tests/audio_test_motor.gd:83` ("the recurrence of the oscillators") and `audio_tuning.gd:127`
  (`MOTOR_MIN_HZ`: "a zero frequency is unstable"; the rotators are stable). Two functions are glued to the previous
  one with no blank lines: `tests/audio_test_motor.gd:85` and `tests/audio_test_spectrum.gd:133`.
- **Tests.** "the river bed is audible (−40.0 dB)" passes on the first frame of the fade-in. Assert that it reaches
  `RIVER_EMITTER_DB` within `EMITTER_FADE_S` + 0.1 s. The CPU check SKIPs whenever the load is above 1.5 per core,
  which is every run on this machine. On a SKIP, still fail above 2× the budget so a regression shows.
- **Emitter edge cases.** `_has_emitter()` counts an emitter that is fading out, so a car that re-enters range during
  the 0.3 s fade stays silent until the next scan (~0.8 s gap). Revive it with `set_mix_db()`.
  `sound_mapper.gd` `_impact_times` / `_contact_times` keep a key for every car ever hit; prune entries older than 1 s.
- **Status accuracy.**
  - "I −16.1 LUFS" was measured on the mono downmix `gameplay.wav`. The stereo mp4 of the identical run is −13.2 LUFS.
  - "0 res://audio errors in 108 553 lines": the logged command (log line 26330) counted `tail -3` only. My runs
    confirm 0, but quote the full count.
- **Scratch (lead rule).** Delete `captures/audio/demo.avi` (74 MB, next to its mp4) and `tmp/audio/voice/` (63 raw
  TTS files from 03:00) when done.

## Verified OK
- **r3 #1, drive voice.**
  - `probe_ev.gd`: A/B/C/D −15.0 / −15.0 / −15.0 / −15.1 dBFS; the 5 rpm cycles hold −15.0 dBFS each.
  - `an_ev.py`: sweeps flat within 0.1 dB, sample peak −8.8 / −9.1 dBFS.
  - `an_drive.py` on my music-muted capture: prominence median 37.0 dB, 90th percentile 39.5 dB; the curve is visible.
- **r3 #2, emitters.**
  - `probe_siren.gd` (movie): floor −66.5 dBFS; the placed siren at 20 m reads −30.4 … −30.9 dBFS steady (−32.2 in
    the fade-in second); the 2D reference is −25.8 dBFS. The largest 10 ms step is 3.1 dB.
  - The tests cover the 20 m sphere, the 0 dB trim and the river emitter.
- **r3 #3–#7.**
  - `probe_bus2`: EvVoice → SFX, ThrusterVoice → SFX.
  - `probe_rt`, 9 s of pause: 0 one-shots, 0 beeps, 0 un-paused sirens or one-shots.
  - Sirens: 4/4/4 switches, at scans 4/10/16/22, 3/9/15/21 and 1/7/13/19.
  - Lap 2 of 2 and heat 4→3 give no line. One impact leaves the scrape at −60 dB. 120 contacts in 1 s give 7 impacts.
  - 159 checks, 0 failed.
- **r3 #8, code.**
  - `deadconst.py`: 0 dead constants, 0 bare literals.
  - Largest file 371 lines (audio_director.gd); tools ≤ 338 (dsp.py).
  - No untyped var, param or return in `game/audio`; `call()` only in tests and `capture/nomusic.gd`.
- **r3 #9, scratch.** Of my list only `/tmp/dbg6.py` and `/tmp/dbg7.py` remain. They import `blender/city/roads` and
  are the roads unit's (also in `jobs/roads/log.jsonl`), so this is accepted. There is no `tools/audio/__pycache__`,
  and round 4 wrote nothing to /tmp.
- **r3 SHOULD.**
  - Horns: 35.3 % (traffic) and 33.6 % (police) of their power above 1 kHz.
  - wind_rush: 11.9 % below 200 Hz, 46.7 % below 1 kHz.
  - Music true peak: −2.0 / −1.5 / −2.2 dBTP.
  - Pool priority: the priority-2 sound is dropped and the 16 priority-0 sounds are untouched.
  - Typed calls fixed; the demo's moving source updates in `_physics_process`.
- **A-INT1 (lead).**
  - `drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu`: `DRIVE done t=18.0 errors=0`, 0
    `res://audio` lines out of 1,734.
  - 60 s main.tscn drive: 0 audio lines up to t = 39.8 s, where it hit a renderer FATAL `Index p_index = -1 …
    size() = 64` that is not audio.
  - main.tscn movie: errors=0. Stub movies: 0 audio lines; only the damage unit's `dent_painter.gd` parse errors.
- **No clipping.** 30.5 s full mix: sample peak −1.9 dBFS, true peak −1.8 dBTP, I −13.2 LUFS (stereo), LRA 4.7 LU.
  main.tscn movie: peak −1.9 dBFS.
- **CPU.** Best of 40 renders: 6.68 % of one core (ev 1.56 %, thruster 5.12 %) at a load of 64.9.
- **Check.** `CHECK 35 files, 0 failed, 0 engine errors, 0 warnings`.
- **Leaks.** A `--verbose` run leaked 78 instances, all OGG objects (28 OggPacketSequencePlayback, 28
  AudioStreamPlaybackOggVorbis, 11 OggPacketSequence, 11 AudioStreamOggVorbis). None is a node or script of the unit,
  so this is the engine's and accepted.
- **Demo.**
  - My 200 s movie: errors=0. All 61 voice steps sound (no silence ≥ 1 s in 97.6–200 s).
  - The 8 silent stretches in the sfx section are the tails of the 8 short one-shots.
  - Captions and meters use #19E6FF on #F2F6FF text and are readable (`demo_sheet_r4.jpg`).
- **Voice lines.** Every line the brief lists (三/二/一/出发 … 重型车辆准备拦截) is in `voice_lines.gd`: 61 lines (45
  announcer, 16 radio).
- **Thrusters (test).** Amplitude centroids 3471 / 3486 / 3558 Hz, power centroids 2.92–3.00 kHz, attack 27 ms,
  release 124 ms.
- **Ownership.** Every round-4 Write/Edit is in `game/audio/**`, `status/audio.md` or `tmp/audio/**`, and no python
  heredoc wrote outside them. Tests extend Node, and every run ends by itself.

## Evidence
- `tools/godot.sh check --only=res://audio/` → `tmp/review/audio/r4/check.txt`
- `tools/godot.sh test res://audio/tests/test_audio.gd` → `test.txt` (159/0). The `--verbose` leak list is in
  `test_verbose_leaks.txt`.
- Probes:
  - `tools/godot.sh test …/r4/probe_ev.gd`, `probe_rt.gd`, `probe_bus2.gd`, `probe_zip.gd` (outputs `*_out.txt`).
  - Movie probes `probe_siren.gd` and `probe_xfade.gd` via
    `python3 tools/slots.py heavy 4 --timeout 600 -- godot --path game --write-movie <avi> --fixed-fps 60 -s
    res://tools/test_host.gd -- --test=<probe>`. Audio: `captures/review/audio/r4/probe_siren.flac`, `probe_xfade.flac`.
- Gameplay:
  - `tools/godot.sh movie --movie=…/r4/rv_full.avi --timeline=res://audio/capture/gameplay_timeline.json --skip-menu
    --stub=world --log=…/rv_full.csv`, plus the same with `--mute-music` (`rv_nomusic`).
  - Kept as `rv_full.mp4`, `rv_nomusic.mp4` and the mono wavs; frames in `rv_full_sheet_r4.jpg`; spectrogram
    `spec_combo_r4.jpg` (top: full mix, bottom: no music).
- main.tscn:
  - `drive --timeline=…/r4/smoke60.json --skip-menu` → `smoke60_out.txt`.
  - The lead's smoke drive → `smoke18_out.txt`.
  - Movie of the smoke timeline → `rv_world.mp4`, `rv_world_sheet_r4.jpg`.
- Demo:
  - `tools/godot.sh shot --scene=res://audio/demo/audio_demo.tscn --out=review_audio_r4 --times=3,20,55,85,110`
    → `captures/review_audio_r4_t*.jpg`.
  - 200 s movie (`--scene=res://audio/demo/audio_demo.tscn`, end at 200 s) → `demo_full_mono.flac`; `an_demo.py`,
    `an_voicegain.py`.

## Lead notes status
- A-INT1: **satisfied** (0 audio errors in every run above).
- Project rules: tests extend Node ✓; runs end by themselves ✓; the scratch list of r3 is cleaned ✓ (two leftovers,
  see SHOULD-FIX).
- Cross-unit requests, open and not blocking:
  - camera: `doppler_tracking` (0 hits outside `game/audio`).
  - modes: `set_total_laps()` (0 callers).
  - world: a `river` POI (none, so the river bed never plays in main.tscn).
  - vehicle: the `boost_kind` flag.
