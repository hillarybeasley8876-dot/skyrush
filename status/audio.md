# audio status

Round 4 (review round 3 closed: 9 MUST-FIX + 9 SHOULD-FIX). The hero sound is back: the motor
whine is a stable, level-correct voice that is audible in the game (the prominence over the
local floor went from 5.5 dB to 37.4 dB in the same measurement), the world emitters are
audible, the game pause does not leak and the siren alternation is regular.

Two real bugs were found in this round, both of them the reason the review said "the hero sound
is gone":

* **the drive voice was a two term recurrence** (`y[n] = 2 cos(w) y[n-1] - y[n-2]`). Its state was
  zeroed at a standstill, so a voice that was ever rendered at rest stayed silent forever, and
  the amplitude drifted with 1/sqrt(sin w) whenever the rpm moved (±10 dB, a sample peak of
  +1.0 dBFS). It is now a **quadrature rotator** (the state is the unit vector of the phase, it
  is renormalised once per block and it is never reset).
* **the drive voice was doppler shifted.** The chase camera does not track its velocity (the
  open request to the camera unit), so the engine pulled the motor note down by a fifth
  (f0 x 0.8) at 250 km/h. The whine was therefore at the wrong frequency and buried in the
  mix. The voice of the player's own car is not doppler shifted any more.

## Done

### 1. The motor whine (MUST-FIX 1, the hero sound)
- `synth/ev_synth.gd`: the four partials are quadrature rotators (`nc = c*cw - s*sw; s = c*sw +
  s*cw`, the coefficients per block from the frequency, `c, s` renormalised by 1/sqrt(c²+s²)
  once per block, the phase starts at (1, 0)). The state is never zeroed: a standstill only
  mutes the gain, so the voice comes back at the same level.
- **Measured** (the review's own `probe_ev.gd`): the cases A/B/C/D (fresh, spawn at rest,
  drive-stop-drive, idle throttle) all read **-15.0 dBFS** (before: A -15.0, B/C/D -45.5), the
  five rpm cycles hold at **-15.0 dBFS** (before: -4.8 … -12.9) and the sample peak is
  **-9.1 dBFS** (before: +1.0). The sweeps (3000 <-> 15000 rpm) are flat within **0.1 dB**
  (before: 6.4 dB).
- The unit test covers it: `audio_test_motor.gd` measures the recovery after a standstill
  (+/- 0.5 dB) and the stability over 5 rpm cycles (the level and the peak).

### 2. The world emitters are audible, and the river bed exists (MUST-FIX 2)
- `emitter_collection.gd` + `world_emitters.gd`: every emitter kind has its own mix trim and
  audio sphere (`SIREN_EMITTER_DB = 0.0`, `SIREN_UNIT_SIZE_M = 20`, `HUM_EMITTER_DB = -6.0`,
  `HUM_UNIT_SIZE_M = 6`, `RIVER_EMITTER_DB = -8.0`, `RIVER_UNIT_SIZE_M = 30`). The old
  `EMITTER_START_DB = -30 dB` is gone.
- Every emitter **fades in and out** (`EMITTER_FADE_S = 0.3 s`, 133 dB/s): the level steps
  **1.1 dB per frame**, never more than the 6 dB the review asked for.
- The **river bed** is created at the nearest "river" point of interest of the world (and fades
  out when the player leaves the river).
- **Measured** (the review's `probe_siren.gd`, movie mode): the siren of a patrol car 20 m away
  is at **-30.6 dBFS** (before: -65.1, the review asked for >= -32), the 2D reference is at
  -25.6 dBFS. The unit test checks the mix level, the audio sphere and the smoothness of the
  fade in and of the fade out, and a world double publishes a "river" POI 50 m away (the test
  finds one river emitter above the silence).

### 3. The two synth voices play on the SFX bus (MUST-FIX 3)
- `audio_director.gd` sets `bus = &"SFX"` on both voices, so the SFX volume of the settings and
  the slow-motion effect (the pitch shift and the low pass) reach the motor, the fan, the hiss,
  the hop tone and the chuff.
- **Measured** (the review's `probe_bus2.gd`): `EvVoice -> SFX`, `ThrusterVoice -> SFX`.

### 4. The game pause does not leak (MUST-FIX 4)
- The two event mappers and the world emitters are `PROCESS_MODE_PAUSABLE` (their signals still
  arrive, their per frame logic does not run), the director keeps its own logic on `ALWAYS`.
- The emitters re-apply the pause every frame (`_apply_pause()`), because **Godot 4.7 only
  takes the pause of a 3D player while the tree is paused** (the emitter players therefore run
  on `PROCESS_MODE_ALWAYS` and are paused by the flag).
- The one-shot pool drops the gameplay sounds while the game is paused; the ui sounds of the
  pause menu still play.
- **Measured** (the review's `probe_rt.gd`): 9 s of pause -> **0** battery beeps, **0** one-shots
  played, **0** sirens playing un-paused, **0** un-paused one-shots. The unit test adds the
  ui_click check.

### 5. The siren alternation is regular (MUST-FIX 5)
- Every patrol car has its **own countdown** (the cars are spread over the half period, so no
  two cars switch in the same scan) and the switch is a **crossfade**: the wail and the yelp play
  all the time on two players, so a switch never restarts a sample and never cuts.
- **Measured** (the review's `probe_rt.gd`): three patrol cars at 60/80/100 m, heat 4, 24 scans:
  every car switches **4 times in 12 s** (before: 4 / 19 / 4) and no two cars switch in the
  same scan. The unit test counts the switches of every car and checks that they never clash.

### 6. The race and collision logic (MUST-FIX 6)
- The last lap is announced when the player has finished `total - 1` laps (`lap != total - 1`),
  not on the finish line.
- The pursuit line is only for a **rising** heat (4 -> 3 announces nothing).
- A scrape needs a **repeated** contact: the same car has to hit again within `SCRAPE_REPEAT_S =
  0.2 s`. A single hit is an impact, not a scrape.
- The scrape of another car follows the car that is scraping (it used to be released and set
  again every 0.15 s) and the **nearest** car wins (it used to be the first one).
- The cooldowns follow the **game clock** and not the wall clock, so they behave the same in a
  fast test run and they stop while the game is paused.

### 7. The tests catch the bugs of this round (MUST-FIX 7)
`game/audio/tests/`: `audio_test_motor.gd` (the recovery, the stability), `audio_test_emitters.gd`
(new: the levels, the fades, the river, the siren switches), `audio_test_runtime.gd` (the synth
buses, the audio sphere, the doppler), `audio_test_gameplay.gd` (the laps, the heat, the scrape,
the pause leaks, the 120 contacts over a second of physics frames).
- **159 checks, 0 failed** (before: 125).

### 8. The code rules (MUST-FIX 8)
- `deadconst.py` (the review's checker): **0 dead tuning constants, 0 bare literals in the
  function bodies** (before: 10 and 72). The stale `HISS_*` constants are gone (the generator
  is the single source of the hiss chain) and the header of `thruster_synth.gd` now names the
  real numbers (5 kHz low pass, +6 dB peak at 3.5 kHz).
- The dead debug hook `OS.has_feature("dbg_no_sfx_fx")` is deleted, the layout slips are fixed
  (the blank lines before `set_scrape`, `_on_vehicle_wrecked` and `# --- per frame`), and
  `music_bed.gd` declares its `_state` with the other members.
- The typed calls are gone: the emitters ask for a one-shot through the `one_shot_requested`
  signal (the director plays it through its pool), the director calls `bed.cutoff_hz()`.

### 9. The scratch hygiene (MUST-FIX 9)
- The 66 files the review listed in `tmp/review/audio/r3/tmp_targets.txt` are deleted from
  `/tmp` (and `/tmp/audio_director_backup.gd`), `tools/audio/__pycache__` is gone and every
  python tool runs with `PYTHONDONTWRITEBYTECODE=1`. The scratch of this round lives in
  `tmp/audio/` and `tmp/audio/r4/`.
- One file of the review's list is still there: `/tmp/dbg6.py`. It is the **city** unit's
  scratch (it loads `data/city/city.json` and the road profiles), not the audio unit's — the
  review's list was built by timestamp. It was left alone, because deleting another unit's
  in-flight scratch is not the audio unit's business.

### 10. The horns are horns and not door chimes (SHOULD-FIX)
- `tools/audio/gen_world.py`: the horns are a **band-limited saw pair** (415/523 Hz for the
  traffic horn, 350/440 Hz for the police air horn) with a **flat sustain** (30 ms attack, 80 ms
  release), a 5.5 Hz vibrato of 7 cents, a resonant peak at 2.5 kHz, a two pole low pass at 3 kHz
  and a soft drive. Before: three pure sines under an exponential decay (a door chime).
- **Measured**: the traffic horn has **32 %** of its energy above 1 kHz, the police horn **30 %**
  (before: 0 % and 3 %; the review asked for >= 25 %).

### 11. The wind bed is a wind and not a hiss (SHOULD-FIX)
- The buffeting layer is a brown noise low pass at 320 Hz (it was a narrow band at 200 Hz).
- **Measured**: `wind_rush` has **7.0 %** of its energy below 200 Hz and **41.7 %** below 1 kHz
  (before: 0.5 % and 28.5 %; the review asked for >= 5 % and >= 40 %).

### 12. The music has a true peak ceiling (SHOULD-FIX)
- `tools/audio/metering.py`: the true peak is measured with a windowed sinc oversampler (the
  cubic interpolation under-read the peaks by 0.8 dB), `tools/audio/mastering.py` holds the
  true peak under the ceiling with a final gain trim, and the music is mastered at -3.3 dBTP
  (the vorbis encoder overshoots the peaks of a dense mix by 0.5-1.5 dB).
- **Measured** (ebur128 on the delivered files): cruise **-2.0**, pursuit **-1.5**, race **-2.2
  dBTP** (before: -0.7 / -0.4 / -1.1; the target is <= -1.5). The PLR is 10.7-12.4 dB (the limit
  of the analyzer is 10) and the short term minimum of the breakdown is -22.2 … -23.4 LUFS (the
  limit is -24). The music is encoded with q8.

### 13. The pool never cuts an important sound (SHOULD-FIX)
- A sound may only steal a sound that is **less important** than itself (a lower priority
  number means a more important sound). When nothing may be stolen, the incoming sound is
  dropped. **Measured** (the review's `probe_rt.gd`): 16 priority-0 sounds + one priority-2
  sound -> the priority-2 sound is **not** played and the 16 important ones are untouched.

### 14. The demo and the spectrum helpers (SHOULD-FIX)
- The demo's pass-by moves in `_physics_process` (the doppler follows the physics steps).
- `spectrum.gd` and `audio_demo.gd` have no bare literals any more and the spectrum helpers
  name their constants (the -120 dB floor is `SILENT_DB`).

### 15. The files are under 400 lines again
`world_emitters.gd` (480) was split into `emitter_collection.gd` (the voices, the fades, the
scan of the scene groups) and `world_emitters.gd` (the sirens and the river), `audio_director.gd`
(420) into `audio_director.gd` (371) + `player_voices.gd` (the telemetry -> the voices) and the
slow motion moved into `bus_setup.gd`. The biggest file is now **359 lines**.

## In progress / next
- Nothing outstanding. Optional polish: the police siren could be a little brighter in the
  1-4 kHz band, and the music's crest factor (PLR 10.7 dB) is lower than round 2 (13 dB)
  because of the true peak ceiling.

## How to test (exact commands)
- `tools/godot.sh check --only=res://audio/` -> "CHECK 35 files, 0 failed, 0 engine errors, 0 warnings"
- `tools/godot.sh test res://audio/tests/test_audio.gd` -> "AUDIO TEST 159 checks, 0 failed"
  (the synth CPU check prints the measured percentage and skips itself on a busy machine)
- `tools/godot.sh drive --timeline=res://audio/capture/gameplay_timeline.json --skip-menu
  --stub=world --log=$HOME/m/skyrush/captures/audio/gameplay.csv` -> the 30 s drive with the
  telemetry log (`grep -c "res://audio"` = 0, the lead's A-INT1 check)
- `tools/godot.sh movie --movie=$HOME/m/skyrush/captures/audio/gameplay.avi
  --timeline=res://audio/capture/gameplay_timeline.json --skip-menu --stub=world` then
  `ffmpeg -i gameplay.avi -map 0:v -map 0:a -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac
  -b:a 192k gameplay.mp4`
- The same run without the music (the whine measurement):
  `tools/godot.sh movie --movie=$HOME/m/skyrush/captures/audio/gameplay_nomusic.avi
  --timeline=res://audio/capture/gameplay_timeline.json --scene=res://audio/capture/nomusic.tscn
  --skip-menu --stub=world --log=$HOME/m/skyrush/captures/audio/gameplay.csv`
- The whine prominence (the review's `an_drive.py`):
  `python3.13 -I tmp/audio/r4/an_drive.py captures/audio/gameplay_nomusic.wav
  captures/audio/gameplay.csv nomusic` -> "median 37.4 dB" (the target is >= 20 dB)
- The spectrogram: `ffmpeg -i captures/audio/gameplay_nomusic.wav -lavfi
  "showspectrumpic=s=1400x600:legend=1:scale=log:stop=3000:gain=3"
  captures/audio/whine_spectrogram.jpg`
- `tools/godot.sh shot --scene=res://audio/demo/audio_demo.tscn --out=audio_demo --times=3,22`
- `python3 tools/audio/analyze.py` -> the QA table (99 files, 0 flagged; the music rows carry the
  PLR and the short term minimum)
- The review's own probes (they run against the shipped code):
  `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/audio/r3/probe_ev.gd`,
  `.../probe_rt.gd`, `.../probe_bus2.gd`
- Rebuild the assets: `tools/audio/build.sh` (add `--voice` to re-download the TTS lines), then
  `tools/godot.sh import && python3 tools/audio/patch_loop_imports.py && tools/godot.sh import`

## Evidence
- `captures/audio/gameplay.mp4` — 30.5 s of real gameplay (the stub world, the car accelerates
  to 260 km/h, drifts, lights the nitro, hops, rolls and brakes): **I -16.1 LUFS, LRA 4.4 LU,
  true peak -1.8 dBFS** (no clipping).
- `captures/audio/gameplay_nomusic.wav` + `captures/audio/gameplay.csv` — the same run without
  the music: the review's `an_drive.py` reads a **whine prominence of 37.4 dB (median) and 39.5 dB
  (90th pct)** over the local floor, with the best offset at 0.25 s (before: 5.5 dB).
- `captures/audio/whine_spectrogram.jpg` — the spectrogram of that run: the bright curve of the
  fundamental (213 Hz at the idle -> 1000 Hz at 250 km/h), the 2.76x inverter partial and the
  drop of the curve when the car brakes.
- `captures/audio/demo.mp4` + `captures/audio/demo_spectrogram.jpg` — the demo (100 steps): the
  synth step shows the sweeping whine and its inverter partial, `tools/godot.sh shot` reports
  **errors=0 warnings=0**, and the meter reads "peak -13.1 dBFS, RMS -19.2 dBFS, 2-4 kHz 3 %"
  on the synth step (`captures/audio_demo_t3_0.jpg`).
- `captures/audio/r4/probe_movie.wav` — the review's `probe_movie.gd`: the shipped drive voice
  at 150 km/h puts the **600 Hz line at -14.5 dBFS, 55.7 dB over the floor** (the review asked
  for >= 40 dB; before: -61.8 dBFS, 8.5 dB).
- `captures/audio/r4/probe_siren.wav` — the review's `probe_siren.gd`: the siren of a patrol car
  20 m away at **-30.6 dBFS** (the floor is -66.7 dBFS, the 2D reference is -25.6 dBFS).
- `tmp/audio/r4/probe_ev.gd` (the review's probe, a copy) -> `EVCASE A/B/C/D -15.0 dBFS`,
  `EVCYCLE 0-4: -15.0 dBFS`; `tmp/audio/r4/an_ev.py` -> the sweeps flat within 0.1 dB, the sample
  peak -9.1 dBFS.
- `tmp/audio/r4/probe_rt.gd` (the review's probe, a copy) -> the sirens 4/4/4 switches, the
  scrape silent after one impact, no line on the last lap of a finished race, no line on a
  falling heat, the priority-2 sound dropped, and 0 leaks in 9 s of pause.
- The unit test: **159 checks, 0 failed**; the synth CPU **6.4 - 7.9 % of one core** (ev
  1.5 - 1.7 %, thruster 4.9 - 6.2 %) on a machine with a load average of 33 - 56 (the budget
  is 8 %; the review measured 5.8 % at a load of 22).
- `tools/audio/analyze.py`: 99 files, 0 flagged; the music PLR 10.7-12.4 dB, the short term
  minimum -22.2 … -23.4 LUFS; the radio at -31.5 dB below 250 Hz, the announcer at -16.0 LUFS,
  the radio at -18.0 LUFS.
- The scratch: `tmp/audio/leak_probe.gd` (the review's request: a minimal one player probe) with
  its output in `tmp/audio/leak_probe_out.txt` — **one** `AudioStreamPlayer` that plays one OGG,
  is stopped and freed leaks **4** ObjectDB instances in Godot 4.7.2 (the engine's own). The
  unit test's count is the audio server's deferred release of the OGG playbacks and it varies
  between 0 and 150 with the load of the machine (the verbose log shows only
  `AudioStreamOggVorbis`, `AudioStreamPlaybackOggVorbis` and `OggPacketSequence` instances, no
  node of the unit).

## Known issues
- The **leaks at exit** are the Godot AudioServer's playbacks, not the audio unit: the minimal
  probe above leaks 4 objects on its own, and the verbose log of the unit test only lists the
  OGG stream and playback objects (the nodes, the players and the cache of the unit are
  released). The count of the unit test varies with the load of the machine (0 … 150).
- The **CPU measurement** is sensitive to the machine load (the other units run Godot in
  parallel): 6.4 - 7.9 % at a load average of 33 - 56, the budget is 8 %. The test prints the
  measured value and skips the check on an oversubscribed machine.
- The headless test environment does not advance the audio clock, so the *playback* checks (a
  voice line finishing, a doppler frequency shift) cannot be measured there: the test checks
  the configuration (the doppler flags, the emitter following its target) and the voice logic
  (the queue order) instead, and the levels are measured from the recorded movies.
- The **world emitters need a listener**: the 3D sounds are attenuated by the distance to the
  camera, and the engine's attenuation law is `unit_size / (unit_size + distance)` (measured:
  -0.6 dB at 10 m, -3.8 dB at 20 m and -9.9 dB at 40 m with a sphere of 20 m). The mix trims
  of the emitters are chosen for that law.
- The ys-api **music** endpoint (`POST /api/suno`) answered `success:false` twice; per the brief I
  stopped there and composed the three loops procedurally instead.

## Requests
- **core**: the audio unit adds an `AudioEffectHardLimiter` (ceiling -1.0 dB) to the **Master**
  bus, a `MusicBed` sub-bus under `Music` and a pitch-shift + low-pass effect on the **SFX** bus
  (the slow-motion cam). Please confirm that this is acceptable, or say where they should live.
- **camera**: the player's own car sounds are **not** doppler shifted any more (the engine and
  the driver move together), but the **passing cars** still need it: GODOT.md §9 needs both the
  emitter and the camera set (`doppler_tracking = DOPPLER_TRACKING_PHYSICS_STEP` on every
  gameplay Camera3D). Grep finds 0 hits outside `game/audio/`. Without it a siren that passes the
  camera is not pitched down.
- **modes**: the announcer needs the lap count of the current race to call the last lap. The
  audio unit exposes `AudioDirector.set_total_laps(laps)`; please call it when a race starts
  (until then the last lap is not announced).
- **vehicle**: `boost_kind` stays "nitro" for ~25 s after the N₂ is spent. The audio unit drives
  the roar from the rear-nozzle telemetry, so it does not drone, but the flag should be cleared.
- **vehicle**: the car can get stuck after a hop (the airborne flag stays true, the speed drops to
  0 at y = 1.01). The capture timeline works around it, but the bug is worth a look.
- **world**: the audio unit looks for a point of interest of kind `river` to place the river bed.
  The sandbox does not publish one, so the river is silent in the stub world. Please add the river
  polyline (or a `river` POI) to `WorldBase.get_points_of_interest()`.
- **police / traffic**: the police radio lines already go through `play_voice`; the world emitters
  now add the siren, the traffic hum, the police horn and the traffic horn automatically, so the
  police unit does not have to place a siren by hand any more. A loop id cannot go through the
  one-shot pool any more (it needs `attach_loop`).
- **hud**: the voice subtitles come from the audio director's `voice_line(id, text, kind)` signal
  and `last_voice_text`; the manifest is `res://audio/voice/voice_lines.gd`
  (`const VoiceLines = preload(...)`, no class_name).
