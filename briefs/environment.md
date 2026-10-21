# Brief: environment — night Shanghai look: WorldEnvironment, sky, weather, shared shaders

## Goal
Port the verified look-dev recipe into the game and own every shared shader/material so all
other units get the SKYRUSH look by naming materials `SH_*`.

## You own
`game/world/env/**` (Modules unit `environment`: `res://world/env/environment.tscn`) and
`game/shaders/**` (shared shaders + `game/shaders/materials/SH_*.tres` consumed by
`core/materials/material_library.gd`).

## Read first
`ART.md` (binding), `ref/art/DOSSIER.md` (all; §2–§5 are your spec), the VERIFIED look-dev project
`ref/art/lookdev/` (`env_recipe.gd`, `materials.gd`, `shaders/*.gdshader`, `fetch_assets.sh`,
`tools/screenshot_stats.py`), `ref/tech/GODOT.md` §3 (feature costs) and §5 (budgets),
`core/settings.gd` (quality presets), `core/materials/material_library.gd`, `CONTRACTS.md` §2.

## Deliverables
1. `world/env/environment.tscn` + scripts: WorldEnvironment from `env_recipe.gd` (AgX, glow levels,
   fog, volumetric fog, SSR, SSAO per quality preset — read `Settings.feature()` and re-apply on
   `Settings.changed`), the night sky shader + HDRI radiance (`shanghai_bund` 2K from Poly Haven via
   `python3 tools/textures/fetch.py hdri shanghai_bund`), the moon light (§3.3), and a **weather
   controller** that sets the shader globals `skyrush_wetness` (default 0.85, "after rain") and
   `skyrush_rain` (0 = dry; a `--rain` option or the menu turns rain on: 0.6) with smooth transitions.
2. `shaders/*.gdshader` ported from look-dev and adapted to read the globals:
   `road_wet` (uses `global uniform float skyrush_wetness/skyrush_rain`), `road_marking`,
   `facade_windows`, `neon_tube`, `hologram_billboard`, `car_paint`, `sky_night_city`, plus new:
   `glass_gold` (Roadster canopy: dark bronze-gold, metallic sheen, fresnel, faint interior visible
   at grazing angles, rain streak option), `water_river` (Huangpu: opaque, dark, two scrolling
   normals, SSR-friendly), `soffit_blue` (under-deck wash), `concrete_stained` (triplanar library
   textures + vertical streak mask + splash-zone darkening, instance uniform tint).
3. `shaders/materials/SH_*.tres` for: `SH_car_paint` (Roadster Ano White #ECEDEF: clear-coat,
   NO flakes/very fine flake, orange-peel micro-normal, wet grime on the lowest 0.3 m; must accept
   `normal_texture` from the imported material — the car's baked panel-gap map), `SH_car_paint_npc`
   (instance-uniform base colour for traffic), `SH_glass_gold`, `SH_glass_tinted` (NPC cars),
   `SH_wet_asphalt`, `SH_road_marking_white`, `SH_road_marking_yellow`, `SH_facade_office`,
   `SH_facade_residential`, `SH_neon`, `SH_hologram`, `SH_water`, `SH_soffit_blue`,
   `SH_concrete_pier`, `SH_concrete_barrier`. Each documented in `shaders/README.md` (uniforms,
   which `*_texture` uniforms MaterialLibrary fills from the imported material, instance uniforms).
4. Textures: fetch the CC0 sets named in art dossier §4–§5 with `tools/textures/fetch.py` (it writes
   `game/assets/textures/<id>/` + manifest; the library is shared — you may add to it, never delete).
5. `world/env/lookdev.tscn`: a look-dev scene inside the game (wet road with markings, a pier, a
   facade block with lit windows, neon signs, a hologram, river edge, the Roadster glb if present
   else a sphere set) for every art review. Camera presets via the capture tool.
6. Quality presets verified: low/medium/high/ultra frame cost table in your status (use the
   8-view method from tech dossier §3.1 or at least fps at 1080p in lookdev).

## Acceptance
`ref/art/lookdev/tools/screenshot_stats.py` on lookdev captures within the value targets
(art dossier §2.4: P50 0.10–0.24, SAT 2–15 %, HUES80 ≤ 3); all SH_ materials compile and appear
in the lookdev capture; the Roadster (once its glb exists) shows white clear-coat with crisp
reflections, gold glass, glowing red bar; wet road shows long light streaks; `tools/godot.sh
check --only=res://shaders/,res://world/env/` clean; preset costs within tech dossier §5 budget.
