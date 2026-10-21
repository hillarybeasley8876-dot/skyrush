# Brief: rivals + modes — race opponents and the game modes (free roam, race, pursuit)

## Goal
Make the city a game: QQ飞车-style races against 5 rival Roadster-class cars on routes through
Shanghai, a pursuit mode, and a free-roam mode with stunts/score — with countdowns, checkpoints,
results and records.

## You own
`game/ai/rivals/**` (Modules unit `rivals`: `res://ai/rivals/rival_director.tscn`) and
`game/modes/**` (Modules unit `modes`: `res://modes/mode_director.tscn`). One worker owns both.

## Read first
`ref/gameplay/DOSSIER.md` §6.2 (rival AI: racing line, look-ahead, corner speed, PD steering,
rubber band, abilities, mistakes, avoidance), §1 (QQ race flow: countdown, 完美起步), §3.4–3.5
(pursuit mode goals, takedown rewards), §8.4 (pop-up texts); `core/events.gd` (`race_countdown`,
`race_started`, `checkpoint_passed`, `lap_completed`, `race_finished`, `stunt`, `takedown`, `toast`),
`core/contracts/race_route.gd`, `world_base.gd` (`get_route_ids`, `get_route`, spawns), `core/game.gd`
(`Game.mode`, `Game.option`), the vehicle unit's `ArcadeCar`/`CarSpec` (rivals use the same physics;
rival cars = Roadster-class specs with different paints/visuals: reuse `roadster.glb` with
different `SH_car_paint` colours via instance parameters, plus 2 npc sports bodies if npc_cars made
any), `game/ai/common/**` (traffic unit; reuse).

## Deliverables
1. Rivals: racing-line follower on `RaceRoute.racing_line` (look-ahead L = 18 + 1.25 v), corner speed
   from curvature, PD steering, rubber band per difficulty (easy/normal/hard), N₂ on straights, drift
   visuals, mistakes, traffic avoidance, names + colours (6 fictional racers with Chinese handles, e.g.
   「浦江闪电」「外滩幽灵」…).
2. Modes (`modes/`): `free` (default: score from `Events.stunt`, near-misses, takedowns; police active),
   `race` (route select, grid, 3-2-1-GO with `race_countdown`, `race_started`; 完美起步 window;
   checkpoints as hologram gates (simple glowing ring meshes or the props sky-lane gate scaled) +
   `checkpoint_passed`; laps; positions live; finish → `race_finished(results)`; police off unless
   "with police" option), `pursuit` (start at heat 2–3, goal: escape (cooldown) or take down N units in
   time; busted/escaped results). Mode selection via `Game.mode` + an API the menu unit calls:
   `ModeDirector.start_mode(mode: StringName, options: Dictionary)` (document it in status).
3. Records: best lap/time per route, high scores → `user://records.cfg`.
4. Tests (sandbox route `sandbox_loop` and later the real routes): `test_race_flow.gd` (headless:
   countdown → start → rivals complete 2 laps without getting stuck; finish order recorded),
   `test_rubber_band.gd`, `test_pursuit_mode.gd`. Windowed captures of a race start grid, mid-race
   pack, finish.

## Acceptance
A full race on a real route can be completed with rivals that drive cleanly, overtake, make
occasional mistakes and finish within plausible gaps; modes switch cleanly; check clean.
