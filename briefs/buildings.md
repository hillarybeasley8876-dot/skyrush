# Brief: buildings — procedural Shanghai city blocks (Blender)

## Goal
Fill every block of the map with believable, detailed, varied Shanghai buildings that read at
street level (shopfronts, signs, AC units, window cages, laundry poles) and from the air (setbacks,
lit crowns, rooftop clutter), cheaply enough for a 4 × 3 km open city at 60 fps.

## You own
`blender/city/buildings/**`, `game/assets/city/blocks/**` (tile glbs + shared textures/atlases).

## Read first
`data/city/SCHEMA.md` (Block), `data/city/test_city.json` (develop on it; switch to `city.json`
when `status/city_layout.md` says it validates), `ref/shanghai/SHANGHAI_DOSSIER.md` §9 (street kit:
shikumen spec, Nanjing Rd neon blades, plane trees), §10.5 (district styles), §11 (palette);
photos `ref/shanghai/img/09_*` and contact sheets; `ref/art/DOSSIER.md` §4.4 (facade shader presets:
office/residential), §4.5 (neon sign rules: stroke widths, backplates), §4.9 (shikumen brick,
granite), §5 (texture IDs), §7 (typography, parody brand list); `ART.md`; `CONTRACTS.md` §2;
`ref/tech/GODOT.md` §4–5 (draw calls, MultiMesh, HLOD, occluders); `blender/lib/*`.

## Building types (one generator module each, all seeded/deterministic)
- **shikumen**: 2–3-storey row houses in lanes (弄堂 3–4 m wide inside the block, gate arch with the
  lane name 「xx里」 on a stone plaque), grey-blue brick with red bands, stone door frames with carved
  pediments, black lacquer doors, wooden windows, tiled roofs + dormers (老虎窗), laundry poles.
- **midrise** (6–12 floors, 1980s–2000s): white/beige tile or grey render, ground-floor shops with
  lightbox signs (generated Chinese parody names), AC units under windows, window security cages,
  balconies, rooftop water tanks + antennas, some rooftop billboard frames.
- **residential_slab** (18–30 floors): repetitive balconies, lit windows (facade shader residential
  preset), stair/elevator cores, rooftop red aviation lights.
- **office_tower** (20–60 floors): curtain wall using `SH_facade_office` (instance seed), podium with
  lobby glazing, crowns with emissive edge lines (white/cyan/magenta per district palette), setbacks.
- **heritage** (D1 back rows): 6–10-storey 1920s–30s stone blocks: rusticated base, string courses,
  cornices, granite texture, warm window glow (Bund front row is a separate unit).
- **neon_street** (Nanjing Rd D2): midrise + dense vertical neon blade signs (1.0–1.5 × 3–8 m, both
  sides, stacked) with Chinese parody names rendered by PIL into an emissive atlas (`SH_neon`
  compatible), big LED screens (hologram/LED shader material slot `SH_hologram`).
- **industrial** (D9): warehouses (corrugated 彩钢板 light blue), sound walls, billboards on poles.
- **park / plaza**: ground cover (paving, lawns, trees as instanced low-poly), lamp spots, benches.

## Technical rules
- Ground floor (0–8 m) is hand-built geometry with real depth (recessed shopfronts, awnings,
  signs); above that, facades are low-poly boxes with textured/shader materials (windows via
  `SH_facade_office` / `SH_facade_residential`; give each building `extras.building_seed` and
  `extras.style` metadata so the world unit sets instance uniforms).
- Real scale: floor height 3.0 (residential) / 3.9 (office) m; doors 2.1–2.6 m; plausible
  footprints per style; setbacks per block `setback`.
- Tiles: same 512 m tiling as roads → `blocks_<tx>_<tz>.glb`; merge per material per tile;
  per building a convex/box `-convcolonly` collider only within 25 m of a road edge; HLOD: also
  export `blocks_<tx>_<tz>_far.glb` (merged boxes with an emissive window atlas) for distances
  > 350 m; occluder boxes list in `extras.occluders` (or a sidecar JSON) for the world unit.
- Budgets per tile: ≤ 600k tris near, ≤ 40k far; ≤ 40 materials; textures shared (trim sheets
  2048², atlases for signs).
- Text on signs: real Chinese words, parody brands only (art dossier §7), never gibberish.

## Process / evidence
Develop each type in isolation (`blender/city/buildings/demo_<type>.py` → preview sheets), then the
test city, then the real map. Godot check scene `game/assets/city/blocks/preview_blocks.tscn` with the
environment unit's environment if present: street-level and aerial captures at night. Measure tile
build time and tris in status.

## Acceptance
Street-level captures look like Shanghai streets at night (not grey boxes): shopfront depth, signs,
AC units, lit windows varied, no repetition visible in one frame; aerial captures show dense,
varied skyline with lit crowns; budgets met; colliders present near roads; no buildings overlapping
roads, sidewalks or water (test script checks every building footprint against city.json).
