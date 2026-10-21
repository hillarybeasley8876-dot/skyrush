# Brief: audio — EV motor, cold-gas thrusters, crashes, sirens, city, music, voice

## Goal
Make the game sound fast, heavy and alive: synthesized EV drive + thruster audio for the
Roadster, sampled/procedural effects for everything else, adaptive music, Chinese announcer
voice lines.

## You own
`game/audio/**` (Modules unit `audio`: `res://audio/audio_director.tscn`), `tools/audio/**`
(offline generators).

## Read first
`ref/tech/GODOT.md` §9 + VERIFIED `ref/tech/snippets/ev_synth.gd` (start from it; max 2 synth
voices), `ref/roadster/DOSSIER.md` §6.1 (thruster sound: broadband hiss, centroid ~3 kHz, sharp
30 ms attack, 120 ms release, pneumatic "chuff"; fan whine), `ref/gameplay/DOSSIER.md` §2.3
(audio as speed cue), `core/events.gd`, `core/contracts/car_telemetry.gd`, `core/settings.gd`
(buses Music/SFX/Voice already created by Settings).

## Deliverables
1. **Player car**: `EvSynth`-based motor whine (pitch follows speed, load follows throttle; inverter
   harmonics; a tyre/road-noise layer ∝ speed; wind ∝ v²), thruster hiss voices driven by
   `telemetry.thrusters` (sum of R and of P groups), Big Hop charge rising tone, landing "whoomp",
   N₂ boost roar (filtered noise + low thump), 小喷 "pssh", drift tyre squeal ∝ rear_slip,
   charge-bay zap + rising chime, battery-low beep.
2. **World/other cars**: generated one-shot/loop files (OGG) in `game/audio/sfx/` made offline by
   your `tools/audio/*.py` (Blender's Python has numpy: run with
   `/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/x.py`,
   or ffmpeg `aevalsrc`/`anoisesrc` filters): impacts (light/medium/heavy metal crunch + glass),
   scrape loop, police siren (Chinese police two-tone wail + yelp), police horn, traffic horns,
   traffic EV hum loop, tyre squeal loop, city ambience bed (distant traffic, rain on/off layer,
   occasional distant siren), river ambience, UI clicks/whooshes, countdown beeps.
   AudioStreamPlayer3D with doppler for passing cars (tech dossier §9 settings).
3. **Music**: try the internal ys-api music endpoint once (`POST https://ys-api.xaminim.com/api/suno`;
   no key, IOA VPN; if it fails, do not retry more than twice). Otherwise compose 3 procedural
   synthwave/cyberpunk loops offline (85–125 BPM: cruise, pursuit, race; 60–90 s each, seamless
   loop, OGG) with your Python sequencer (bass, arps, pads, drums from synthesized samples). An
   adaptive mixer crossfades by state (free roam / pursuit heat / race / menu).
4. **Voice lines** (Chinese announcer + police radio): generate with the internal TTS
   `POST https://ys-api.xaminim.com/api/minimax_tts` JSON {text, voice_id, speed, emotion} → returns
   an mp3 URL (download it, convert to OGG with ffmpeg). Voices: announcer
   `Chinese (Mandarin)_Male_Announcer` (fallback `presenter_male`); police radio dispatcher: a
   female voice (try `Chinese (Mandarin)_Wise_Women`, then `female-shaonv`, fall back to
   `presenter_female`), processed with a radio band-pass + light distortion offline.
   Lines (≥ 40): countdown 三/二/一/出发, 完美起步, 漂移/完美漂移, 氮气加速, 飞行航道开启, 飞跃加油站,
   飞跃收费站, 撞毁, 连击, 狂暴, 闪充完成, 电量不足, 警察来了, 追捕升级, 甩掉警察了, 被捕了,
   终点, 新纪录 …; radio: "注意，目标车辆正在逃逸", "前方路口设卡", "无人机已升空", "重型车辆准备拦截" ….
   Manifest `audio/voice/voice_lines.gd` maps ids → files + subtitle text (HUD may show subtitles).
5. `audio_director.gd`: listens to Events, owns buses/ducking (voice ducks music −6 dB), caps
   simultaneous one-shots (≤ 24), respects Settings volumes.

## Acceptance
`audio/demo/audio_demo.tscn` plays each category in sequence with labels (and a headless test that
loads every stream and checks durations > 0); spectral sanity for thrusters (centroid 2–4 kHz,
measure with `AudioEffectSpectrumAnalyzer` or offline FFT); no clipping (peak ≤ −1 dBFS on Master
during a scripted 30 s gameplay capture); CPU ≤ 8 % of one core; check clean. Record a 30 s
gameplay capture with `--write-movie` in the sandbox (stub or real car) for the lead to listen to:
`captures/audio/gameplay.avi` → convert to mp4 with ffmpeg.
