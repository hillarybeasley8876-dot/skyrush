# Brief: landmarks — Lujiazui towers, Oriental Pearl, bridges, dragon pillar (Blender)

## Goal
The skyline icons at real size with night lighting: they are visible from everywhere in the map
and sell "this is Shanghai" in every screenshot.

## You own
`blender/landmarks/**`, `game/assets/landmarks/**`.

## Read first
`ref/shanghai/SHANGHAI_DOSSIER.md` §1.2 (dragon pillar spec: Ø 5 m × 29.4 m, brushed steel +
dark archaic bronze relief of 9 dragons, sun/moon, thunder-pattern background — DO/DON'T), §3
(Nanpu towers H-shape with bent legs, 150 m, cable fans, red name sign; Lupu arch silhouette),
§5.5 (Waibaidu steel truss bridge, exact dimensions), §6 (Oriental Pearl geometry table, Jin Mao
13 tiers, SWFC aperture, Shanghai Tower twisting rings, Pearl Ring skybridge), §6.4 (skyline order),
§11 palette, §12; photos `ref/shanghai/img/01_*`, `03_*`, `05_*`, `06_*` + `sheets/c_pillar.jpg`;
`ref/art/DOSSIER.md` §4.4 (facade shader for tower glass), §4.6 (LED/hologram), §2.3 (emission
tiers); `ART.md`; `CONTRACTS.md` §2; `blender/lib/*`.

## Assets (each its own .glb in `game/assets/landmarks/`, origin at its anchor on the ground)
1. `oriental_pearl.glb` — 3 Ø 9 m tubes + 3 Ø 7 m braces at 60°, lower sphere Ø 50 (centre y 93),
   5 small spheres Ø 12, upper sphere Ø 45 (centre 272.5), space module Ø 14 (335–349), antenna to
   468 m, podium. Spheres: pink-magenta glass `#B0306A` with silver bands; separate emissive
   **LED dot-grid** surfaces (material `SH_hologram` mode LED or an emissive with a dot texture) the
   world unit animates pink→violet→blue; vertical tube light strips `#7A4CFF`; red aviation light.
2. `jin_mao.glb` — octagonal pagoda tiers (13, heights per §6.2 GAME details), aluminium fins every
   1.5 m, glass `#3E4A52`, gold `#FFD27A` emissive edge lines on every setback, crown + spire.
3. `swfc.glb` — square prism cut by two sweeping arcs narrowing to a blade, inverted-trapezoid
   aperture (440–472 m) with the skywalk beam, reflective glass `#5C7A8C`, white edge lines.
4. `shanghai_tower.glb` — 120 stacked rings rotating to 120° and scaling to 0.5, rounded-triangle
   plan with the V-notch, double-skin look, white floor-band dots `#E6F2FF`, crown fins 546–632 m.
5. `pearl_ring.glb` — circular skybridge Ø 117.5 m, deck 9.7 m at y 6.5, Y-columns, glass balustrade,
   LED handrail, stairs/escalators at 4 points, `-colonly` deck collider (it spans roads: keep 5.5 m
   clearance).
6. `lujiazui_backdrop.glb` — 8–12 generic but distinct 150–260 m towers (IFC twins, etc.) with lit
   crowns, for density behind the trio.
7. `nanpu_bridge.glb` — 2 H-towers with bent legs (150 m), crossbeams, red 「南浦大桥」 name sign
   (emissive at night), cable fans (180 cables, thin cylinders/flat strips with white lit lines),
   tower floods; cable deck ends attach to the roads unit's `CableAnchor_*` positions (read
   `game/world/data/road_furniture.json` when it exists; until then use dossier §3.2 numbers).
8. `lupu_bridge_far.glb` — low-poly half-through arch silhouette with emissive rainbow arch lights.
9. `waibaidu_bridge.glb` — riveted through-truss, 2 spans of 52.18 m, curved top chord 9.144 m
   mid-span, timber sidewalks, silver-grey paint `#9AA0A6`, warm LED lines `#FFC24D`, drivable
   deck collider (road surface itself from the roads unit — coordinate: you supply truss + sidewalks,
   roads supplies the carriageway; leave the carriageway 11.2 m clear).
10. `dragon_pillar.glb` — Ø 5 m column + plinth, brushed steel with a **generated relief texture set**
   (normal + height + AO + curvature, 4096 × 2048 wrapping the column, made procedurally in Python/
   numpy or Blender: archaic angular kui-dragons spiralling, square-spiral 雷纹 background, sun/moon
   discs) — this is a hero close-up object; must look crafted, not noise.
11. `broadway_mansions.glb` belongs to the bund unit — not you.

## Lighting
Each glb exports Empties for the world unit's lights (`Flood_*`, `Aviation_*`) and named emissive
meshes (`LED_*`) that the world unit can animate. Emission tiers per art dossier §2.3 (crowns E3–E4,
large LED areas ≤ E2.5 so the frame does not flood).

## Evidence / acceptance
Per asset: Blender previews (night + studio) and a side-by-side vs a reference photo; a Godot scene
`game/assets/landmarks/preview_skyline.tscn` placing all at their dossier anchors with the
environment: captures (a) from the Bund promenade looking east (order: OPT front-left, trio behind,
Shanghai Tower tallest and rightmost), (b) from Century Ave, (c) Nanpu bridge from the spiral,
(d) dragon pillar close-up at night with 4 warm uplights. Polycount ≤ 150k per tower, pillar ≤ 60k
(detail in textures).
