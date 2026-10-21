# Brief: props — street kit and special sites (toll plaza, gas & charge stations, sky lanes)

## Goal
Every object that furnishes the streets and the gameplay sites, modelled and textured in detail:
these are what the camera passes at 2–20 m at 250 km/h, so they carry the "detail" feeling.

## You own
`blender/props/**`, `game/assets/props/**` (one glb per prop or per site + shared atlases),
`tools/signs/**` (sign/plate/text texture generators).

## Read first
`ref/shanghai/SHANGHAI_DOSSIER.md` §2.4 (deck lamps, planters, noise walls), §2.6 (gantries, guide
signs, VMS, markings), §4 (tunnel signals/fans), §7 (toll plaza full spec), §8 (gas station "中国石华
SINOPEX" + charging "SKY 闪充 FLASH" specs), §9 (street kit table: lamps incl. magnolia 玉兰灯 and
heritage lamps, traffic lights, road-name signs blue/green rule, bus stop, plane trees, metro
entrance, taxi/police notes), §11 palette; photos `ref/shanghai/img/02_*`, `07_*`, `08_*`, `09_*`;
`ref/gameplay/DOSSIER.md` §3.4 (pursuit breakers: gas canopy supports, scaffolding, billboards),
§5.6 (sky-lane signage: gantry "飞行航道 SKY LANE ▲ 300 m", launch pad 30 m ramp with chevrons,
ring gates Ø 14 m), §5.7 (obstacle heights); `ref/art/DOSSIER.md` §4.5 (neon rules), §4.8 (police
livery — not yours, npc_cars), §6 (decals), §7 (typography); `ART.md`; `CONTRACTS.md` §2.
Fonts: `game/assets/fonts/` (Noto Sans SC, Smiley Sans; OFL). PIL is available in `/usr/bin/python3`.

## Street kit (each ≤ 3k tris unless noted, LOD-friendly, textured, pivot at ground)
Lamps: `lamp_deck_double` (11 m, 2 arms 2.5 m, LED heads emissive + Empty `Light`), `lamp_street`,
`lamp_magnolia` (9 white petal globes), `lamp_heritage` (Bund cast iron), `lamp_shikumen` (wall
bracket); `traffic_light_mast` (7 m arm, vertical heads + countdown box, emissive lens meshes named
`Lens_R/A/G` for the world unit to switch); `road_name_sign` (template + generator); `guide_gantry`
(box truss spanning a parameter width — export 3 widths 19/27/34 m) + `guide_sign` panels generated
from text by `tools/signs/guide_sign.py` (green `#00704A`, white Chinese 0.55 m + English 0.28 m,
lane arrows); `vms_board` (LED schematic emissive); `bus_stop` (with backlit ad + route board);
`plane_tree` (trunk with mottled bark, canopy cards — 3 variants, ≤ 6k tris), `planter_pot`
(white box + bougainvillea / privet variants, 2 meshes ≤ 300 tris for instancing), `noise_wall`
(3.5 m panel + post module), `metro_entrance` (+ parody logo totem), `bin`, `bollard`,
`hydrant`, `bike_share` (parody 2–3 colours) and `e_scooter`, `ac_unit`, `cone`, `crash_barrier`,
`crowd_barrier`, `billboard_pole` (pursuit breaker: supports named `Support_1/2`), `scaffold`
(breaker), `neon_blade_frame`, `hologram_projector`.
Police kit: `roadblock_barrier`, `spike_strip` (animated deploy pose), `police_sign_board`.

## Sites (each a single glb with named parts; real dimensions from the dossier)
1. `toll_plaza.glb` — dossier §7.2: 110 × 20 m canopy, bull-nose fascia with the fictional
   「申城西收费站 SHENCHENG WEST TOLL」 sign, per-lane signal boxes (emissive meshes `LaneSignal_<n>`
   red ✕ / green ↓), islands with crash cushions, booths, **barrier arms as separate nodes**
   `Barrier_<n>` (pivot at the hinge; the world unit makes them breakable), ETC gantry, high-mast
   lights (Empties `Light_*`), plaza pavement with joints. Collision `-convcolonly` for islands,
   booths, columns, canopy.
2. `gas_station.glb` — §8.1 "中国石华 SINOPEX": canopy (underside y 6.0) with red fascia, LED
   downlights (emissive), 6 columns named `Support_1..6` (pursuit breaker: the world unit can drop
   the canopy when supports are hit), dispensers, bollards, price pylon, store "易快 EZ-JOY".
3. `charge_station.glb` — §8.2 "SKY 闪充 FLASH": canopy with cyan LED line, 12 bays, 6 slim white
   posts ("VOLTA" red lit text) + 6 boom dispensers, kW readouts (emissive), totem. Empty
   `ChargeArea` (centre + size in extras) for the world unit's ChargeStation trigger.
4. `sky_lane_pad.glb` (30 m launch ramp with animated-chevron emissive material slots
   `Chevron_*`), `sky_lane_gate.glb` (hologram ring Ø 14 m, magenta chevrons; material `SH_hologram`),
   `sky_lane_gantry.glb` (overhead sign "飞行航道 SKY LANE ▲ 300 m").

## Evidence / acceptance
`tools/blender.sh preview` sheets per prop (night + studio, no UNTEXTURED), a lineup image of the
street kit with a 1.75 m figure for scale, and a Godot scene `game/assets/props/preview_props.tscn`
with the environment: captures of the toll plaza, gas station and charge station at night from
the driver's view and from a hop apex (7 m up). Text on every sign is correct Chinese + English.
