# Brief: npc_cars — traffic, taxis, buses and police vehicles (Blender)

## Goal
A believable 2030s Shanghai street fleet and a fictional cyber-police force, game-ready,
textured in detail, with named parts so they can crash, deform and lose panels.

## You own
`blender/npc_cars/**`, `game/assets/cars/npc/**` (one `.glb` per model + shared textures).

## Read first
`ART.md`, `CONTRACTS.md` §1, §2, §6 (node names), `ref/art/DOSSIER.md` §4.7 (car paint, traffic
colour mix), §4.8 (police livery "天巡 SKYPOL", light bar pattern, glass), `ref/gameplay/DOSSIER.md`
§3.4 (police vehicle classes), `ref/shanghai/SHANGHAI_DOSSIER.md` (vehicle section: taxis, buses,
police look — when present), `blender/lib/*` (use it).

## Models (all EVs; fictional brands, no real logos)
| File | Type | Size L×W×H m | Notes |
|---|---|---|---|
| `sedan_ev.glb` | 4-door EV sedan | 4.85×1.90×1.47 | the most common car; flush handles, light bars |
| `suv_ev.glb` | mid SUV | 4.75×1.93×1.68 | |
| `hatch_ev.glb` | small city EV | 3.95×1.77×1.55 | cute, rounded |
| `taxi.glb` | sedan variant | 4.85×1.90×1.47 + roof sign | fictional teal #1E8C8A "申城出租" roof light (emissive), door text, number |
| `robotaxi.glb` | 2-seat pod | 4.20×1.90×1.55 | cyberpunk flavour, roof LiDAR, white/black |
| `bus.glb` | 12 m electric city bus | 12.0×2.55×3.2 | "申城公交 71路" LED route sign (emissive), big windows, doors |
| `van.glb` | delivery van | 5.3×2.0×2.1 | "申城快递" livery |
| `truck.glb` | box truck | 7.5×2.35×3.3 | |
| `police_patrol.glb` | patrol EV sedan | 4.85×1.90×1.50 | livery per art dossier §4.8 ("天巡 SKYPOL", navy band, yellow pinstripe), light bar |
| `police_interceptor.glb` | low sports EV | 4.70×1.98×1.25 | aggressive, same livery family |
| `police_suv.glb` | heavy armoured SUV | 5.2×2.1×1.95 | ram bar, roof light bar |
| `police_drone.glb` | quad drone, Ø 1.6 m | | spotlight emitter marker `Spot`, red/blue strobes |

## Requirements
- Node names: root Empty named after the file; `Body`, `Glass`, `Wheel_FL/FR/RL/RR` (origin at wheel
  centre), `Bumper_F`, `Bumper_R`, `Hood`, `Door_FL/FR/RL/RR` (where they exist), `LightBar` (police),
  `Lamp_F`, `Lamp_R` (emissive meshes), Empties `Light_Front`, `Light_Rear`, `Siren` (police),
  `Spot` (drone), and inner dark surfaces behind detachable panels (as the hero car).
- Materials: body paint named `SH_car_paint_npc` (colour set in Godot per instance), glass
  `SH_glass_tinted`, everything else Principled with textures: tyres + rims (shared 1024 tread/
  sidewall normal), black trims, chrome-free modern details, lamp emissives (white front #EAF2FF
  E6, red rear #FF2030 E4), interior silhouettes (seats/dash visible through glass), plates
  (Shanghai blue plates for petrol-era vans/trucks "沪B·xxxxx", green NEV plates "沪A·Dxxxxx"
  for EVs — generate PNGs with PIL using `game/assets/fonts/NotoSansSC-Variable.ttf`).
- Police livery = 2048×1024 PNG on a second UV map, art dossier §4.8; no 警徽, no real emblems.
- Polycount LOD0: cars 10k–25k, bus/truck ≤ 30k, drone ≤ 8k. Shared texture sets (one trim sheet
  for tyres/rims/lights/plates; one for interiors) to keep draw calls low.
- Proportions and silhouettes must read correctly at 30–80 m (real wheel sizes, overhangs,
  greenhouse shapes) — look up real 2025–2026 Chinese EV proportions (e.g. sedans ~4.9 m, SUVs
  ~4.8 m) but invent the styling.

## Evidence / acceptance
For each model: `tools/blender.sh preview <glb> <name>` sheets (studio + night), stats with no
UNTEXTURED materials, correct bbox; a lineup render of all vehicles side by side (one image) with
a 1.75 m human scale figure; Godot import check scene `game/assets/cars/npc/preview_npc.tscn`
captured with `tools/godot.sh shot`. Police light bar emissive halves present and named
`LightBar_Red` / `LightBar_Blue` (so the police unit can strobe them).
