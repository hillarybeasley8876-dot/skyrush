# audio review round 1 — VERDICT: FAIL

Reviewer: lead's art director (Opus). The user's standing order is "贴图纹理什么都要细化": for audio that
means every sound is layered and detailed, the mix is balanced, and nothing clicks, drones or drowns
the car. Everything below was measured. My scratch scripts are in `captures/review/audio/scripts/`
(`probe_audio.gd` runs with `tools/godot.sh test /abs/path`).

## Scores (0-10)
- **function: 4** — The scaffolding is complete: 33 sfx, 3 music loops, 61 voice lines, director,
  mapper, 2 synths, demo and test, and check is clean. But the player car is inaudible in the real mix,
  the demo is drowned after its SFX section, the "gameplay" capture is the idle title menu, the rear
  (N₂) thruster voice fails the spectral spec, there is no positional/doppler world audio, and synth CPU
  is over budget.
- **visual/feel (sound quality): 3** — The tyre squeal is noise, not a squeal. The boost roar is white
  noise plus a 62/93 Hz drone. Loops click and the city bed carries DC. The music is one 4-bar loop
  repeated and brick-walled. The radio FX is weak and voice loudness spreads 8 LU.
- **code: 5** — Clean split into files of 400 lines or fewer, mostly typed. But there are about 120
  magic numbers in logic, the test still `extends SceneTree` (against a lead rule), the one-shot pool
  bookkeeping is broken, synths are reparented into the car, and every run exits with
  "resources still in use".

## MUST-FIX

1. **The player car is inaudible in the real mix** (SPEC pillars 1 "the car is the star" and 2 "speed
   you can feel").
   - Evidence, music muted (`captures/review/audio/drive_nomusic.mp4`, full throttle 100→180 km/h,
     t = 1.5–5.5 s): the car alone measures **−45 dBFS RMS**. The whine itself is fine and tracks speed
     (193 → 633 Hz).
   - Same drive with music (`drive.mp4`): −15…−16 dBFS. The strongest tonal peaks in 150–1100 Hz are
     the cruise lead notes 521/586/656 Hz, and there is no rising whine line
     (`review_drive_whine_zoom.jpg`). So the music sits about 30 dB above the car.
   - The music files are brick-walled: cruise −8.4 LUFS, pursuit −6.9, race −5.6 (race crest ≈ 6.7 dB).
     In game that becomes −18.4 / −13.9 / −12.6 LUFS after state, bus (0.7) and master (0.9) gains.
   - Do:
     - (a) Remaster the 3 loops to −14 LUFS integrated, true peak ≤ −1.5 dBTP, peak-to-loudness ≥ 10 dB.
       Use soft-clip drive ≤ 1.1 and drop the "RMS to −12 dBFS" normalise (gen_music.py:221–229).
     - (b) Gain-stage to these targets, measured on Master with Settings defaults as short-term (3 s)
       LUFS:

       | Layer | Target (short-term LUFS) |
       |---|---|
       | Car, full throttle at 150 km/h | −20…−16 |
       | Cruise music | −26…−23 |
       | Pursuit / race music | −24…−21 |
       | Ambience | −32…−28 |
       | Voice (music ducked) | −18…−16 |
       | Boost roar | +4…+6 LU over the motor |

     - (c) Expose an output gain on both synths. Make sure the whine stays loud when `motor_load` is 0:
       it is 0.25× today (ev_synth.gd:86).
     - (d) Road and wind must be clearly audible from 60 km/h.
   - Verify: re-run a drive with and without music and put the per-layer LUFS in status. In the full
     mix the whine must be the strongest tonal line in 150–1100 Hz while accelerating.

2. **The 30 s "gameplay" capture is not gameplay, and its numbers are invalid.**
   - `captures/audio/gameplay.mp4`: the car stands behind the SKYRUSH title menu for all 30 s
     (`worker_capture_sheet.jpg`). Short-term loudness is flat at −16.3 ±0.2 LUFS (LRA 0.7 LU).
   - The AVI **does** have Godot's PCM track (pcm_s16le, 48 kHz), so the status claim "movie writer
     has no audio" is wrong. Your AudioEffectCapture WAV holds only **13.72 s of 30 s**, so "peak −5.21
     dBFS" and "CPU 6.43 %" were measured on a partial session with the car idle.
   - Do:
     - Delete the WAV path and `capture_gameplay.gd`.
     - Record with the core tool:
       `tools/godot.sh movie --movie=/Users/minimax/m/skyrush/captures/audio/gameplay.avi --timeline=res://audio/capture/gameplay_timeline.json --skip-menu --stub=world`
     - The timeline must cover: 0 → ≥ 200 km/h, a drift ≥ 2 s with squeal, 小喷, hop, Big Hop charge +
       release + landing, barrel roll, nitro and one wall hit. Keep the car on the stub floor: my nitro
       run left it at 339 km/h at t ≈ 9 s.
     - Mux:
       `ffmpeg -i gameplay.avi -map 0:v -map 0:a -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k gameplay.mp4`
   - Verify: `ffmpeg -i gameplay.avi -map 0:a -af ebur128=peak=true -f null -` gives true peak ≤ −1.0
     dBTP and LRA ≥ 4 LU. A 6-frame contact sheet shows the car moving.

3. **Synth CPU exceeds the 8 % budget.**
   - My worst case: both nozzle groups at 1.0, hop_charge 0.5, 12 000 rpm, load 1, 200 km/h, 1 s of audio
     rendered.
   - Result over 3 runs: thruster 4.2–5.3 % + EV 5.4–7.1 % = **9.5–12.4 % of one core**. The machine
     load average was about 17, so this may be somewhat inflated, but even the best run exceeds 8 %. The
     GODOT.md §9 reference voice costs 3.1–3.4 %.
   - Do:
     - No per-sample `sin()` or `fmod()`: use a rotating phasor or a 4096-entry sine table.
     - Use one pre-generated 65 536-sample noise table instead of 4 LCG steps per sample.
     - Render the road and wind layers (≤ 2.2 kHz) at ¼ rate and interpolate, or move the noise beds to
       looping OGG players with bus filters. Keep only tonal content in GDScript.
   - Verify: add a worst-case CPU check to the test (render 1 s from both voices, print %). It must be
     ≤ 8 % total. Run it on a quiet machine and state the load average in status.

4. **The rear (R1–R4, N₂) thruster voice fails the spectral spec and is quieter than the perimeter
   jets.**
   - My render with R = 1, P = 0: amplitude centroid **1 484 Hz** (power centroid 602 Hz), with 22 % of
     its energy below 200 Hz. DOSSIER §6.1 says "no combustion rumble".
   - RMS is −28.8 dBFS, against −19.4 dBFS for P only. The test only checks P = 1.0, R = 0.35.
   - Do:
     - Run the rear group through the hiss chain (HP 600 Hz + 2× LP 4 kHz, or LP 3.2 kHz). Add a
       150–500 Hz body layer at least 10 dB under it.
     - Rear at full = perimeter at full + 3 dB.
     - Normalise the group sums instead of clamping the raw sum at 1.0 (audio_director.gd:349–350; today
       1 nozzle sounds like all of them). Use rear/4 and perimeter/6, then √ for loudness.
     - Add the ±5 % pitch with thrust (DOSSIER §6.3 item 5).
   - Verify: test centroids for (R1,P0), (R0,P1) and (R1,P1), all in 2–4 kHz, energy < 200 Hz ≤ 2 %,
     and RMS(R only) ≥ RMS(P only).

5. **The pneumatic "chuff" fires on ignition instead of cut-off, and it is a "pew".**
   - thruster_synth.gd:156–159 sets `_chuff = 1.0` on `hot and not _was_hot`. My probe reads 0.619
     right after ignition and 0.001 right after cut-off.
   - The sound itself is a 1.5 kHz → 0 sine sweep.
   - Do: trigger on hot → cold. Make it an exhaust burst: 60–90 ms band-passed noise (centre 1.2 kHz,
     Q ≈ 1), 2 ms attack, 40 ms exponential decay, plus a 90 Hz, 50 ms "puff" at −12 dB.
   - Verify: the test sees no chuff after ignition, and chuff energy in the 150 ms after cut-off is
     ≥ −24 dB relative to the sustained hiss.

6. **Fan whine is missing.** The brief asks for "fan whine"; DOSSIER §6.3 says "1.5–3 kHz whine that
   rises with suction". Nothing in game/audio reads `telemetry.downforce_kg`.
   - Do: add one sine plus a weak 2nd harmonic to the EV voice: 1.5 kHz at 0 kg rising to 3 kHz at max
     downforce, level ∝ downforce, about −18 dB under the motor at max.
   - Verify: test renders downforce 0 and max. The peak is in 1.5–3 kHz and rises with downforce.

7. **There is no positional or doppler world audio** (brief: "AudioStreamPlayer3D with doppler for
   passing cars").
   - `play_3d()` drops a pooled AudioStreamPlayer3D at a fixed point. A loop id (status tells police to
     call `play_3d(&"siren_wail", …)`) never stops, never moves, and holds a pool slot forever. Doppler
     on a static player does nothing.
   - No Camera3D in the project sets `doppler_tracking`: grep finds 0 hits. GODOT.md §9 needs both the
     player and the camera set, so doppler is off everywhere.
   - These ids are never played by runtime code: `traffic_ev_hum`, `siren_yelp`, `police_horn`,
     `horn_traffic*`, `river_ambience`, `scrape_loop`, `glass_break`.
   - Do:
     - (a) Add `attach_loop(id, target: Node3D, volume_db, pitch) -> AudioStreamPlayer3D` and
       `stop_loop(handle)`. The emitter follows its target in `_physics_process` and is freed on the
       target's `tree_exiting`. `play_sfx` and `play_3d` must reject loop ids.
     - (b) Let the director drive emitters from groups, with no edits in other units:
       - hum on the nearest ≤ 6 `traffic` cars within 60 m, pitch following their speed;
       - siren on `police` cars while heat ≥ 1: wail at heat 1–2, alternating wail/yelp at heat ≥ 3,
         yelp within 40 m;
       - all of them with DOPPLER_TRACKING_PHYSICS_STEP.
     - (c) Play the river bed from the nearest river point, or set its volume by distance < 150 m.
     - (d) In status/audio.md, ask the camera unit to set `doppler_tracking =
       DOPPLER_TRACKING_PHYSICS_STEP` on every gameplay Camera3D.
     - (e) Correct the police request in status.
   - Verify: a test like GODOT.md §9, where a 440 Hz emitter passing at 50 m/s reads 515 ± 5 Hz
     approaching and 384 ± 5 Hz receding. Also a capture with 3 or more traffic cars passing.

8. **The demo is drowned after the SFX section.** It plays the 10 loop ids through the one-shot pool and
   never stops them.
   - My 100 s movie of `audio_demo.tscn` (`captures/review/audio/demo.mp4`) measures −6.0…−6.2 dBFS RMS
     in the cruise, pursuit, race and voice sections alike. The quietest 250 ms between voice lines is
     −6.7 dBFS. Music and voice cannot be judged.
   - The two synths are AudioStreamPlayer3D with no Camera3D or AudioListener3D in the scene. The 2–4 kHz
     band shows no 2.4 s thruster on/off pattern (it stays at 2–11 dB the whole time).
   - Do:
     - Each loop gets 3 s on its own player and is stopped at the end of its step.
     - Add a current AudioListener3D at the synths for the synth step.
     - Voice step = line length + 0.4 s. Radio lines run up to 2.86 s; the step is 1.6 s today.
     - Add a live Master peak/RMS meter and a 2–4 kHz centroid readout to the caption panel
       (`demo_sheet.jpg`: today it is a caption only).
   - Verify: re-record the demo. Each music section has its own LUFS, the quietest 250 ms between voice
     lines is ≤ −40 dBFS, and thruster pulses show as swings of 15 dB or more in 2–4 kHz.

9. **Loop seams click and some files carry a DC offset, because the generators are not circular.**
   - Seam ratio (2nd difference at the loop point ÷ the file's p99.9):

     | File | Seam ratio | Other |
     |---|---|---|
     | `city_ambience` | **13.0×** | 15 dB envelope jump at the seam |
     | `traffic_ev_hum` | **7.1×** | |
     | `siren_wail` | 1.8× | largest step in the whole file |
     | `river_ambience` | 1.4× | |
     | `scrape_loop` | | 6.6 dB level jump at the seam |

   - DC offset: `city_ambience` −0.045 (a brown-noise random walk), `river_ambience` −0.021,
     `charge_zap` −0.0135.
   - Noise layers, reverb, soft-clip and filters run linearly, so the docstring "every layer has a
     period dividing 30 s" (gen_world.py:119–138) is false.
   - Do: filter noise in the frequency domain over exactly the loop length, or render loop + 1 s and
     equal-power crossfade the tail into the head over 100–250 ms. DC-block every asset (HP 25 Hz).
     Extend analyze.py with seam ratio, seam envelope jump, DC and LUFS columns. Flag ratio > 1.0,
     jump > 1.5 dB and |DC| > 0.002.
   - Verify: analyze.py table in status with 0 flagged ("0 flagged" today checks none of this).

10. **The sound design is thin where it matters** (`captures/review/audio/sfx_spectra.jpg`; tiles
    row-major: hiss, roar, ignite, pssh / whoomp, hop, impact_heavy, glass / wail, yelp, squeal, zap /
    chime, hum, police_horn, city).
    - Problems:
      - `tyre_squeal` is band-passed noise (1.5 / 2.3 kHz, Q 3–4) with no tone.
      - `boost_roar_loop` is near-white noise flat to 20 kHz plus a constant 62 + 93 Hz drone
        (centroid 4.4 kHz). In my drive it covers everything like TV static.
      - The chirps in `mini_pssh` (gen_sfx.py:141, `2600t−9000t²`) and `hop_release` cross 0 Hz and come
        back up as a stray rising tone, with aliased lines.
      - `impact_heavy` is a few low modes plus clicks.
      - `city_ambience` has a constant AM siren (the brief says "occasional").
      - `river_ambience` has no water or ship detail.
    - Targets:
      - Squeal: stick-slip tone at 900–1300 Hz random-walking ±60 Hz at 6–12 Hz, 2–3 harmonics, plus a
        scrub-noise layer at −10 dB. Peak ≥ 15 dB over its band mean.
      - Roar: pink-noise based, a 120–600 Hz body with 2–7 Hz turbulence (±2 dB), a hiss matched to the
        thruster chain, and energy at 10 kHz+ at least 18 dB under 1 kHz. Move the thump into
        `boost_ignite` as a 45–70 Hz pitch-drop burst.
      - Chirps: never cross 0 Hz, and use band-limited oscillators.
      - Impacts: 3 layers. A body thump at 60–120 Hz, 8–14 inharmonic metal modes at 300 Hz–6 kHz
        decaying over 0.2–1.2 s, and debris/glass tinkles scattered over 50–600 ms.
      - City bed: 60 s of traffic wash plus 6–10 scattered events: doppler pass-bys, 2–3 distant
        dual-tone horns at about 420/500 Hz, 1 distant siren pass of ≤ 8 s, and a metro rumble.
      - River: water lapping (noise bursts at 200–1500 Hz), wind, and 1–2 Huangpu ship horns per minute
        (110–180 Hz, 2–4 s).
    - Verify: regenerate the sheet in my tile order and put centroid / peak / flatness per file in
      status.

11. **The music has no arrangement, and the masters are crushed.** Every phrase is identical: cruise
    phrase-start energy is −9.8 / −9.9 dB at all 5 internal phrase starts and at the seam, and pursuit and
    race behave the same. gen_music.py:155–205 repeats the same bar and the same 4-bar riff.
    - Do, inside each loop:
      - A (8 bars) → B (8 bars: bass octave pattern + answer riff) → 4-bar breakdown (drums out, pad
        filter sweep, riser) → A′ (lead an octave up).
      - Fills on bars 4/8/12/16, a crash on each section start, kick side-chain pump on the pads, a
        gated-reverb snare, and an arp filter LFO over 8 bars.
      - Keep the seam clean: my energy test passes today. Master as in item 1.
    - Verify: a per-4-bar table in status (energy and centroid) where sections differ by ≥ 1.5 dB or
      ≥ 300 Hz.

12. **Voice lines cut each other off, the radio FX is weak, and loudness is not normalised.**
    - One `_voice_player` serves both announcer and police radio, and `play_voice` replaces whatever is
      running. sound_mapper.gd:212–213 plays `heat_up` and cuts it immediately with `police_arrive`.
      `game/ai/police/police_radio.gd` cuts the announcer and vice versa.
    - Radio lines: 13 % of their energy is below 250 Hz (−8.8 dB). Above 3.5 kHz they sit at −18.2 dB,
      against −15.3 dB for the clean announcer (`voice_spectra.jpg`, bottom row).
    - Loudness spread: announcer 8.2 LU (busted −19.3 … new_record −11.1 LUFS), radio 6.2 LU.
    - Do:
      - Two channels (announcer, radio) and a priority queue:

        | Priority | Lines | Rule |
        |---|---|---|
        | P0 | countdown, finish, busted, escaped | never cut |
        | P1 | heat, stunts | queued ≤ 2 s |
        | P2 | drift, hop, near-miss | dropped when busy, gap ≥ 4 s |

        "漂移！" on every drift and "电量不足" every 8 s is spam: play once per crossing, then every 30 s.
      - Radio: 4th-order HP 300 Hz and 4th-order LP 3.0 kHz after the saturation, +3 dB at 1.8 kHz,
        band-limited hiss.
      - Loudness: announcer −16 LUFS ±0.5, radio −18 ±0.5, true peak ≤ −1.5 dBTP.
    - Verify: a test fires `heat_changed(2)` and both lines play to the end in order. Radio energy below
      250 Hz ≤ −25 dB and above 3.5 kHz ≤ −30 dB. LUFS spread ≤ 1 LU per kind.

13. **The one-shot pool bookkeeping is wrong.**
    - `_steal_oldest()` (audio_director.gd:222–238) picks the **smallest** playback position, which is
      the newest sound, contradicting its own comment.
    - When a pool is full, `_take_2d()` / `_take_3d()` return `pool[0]`, restarting it whatever its age.
      `play_sfx` then appends a duplicate to `_active_2d`.
    - Probe: after 20 `play_sfx` calls, `active_oneshots()` returns 20 while only 16 players are
      playing, and the first sound was killed by the fallback.
    - Do: steal per pool by (priority, start time). No duplicates. Loop ids may not use the pool
      (item 7).
    - Verify: test 30 calls; active == players really playing ≤ 24, and the oldest is the one stolen.

14. **The music state crossfade drops about 25 dB, and the menu state detunes.**
    - music_bed.gd:111 lerps in dB at λ = 3/s. Outgoing (−6 → −60) plus incoming (−60 → −3) sum to
      −28.6 dB at 0.25 s and −15.7 dB at 0.5 s: a hole on every state change.
    - The menu is cruise at pitch 0.85 (−2.8 semitones) and snaps back to 1.0.
    - Do: equal-power crossfade in linear gain over 2.0 s. For the menu, use the same pitch through an
      AudioEffectLowPassFilter on MusicBed, sweeping 20 kHz → 1.2 kHz over 0.6 s.
    - Verify: log the bed RMS during cruise → pursuit; it must not dip by more than 3 dB.

15. **Events are not hooked.** These lines are never played: sky_lane_open, final_lap, new_record,
    boost_fierce, boost_ready, drift_chain_big, overtake, position_up, race_end, vehicle_wrecked,
    one_more.
    - Do: connect these events:
      - `sky_lane_launch` → `sky_lane_open` + launch hiss;
      - `flight_changed(false)` → exit puff;
      - `n2_ring` → a new ring chime;
      - `charge_started` → `charge_zap`, synced to the 0.45 s flash; chime + voice stay on `finished`;
      - `lap_completed` → `final_lap` on the last lap;
      - `boost_ready` when N₂ crosses 100 or 200;
      - heavy impact → + `glass_break`;
      - sustained contact → `scrape_loop`.
    - For lines that have no event yet, name the unit that should fire them in status.
    - Verify: the test emits each event and checks `sfx_played` / `voice_line`.

16. **Lead rule: tests must `extends Node`.** `game/audio/tests/test_audio.gd` is `extends SceneTree`
    and runs through the legacy branch. Convert it to the test_host convention
    (`res://core/tests/test_core_smoke.gd`), keeping the 75 checks and adding the new ones above.
    - Verify: `tools/godot.sh test res://audio/tests/test_audio.gd` runs via test_host and exits 0.

17. **About 120 magic numbers in logic.** Examples:
    - `audio_director.gd`: lines 96–97, 127–128, 315 (`1.0/0.18`), 319 (`0.6`), 336 (`speed * 60.0`,
      `throttle * 3200.0`), 337, 354–361 (`-40`, `0.08`, `-8`, `8`, `0.92 + 0.2`, `-6`, `10`, `0.08/300`).
    - `sound_mapper.gd`: lines 98–102 (`12000` / `3000` / `15000` N·s), 147–148, 263–270.
    - `music_bed.gd`: lines 14–17, 44–46, 93, 111.
    - `ev_synth.gd`: line 86, lines 92–94 (one-pole coefficients hard-coded for 48 kHz, wrong at the
      Dummy driver's 44.1 kHz) and line 108.
    - `thruster_synth.gd`: lines 185–219 (`0.0005`, `0.02`, `0.12`, `1500`, `0.16`, `0.999`).
    - Do: named consts with units, or one `audio_tuning.gd`. Compute filter coefficients from Hz and
      `_rate`.
    - Verify: no bare literals in function bodies except 0, 1 and 0.5.

18. **Every run exits with an engine ERROR from this unit.** `ERROR: 14–28 resources still in use at
    exit` shows up in the test, the demo and full-game runs. `--verbose` lists `res://audio/sfx/*.ogg`
    (rain_layer, city_ambience, boost_roar_loop, …), their playbacks and 2 AudioStreamGeneratorPlayback.
    The cause is the static `_cache` in sfx_library.gd plus players still alive at quit.
    - Do: clear the cache and stop the players in the director's `_exit_tree`.
    - Verify: in the `--verbose` output, no `res://audio` resource appears as "still in use".

## SHOULD-FIX
- **Synth reparenting.** The synths are reparented into the car (audio_director.gd:328–329). If the car
  is freed (other units' demos and tests reassign `Game.player`), the next `reparent()` hits a freed
  object. Keep the synths under the director and copy the car transform in `_physics_process`; doppler
  still works.
- **OGG encoder.** ffmpeg's native Vorbis encoder is experimental and stereo-only. Blender's Audaspace
  writes libvorbis OGG, mono included. I verified it with `Blender -b --python`:
  `aud.Sound.file(wav).write(out, 48000, aud.CHANNELS_MONO, aud.FORMAT_FLOAT32, aud.CONTAINER_OGG, aud.CODEC_VORBIS, 160000)`,
  and ffprobe reports vorbis, 1 ch. Use mono for all one-shots and 3D sources.
- **Limiter.** `AudioEffectLimiter` is deprecated. Use `AudioEffectHardLimiter` (ceiling −1.0 dB,
  release 0.1 s).
- **Wind and road.** gameplay DOSSIER §8.5 asks for wind pitch 0.8 → 1.3 with speed, from −20 to −4 dB.
  Road noise is ∝ v² today (`road * road`, ev_synth.gd:89), while the brief says ∝ speed.
  `motor_load` should change timbre: the line 84 comment promises a filter that does not exist, and the
  partial mix (line 108) is static.
- **Hop charge tone.** It is a bare 220 → 880 Hz sine. Use a detuned saw pair through a resonant LP that
  opens with the charge, with tremolo rising from 4 to 14 Hz near full charge.
- **Boost roar trigger.** Drive the roar from the rear-nozzle telemetry rather than `boost_kind`. In my
  drive the vehicle kept `boost_kind = "nitro"` for 25 s with N₂ at 0, so the roar droned on. Report
  that vehicle bug in status.
- **Distant siren.** It sits static 70–160 m away, and at 70 m/s it is gone in 2 s. Make it follow the
  player, or replace it with item 7.
- **Housekeeping.**
  - Type the handlers `vehicle: VehicleBase` instead of Variant (sound_mapper.gd:70–169).
  - `_rbj_*` should return `PackedFloat64Array`.
  - `sfx_ids()` should use `ResourceLoader.list_directory()`, so it works in exported builds.
  - Split `audio_director.gd` (361 lines) before items 7, 12 and 13, e.g. `oneshot_pool.gd`,
    `voice_queue.gd`, `world_emitters.gd`.

## Verified OK
- **Ownership.** The worker's Write/Edit calls (jobs/audio/log.jsonl) touched only `game/audio/**`,
  `tools/audio/**` and `status/audio.md`. `tmp/audio/` is empty, and the stray `tmp/openapi.json` is
  gone. git diff outside the unit shows only other units' work.
- **File sizes.** All files ≤ 400 lines (largest: common.py 379, audio_director.gd 361).
- **Check.** `CHECK 12 files, 0 failed, 0 engine errors, 0 warnings`.
- **Test.** `AUDIO TEST 75 checks, 0 failed`; every stream loads with a duration > 0.
- **Asset inventory.** 33 sfx, 3 music loops at 95 / 124 / 112 BPM and 60.6 / 61.9 / 68.6 s (brief: 85–125
  BPM, 60–90 s). The music seams are clean: phrase-start energy at the seam matches internal phrases
  within 0.1 dB.
- **Voice.** 61 lines (45 announcer + 16 radio); every line the brief lists is present with a subtitle,
  in the requested voices. The police unit already plays the radio lines through `play_voice`.
- **Ducking and buses.** Music ducks −6.00 dB under voice. Settings' bus volumes are left alone, and the
  core request for the Master limiter and MusicBed bus is properly filed in status.
- **Thruster envelope.** Perimeter hiss centroid is 2 861 Hz (in band); attack 30 ms, release 120 ms.
- **Motor whine.** It tracks speed in game (193 → 633 Hz at 25 → 180 km/h, music muted).
- **No clipping.** My 30 s drive: true peak −1.3 dBTP. Demo: −1.91 dBFS, 0 clipped samples (both held
  by the limiter).
- **Demo captions.** Chinese renders correctly (`demo_sheet.jpg`, from my 5 shots).
- **ys-api.** `/api/suno` was tried twice before falling back to procedural music, as the brief allows.

## Evidence
- `tools/godot.sh check --only=res://audio/` → `CHECK 12 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://audio/tests/test_audio.gd` → `AUDIO TEST 75 checks, 0 failed`, then
  `WARNING: 70 ObjectDB instances were leaked` and `ERROR: 18 resources still in use at exit`.
  The `--verbose` rerun lists the `res://audio/sfx/*.ogg` streams.
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/audio/probe_audio.gd` (copy in
  `captures/review/audio/scripts/`):
  - `thruster P_only 2501 Hz zero-cross` / `R_only 846 Hz`;
  - numpy on the dumps: P 2861 Hz, R 1484 Hz amplitude centroid, R energy < 200 Hz 22.1 %, RMS
    −28.8 vs −19.4 dBFS;
  - `chuff level right after IGNITION: 0.619`, `after CUT-OFF: 0.001`;
  - `cpu thruster 5.26 / 4.15 / 4.56 %`, `cpu ev 7.14 / 5.35 / 6.58 %`;
  - `after 20 play_sfx: active_oneshots()=20, pool players really playing=16`.
- Offline asset analysis (`scripts/an.py`, `click.py`, `mseam.py`, `radio.py`):
  - LUFS: cruise −8.4, pursuit −6.9, race −5.6; city_ambience −41.6 with DC −0.0448.
  - Seam ratios: city 13.04, hum 7.07, wail 1.80.
  - Radio below 250 Hz −8.8 dB, above 3.5 kHz −18.2 dB (announcer −15.3).
- Worker capture `captures/audio/gameplay.avi`:
  - ffprobe shows `pcm_s16le 48000` audio inside the AVI; the WAV is only 13.72 s;
  - ebur128: I −16.6 LUFS, LRA 0.7 LU, TP −6.1 dB;
  - sheet `captures/review/audio/worker_capture_sheet.jpg`: idle title menu.
- My drive: `tools/godot.sh movie --movie=…/drive.avi --timeline=…/scripts/drive.json --skip-menu
  --stub=world`.
  - Telemetry: speed 202 km/h at t = 5 s with nitro, 339 at t = 8, then off the world.
  - ebur128: I −14.2 LUFS, LRA 2.0 LU, TP −1.3 dB.
  - `captures/review/audio/drive.mp4`, `review_drive_sheet.jpg`, `review_drive_whine_zoom.jpg`.
- Music muted via `scripts/mute_music.tscn` wrapping main.tscn (`--scene=`):
  `captures/review/audio/drive_nomusic.mp4`; per-frame RMS −44.7 … −45.9 dBFS at t = 1.5–5.5 s.
- Demo: 100 s movie `captures/review/audio/demo.mp4`; section RMS: synth −23.6, end of sfx −6.4,
  cruise −6.2, pursuit −6.0, race −6.1, voices −6.0 dBFS. Shots: `review_audio_r1_t{3,40,60,75,100}_0.jpg`.
- Spectrogram sheets: `captures/review/audio/sfx_spectra.jpg` and `voice_spectra.jpg` (top: launch_perfect,
  heat_max; bottom: radio_escape, radio_reinforce).
- Doppler: grep for `doppler_tracking` outside game/audio → 0 hits.
- Encoder: Blender Audaspace libvorbis mono test → `stream|codec_name=vorbis|sample_rate=48000|channels=1`.
