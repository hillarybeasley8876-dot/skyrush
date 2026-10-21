# Brief: police — 天巡 SKYPOL pursuits (heat, tactics, roadblocks, spikes, drones, busted/escape)

## Goal
NFS-grade police chases through night Shanghai: patrols react to offences, units ram/PIT/box,
roadblocks and spike strips appear at heat, drones hunt from above, and the player escapes by
breaking line of sight, flying sky lanes or wrecking them.

## You own
`game/ai/police/**`. Entry (Modules unit `police`): `res://ai/police/police_director.tscn`.
Reuse `game/ai/common/**` (traffic unit) for lane following/steering; request changes there.

## Read first
`ref/gameplay/DOSSIER.md` §3.1–3.4 (heat table, tactics, escape/cooldown/busted rules, pursuit
breakers, charge bay sight-loss), §3.5 (takedowns of police), §6.3 (police AI state machine table:
PATROL/PURSUE/RAM/PIT/BOX/HEAD-ON/ROADBLOCK/SPIKES/DRONE + catch-up fairness + radio lines), §7.3
(police HP/mass); `core/events.gd` (`infraction`, `heat_changed`, `pursuit_state_changed`, `toast`,
`flight_changed`, `charge_finished`), `core/contracts/world_base.gd` (POIs: police_station,
roadblock_site, hiding_spot; `get_roadblock_sites`, `nearest_road_transform`); the vehicle unit's
`ArcadeCar` + `CarSpec` presets (patrol, interceptor, heavy_suv) — police use the SAME car physics
with an AI input source (`set_controls`, `request_hop` etc.); npc_cars glbs `police_patrol`,
`police_interceptor`, `police_suv`, `police_drone` (light bar meshes `LightBar_Red/Blue`, Empty
`Siren`, drone `Spot`); props `roadblock_barrier`, `spike_strip`.

## Deliverables
1. `police_director.gd` (dispatcher): heat 0–5 per §3.4 (infractions start heat 1; time and
   disabled-unit counts raise it), unit budget per heat, spawning out of view on lanes ahead/behind
   or from police-station POIs, backup timers, roles assignment (pursue, ram, PIT, box trio,
   head-on SUV, roadblocks 350–450 m ahead on the predicted route at `roadblock_site` POIs or lanes,
   spike strips, drones at heat ≥ 4 with spotlight cone + EMP at 5).
2. Line of sight (raycasts every 0.2 s from roofs, 220 m ground / 350 m drone), evade → cooldown
   (×2 in hiding spots), busted meter (§3.2/3.4 rules; never while airborne/flying), sight loss when
   the player enters a sky lane (ground units) or flash-charges (1.0 s), pursuit end → reward toast.
3. Unit behaviour state machines per §6.3 table, using `ai/common` steering; catch-up rules; never
   more than 3 units within 30 m; despawn far units out of view.
4. Light bars: strobe pattern per art dossier §4.8 (or 2 Hz alternate) via instance parameters on
   `LightBar_Red/Blue`, plus one OmniLight3D each (no shadows) only for the 3 nearest units; sirens via
   the audio unit (emit signals/groups it can use — coordinate in status).
5. Radio chatter: emit `Events.toast(text, &"police")` for key moments with lines from §6.3 / audio
   unit's voice manifest ids if present.
6. Tests (sandbox): `test_heat.gd` (infraction → heat 1, timers raise heat, cooldown → escape),
   `test_busted.gd`, `test_roadblock.gd` (spawned ahead out of view, gap rules), `test_pit.gd`
   (a scripted player car on a straight gets PIT-ted within 30 s at heat 3), `test_drone.gd`.
   Windowed captures of a heat-3 chase on the sandbox loop and later the real map.

## Acceptance
Chases feel aggressive but fair (the lead plays it), tactics visibly happen, escape is possible by
the rules, police can be taken down (damage unit), perf ≤ 1.5 ms/frame with 12 units, tests pass.
