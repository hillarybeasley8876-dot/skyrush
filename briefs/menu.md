# Brief: menu — title screen, mode select, settings, pause, results, loading

## Goal
A stylish, fast, cyberpunk-Shanghai front end (Chinese first) that gets the player into a
drive in seconds and shows off the car and the city.

## You own
`game/ui/menu/**`. Entry (Modules unit `menu`): `res://ui/menu/menu.tscn` (CanvasLayer).
Shared theme/fonts: `game/ui/theme/**` is the hud unit's — use it; request changes in status.

## Read first
`ART.md` (§3 UI palette, §7 typography), `ref/art/DOSSIER.md` §7, `SPEC.md` §3–4, `core/game.gd`
(`set_paused`, options), `core/settings.gd` (quality presets, volumes), `core/events.gd`
(`loading_progress`, `game_paused`, `race_finished`), modes unit API (`ModeDirector.start_mode`, see
`status/modes.md`), routes from `Game.world.get_route_ids()/get_route()`.

## Screens
1. **Loading**: listens to `loading_progress`; animated SKYRUSH 飞驰申城 logo (Smiley Sans), tips.
2. **Title**: logo over a live 3D background — the camera slowly orbits the player's Roadster parked on
   the Bund promenade road at night (use the real world + car; just a camera you own); "按任意键开始".
3. **Main menu**: 自由驾驶 Free Roam · 竞速赛 Race (route list with names, length, best time; difficulty;
   laps) · 警匪追逐 Pursuit · 设置 Settings · 退出 Quit. Gamepad + keyboard navigation, focus
   highlights, sounds via the audio unit (emit or call its UI methods if exposed).
4. **Settings**: quality preset (low/medium/high/ultra → `Settings.set_quality`), volumes (Master/Music/
   SFX/Voice), rain on/off (environment unit API, see its status), motion blur toggle (camera unit),
   controls reference page (keyboard + gamepad tables from SPEC §4).
5. **Pause** (`pause` action): resume, restart, settings, quit to menu (`Game.set_paused`).
6. **Results**: race standings / pursuit outcome / free-roam score summary with records; continue/
   retry. Respond within 1 frame to confirm presses (BEAK RASH lesson: no double-confirm cadence bugs).
`--skip-menu` (`Game.has_option("skip-menu")`) starts free roam directly (tests/captures rely on it).

## Acceptance
Every screen captured (`captures/menu/`), navigable with keyboard only and gamepad only (scripted
input test), text crisp CJK, no overlap at 16:9/16:10/21:9, title background running ≥ 60 fps,
`--skip-menu` works, check clean.
