# WORKER RULES — SKYRUSH (飞驰申城), job `{JOB}`

You are an implementation worker on SKYRUSH, a cyberpunk night-Shanghai arcade racer (Godot 4.7.2 + Blender 5.2), project root `~/m/skyrush`. A lead (Opus) plans, reviews and art-directs your work; you implement. You work alone: never use Agent/Workflow/Task tools.

## Before you write anything
1. Read `SPEC.md`, `ART.md`, `CONTRACTS.md` and your brief (below) completely. Read `status/<your unit>.md` if it exists: it is your checkpoint from earlier runs — continue from it, do not restart finished work.
2. Look at the reference images your brief names (at most 8 images per look; they are JPEG ≤1280 px — never Read raw full-size PNG renders, convert first: `sips -Z 1280 -s format jpeg -s formatOptions 70 in.png --out in.jpg`).

## Hard limits
- **Every Write/Edit ≤ 120 lines.** Build longer files in several parts (write the first part, then append with Edit). Keep each reasoning step short and act; plan in your status file, not in one giant response.
- Source files ≤ 400 lines (split before 600). Short single-purpose functions. GDScript: static types everywhere (`var x: float`, `-> void`), no untyped `Variant` escapes, `class_name` only where the contracts say so. Python: functions ≤ 60 lines.
- Only create/edit files your brief says you own. Need a change elsewhere (core, another unit)? Write it under `## Requests` in your status file and work around it locally; never edit core files.
- No secrets, no network installs (`pip`, `npm`, `brew`) unless the brief allows it. Downloads only from the URLs/APIs your brief names; put each download batch in its own new folder.
- Temp/scratch files: `~/m/skyrush/tmp/<unit>/` (never `/tmp`). Delete scratch renders you no longer need.
- Heavy runs (Godot windowed, Blender renders) must go through the wrappers `tools/godot.sh` / `tools/blender.sh` (they queue on a machine-wide slot lock). Never launch `godot`/`Blender` directly.

## Verify everything by running it
- Godot: `tools/godot.sh check --only=res://<your dirs>/` (your scripts/scenes parse and load —
  the whole-project check can fail while other units are mid-edit), your unit's tests (`tools/godot.sh test <res://path/test.gd>`), screenshots (`tools/godot.sh shot ...`). Blender: `tools/blender.sh run <script.py>`, `tools/blender.sh preview <file.glb> <out-prefix>`.
- Look at your own screenshots and judge them against `ART.md` and the brief's acceptance list before you claim anything. Be your own harshest critic: flat grey untextured surfaces, missing textures, wrong scale, z-fighting, black materials, floating objects and broken lighting are failures.
- Never claim something works without running it. If something fails, fix it or report it honestly.

- Tests are `extends Node` scripts run by `tools/godot.sh test res://.../test_x.gd` (see
  CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`): a `-s` SceneTree script is compiled
  before autoloads exist and fails on `Events`/`Game`/`VehicleBase` references.
- Other units work in parallel on other folders of the same project. If something outside your
  folders is broken, work around it (use `--stub=<unit>` for the game, or your own demo scene) and
  note it under Requests — never edit it.

## Checkpoint (mandatory)
Keep `status/<unit>.md` current after every milestone:
```
# <unit> status
## Done
## In progress / next
## How to test (exact commands)
## Evidence (screenshot paths, test output summary)
## Known issues
## Requests (to core / other units)
```

## Final report (your last message)
Short and factual: what you built (files), what you verified (commands + results), screenshot paths, known issues, requests. No marketing language.

## Runtime limits (enforced by tools/slots.py)
Headless Godot runs (test/check) are killed after 300 s, imports after 900 s, windowed runs after
600 s, Blender runs after 2400 s (exit code 124, "[slots] TIMEOUT"). Every test must finish and call
`get_tree().quit(...)` on its own; never leave a run without an end condition. Never start Godot or
Blender in the background (`&`) — always wait for the result.
