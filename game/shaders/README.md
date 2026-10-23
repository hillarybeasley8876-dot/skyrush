# SKYRUSH shared shaders and materials (shaders unit)

Every surface in the game uses one of the materials in `materials/SH_*.tres`. The `SH_` prefix is
the contract: a material with that name in an imported glTF is replaced at runtime by the matching
file in this folder (`core/materials/material_library.gd`). The shaders themselves are the port of
the verified look-dev (`ref/art/lookdev/`), adapted to the game and documented here.

Read `ART.md` (binding) and `ref/art/DOSSIER.md` §2–§5 for the numbers behind these values.

## Global uniforms

| Global | Type | Range | Who writes it |
|---|---|---|---|
| `skyrush_wetness` | float | 0 dry .. 1 soaked (default 0.85 = "just after rain") | `world/env/weather_controller.gd` |
| `skyrush_rain` | float | 0 dry .. 1 raining (0.6 while it rains) | `world/env/weather_controller.gd` |

Shaders that react to the weather declare them with `global uniform float skyrush_wetness;`.
A per-material `wetness_bias` / `rain_bias` is added to the global, so a single material can be
made drier or wetter than the weather without touching the global.

```gdscript
RenderingServer.global_shader_parameter_set(&"skyrush_wetness", 0.85)
```

## Instance uniforms vs plain uniforms (important)

* **Plain** `uniform` — one value per material. It is saved in the `.tres` and is what you use for
  per-material differences (hero car vs traffic car, office vs residential facade).
* **instance uniform** — one value per mesh instance, set with
  `mesh.set_instance_shader_parameter("name", value)`. Use it for per-object variety
  (neon colour, car colour, building seed, concrete tint).

**A material-level value for an instance uniform is ignored by the renderer.** Godot cannot store
instance-uniform defaults in a `.tres`, and `ShaderMaterial.set_shader_parameter()` on an instance
uniform does not reach the shader either. This was measured, not assumed:
`shaders/tests/instance_uniform_probe.gd` renders three spheres and shows that a material-level
instance default is ignored while a per-instance override works.

Consequence: the per-object values below carry their default **in the shader source**, and the unit
that owns the object must set the override itself. `SH_car_paint_npc` therefore paints traffic cars
Ano White until the traffic director sets `base_color` per car.

## Shaders

| File | Used by | Notes |
|---|---|---|
| `road_wet.gdshader` | `SH_wet_asphalt` | World-space UV, anti-tiling double sample, macro variation, wetness, puddles, rain ripples. Vertex colour R = wheel-track polish, G = gutter (collects water). |
| `road_marking.gdshader` | `SH_road_marking_white`, `SH_road_marking_yellow` | Paint on thin mesh strips 5 mm above the asphalt. `mask_texture` + `use_mask` for baked glyphs. Retro-reflective fake within 70 m. |
| `facade_windows.gdshader` | `SH_facade_office`, `SH_facade_residential` | Procedural floors/bays/windows, per-building `building_seed`, cladding texture + rain grime, LOD fade below ~2 px per cell. Window emission peaks at 0.95 so windows never bloom. |
| `neon_tube.gdshader` | `SH_neon` | White-hot core, saturated rim, dropout/faulty flicker, flat LED strip mode. |
| `hologram_billboard.gdshader` | `SH_hologram` | mode 0 = LED dot grid (tower screens), mode 1 = additive hologram with scanlines, chroma split and glitch. |
| `car_paint.gdshader` | `SH_car_paint`, `SH_car_paint_black`, `SH_car_paint_npc` | Clear coat, orange-peel micro-normal, fine flake, livery on UV2, road grime in the lowest 0.3 m, rain water film. |
| `sky_night_city.gdshader` | (the sky, not a mesh) | Gradient + city-lit cloud deck; the radiance cubemap pass samples the real `shanghai_bund` HDRI at 0.18 energy and cross-fades to `vignaioli_night` while it rains (`rain_mix`). |
| `glass_canopy.gdshader` | `SH_glass_smoke` | Roadster canopy: neutral dark smoke (the first Roadster had bronze-gold), fresnel, metallic sheen, faint interior, rain streaks. |
| `glass_tinted.gdshader` | `SH_glass_tinted` | Dark tinted glass for traffic cars. |
| `water_river.gdshader` | `SH_water` | The Huangpu: opaque, very dark, two scrolling normals 40 deg apart, plus rain ripples while it rains, SSR friendly. |
| `soffit_blue.gdshader` | `SH_soffit_blue` | Under-deck wash (#2357F3, E1 = 0.9) plus the two edge LED strips (E3). UV: u = along the deck in METRES, v = across it. |
| `concrete_stained.gdshader` | `SH_concrete_pier`, `SH_concrete_barrier`, `SH_granite_bund`, `SH_kerb`, `SH_sidewalk`, `SH_tactile` | Triplanar library textures, thin vertical rain drips (the Leaking004 opacity sheet, mapped once over the 1.8-6 m band), splash-zone darkening, masonry courses, per-instance tint. |

## Materials (`materials/SH_*.tres`)

Every material is a `ShaderMaterial` pointing at one of the shaders above.

### Which textures `MaterialLibrary` fills in

`core/materials/material_library.gd` copies the imported glTF material's textures into the
matching shader uniforms **when the shader declares them**:

| Imported glTF slot | Shader uniform | Present in |
|---|---|---|
| albedo | `albedo_texture` | road_wet, facade_windows, car_paint, glass_canopy, glass_tinted, neon_tube, soffit_blue, concrete_stained |
| normal | `normal_texture` | road_wet, facade_windows, car_paint, soffit_blue, concrete_stained |
| roughness | `roughness_texture` | road_wet, car_paint, concrete_stained |
| emission | `emission_texture` | neon_tube, hologram_billboard |

The imported COLOURS are not forwarded yet (`core/materials/material_library.gd`): a sign that exports
`SH_neon` with its own emission colour renders in the library default until core copies
`albedo_color` → `albedo_color` and `emission` → `emission_color`.

So a road glTF that carries its own asphalt map automatically replaces the library texture in
`SH_wet_asphalt`, and the Roadster's baked panel-gap map replaces the normal in `SH_car_paint`.
All other uniforms stay as the `.tres` sets them.

### The material list

| Material | Shader | Key values | Instance uniforms (set per object) |
|---|---|---|---|
| `SH_wet_asphalt` | road_wet | `albedo_mul 0.50` (asphalt_02 -> wet #2A2A2A), `tile_m 3.0`, `macro_tex` aerial_asphalt_01 at 30 m, `puddle_amount 0.24`, wet roughness 0.18 | - |
| `SH_road_marking_white` | road_marking | `paint_color #E9E7DF`, `wear 0.25` | - |
| `SH_road_marking_yellow` | road_marking | `paint_color #E8B520`, `wear 0.35` | - |
| `SH_facade_office` | facade_windows | `floor_h 3.9`, `bay_w 1.5`, `lit_ratio 0.15` (6-7 % of the facade), `ground_floors 2.0`, wall `#383A3E` | `building_seed` |
| `SH_facade_residential` | facade_windows | `floor_h 2.95`, `bay_w 3.3`, `lit_ratio 0.22`, `tv_ratio 0.05`, wall `#8E877C`, `blinds_max 0.9` | `building_seed` |
| `SH_neon` | neon_tube | `emission_color #FF2A8A`, `emission_energy 5.0` (E3 4-6, hero E4 8-12), `core_whiten 0.12`, `dropout_rate 0.015`; the imported base-colour and emission maps mask the tube colour | `neon_color` (alpha > 0 = valid), `neon_energy` (> 0 = valid), `neon_seed`, `faulty`, `is_flat_strip` |
| `SH_hologram` | hologram_billboard | `emission_texture` = the ad artwork (the props' own PNG is forwarded here), `scan_lines 220`, `chroma_px 2`, `glitch_rate 0.08` | `mode`, `energy`, `tint` |
| `SH_car_paint` | car_paint | Ano White `#ECEDEF`, `base_roughness 0.12`, `clearcoat 1.0 / 0.04`, `flake_strength 0.06`, `grime_amount 0.15`, `grime_height_m 0.30`, orange peel 0.10 in object space, the clear coat broken up by the `SurfaceImperfections001` dust sheet (object space, 2 m tile) | `base_color_override` (alpha > 0 = valid), `panel_offset_y` |
| `SH_car_paint_black` | car_paint | the gloss black of the two-tone Roadster: `#0B0C0E`, `base_roughness 0.10`, `clearcoat 1.0 / 0.03`, no flake, grime as the white paint. The rival cars keep it black when they take their racing colour (`RivalVisual`) | `base_color_override`, `panel_offset_y` |
| `SH_car_paint_police` | car_paint | POLICE_WHITE `#F2F4F5`, metallic 0, `base_roughness 0.35`, clear coat 1.0 / 0.06, grime 0.35 | `base_color_override`, `panel_offset_y` |
| `SH_car_paint_taxi` | car_paint | the fictional teal `#1E8C8A`, metallic 0.2, `base_roughness 0.38`, clear coat 0.9 / 0.07 | `base_color_override`, `panel_offset_y` |
| `SH_car_paint_npc` | car_paint | `metallic 0.3`, `base_roughness 0.42`, `clearcoat 0.8 / 0.08`, `flake_strength 0.2`, `grime_amount 0.45`, `grime_height_m 0.45` | `base_color_override` (**the traffic director must set it per car**), `panel_offset_y` |
| `SH_glass_smoke` | glass_canopy | tint `#0A0B0C`, `base_alpha 0.55`, `fresnel_opacity 0.8`, `sheen_strength 0.45`, `roughness 0.04`, the grime and the rain streaks in object space, the imported grime at its authored UV | - |
| `SH_glass_tinted` | glass_tinted | tint `#0A0E12`, `base_alpha 0.72`, `roughness 0.08`, `grime_amount 0.25` | - |
| `SH_water` | water_river | `#0B1016`, `roughness 0.08` (DOSSIER 4.9), `wave_strength 0.38`, two normals at 0.6 / 0.25 m/s 40 deg apart, `tile_m 6.0` | - |
| `SH_soffit_blue` | soffit_blue | wash `#2357F3` at `wash_energy 0.9` with `wash_falloff 0.45` (100 % at the outer edge, ~55 % toward the girder), the strips `#5A3DFF` E3 (4.5) and 5 cm wide (`strip_width_m` / `soffit_width_m`), the formwork joints every 1.2 m (u in METRES) and the girder lines at v = 0.25 / 0.5 / 0.75, the water stains from the `Leaking004` OPACITY sheet, `uv_scale 1.0` | - |
| `SH_concrete_pier` | concrete_stained | `concrete` 4 m, `base_color #7A7874`, `tex_mean` = the scan's measured mean, `detail_mean` = the detail scan's own mean, `streak_amount 0.18`, `drip_amount 0.35` (the Leaking004 opacity stains, 1.8-6 m), `splash_height_m 0.6` | `tint_override`, `splash_override`, `base_y` |
| `SH_concrete_barrier` | concrete_stained | `concrete_wall_008` 2.71 m, `streak_amount 0.22`, `drip_amount 0.25`, `splash_height_m 0.35` | `tint_override`, `splash_override`, `base_y` |
| `SH_granite_bund` | concrete_stained | the conditioned `granite_bund` scan over the `granite_tile_03` detail, 1.8 m, `normal_scale 0.5` (DOSSIER 4.9), masonry courses 0.45 x 1.8 m, `streak_amount 0.12`. The gold comes from the 2500 K uplights, never from the albedo | `tint_override`, `splash_override`, `base_y` |
| `SH_sidewalk` | concrete_stained | `PavingStones144` 1.4 m, `#6E6C68`, no splash zone (it is flat), wet-darkened | `tint_override`, `splash_override`, `base_y` |
| `SH_kerb` | concrete_stained | the Bund granite darkened to `#8E8C86` (DOSSIER 4.9), 1.8 m | `tint_override`, `splash_override`, `base_y` |
| `SH_tactile` | concrete_stained | the 30 cm yellow tactile strip (盲道) at the kerb edge, `TactilePaving003` 1.2 m | `tint_override`, `splash_override`, `base_y` |

### Emission tiers (DOSSIER 2.3)

Windows and the soffit wash stay at E1 (below the glow threshold 1.2, they never bloom). Neon tubes
and LED strips are E3 (4-6). The hero sign of a frame may go E4 (8-12). The Roadster's red light bar
is E4 (10) - that is the car unit's material, not this library.

## Regenerating the materials

The `.tres` files are generated from one place so the whole library can be re-tuned together:

```
tools/godot.sh test res://shaders/material_factory.gd
```

`material_factory.gd` writes every `SH_*.tres`. It is the source of truth for the values above;
hand-editing a `.tres` is fine (they are plain text) but a regeneration overwrites it.

**A missing texture is FATAL.** The factory counts every texture a recipe asked for and could not
find, prints `MATERIAL FAIL missing texture <path>` and exits 1. The same goes for a material that
loses its parameters on save (a shader that does not compile). `test_materials.gd` checks the
saved files: every sampler of every material must be bound to a texture, except the ones
`MaterialLibrary` fills at runtime from the imported material.

## Tests

```
# the tests are Node scripts (the core test host loads them after the autoloads exist)
tools/godot.sh test res://shaders/tests/test_materials.gd     # every material + shader loads and is complete
tools/godot.sh test res://shaders/material_factory.gd         # regenerates the SH_*.tres
tools/godot.sh run  res://shaders/tests/instance_uniform_probe.tscn 6   # visual probe (needs a window)
```
