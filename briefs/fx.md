# Brief: fx — world-space effects director (tyres, sparks, rain, charge, debris dust)

## Goal
Every non-thruster particle/decal effect that makes driving tactile, plus the director that wires
effects (including the thruster system) to cars.

## You own
`game/fx/**` except `game/fx/thrusters/` (fx_thrusters unit). Entry (Modules unit `fx`):
`res://fx/fx_director.tscn`.

## Read first
`ref/gameplay/DOSSIER.md` §2.3 (speed cues), §3.3 (takedown presentation: oversized sparks/glass),
§5.5, §7 (crash/damage visuals); `ref/art/DOSSIER.md` §2.3 (emission tiers), §4.1 (wet road),
§6 (decals); `ref/tech/GODOT.md` §3.2 (particle and decal budgets); `core/events.gd`,
`core/contracts/*`, `core/settings.gd` (`Settings.feature("particles")`, `"rain"`).

## Deliverables
1. `fx_director.gd`: on ready, instance `res://fx/thrusters/thruster_system.tscn` if it exists and
   `attach()` the player; listen to node_added / group `vehicles` to attach effects to every car
   (full effects for the player + 3 nearest cars, reduced beyond 60 m, none beyond 150 m).
2. **Tyre smoke** from rear wheels when `telemetry.rear_slip` > 0.25 or drifting: lit soft puffs,
   grey-white #C9CCD2, rising and drifting back, coloured by nearby neon (lit particles). Wet road
   variant (spray mist + water droplets) when the shader global `skyrush_wetness` > 0.5.
3. **Skid marks**: ribbon decals/meshes along rear wheel contact points during drift/hard braking,
   dark rubber (#151515, α 0.6), fade after 20 s, pooled (≤ 400 segments).
4. **Sparks** on `vehicle_collided` with impulse > threshold and on scraping (contact persisting):
   bright E5 streaks (emission 20, < 0.3 s), gravity, bounce; oversized in slow-mo (takedowns).
   Plus **glass shards** and **plastic bits** bursts for big hits (small lit debris quads).
5. **Rain** (when `Settings.feature("rain")` and the global shader parameter `skyrush_rain` > 0 —
   read it with `RenderingServer.global_shader_parameter_get(&"skyrush_rain")`; the environment unit
   owns the weather and sets `skyrush_rain` / `skyrush_wetness`, declared by core in project.godot):
   camera-attached streak particles (≤ 6k), splash rings on the road near the camera, spray from
   tyres when `skyrush_wetness` > 0.5.
6. **Charge flash** on `charge_started/finished`: cyan #19E6FF electric arcs around the car (1.0 s),
   ground ring, bloom flash E4, "闪充" style energy ribbons.
7. **N₂ boost** extras: blue-white vapour streak behind the car, wheel-arch glow; **near-miss**
   streak; **wreck** smoke column (dark grey #2A2A2E) + small fire licks only for wrecked cars
   (damage unit emits `vehicle_wrecked`; you own the visuals), electrical sparks for EVs.
8. Demo scene `fx/demo/fx_demo.tscn` in the sandbox with the stub or real car, scripted to show
   each effect; captures in `captures/fx/`.

## Acceptance
Effects visible and believable in captures (sandbox + main scene), budgets met (≤ 20k billboard
particles total incl. rain, ≤ 64 decals), quality presets respected, `tools/godot.sh check
--only=res://fx/` clean, no errors when cars spawn/despawn rapidly (test script that spawns and
frees 50 cars).
