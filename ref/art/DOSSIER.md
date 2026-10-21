# SKYRUSH: NEON SHANGHAI (飞驰申城) - Art Direction & Texture Dossier

Version 1.0 - 2026-10-19 - target: Godot 4.7.2 Forward+ (tested on Metal, Apple M1 Max), Blender 5.2 LTS.
Written for the implementer (MiniMax M3.1): follow the numbers literally. When a number is marked
**(est.)** it is a reasoned starting value, **(unverified)** means no source was found, **[V]** means it was
rendered and checked in the look-dev scene `ref/art/lookdev` on Godot 4.7.2, **[S]** means it comes from a cited source.

## 0. Files that come with this dossier

| Path | What it is |
|---|---|
| `ref/art/lookdev/` | Small Godot 4.7.2 project that renders the recipe. Run `bash fetch_assets.sh`, then once `Godot --headless --path ref/art/lookdev --import`, then `Godot --path ref/art/lookdev --resolution 1280x720 -- out=res://renders/x.png frames=150` (Godot = `/Applications/Godot.app/Contents/MacOS/Godot`; opens a window ~5 s, writes the PNG, quits) |
| `ref/art/lookdev/env_recipe.gd` | **[V]** WorldEnvironment + sky + fog + glow + tonemap recipe. Copy unchanged into the game. |
| `ref/art/lookdev/materials.gd` | **[V]** Material factory (road, paint, facade, neon, hologram, car paint, granite, chrome, rubber, glass, emissive) |
| `ref/art/lookdev/shaders/*.gdshader` | **[V]** 7 shaders: `sky_night_city`, `road_wet`, `road_marking`, `facade_windows`, `neon_tube`, `hologram_billboard`, `car_paint` (all compile on 4.7.2, no errors) |
| `ref/art/lookdev/tools/bake_road_glyphs.py` | **[V]** Headless Blender script: bakes Chinese road-text glyphs (GB 1:3 stretch) + GB straight arrow as PNG decals |
| `ref/art/lookdev/tools/screenshot_stats.py` | **[V]** Measures a screenshot against the value/colour targets of section 8 (no PIL, needs ffmpeg) |
| `ref/art/lookdev/tools/fetch_textures.sh` | **[V]** Downloads the whole section-5 shopping list (CC0) + HDRIs and applies the 5.4 conditioning |
| `ref/art/img/INDEX.md` | 25 reference images (real Shanghai night photos with licences, genre mood shots, look-dev baseline, GB arrow figure) |

Rule zero: never invent a new colour, energy or texture outside this document. If something is missing, add it here first.

## 1. The look

### 1.1 One-paragraph definition
SKYRUSH is **"real Shanghai at 23:00 after rain, pushed 15 % toward cyberpunk"**: a dark, wet, blue-violet city
(sky and haze around sRGB #070A16-#3B3247) whose structure is drawn by light, not by surfaces. Every district has
**one signature light** taken from the real city - golden 2500 K uplit granite on the Bund, saturated LED blue on the
underside of the Yan'an elevated road, red-orange-yellow neon stacks on Nanjing Road, magenta/cyan LED crowns and
facade ads in Lujiazui, an orange sodium filigree when seen from the air - and everything else stays quiet so that
signature can read. Wet asphalt doubles every light as a long streak reflection. Surfaces up close are richly
textured (grit, cracks, paint wear, stains, rubber marks, rain ripples) but darker than the lights they reflect.
The player's red Roadster, its white cold-gas thruster plumes and the police red/blue strobes are the only things
allowed to compete with the city signature in a given frame.

### 1.2 What real Shanghai looks like at night (use these facts, they make it "recognisable")
- **Bund (外滩)**: 38 buildings, ~29,800 LED fixtures (2018 upgrade), switched on together at 19:00 in a ~10 s cascade
  ("高光十秒") and off at 23:00. Colour temperature adjustable 1800-3000 K; daily mode **~2500 K**, summer 3000 K,
  **1800 K = the signature "golden halo" mode**. Fixtures are hidden: "见光不见灯" (you see light, not lamps). [S]
  (news.china.com 2026-08-28; shanghai.gov.cn 2026-08-20; jfdaily). Peace Hotel's pyramid roof is lit green-teal (sh01).
- **Elevated roads (延安高架 / 南北高架 / 内环)**: the "申"-shaped elevated network has full-colour LED landscape
  lighting under the theme "东方彩带·上海动脉" (wenhui.com.cn 2021-05-03); historically the underside used blue-violet
  fluorescent tubes (lightingchina.com news 21887). Today the soffit reads **saturated blue #2357F3** (measured, sh05). [S]
- **Nine-Dragon Pillar (九龙柱)**: the giant pier at the Yan'an x North-South elevated junction, clad in stainless steel
  and copper dragon reliefs that read gold (jfdaily). Must exist, lit by 4 warm uplights (est.). [S]
- **Lujiazui**: dark tower masses; a few facades carry giant LED ads (blue #0649D7, red #C62B42 measured, sh03);
  Oriental Pearl spheres magenta, tower crowns cyan/white (est. from sh10). Riverside lighting runs ~18:00/19:00 to 22:00/23:00
  depending on season and events (sina.cn 2018-10-26; shanghai.gov.cn 2024-09-28). [S]
- **Nanjing Road (南京路)**: dense vertical CJK neon, red/orange/yellow dominated (#C3431B #CE1F39 #DEAB20, sh07),
  historic department stores washed gold with violet/blue dome accents (sh08). [S]
- **From the air**: black ground, orange road grid (#BA882F, sh04) - the template for flight sections. [S]
- **Guide signs**: expressways / urban express (elevated) roads use green signs with white text (sh06 shows green
  gantries); ordinary streets use blue signs (GB 5768.2 convention, (est.) for exact hues).

### 1.3 What we take from each genre reference (ref/art/img/cp*)

| Reference | Take | Leave |
|---|---|---|
| Cyberpunk 2077 | practical-light density at street level, signage hierarchy, magenta/teal accents | character-level clutter, yellow-green UI tint |
| Blade Runner 2049 | huge scale cues, haze that swallows distance, restraint (few lights, big darkness) | the orange sandstorm (only as a weather event) |
| Ghost in the Shell 1995 | dense CJK street signage, teal dusk over water, aerial street grid | cel-shading |
| NFS 2015 / Heat | wet asphalt mirror, light bars reflected in road, purple/blue neon on chase routes | permanent rain + total desaturation (2015) |
| RUINER | red monochrome as a *state* (police heat max) | as a default palette |

### 1.4 Do / Don't (each line is checkable on a screenshot)
DO
1. Keep a value hierarchy: sky < building mass < street surfaces < lit facades < signs < hero lights (numbers in 2.4).
2. Give each frame one dominant accent family plus at most two secondaries (screenshot_stats HUES80 <= 3).
3. Make every bright sign within 40 m produce a visible vertical streak on the wet road (SSR + probe).
4. Light the Bund gold with 2500 K uplights on neutral grey stone (albedo ~#ABAAA3), never with gold albedo.
5. Keep building silhouettes darker than the sky behind them (sky horizon #3B3247 + city glow #5A4048).
6. Put texture detail where the camera is: road, curbs, barriers, piers, the first 8 m of facades.
7. Use real Chinese road paint dimensions (section 6) and real CJK typography (section 7).
8. Break every tiling texture with macro variation + decals (section 5.3).

DON'T
1. No flat unlit grey boxes: every visible surface needs a texture, a facade shader or an emissive role.
2. No neon everywhere at equal intensity: max 15 % saturated-bright pixels (26 % only on Nanjing Rd).
3. No pure black #000000 anywhere except tyre shadows; no pure white albedo (> #F0F0F0).
4. No glowing windows: office windows stay below the glow threshold (energy <= 1.0).
5. No sub-pixel neon: strokes must be >= 2 px at the distance they are seen (section 4.5).
6. No gold-foil puddles: always place a ReflectionProbe; HDRI radiance energy <= 0.25.
7. No real brands, logos, police emblems (警徽) or real phone numbers.
8. No orange fire from the Roadster thrusters: cold gas = white/blue-white condensation plumes.

### 1.5 District mood table (one signature light per district)

| District | Signature light (energy tier, 2.3) | Secondary | Haze / fog | Saturated-bright budget |
|---|---|---|---|---|
| Bund 外滩 (west bank) | 2500 K uplights on granite (lights, not emission); 1800 K "gold" for the race start | Peace Hotel roof teal-green #2FBF9A E2, river reflections | low, fog_density 0.0035 | 3-8 % |
| Lujiazui 陆家嘴 | LED facade ads + crowns: magenta #FF2A8A, cyan #20E0FF, white (E3-E4) | Jin Mao gold #FFC86B (est.) E2 | medium, aerial look | 4-12 % |
| Yan'an elevated 延安高架 deck | 4000 K LED pole lamps every 30 m (E2 heads) | green guide gantries, traffic-guidance screens | medium | 2-8 % |
| Under the elevated (ground) | soffit wash blue #2357F3 (E1.5 emission + strips E3) | sodium side streets 2000 K | high + volumetric | 5-26 % (zone `underdeck`) |
| Nanjing Rd 南京路 | stacked vertical neon red #FF3030 / orange #FF6A1A / yellow #FFB000 (E3-E4) | gold department stores | rain variant, ripples | 8-26 % (zone `nanjing`) |
| Shikumen lanes 石库门弄堂 | single bare warm bulbs 2700 K, shop lightboxes | TV-blue windows | high, low ceiling of fog | 1-5 % |
| Flight layer (> 80 m) | orange street grid below (lamps as emissive specks), tower crowns | aircraft warning lights red #FF2020 blinking 1 Hz (est.) | aerial perspective | 1-10 % (zone `flight`) |

## 2. Palette

### 2.1 Colour tokens (sRGB hex; enter exactly these in Godot colour pickers)

| Token | Hex | Role / where it goes |
|---|---|---|
| SKY_ZENITH | #070A16 | sky shader `zenith_color` |
| SKY_MID | #121733 | sky shader `mid_color` |
| SKY_HORIZON | #3B3247 | sky shader `horizon_color` (must be brighter than tower silhouettes) |
| SKY_CITY_GLOW | #5A4048 | sky shader `city_glow_color` (light pollution band, bottom 10 % of dome) |
| CLOUD_BASE / CLOUD_LIT | #1C1A24 / #4A3A3C | cloud deck overhead / near horizon (lit by sodium from below) |
| FOG_HAZE | #2A2638 | `Environment.fog_light_color` |
| VOLFOG_ALBEDO | #9AA0B8 | `volumetric_fog_albedo` |
| RIVER_WATER | #0B1016 | Huangpu albedo (roughness 0.08 + animated normal) (est.) |
| ASPHALT_DRY / WET | #424240 / ~#2A2A2A | road average albedo dry (texture x0.55) / result when wet |
| CONCRETE | #7A7874 | piers, barriers, soffits (albedo) |
| GRANITE_BUND | #ABAAA3 | Bund stone average albedo (conditioned texture, 5.4) |
| BRICK_SHIKUMEN_GREY / RED / MORTAR | #5E6266 / #8A3B2E / #B9B4A8 | shikumen walls (est. from typical 青砖/红砖) |
| PAINT_WHITE / PAINT_YELLOW | #E9E7DF / #E8B520 | road paint albedo |
| SODIUM_2000K | #FF890E | old street lamps (HPS) light colour |
| LED_3000K / LED_4000K | #FFB16E / #FFCEA6 | shop-front light / elevated-deck pole lamps |
| BUND_2500K / BUND_GOLD_1800K | #FF9F46 / #FF7E00 | Bund uplights daily / race-start "golden halo" |
| SOFFIT_BLUE | #2357F3 | under-deck LED strips + soffit emission (measured sh05) |
| NEON_MAGENTA / CYAN / AMBER / RED / ORANGE / VIOLET / GREEN | #FF2A8A / #20E0FF / #FFB000 / #FF3030 / #FF6A1A / #8A5CFF / #3BFF7A | sign emission colours (green only for pharmacy crosses + charging OK states) |
| ROADSTER_RED_PAINT | #A3121B | car_paint base_color (est.; Tesla brand red is #E31937 [S brandcolorcode], paint is darker tricoat) |
| ROADSTER_LIGHTBAR | #FF1A2E | rear light bar emission (thin red strip seen in reveal frames, sheet_0) (unverified geometry) |
| HEADLIGHT_6000K | #F4F7FF | headlight SpotLight3D colour; DRL emission #EAF2FF |
| THRUSTER_PLUME | #CFE8FF | cold-gas plume particles (albedo, lit, alpha); core emission <= 0.3 |
| POLICE_WHITE / NAVY / YELLOW | #F2F4F5 / #1B2A4E / #F5C400 | patrol livery (white body, navy 藏蓝 band, yellow pinstripe - after GA 524-2004 description) [S baidu compilation] |
| POLICE_RED / POLICE_BLUE | #FF2020 / #2050FF | light-bar emission + OmniLights |
| GUIDE_SIGN_GREEN / STREET_SIGN_BLUE | #00704A / #1F4E9E | sign panels (est.), white #F5F5F0 text, retroreflective (emission 0.15) |
| VMS_GREEN / YELLOW / RED | #00C853 / #FFD600 / #FF1744 | traffic-guidance screens (congestion bars) on black #050505 |
| UI_CYAN / UI_MAGENTA / UI_AMBER / UI_RED / UI_GREEN | #00E5FF / #FF2BD6 / #FFB300 / #FF3355 / #39FF88 | HUD: primary / boost & flight / warning / police heat / charge |
| UI_WHITE / UI_PANEL | #F5F7FF / #0B0F1A @ 70 % | HUD text / panel background |

### 2.2 Colour temperature -> light_color (Tanner-Helland blackbody fit, computed)
1800 K #FF7E00 · 2000 K #FF890E · 2200 K #FF9227 · 2500 K #FF9F46 · 2700 K #FFA757 · 3000 K #FFB16E ·
3500 K #FFC18D · 4000 K #FFCEA6 · 5000 K #FFE4CE · 5500 K #FFEDDE · 6000 K #FFF6ED · 6500 K #FFFEFA.
Keep `rendering/lights_and_shadows/use_physical_light_units = false` (default) and use these colours instead of
`light_temperature` (that property only acts with physical units).

### 2.3 Emission energy tiers (StandardMaterial3D `emission_energy_multiplier` or shader EMISSION scale)

| Tier | Energy | Blooms? (threshold 1.2) | Used for |
|---|---|---|---|
| E0 | 0.05-0.35 | no | retroreflective paint/sign fake, LED screen black level |
| E1 | 0.6-1.0 | no | office/residential windows (facade shader `window_energy` 1.0), soffit wash 0.9 [V] |
| E2 | 2-4 | slight halo | lamp heads far away, shop lightboxes, Peace Hotel roof, LED screens (2-3) |
| E3 | 4-6 | yes | neon signs, soffit LED strips 5 [V], street-lamp heads 6 [V], holograms 3.5 |
| E4 | 8-12 | strong | hero sign per frame (max 1-2), brake lights 10, police strobes 12, headlight lenses 8 |
| E5 | 20+ | flash | lightning, crash sparks (particles, < 0.3 s) |

### 2.4 Tonemap, exposure, glow and value targets
- Tonemapper **AgX** (`TONE_MAPPER_AGX` = 4): keeps neon hue while the tube core whitens and it is the HDR-output-ready
  choice (Filmic does not support Godot 4.7 HDR output - Godot docs). `tonemap_exposure 1.0`, `tonemap_agx_white 10.0`,
  `tonemap_agx_contrast 1.3`, `adjustment_saturation 1.08`. Auto-exposure OFF (`CameraAttributesPractical`). [V]
- Glow (`env_recipe.gd`) [V]: enabled, blend SCREEN, `glow_hdr_threshold 1.2`, `glow_hdr_scale 2.0`,
  `glow_hdr_luminance_cap 12`, `glow_intensity 0.5`, `glow_strength 1.0`, `glow_bloom 0.0`, not normalized,
  levels 1..7 = 0.0, 0.5, 0.7, 0.4, 0.15, 0.0, 0.0. (Earlier test with level-5 0.3 / level-6 0.1 made lamp blobs
  the size of the moon - do not raise the wide levels.)
- Value structure of a gameplay frame (measured with `tools/screenshot_stats.py`; real Shanghai photos and genre refs
  were measured to set these; the look-dev baseline passes at P50 0.142, SAT 4.2 %):

| Metric (display luminance 0-1) | Target | Meaning |
|---|---|---|
| P5 | 0.02-0.10 | deep blacks but not crushed |
| P50 | 0.10-0.24 | mid-tones (night, but readable road) |
| P95 | 0.40-0.78 | lit surfaces, reflections |
| P99 | 0.55-0.97 | highlight headroom (neon cores, lamps) |
| SAT (% pixels S>0.45 & V>0.55) | 2-15 % | the emissive budget; zones: nanjing 8-26, underdeck 5-26, flight 1-10 |
| HUES80 | 1-3 | hue families covering 80 % of saturated pixels (colour harmony) |

## 3. Lighting recipe (Godot 4.7 Forward+)

### 3.1 WorldEnvironment - use `EnvRecipe.make_world_environment()` as is [V]

| Group | Values | Why |
|---|---|---|
| Background / ambient / reflections | BG_SKY; ambient source SKY energy 1.0; reflections source SKY | radiance comes from the HDRI pass of the sky shader |
| Fog (exponential) | colour #2A2638, density 0.0035, sky_affect 0.35, height 6.0, height_density 0.015, aerial 0.0 | thick near the street, thin above roofs |
| Volumetric fog | density 0.005, albedo #9AA0B8, emission black, anisotropy 0.45, length 96, detail_spread 2.0, ambient_inject 0.15, gi_inject 0.0, sky_affect 0.15 | light shafts from headlights/police/lamps |
| SSR | on, max_steps 64, fade_in 0.15, fade_out 2.0, depth_tolerance 0.2 | wet road streaks |
| SSAO | on, radius 1.2, intensity 1.6, light_affect 0.0 | contact darkening under barriers, cars |
| SSIL / SDFGI | off (High preset: SSIL on, intensity 1.0, radius 5) | neon bounce on walls is nice but costly |
| Per-zone overrides | Nanjing rain: volumetric 0.009; Flight: fog_density 0.0015 + fog_aerial_perspective 0.5; Underdeck: volumetric 0.008 | (est.) tune with screenshot_stats |

### 3.2 Sky
- Visible sky = `shaders/sky_night_city.gdshader` (gradient + city-lit cloud deck from a 512 px seamless
  `NoiseTexture2D`). Reflections/ambient = **the same shader's `AT_CUBEMAP_PASS` branch sampling an HDRI**, so you get
  a stylised sky to look at and real-city light to reflect. `Sky.process_mode = QUALITY`, `radiance_size = 256`,
  `radiance_energy 0.25` (0.45 gave gold-foil puddles). [V]
- HDRIs (Poly Haven, CC0, verified via api.polyhaven.com/files):

| Use | Poly Haven ID | Notes | 2K URL |
|---|---|---|---|
| Primary (all of Puxi/Bund/Lujiazui) | `shanghai_bund` | Greg Zaal, the actual Bund at night, 2018, partly cloudy, EV cap 17, WB 3300 K | https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/shanghai_bund_2k.hdr (md5 7514519f...) |
| Rain / wet streets | `vignaioli_night` | rainy square, wet cobbles, dark cloudy sky, WB 3000 K | https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/vignaioli_night_2k.hdr |
| Warm residential streets (shikumen) | `hansaplatz` | sodium-lit plaza, black sky | https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/hansaplatz_2k.hdr |
| Sky-only (flight layer) | `kloppenheim_07_puresky` | overcast night, no ground; multiply by 0.3 | https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/kloppenheim_07_puresky_2k.hdr |
| Alternative (ambientCG, CC0) | `NightEnvironmentHDRI002` | city plaza at night | https://ambientcg.com/get?file=NightEnvironmentHDRI002_2K.zip |

  Set `radiance_rotation_deg` so the HDRI's Lujiazui skyline points to the game's east bank (est. start at 0, rotate
  in 15 deg steps while looking at the chrome sphere).

### 3.3 Moon
One `DirectionalLight3D` "moon": colour #9FB4FF, energy 0.06, shadows OFF on streets; in flight sections energy 0.12
with shadows on (`directional_shadow_max_distance 600`) so tower tops get a rim (est.). Never brighter than street
lamps: the city, not the moon, lights SKYRUSH.

### 3.4 Street-light rhythm and dynamic-light budget

| Road type | Pole height / spacing | Colour | Real light per pole | Fake light |
|---|---|---|---|---|
| Elevated deck (Yan'an etc.) | 10 m / 30 m, both sides staggered (est.) | LED_4000K #FFCEA6 | OmniLight3D energy 2.5, range 18 m, vol-fog 0.2, no shadow [V] | lamp head emission 6 [V]; road light-pool Decal beyond 80 m |
| Ground arterial | 11 m / 35 m, both sides (est.) | mix: 70 % LED_4000K, 30 % SODIUM_2000K (older side streets) | as above, energy 2.0 | emissive head + pool decal |
| Shikumen lane | 4 m wall brackets / 12 m | 2700 K #FFA757 | OmniLight3D energy 0.8, range 7 m | bulb emission 4 |
| Bund facade | ground uplights every 5 m, 1 m from wall, 40 deg | BUND_2500K | SpotLight3D energy 25, range 30, pitch 80 deg up [V] | cornice strips emission E2 |

Budget per frame (Forward+, desktop target): <= 32 visible Omni/Spot lights (all with `distance_fade_enabled`,
begin 60 m, length 20 m), <= 3 shadowed (2 player headlights + 1 hero), <= 2 AreaLight3D (hero LED screens only;
the Godot 4.7 docs warn they add GPU cost to every object once one is in view), <= 64 visible Decals,
`rendering/limits/cluster_builder/max_clustered_elements` 512 (default). Everything farther away is emission +
glow + light-pool decals. Player headlights: 2 SpotLight3D, #F4F7FF, energy 10, range 70, angle 22, shadows on,
volumetric 1.5 [V].

### 3.5 Reflection probes (mandatory on every drivable road) [V]
- One `ReflectionProbe` per 120-170 m of road: `size` = (road width + 40 m, 40 m, segment length),
  `origin_offset` so the capture point sits ~2 m above the road centre, `box_projection true`,
  `update_mode UPDATE_ONCE`, `intensity 1.0`, `ambient_mode AMBIENT_DISABLED`, `blend_distance 4`.
  Interiors/tunnels: `interior true`, box exactly the tunnel. Flight layer: none (sky radiance only).
- Project: `rendering/reflections/reflection_atlas/reflection_size 512`, `reflection_count 64` (default).
- Re-capture a probe (call `update_mode = UPDATE_ONCE` again) only when a district's lights change (Bund 19:00 cascade).
- Effect in the look-dev: without a probe the wet road mirrored the HDRI's golden Bund (fake "gold foil" puddles);
  with one probe it reflects our own lamps and blue soffit.

### 3.6 Project settings (rendering)

| Setting | Value | Note |
|---|---|---|
| renderer/rendering_method | forward_plus | SSR, volumetric fog, AreaLight textures need Forward+ |
| anti_aliasing/quality/msaa_3d | 2 (2x) | clean geometry edges [V] |
| anti_aliasing/quality/use_taa | true on PC "High", false on "Medium" | killed granite/normal-map sparkle in the look-dev [V]; ghosting at 200+ km/h untested (open question) |
| anti_aliasing/screen_space_roughness_limiter | enabled (default amount 0.25, limit 0.18) | keeps wet-road speculars from flickering |
| anti_aliasing/quality/use_debanding | true | dark gradients in sky/fog |
| textures/default_filters/anisotropic_filtering_level | 4 (16x) | roads seen at grazing angles [V] |
| lights_and_shadows/positional_shadow/atlas_size | 4096 (default) | 3 shadowed lights max |
| environment/volumetric_fog/volume_size / volume_depth | 64 / 64 (default) | raise to 96/96 only on High |
| scaling_3d/mode | FSR2 (or bilinear) at 0.77 scale on Medium | (est.) |

### 3.7 Cheap fakes that carry the look
1. **Light-pool decal** under every lamp farther than 60 m: `Decal` size (10, 6, 10) m, `texture_emission` = radial
   gradient PNG 256 px (white centre to black edge, smoothstep), `emission_energy 0.6`, `modulate` = lamp colour,
   `upper_fade 0.3`, `lower_fade 0.3`, `distance_fade` begin 200 length 50. Real OmniLights only within 60 m.
2. **Soffit wash** under elevated decks: separate downward-facing plane 3 cm below the deck, StandardMaterial3D
   albedo #6E6C68, emission SOFFIT_BLUE energy 0.9, plus two LED strips (`neon_tube`, flat, E3 = 5) at the deck
   edges [V]. Optional gradient: `emission_texture` 64x512 px, 100 % at the edges -> 55 % at the centre line.
3. **Window glow** never uses lights: `facade_windows.gdshader` emission only (E1).
4. **Bund "高光十秒"**: at race start set all Bund uplights to energy 0, then switch building groups on in sequence
   over 10 s (38 groups, 0.26 s apart, west-to-east), light colour BUND_GOLD_1800K for 20 s, then ease to BUND_2500K.

## 4. Material recipes

Common rules: albedo textures sRGB (`source_color`), normal maps **OpenGL convention** (`*_nor_gl`, ambientCG
`*_NormalGL`), ORM = Poly Haven `arm` (R AO, G rough, B metal) -> `orm_texture`. Metallic is 0 or 1 except car flakes.
Roughness never < 0.02. Albedo range: darkest 0.03 linear (~#303030 rubber), brightest #E9E7DF paint.

### 4.1 Wet asphalt with puddles - `shaders/road_wet.gdshader` [V]

| Uniform | Value | Note |
|---|---|---|
| albedo/normal/rough_tex | Poly Haven `asphalt_02` diff / nor_gl / rough (3.0 m) | or ambientCG Asphalt025C (already wet) / Asphalt033 |
| tile_m | real texture size: asphalt_02 3.0, clean_asphalt 2.09, Asphalt033 2.5, Asphalt020L 4.6 | world-space UV, no unwrap |
| macro_tex / macro_m | `aerial_asphalt_01` diffuse (30 m scan!) or seamless noise / 37 m | kills repetition |
| albedo_mul | 0.55 | asphalt_02 mean #5B5955 -> #424240 dry |
| wetness | 0.85 after rain, 0.45 damp, 0.0 dry | drive with a weather global |
| puddle_amount / puddle_m | 0.20 / 14 m | more = cheap-looking polka dots |
| rain | 0.6 raining, 0 after | ripple normal only inside puddles |
| vertex COLOR | R=0 in the two wheel paths of each lane (track polish), G=0 along gutters (collect water) | Blender generator paints these; white = neutral. `mesh.color_attributes.new()` starts white (1,1,1,1) in Blender 5.2 [V]; meshes without colours read as white in Godot [V]. **Trap:** the Blender 5.2 glTF exporter defaults to `export_vertex_color='MATERIAL'` (colours only if a material uses them) - export roads with `export_vertex_color='ACTIVE'` [V] |

Result [V]: dry #424240 -> wet ~#2A2A2A, wet roughness = rough*0.25+0.03 (~0.22) gives long light streaks,
puddles roughness 0.03 mirror. Needs SSR on and a ReflectionProbe (3.5).

### 4.2 Lane markings and road paint - `shaders/road_marking.gdshader` on mesh strips [V]
- Geometry: thin quads/boxes generated by the Blender road tool, **5 mm above the asphalt** (never coplanar, never
  Decals for continuous lines). UV u = 0..1 across, v = metres along. Arrows/text = quads with `use_mask = true`
  and the baked PNG (section 6.3).
- Uniforms: `paint_color` PAINT_WHITE / PAINT_YELLOW, `wear` 0.15 (new elevated) .. 0.45 (old street), same
  `wetness` as the road, `retro_strength 0.35` (glass-bead retroreflection fake, fades 6 m -> 70 m from the camera).
- Wet paint darkens only 20 % and goes to roughness 0.18 (dry 0.62): paint must stay brighter than wet asphalt.

### 4.3 Concrete piers, barriers, soffits (StandardMaterial3D, triplanar)

| Param | Value |
|---|---|
| albedo_texture / normal / orm | Poly Haven `concrete` (4 m panels with vertical grooves + dirt streaks) for piers; `concrete_wall_008` (2.71 m, stained) for barriers; ambientCG `Concrete046` (2.4 m, smooth) for new decks |
| uv1_triplanar / uv1_world_triplanar | true / true; `uv1_scale` = 1 / real size (e.g. 0.25 for 4 m) |
| albedo_color | #FFFFFF; target mean #7A7874 (condition texture if needed, 5.4) |
| detail_enabled | true; `detail_albedo` = Poly Haven `concrete_wall_008` diff, `detail_blend_mode` MUL, `detail_uv_layer` UV1, uv scale x3; `detail_mask` = NoiseTexture2D 128x1024 (stretched -> vertical streak variation) |
| Stains | Decals from ambientCG `Leaking004/009/016A` (vertical drips) under every deck drain and at 30 % of piers, height 2-6 m; `AsphaltDamageSet002` scuffs at barrier bottoms; GraffitiSet001 on 10 % of pier bases (0-2.5 m) |
| Vertex colour (Blender) | darken bottom 0.6 m (splash zone) to 70 %, darken top 0.8 m under deck drip line to 80 % |
| Roughness | 0.85 dry, 0.55 under the wet deck edge (est.) |

Nine-Dragon Pillar: concrete core + dragon relief mesh, metallic 1.0, albedo #B8873A (aged copper-gold, est.),
roughness 0.35, lit by 4 SpotLights 2500 K energy 15 from the median.

### 4.4 Glass curtain-wall skyscrapers - `shaders/facade_windows.gdshader` [V]
- One shared material for all generic towers; per building `set_instance_shader_parameter("building_seed", n)`.
  With `MultiMeshInstance3D` (instance uniforms are per node, not per instance) set `multimesh.use_custom_data = true`
  and `set_instance_custom_data(i, Color(randf(), 0, 0, 0))` - the shader reads `INSTANCE_CUSTOM.x` [V compile].
- Building origin at its base or on the street (world height drives floors: `ground_y` = street height).
- Office preset: `floor_h 3.9`, `bay_w 1.5`, `window_frac (0.86, 0.62)`, `sill_frac 0.22`, `lit_ratio 0.38`,
  `dark_floor_ratio 0.18`, `tv_ratio 0.0`, `wall_color #2E2F32`, `glass_color #0B0E13`, `glass_roughness 0.06`.
- Residential preset: `floor_h 2.95`, `bay_w 3.3`, `window_frac (0.55, 0.55)`, `sill_frac 0.3`, `lit_ratio 0.55`,
  `dark_floor_ratio 0.05`, `tv_ratio 0.05`, `wall_color #8E877C` (beige tile), `blinds_max 0.9`.
- Window light colours: warm 2700 K #FFA757, neutral 3500 K #FFC18D, cool LED office #DEE8FF (stylised);
  `window_energy 1.0` (E1, never blooms). Far LOD fades the window grid to its average below ~2 px per cell
  (no moire) [V]. Ground floors (0-8 m): hand-built shopfront meshes with lightboxes, not the shader.
- Hero towers (Shanghai Tower, SWFC, Jin Mao, Oriental Pearl): modelled silhouettes + this shader + emissive crown
  strips (E3/E4). Distant LOD (> 1.5 km): ambientCG `Facade009/013/017` night facade textures (they include an
  emission map) on low-poly boxes.

### 4.5 Neon tubes and LED channel letters - `shaders/neon_tube.gdshader` [V]
- One material for every sign; per sign set instance uniforms `neon_color`, `neon_energy` (E3 4-6, hero E4 8-10),
  `neon_seed`, `faulty` (0/1). `core_whiten 0.3` (tube centre reads white-hot, edge saturated).
- Geometry: real tubes are 12-20 mm and turn sub-pixel beyond ~10 m. In-game strokes must be >= 2 px where seen:
  stroke width (m) >= distance (m) x 0.0026 at 1080p / 70 deg FOV (est. from 1 px = 0.00128 x distance).
  So: hand-height shop signs 40 mm tubes; signs seen from the deck at 30-60 m -> 8-16 cm flat LED channel strokes
  (look-dev bars 12 cm read cleanly at 30 m) [V]; tower-top letters seen at 300 m -> 0.8 m strokes.
- Add a back-plate (black anodised metal #141416, roughness 0.4) 8 cm behind each sign: the dark plate makes
  colours pop and gives the sign a daytime-plausible object.

### 4.6 Holographic / LED billboards - `shaders/hologram_billboard.gdshader` [V]
- Giant LED screens on towers: `mode 0` (LED dot grid), `led_grid` = screen metres x 6 (e.g. 40x22 m -> 240x132),
  `energy 2.5` (big area = do not exceed E2/E3 or the frame floods). Content: our own 1024x576 PNG ads (section 7).
- Floating holograms (cyberpunk layer, sparingly: max 3 visible): `mode 1`, `tint #8DEAFF`, `scan_lines 220`,
  `chroma_px 2`, `glitch_rate 0.08`, `energy 3.5`, additive, unshaded, `depth_draw_never`.
- Optional: one `AreaLight3D` per hero screen (size = screen, `area_texture` = 128x64 blurred copy of the ad,
  energy 2, range 25 m) - High preset only.

### 4.7 Car paint - `shaders/car_paint.gdshader` [V]

| Uniform | Roadster (hero) | Police patrol | Traffic cars |
|---|---|---|---|
| base_color | #A3121B (est.) | #F2F4F5 | random from: #E8E8E6 white 35 %, #0E0F11 black 20 %, #9DA3A8 silver 25 %, #1F3A5F blue 8 %, #5A5F63 grey 12 % (est., China fleet is mostly white/black/silver) |
| metallic_amount / base_roughness | 0.45 / 0.38 | 0.0 / 0.35 | 0.3 / 0.42 |
| flake_normal / flake_tiling / flake_strength | NoiseTexture2D 256 normal / 90 / 0.35 | none (0.0) | 90 / 0.2 |
| clearcoat_amount / clearcoat_rough | 1.0 / 0.04 (4.7 clearcoat is energy-conserving, release notes) | 1.0 / 0.06 | 0.8 / 0.08 |
| grime_height_m / grime_amount | 0.45 / 0.15 (hero stays clean) | 0.45 / 0.35 | 0.45 / 0.45 |
| livery (UV2 RGBA sheet) | optional stripes | yes (4.8) | taxis: 大众/强生-style colours are real brands -> use fictional teal #1E8C8A taxi with roof light "申城出租" |

### 4.8 Small hero materials (StandardMaterial3D unless noted)

| Material | Recipe |
|---|---|
| Tinted glass (car) | `transparency ALPHA`, albedo #0A0E12 alpha 0.55 (windscreen 0.35), roughness 0.03, metallic 0, specular 0.5 [V]. Dirt: `next_pass` material with ambientCG `SurfaceImperfections001` opacity as alpha (albedo #8A8578, alpha x0.25, roughness 0.6) + `Leaking016A` rain streaks on side glass when raining |
| Chrome / brushed metal | chrome: albedo #C4C5C5, metallic 1, roughness 0.08 [V]. Brushed (wheel spokes, trims): ambientCG `Metal051A` (circular) / `Metal009` (linear) maps, metallic 1, roughness map x1.0, `anisotropy_enabled` true, anisotropy 0.6 |
| Tyre rubber + sidewall | albedo #2A2A2A (never darker; rubber is ~0.03 linear), roughness 0.86 dry / 0.6 wet [V]. Tread + sidewall are a Blender bake: 4 circumferential grooves 10 mm wide 8 mm deep + 3 mm sipes every 30 mm (normal map 1024x256 tiling around the circumference); sidewall embossed text "SKYRUSH  HYPERGRIP  275/35 R21" (fictional, (est.) size) in Noto Sans SC Bold, 22 mm cap height, normal-only (same albedo), roughness 0.75 sidewall / 0.55 thin "tyre-shine" ring near the rim. Rubber micro-detail: ambientCG `Rubber001` normal at 0.3 strength |
| Carbon fibre | ambientCG `Fabric004` (black carbon) color/normal/roughness; uv scale so one weave cell is 6 mm (est.); albedo multiply #1C1E22, metallic 0.0, roughness 0.35, `clearcoat_enabled` true, `clearcoat` 1.0, `clearcoat_roughness` 0.05, `anisotropy_enabled` true, anisotropy 0.5 |
| Leather / Alcantara interior | seats ambientCG `Leather020` (red perforated) or `Leather026` (black smooth) at 0.3 m tiles; headliner/dash `Fabric082A` (fine grey weave); stitching = baked normal + #C8102E thread albedo decal |
| Emissive light bars | Roadster rear bar: emission #FF1A2E, energy 4 (tail) / 10 (brake), albedo #3A0508, emission_texture 128x4 px vertical stripes (LED segments, 50 % duty) so the bar reads as LEDs up close; front DRL #EAF2FF energy 6; headlight lens energy 8 + SpotLights (3.4) |
| Cold-gas thrusters | NOT fire. GPUParticles3D, 300 particles, lifetime 0.5 s, size 0.15 -> 1.2 m, albedo THRUSTER_PLUME alpha 0.7 -> 0, lit (receives lights), emission 0.3 at birth only; nozzle ring emission #9FD8FF energy 3 while firing |
| Police livery (fictional unit "天巡 SKYPOL") | body POLICE_WHITE, 45 cm navy #1B2A4E band along the lower doors, 3 cm yellow #F5C400 pinstripe above it running to the rear, door text "天巡 SKYPOL" Noto Sans SC Bold white on navy, roof number "沪-07". No 警徽, no 公安/警察/POLICE text (section 9). Livery = 2048x1024 RGBA sheet on UV2 of the police mesh |
| Police light bar | two emissive halves POLICE_RED / POLICE_BLUE energy 12 + one OmniLight3D each (range 14 m, energy 4, vol-fog 2.0, no shadow). Pattern (0.75 s loop, est.): red on 0-70 ms, off, red 130-200 ms, off; blue 375-445 ms, off, blue 505-575 ms, off. Drive emission and light energy from the same AnimationPlayer track |

### 4.9 City materials

| Material | Recipe |
|---|---|
| Bund granite (外滩) | conditioned Poly Haven `granite_tile_03` (1.8 m) diff -> mean #ABAAA3 (5.4), nor_gl `normal_scale 0.5` (full strength sparkles beyond 15 m), arm; triplanar world UV, `uv1_scale` 1/1.8 [V]. Cornices/columns are geometry; gold = BUND_2500K uplights [V]. Window glass #0B0E13 with warm interior emission E1 |
| Shikumen grey brick (石库门) | Poly Haven `dark_brick_wall` (1.04 m) or ambientCG `Bricks056` (1.05 m) as main wall; every 9th to 12th course a 3-course band of Poly Haven `church_bricks_03` red brick (1.2 m) via vertex-colour mask; mortar lines read #B9B4A8; stone gate frame (石库门框) = granite_bund material, 0.25 m deep, 2.8 x 1.6 m opening; doors black lacquer #1A1410 roughness 0.3 with brass ring knockers (metallic 1, #B08D57, roughness 0.35); triangular/arched pediment above the gate with relief (geometry) |
| Plane trees (法国梧桐) | Lower trunk 0-1.5 m Poly Haven `bark_platanus` (1.5 m, coarse plates); upper trunk/branches `japanese_sycamore` (1.09x2.19 m, the pale mottled peeling look Shanghai's planes are known for). Leaves: ambientCG `LeafSet027` atlas (maple-like palmate = close to Platanus), alpha scissor 0.5, cull disabled, `backlight_enabled` #6E7A2A; tint summer #4F6B2E, October mix 70 % #6A7A2E + 30 % #9C8A3A (est.). Street leaf litter = same atlas as decals at kerbs |
| Sidewalk | ambientCG `PavingStones144` (grey rectangular modern) or Poly Haven `square_tiles_03` (2 m); tactile strip 30 cm wide `TactilePaving003` (yellow, 1.2 m) along every sidewalk 25-60 cm from the kerb (est.); kerb = granite_bund material darkened #8E8C86 |
| Huangpu river | albedo RIVER_WATER, roughness 0.08, metallic 0, two scrolling NoiseTexture2D normals (as_normal_map, 0.6 m/s and 0.25 m/s, 40 deg apart), SSR on; no transparency (it is opaque mud-brown water) |
| Corrugated / construction hoardings | ambientCG `CorrugatedSteel007A` (light-blue painted, the typical Chinese 彩钢板 site fence), Poly Haven `corrugated_iron_02` galvanized for roofs; rust variants `rusty_metal_02` / ambientCG `Rust007` |
| Street furniture | lamp posts / barriers / sign gantries: ambientCG `Metal027` (black powder coat) or `PaintedMetal014` (grey painted, rust), roughness map x1, plus dirt decals at the base |

### 4.10 Set-piece kits (fly-over targets)

| Kit | Geometry (est.) | Materials | Lights |
|---|---|---|---|
| Gas station 中石华 | canopy 24 x 14 m, underside 5.2 m high, fascia 1.2 m tall; 4 islands x 2 pumps; price pylon 8 m | canopy underside white panel #E8E8E6 rough 0.5 with 12 recessed LED panels (emission 6000 K #FFF6ED E3); fascia brand teal E3 strip; pumps acg:Metal050A + plastic #E8E8E6; forecourt acg:Concrete046 + oil-stain decals | 2 SpotLight3D down (energy 6, range 12, angle 70, no shadow) or 1 AreaLight3D 20 x 10 m (High preset); the forecourt must be the brightest ground in the district (P99 area) |
| Charging hub 申城闪充 | canopy 30 x 8 m with solar-panel roof (dark blue #142033 metallic 0.3 rough 0.25), 8 pylons 2.2 m | pylon body white #E8E8E6 + black glass #0B0E13; vertical LED bar 1.2 x 0.08 m per pylon (state colours 7.1); bay markings 6.2 | 1 SpotLight3D per 2 bays (4000 K, energy 3); LED bars emission only |
| Toll plaza (city-edge expressway) | canopy 6.5 m high over 8-12 lanes, booths 1.6 x 3 m, lane islands 0.3 m high with yellow/black striped noses | canopy painted metal acg:Metal027 underside light grey; booth glass; island noses yellow #F5C400 / black stripes 45 deg 20 cm; lane signal boxes (green arrow / red X, LED E3); ETC lane sign colour (unverified, check photos) | canopy downlights 5000 K: emission panels + 1 SpotLight per 2 lanes within 60 m of the player |
| Elevated deck module | 3 lanes x 3.75 m + 0.5 m shoulders + 0.5 m barriers = ~13 m per direction (est.); piers every 30 m; deck 1.6 m thick | road_wet, road_marking, concrete (4.3), soffit wash (3.7) | pole lamps 3.4 |

## 5. Texture shopping list (all CC0; every URL HTTP-200 checked 2026-10-19)

**Download everything with `bash ref/art/lookdev/tools/fetch_textures.sh <out_dir>`** (~1.5 GB; resumable;
only image files are extracted). URL patterns, if you fetch by hand:
- Poly Haven 2K: `https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/<id>/<id>_<map>_2k.jpg`, map = `diff`,
  `nor_gl`, `rough`, `arm` (AO/rough/metal), displacement = `.../Textures/png/2k/<id>/<id>_disp_2k.png`.
  Exceptions: `leather_red_02` colour map is `coll1` (or `coll2`), `forest_leaves_02` colour map is `diffuse`.
  The script asks `https://api.polyhaven.com/files/<id>` so exceptions are handled automatically.
- ambientCG 2K: `https://ambientcg.com/get?file=<ID>_2K-JPG.zip` -> `<ID>_2K-JPG_Color.jpg`, `_NormalGL.jpg`
  (use this, not NormalDX), `_Roughness.jpg`, `_AmbientOcclusion.jpg`, `_Metalness.jpg`, `_Displacement.jpg`,
  `_Opacity.jpg`, `_Emission.jpg`. Ignore the bundled `.tres` (non-standard uids, parallax `heightmap_scale 1.0`).

### 5.1 The list

| Need | Pick (source:ID) | Real size | Maps | Use / note |
|---|---|---|---|---|
| Wet asphalt A | acg:Asphalt025C | n/a in API (assume 2 m, est.) | color, normal, rough, ao, disp | photographed wet; for puddle-heavy streets |
| Wet asphalt B (cracked) | acg:Asphalt024C | n/a (2 m est.) | same | old ground streets |
| Dry asphalt A (main) | ph:asphalt_02 | 3.0 m | diff, nor_gl, rough, arm, disp | default road under road_wet.gdshader [V] |
| Dry asphalt B (smooth deck) | ph:clean_asphalt | 2.09 m | same | new elevated decks |
| Dry asphalt C (granular) | acg:Asphalt033 | 2.5 m | color, normal, rough, ao, disp | ramps, toll plaza |
| Dark smooth asphalt | acg:Asphalt020L | 4.6 m | same | tunnels, Bund tunnel |
| Macro variation | ph:aerial_asphalt_01 | 30 m | diff (+ others) | `macro_tex` of road_wet at `macro_m` 30 |
| Road with markings (reference only) | acg:Road007 (white dashed), acg:Road011A (yellow centre) | 7.5 m | color, normal, rough | do NOT use in game: US-style; we paint per GB 5768 (6.1) |
| Race track asphalt | ph:asphalt_track | 2.0 m | diff, nor_gl, rough, arm | pit/garage, test track |
| Concrete smooth | acg:Concrete046 / acg:Concrete034 | 2.4 m / 1.1x0.55 m | color, normal, rough | new decks, barriers |
| Concrete rough | ph:rough_concrete | 1.23 m | diff, nor_gl, rough, arm | parapets, pier caps |
| Concrete stained | ph:concrete (vertical grooves, streaks) / ph:concrete_wall_008 / acg:Concrete035 | 4.0 / 2.71 / n/a m | full | piers / barriers / old walls |
| Painted concrete floor | ph:painted_concrete_02 | 4.0 m | full | car parks, garages |
| Sidewalk pavers | acg:PavingStones144, acg:PavingStones136, ph:square_tiles_03, ph:concrete_pavement_02 | n/a, n/a, 2.0, 1.8 m | full | modern grey pavers |
| Tactile paving (盲道) | acg:TactilePaving003 / 001 (yellow) | 1.2 / 0.8 m | color, normal, rough, disp | 30 cm strip on every sidewalk |
| Granite / stone facade | ph:granite_tile_03 (conditioned, 5.4), ph:granite_tile_04 (paving), acg:Bricks032 (light grey stone) | 1.8 / 2.0 / n/a m | full | Bund facades, promenade, kerbs |
| Grey brick | ph:dark_brick_wall, acg:Bricks056, ph:brick_wall_08, acg:Bricks034 | 1.04 / 1.05 / 1.89 / n/a m | full | shikumen 石库门 walls |
| Red brick bands | ph:church_bricks_03 | 1.2 m | full | shikumen bands, old warehouses |
| Painted metal | acg:Metal027 (black powder coat), acg:PaintedMetal014 (grey + rust), ph:blue_metal_plate | n/a, n/a, 2.5 m | color, normal, rough, metal | poles, gantries, kiosks |
| Brushed metal | acg:Metal009 (linear), acg:Metal051A (circular), acg:Metal050A (clean alu) | n/a | color, normal, rough, metal | wheels, trims, pumps |
| Rusty metal | ph:rusty_metal_02, acg:Rust007 | 1.0 m / n/a | full | old bridges, shutters |
| Corrugated metal | ph:corrugated_iron_02 (galvanised), acg:CorrugatedSteel007A (light-blue 彩钢板) | 2.7 m / n/a | full + metal | roofs / construction hoardings |
| Diamond plate | acg:DiamondPlate008A | n/a | full | truck beds, ramps |
| Carbon fibre | acg:Fabric004 | n/a (set 6 mm weave, est.) | color, normal, rough, metal | Roadster splitter, mirrors |
| Rubber | acg:Rubber001 | 0.75 m | color, normal, rough, disp | tyre micro-normal, mats |
| Tyre tread | none suitable (only ground tyre tracks exist) | - | - | bake in Blender (4.8) |
| Leather / fabric | acg:Leather026 (black), acg:Leather020 (red perforated), acg:Leather034C (stitched), ph:leather_red_02, acg:Fabric082A | 0.3-0.6 m | full | Roadster + police interiors |
| Glass dirt / streaks | acg:SurfaceImperfections001/002 (water stains), acg:Smear005, acg:Fingerprints002, acg:Leaking016A (drips) | n/a | color, normal, opacity | windscreen/glass overlays |
| Plane-tree bark | ph:bark_platanus (lower trunk), ph:japanese_sycamore (mottled upper) | 1.5 m / 1.09x2.19 m | full | 法国梧桐 |
| Leaves / grass | acg:LeafSet027 (maple-like atlas, scattering map), acg:Grass004, ph:forest_leaves_02 (litter) | 0.9 / 1.4 / 3.0 m | full + opacity | trees, verges, litter |
| Gravel | ph:gravel_stones, acg:Gravel022 | 2.0 / 1.5 m | full | rail beds, construction |
| Manhole / grates | acg:ManholeCover009 (round iron), acg:ManholeCover011 (square concrete, 0.9 m), acg:ManholeCover007, acg:Grate002 (gutter), ph:metal_grate_rusty (0.5 m) | as listed | full + opacity + metal | decals or inset meshes (6.2) |
| Road damage | acg:AsphaltDamageSet001 (cracks/potholes), acg:AsphaltDamageSet002 (scuffs) | atlas | color, normal, rough, opacity | decal atlases |
| Graffiti | acg:GraffitiSet001 | 1.2 m atlas | color, normal, rough, opacity | pier bases, tunnel walls |
| Police / warning tape | acg:Tape003 (blue/white), acg:Tape001 (yellow/black) | atlas | color, opacity | crash scenes |
| Night facades (far LOD) | acg:Facade009, Facade013, Facade017 | n/a | color, normal, rough, emission | towers > 1.5 km |
| HDRIs | ph:shanghai_bund, ph:vignaioli_night, ph:hansaplatz, ph:kloppenheim_07_puresky, acg:NightEnvironmentHDRI002 | 2K | .hdr / .exr | section 3.2 |

(Road011A is listed for reference only and is not in fetch_textures.sh.)

### 5.2 Texel density targets

| Asset class | Density | Texture budget |
|---|---|---|
| Roadster (hero) | paint is procedural (car_paint shader, no albedo map); livery/decal sheet 2048x2048 on UV2 (~470 px/m over ~4.3 m, est. length) | body 2048 livery + 2048 normal (panel gaps, vents baked from high-poly); wheels+tyres 1024 set; interior 2048; lights 1024; glass dirt 1024 |
| Police / traffic cars | 1024 px/m-equivalent hero zones, 512 elsewhere | 1024 livery + 1024 normal per model |
| Road, kerbs, sidewalks | 512-680 px/m (2K over 3-4 m) + detail normal x4 | tileable 2K sets (5.1) |
| Piers, barriers, soffits | 512 px/m triplanar | tileable 2K + decals |
| Building ground floors (0-8 m) | 256-512 px/m | tileables + one 2048 trim sheet per district (cornice, sill, frame, pipe, AC unit, sign frame strips) |
| Upper floors | shader-generated (facade_windows) or 128 px/m tileable | no unique textures |
| Props (lamps, pumps, chargers, booths, barriers) | ~512 px/m | 1024 per prop family; < 1 m props 512 |
| Far towers > 1.5 km | 32-64 px/m | ambientCG Facade atlases / shader |

Check in Godot with a checker material (`uv1_scale` so 1 tile = 1 m): at 5 m from the camera a 2K-over-4 m road must
show no blur; at 20 m the facade trims must still separate cornice from sill.

### 5.3 Breaking up tiling (apply ALL of these on roads and big walls)
1. Two-sample blend at unrelated scales (x1 and x0.61 + offset) chosen by a macro noise - built into road_wet [V].
2. Macro brightness variation +-12 % from a 30-37 m texture (aerial_asphalt_01 or noise) [V].
3. Never let texture size equal a layout module: asphalt 3.0 m vs lane 3.75 m, pavers 2.0 m vs bay 6 m.
4. Detail normal at x4 frequency (BaseMaterial3D `detail_normal`) for close-up grit.
5. Decals every 6-15 m on roads (cracks, patches, oil, manholes) and every pier (drips, graffiti) - section 6.
6. Vertex-colour masks from Blender: wheel tracks, gutters, kerb dirt, splash zones (road_wet uses R/G).
7. World/triplanar UVs on concrete so seams never line up with geometry edges.

### 5.4 Conditioning and import
- Conditioning = adjust a scan once so its average matches the palette (2.1). Measure the mean with
  `ffmpeg -v error -i in.jpg -vf scale=1:1:flags=area -f rawvideo -pix_fmt rgb24 - | xxd -p`. Measured means:
  asphalt_02 #5B5955 (use `albedo_mul 0.55` in road_wet), granite_tile_03 #645A52 -> conditioned to #ABAAA3 with
  `hue=s=0.55,lutrgb=r='clip(val*1.78,0,255)':g='clip(val*1.88,0,255)':b='clip(val*1.90,0,255)'` [V].
  Targets: concrete #7A7874 +-10, brick grey #5E6266, asphalt dry #424240.
- Godot import: albedo = VRAM Compressed, mipmaps on, sRGB (default); `*_nor_gl` / `*_NormalGL` = Normal Map
  "Enable" (Godot auto-detects when used in a normal slot); roughness/ARM/ORM linear (default detect).
  HDR/EXR = default (the HDR GAMMA/PRIMARIES header warnings on import are harmless) [V].
- Project layout: `assets/tex/<source>/<id>/<file>` exactly as the fetch script writes it; materials in
  `assets/materials/<district>/<name>.tres`; never edit files in `assets/tex` by hand (re-run conditioning).

## 6. Decals and road paint

### 6.1 Chinese road paint - GB 5768.3 dimensions (paint = mesh strips/quads with road_marking.gdshader)

| Marking | Spec | Source |
|---|---|---|
| Lane divider, same direction (可跨越同向车行道分界线) | white dashed, **600 cm dash / 900 cm gap** on roads >= 60 km/h (elevated decks), 200/400 cm below 60 km/h; width 10 or 15 cm (use 15) | [S] GB 5768.3-2009 4.3.3 |
| Edge line | white solid (width: use 20 cm, est.); **left edge of a one-way carriageway = yellow solid 15/20 cm** (every elevated deck) | [S] 4.5.2, 4.5.5 |
| Centre line, two-way streets | crossable: single yellow dashed **400 cm dash / 600 cm gap**, 15 cm; no-crossing: double yellow solid 15 cm each, 10-30 cm apart (or yellow solid+dashed) | [S] 4.2.3, 5.2.2 |
| Crosswalk (斑马线) | white bars **40 or 45 cm wide, 60 cm gap** (max 80), parallel to the road axis; crossing width >= 300 cm in 100 cm steps; >= 150 m apart mid-block | [S] 4.9.3 |
| Bus lane - 2009 standard | yellow dashed 400/400 cm, 20/25 cm wide + white text 公交专用 (repeated after every junction) | [S] 5.11.1 |
| Bus lane - GB 5768.3-2025 (in force 2026-05-01) | **white "5-1" dashed (500 cm line / 100 cm gap), 20/25 cm + white text 公交** - Beijing/Tianjin repainting since June 2026 | [S] bj.people.com.cn 2026-06-10, tj.gov.cn 2026-08-22, openstd.samr.gov.cn |
| Road text (路面文字标记) | glyph height x width x spacing: >= 100 km/h 900x300x600 cm; 40-100 km/h **600x200x400 cm**; <= 40 km/h 300x100x200 cm; city roads may use 0.5-0.7x; characters stacked along the lane, read near -> far | [S] table 4, 4.16.4 |
| Speed-limit numbers | maximum = yellow, minimum = white, same heights as table 4 (e.g. "60" on the Yan'an deck) | [S] 4.16.2 |
| Guide arrows (导向箭头) | white. 40-100 km/h roads: total **600 cm**, straight arrow head 240 cm long x 90 cm wide, shaft 30 cm wide; turn arrows: see `img/gb5768_3_2009_fig44_arrows_6m.jpg`; <= 40 km/h use fig. 43 (300 cm system, est. half scale); urban 40-60 km/h may use fig. 46 (450 cm) | [S] 4.15.4 + fig. 44 |
| Distance-confirmation lines (车距确认线) | white zig-zag 300 cm wide, stroke 40/45 cm, two strokes 5 m apart per group, groups every 50 m x 5 | [S] 4.10.2 |
| Stop line | white solid **20, 30 or 40 cm** wide across the whole approach, 100-300 cm before the crosswalk | [S] 5.5.3, 5.5.4 |

Game decision needed (section 9): 2025 white bus lanes (accurate for a 2026 setting) vs. the more recognisable 2009 yellow ones.
Suggested compromise: white 5-1 on repainted Puxi arterials, one legacy yellow segment on Nanjing Rd W as realism.

### 6.2 Decal list
Godot `Decal` defaults: `upper_fade 0.3`, `lower_fade 0.3`, `normal_fade 0.5` (road decals do not climb kerbs),
`distance_fade_enabled true` begin 40 m / length 15 m (small) or 80 / 20 (large), `cull_mask` = environment layer only
(put vehicles on render layer 2 so decals never land on cars).

| Decal | Size | Source | Notes / placement |
|---|---|---|---|
| Road text glyphs, arrows | per 6.1 | baked (6.3) | mesh quads, not Decals (keeps wet behaviour) |
| Manhole round | dia 0.70 m (est.) | acg:ManholeCover009 | inset mesh 3 mm below the road + 1.2 m asphalt-patch decal around it; one every 20-40 m in lane centres; text 雨水/污水/电力/通信 (est.) as 9 cm baked glyphs |
| Manhole square / utility | 0.9 m | acg:ManholeCover011, acg:ManholeCover007 | sidewalks, verges |
| Gutter grate | 0.75 x 0.45 m (est.) | acg:Grate002, ph:metal_grate_rusty | along kerbs every 25-30 m (est.), road_wet `COLOR.g` low spot around it |
| Cracks, patches, potholes | 1-4 m | acg:AsphaltDamageSet001 | every 8-15 m on ground streets, every 25 m on decks |
| Scuffs / rubber smears | 2-6 m | acg:AsphaltDamageSet002 | junctions, toll plaza, ramp ends |
| Oil stains | 0.6-1.5 m | generate: radial noise PNG 512, albedo #1A1714 alpha 0.6, ORM roughness 0.15 | lane centres before stop lines, gas station, parking |
| Puddles (hero spots) | 2-6 m | generate: noise blob mask 1024, albedo #000000 alpha 0.4, ORM roughness 0.03, flat normal | only where road_wet puddles are not enough (photo spots) |
| Tyre skid marks | 0.24 m wide ribbons | runtime ArrayMesh ribbon (not Decal): #121212 alpha 0.75, roughness 0.45, fade over 30 s, ring buffer 4 x 256 quads | spawned when wheel slip > threshold; drift = long arcs |
| Graffiti | 0.5-2 m | acg:GraffitiSet001 | pier bases 0-2.5 m, tunnel walls; 1 per 3 piers |
| Posters 小广告 | 0.30 x 0.45 m | generate (6.3) | piers, utility boxes, 1.2-1.8 m high, clusters of 3-7, torn edges; fake numbers "1XX-XXXX-XXXX" |
| Drips / water stains | 0.5 x 3 m | acg:Leaking004 / 009 / 016A | under deck drains, every pier side facing the road |
| Leaf litter | 0.3-1 m | acg:LeafSet027 atlas | kerbs under plane trees (Puxi), October colours |
| Rubbish | props + stain decals | modelled cups/bags | 1 item per 20 m on side streets; none on elevated decks (Shanghai is clean) |
| Light pools | 10 x 10 m | generated radial gradient | section 3.7 |
| Police / crash tape | strips | acg:Tape003 (blue/white), Tape001 | crash scenes |
| Charging-bay marking | 2.5 x 5.3 m bay (est.) | baked glyphs 充电车位 + bolt icon | white paint + green bay fill (unverified local practice) |

### 6.3 Generating what cannot be downloaded
1. **Road text + straight arrow** (tested on Blender 5.2.1, headless, never touches an open Blender):
   `blender -b --factory-startup --python ref/art/lookdev/tools/bake_road_glyphs.py -- --font NotoSansCJKsc-Bold.otf --out assets/decals/roadtext --chars "公交专用慢出口" --px 256`
   -> `roadtext_u516c.png` ... (256x768 white-on-transparent, glyph stretched to the 1:3 GB box with 4 % margin) and
   `arrow_straight_600.png` (256x1536 for a 1.0 x 6.0 m frame; 36 % coverage = exact GB area) [V].
   Font: `https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Bold.otf` (OFL).
   Place glyph quads 2.0 x 6.0 m (60-80 km/h) with 4.0 m gaps, first character nearest to the driver.
2. **Turn / merge / U-turn arrows**: add vertex lists to `bake_straight_arrow()` traced from
   `img/gb5768_3_2009_fig44_arrows_6m.jpg` (all dimensions in cm are printed on the figure: e.g. turn arrow =
   270 cm shaft + 120 cm 45-degree bend + head 100/60/60/90 cm, offsets 40/80/30 cm).
3. **SVG route** (for logos, icons, charging bolt): draw in any vector tool, import in Blender
   (`bpy.ops.import_curve.svg`), then render with the same orthographic white-on-transparent setup.
4. **Posters, ads, LED-screen content**: build in Godot as a `SubViewport` (1024x576 or 512x768) with
   `Label`/`TextureRect`/`ColorRect` nodes using the section-7 fonts and palette, then
   `viewport.get_texture().get_image().save_png()` once at edit time; ship the PNGs. Layout rule: max 3 elements
   (CJK brand name >= 40 % of height, one Latin sub-line, one shape/icon), 8 % safe margin, 2 brand colours + white.
5. **Oil / puddle / light-pool masks**: Godot `NoiseTexture2D` (cellular or simplex, seamless off) +
   `GradientTexture2D` (radial fill), saved once as PNG.

## 7. Neon, billboards and typography

### 7.1 Parody brands and signs (all fictional - no real trademarks, logos or trade dress)

| Name | What | Colours | District | Behaviour |
|---|---|---|---|---|
| 中石华 ZHONGSHIHUA | gas-station chain (canopy fascia + price pylon) | teal #00B3A6 + white + amber #FFB000 (deliberately not Sinopec orange or PetroChina red/yellow) | ring roads, toll exits | canopy underside 6000 K LED panels E3 + 2 SpotLights; price digits amber 7-segment E3 |
| 申城闪充 SHENCHENG FLASH | ultra-fast charging hub (flash charging) | electric cyan #20E0FF + white; state colours idle blue #2A6BFF, charging green #39FF88, fault amber blink 2 Hz | Pudong, Jing'an | pylons with vertical LED progress bar filling bottom-up during flash charge; canopy edge strip E3 |
| 浦江电讯 PUJIANG TELECOM | tower-crown LED ad | magenta #FF2A8A + white | Lujiazui | LED screen mode 0, 8 s loops |
| 海派百货 HAIPAI DEPT. STORE | historic store vertical neon | gold #FFB000 + red #FF3030 | Nanjing Rd E | stacked vertical CJK neon, 1 faulty letter |
| 赛博火锅 CYBER HOTPOT | restaurant | red #FF3030 + orange #FF6A1A | Nanjing Rd, Huanghe Rd | steam particles over the sign |
| 量子奶茶 QUANTUM MILK TEA | drinks kiosk | pink #FF2A8A + mint #3BFFC8 | everywhere at street level | lightbox E2 |
| 老弄堂小笼 24H | dumpling shop | warm white #FFC18D + red | shikumen lanes | bare-bulb strip, steam |
| 邻里24 NEIGHBOR 24 | convenience store | orange #FF6A1A + white | everywhere | whole shopfront lit E2, 6500 K interior |
| 星光量贩 KTV | karaoke | violet #8A5CFF + magenta | Jing'an side streets | chasing-border neon (sequential segments 12 Hz) |
| 破晓电竞 DAWNBREAK ESPORTS | esports arena | cyan + violet | Pudong | hologram mode 1 |
| 云端速递 CLOUD EXPRESS | drone delivery | white + cyan | rooftops (flight layer) | blinking nav lights on drones |
| 永福大药房 | pharmacy | green cross #3BFF7A | residential streets | the only green neon allowed |
| 飞驰申城 SKYRUSH | the game's own race banners | UI_MAGENTA + UI_CYAN | race starts, overpasses | hero E4 |
| 文明驾驶 安全出行 / 前方拥堵 注意减速 | traffic-guidance screens + VMS (诱导屏) | congestion bars VMS_GREEN/YELLOW/RED on black, amber 7x7 LED text | elevated decks every ~1.5 km (est.) | live data from the game's traffic system |

Legal note: 中石华 is a close parody of 中石化 (Sinopec); keep it or switch to 华石油 after a legal check (section 9).

### 7.2 Typography (all SIL OFL 1.1 - licence files checked on GitHub 2026-10-19; ship the OFL.txt with the game)

| Font | Use | Download |
|---|---|---|
| Noto Sans CJK SC Bold / Noto Sans SC (variable) | road text, guide signs, police door text, VMS fallback | github.com/notofonts/noto-cjk (OTF above); `https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf` |
| Noto Serif SC | Bund heritage plaques, hotel names, 海派百货 | `https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf` |
| Smiley Sans 得意黑 (oblique condensed) | HUD titles, race banners, modern ads (浦江电讯, 申城闪充) | `https://github.com/atelier-anchor/smiley-sans/releases/download/v2.0.1/smiley-sans-v2.0.1.zip` (RFN "Smiley"/"得意黑": do not rename a modified version) |
| ZCOOL KuaiLe 站酷快乐体 | playful food/drink signs (量子奶茶) | `https://raw.githubusercontent.com/google/fonts/main/ofl/zcoolkuaile/ZCOOLKuaiLe-Regular.ttf` |
| ZCOOL QingKe HuangYou 站酷庆科黄油体 | bold pop ads, KTV | `https://raw.githubusercontent.com/google/fonts/main/ofl/zcoolqingkehuangyou/ZCOOLQingKeHuangYou-Regular.ttf` |
| Ma Shan Zheng 马善政楷书 | brush signs: hotpot, pharmacy, dumplings | `https://raw.githubusercontent.com/google/fonts/main/ofl/mashanzheng/MaShanZheng-Regular.ttf` |
| LXGW WenKai 霞鹜文楷 | handwritten posters 小广告 | github.com/lxgw/LxgwWenKai (releases) |
| Fusion Pixel 12 px 缝合像素 | LED dot-matrix VMS, scrolling shop LED, toll displays | `https://github.com/TakWolf/fusion-pixel-font/releases/download/2026.10.16/fusion-pixel-font-12px-proportional-ttf-v2026.10.16.zip` |
| Orbitron / Rajdhani / Share Tech Mono | HUD speed digits / HUD labels / telemetry | google/fonts `ofl/orbitron`, `ofl/rajdhani`, `ofl/sharetechmono` |

Godot: import CJK fonts as `FontFile` with MSDF (`multichannel_signed_distance_field = true`, `msdf_pixel_range 16` default, `msdf_size 48`)
for 3D signs (`Label3D` or baked textures), regular rasterised for HUD. Never fake bold/italic CJK.

### 7.3 Glow and flicker behaviour (implemented in neon_tube / hologram shaders) [V compile]
- Healthy neon: `dropout_rate 0.015` of 120 ms slots (~1 blink every 8 s), +-3 % hum. Never flicker the hero sign.
- Faulty neon: `faulty = 1` on <= 8 % of signs (never on the race route's hero signs): 22 % dropouts + 31 Hz stutter.
- LED screens: no flicker; content changes every 6-10 s with a 0.3 s wipe.
- Holograms: glitch slots 12 Hz at 8 %, 220 scanlines, 2 px RGB split, 24 Hz brightness jitter +-10 %.
- Bund cascade at 19:00 / race start (3.7). Lujiazui show: tower crowns cycle magenta -> cyan -> white every 12 s (est.).
- Do not animate faster than 15 Hz anywhere except police strobes and glitches (photosensitivity; add an option to
  disable flicker globally).
- Glow per sign comes only from emission energy (2.3); never add extra glow sprites to E1/E2 objects.

## 8. Art-critic checklist (apply to every screenshot; 1080p, gameplay camera)
Run `python3 -I ref/art/lookdev/tools/screenshot_stats.py shot.png [--zone nanjing|underdeck|flight]` first.

| # | Check | Pass when |
|---|---|---|
| 1 | Value structure | P5 0.02-0.10, P50 0.10-0.24, P95 0.40-0.78, P99 0.55-0.97 (tool) |
| 2 | Emissive budget | SAT 2-15 % (zones as in the tool); no region of 25 % of the frame is uniformly bright |
| 3 | Colour harmony | HUES80 <= 3; one district signature colour is clearly dominant; red/blue police lights only during chases |
| 4 | Silhouette | tower tops readable against the sky glow; car silhouette separated from the road by a rim/reflection |
| 5 | Wet road | every bright source within 40 m has a vertical streak reflection; no gold-foil/HDRI content in puddles |
| 6 | Texture @ 5 m | asphalt grit, paint wear, cracks visible; no blurry mip; no stretched UVs on kerbs/barriers |
| 7 | Texture @ 20 m | facade trims separate (cornice/sill/frame), decals visible (manholes, patches), signs legible |
| 8 | Texture @ 100 m | no moire in windows or zebra crossings, no sparkle on stone/metal (TAA/normal_scale), tiling invisible |
| 9 | Tiling | no repeat recognisable over 3 tiles; macro variation present on roads and big walls |
| 10 | Scale cues | lamp posts 10-11 m, lanes 3.5-3.75 m, door 2.1-2.4 m, window floors 3.9/2.95 m, people/props present |
| 11 | Neon legibility | every sign stroke >= 2 px at the distance shown; tube core whiter than edge |
| 12 | Emission discipline | windows never bloom; at most 2 E4 objects per frame; no pure white albedo, no pure black except tyre shadow |
| 13 | Noise | no fireflies on wet road, no volumetric-fog blobs larger than 8 % of frame width around lamps |
| 14 | Shanghai identity | at least one of: Bund gold, blue soffit, Nanjing neon stack, Lujiazui crowns, Chinese road text/signs |
| 15 | Correct paint | lane dashes 6/9 m on decks, yellow left edge on one-way decks, zebra 40-45 cm bars, text stacked near->far |
| 16 | Legal | no real logos, plates, police emblems or phone numbers; CJK fonts only from 7.2 |

## 9. Open questions (decide before content production)
1. Bus lanes: GB 5768.3-2025 white "5-1" + 公交 (correct for 2026) or 2009 yellow + 公交专用 (more recognisable)?
2. Police: the dossier uses a fictional unit "天巡 SKYPOL" with a police-like white/navy/yellow livery. Is even that
   acceptable for a China release (police depiction, chases)? Needs a legal/publishing check.
3. Parody names close to real brands (中石华 vs 中石化) - keep or move further away (华石油)?
4. Roadster rear light bar: the reveal frames (ref/video/sheet_0) show a thin red strip; exact geometry/colour of the
   2026-10-15 car is unverified here - align with the roadster dossier.
5. TAA at 200+ km/h: removes stone/metal sparkle in the still look-dev but ghosting in motion is untested.
6. AreaLight3D cost on the min-spec GPU: untested (docs warn of a per-object cost) - keep High-preset only.
7. Volumetric fog cost with 30+ lights at 64^3 froxels: untested beyond the look-dev (6 lamps + 2 headlights + 5 spots).
8. The `shanghai_bund` HDRI reflects the real skyline; with probes it only shows where SSR/probes miss (sky). OK?
9. Toll-plaza ETC signage colours and charging-bay paint colours in Shanghai: not verified (marked unverified).
10. Ambient CG asset real-world sizes are missing for many IDs (marked "n/a ... est."): confirm with the checker test.

## 10. Implementation order (for the implementer)
1. Copy `ref/art/lookdev/{env_recipe.gd, materials.gd, shaders/}` into the game; run `fetch_textures.sh`.
2. Build one 300 m elevated-deck test strip (4.10) with road_wet + road_marking + piers + soffit + lamps + probes.
3. Screenshot from the chase camera at 3 times of the race: run screenshot_stats; fix until PASS.
4. Add facades (facade_windows) and one district signature (Bund uplights) -> PASS again with `--zone` as needed.
5. Only then add neon brands (7.1), decals (6.2) and set-piece kits; re-run the checklist (section 8) every time.

## 11. Sources (accessed 2026-10-19)
- Bund lighting: news.china.com/socialgd/10000169/20260828/49704137.html (38 buildings, ~29,800 LED, 1800-3000 K,
  2500 K daily, 1800 K golden halo, 19:00-23:00, hidden fixtures); shanghai.gov.cn/nw4411/20260820/f441a5da943447e79613ab4d5dbcc0a5.html;
  sohu.com/a/1081200566_121106832 (2026-09-26/27 hours 18:30-23:00).
- Huangpu riverside / Lujiazui lighting hours: news.sina.cn/2018-10-26/detail-ihmxrkzx3229259.d.html (19-21 h summer,
  18-22 h winter); shanghai.gov.cn/nw4411/20240928/4cecd325051a4230b8bd2c130c045787.html (event mode 18-23 h).
- Elevated-road lighting: wenhui.whb.cn/zhuzhan/cs/20210503/403164.html ("申"字形 full-colour LED, 东方彩带·上海动脉);
  lightingchina.com/news/21887.html (blue-violet fluorescent tubes under Yan'an/North-South elevated, search snippet);
  sohu.com/a/589575837_790178 (blue LED line lights on Yan'an elevated buildings); jfdaily.com/news/detail?id=4610 (Nine-Dragon Pillar, via search snippet).
- Road markings: GB 5768.3-2009 full text upload.wikimedia.org/wikipedia/commons/6/6c/China_GB_5768.3-2009.pdf
  (4.3.3, 4.5, 4.9.3, 4.10.2, 4.15.4 + fig. 44, 4.16 table 4, 5.11.1); GB 5768.3-2025 openstd.samr.gov.cn (published
  2025-10-05, in force 2026-05-01); bj.people.com.cn/n2/2026/0610/c14540-41605836.html; tj.gov.cn/sy/tpxw/202608/t20260822_7356833.html.
- Police livery description (GA 524-2004): compilation.baidu.com/view/d5e0d65177232f60ddcca18f.html (white body,
  navy 藏蓝 main colour, yellow lines at the rear sides).
- Tesla brand red #E31937: brandcolorcode.com/tesla; paint codes: service.tesla.com (Ultra Red tricoat).
- Godot 4.7: godotengine.org/releases/4.7 (AreaLight3D, HDR output, clearcoat fix, DrawableTexture2D);
  docs.godotengine.org/en/stable/classes/class_environment.html, class_arealight3d.html; property names/defaults
  from `godot --doctool` of 4.7.2.stable.
- Assets/APIs: api.polyhaven.com (assets, files, info), ambientcg.com/api/v3/assets (docs.ambientcg.com), Steam
  store API (store.steampowered.com/api/appdetails), Wikimedia Commons API - per-image credits in img/INDEX.md.
- Fonts: github.com/google/fonts (ofl/*), github.com/atelier-anchor/smiley-sans, github.com/TakWolf/fusion-pixel-font,
  github.com/lxgw/LxgwWenKai, github.com/notofonts/noto-cjk.
