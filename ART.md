# ART.md — art bible (binding for every visual unit)

Owner: the lead (Opus) is the art director. Workers follow this literally; when in doubt, choose
the option that adds texture detail and value contrast. Research back-up: `ref/art/DOSSIER.md`,
car: `ref/roadster/DOSSIER.md`, city: `ref/shanghai/DOSSIER.md`.

## 1. The look in one paragraph
Shanghai, 1 a.m., just after rain, a few years from now. A deep indigo-black sky with a magenta and
orange light-pollution glow on the horizon; low haze that catches every light; wet asphalt that
mirrors neon as long vertical streaks. The Bund glows warm gold; the Lujiazui towers wear cool
cyan-white LED skins. Street level is dense: Chinese neon shop signs, holographic billboards,
sodium and LED street lamps, flower boxes on elevated parapets, blue light strips under the decks.
The **white Roadster** is the cleanest bright object in frame; its **red light bar** and
**blue-white cold-gas plumes** are the strongest accents. Real Shanghai first, cyberpunk on top.

## 2. Value and colour hierarchy (screenshots are judged on this)
1. Darkest: sky and building masses (never pure #000 — keep detail in the darks).
2. Mid: wet roads, concrete, glass — their brightness comes from reflections, not albedo.
3. Bright, many small points: lit windows (15–30 % of a façade, in clustered floors, see §11), street lamps,
   signs. The city must read LIT from every distance — a dark grey block is a bug.
4. Brightest, rare: the player car's light bar and thrusters, police lights, landmark crowns.
No more than ~15 % of any frame may be saturated neon. Warm/cool contrast: gold Bund vs cyan Pudong.

## 3. Palette (hex, sRGB)
| Role | Colours |
|---|---|
| Sky zenith → horizon | `#05060F` → `#1A1033` → horizon glow `#5A1F4F`, faint city orange `#FF6A3D` |
| Fog / haze | `#1B1530` (distance fog), volumetric albedo `#9AA3C7` |
| Neon primaries | pink `#FF2BD6`, cyan `#19E6FF`, blue `#3D5CFF`, violet `#9B5CFF`, amber `#FFB000`, red `#FF2A3A`, acid green `#9DFF3C` (rare) |
| Street light | sodium `#FFB46B` (old streets), LED `#D9E8FF` (expressways), under-deck strips `#2F7BFF` |
| Bund | floodlit stone `#E9C98F` on `#C9B79A`, gold lamps `#FFCF87` |
| Roadster | **Ano White `#ECEDEF`** (the reveal car — overrides the red in ref/art), black trim `#111113`, light bar `#FF1A2E`, plume `#CFE8FF`. **Changed 2026-10-23 (owner's request): the car is black and white** — white pearl body, gloss black panels `#0B0C0E`, black wheels, neutral smoke glass `#0A0B0C` (the gold glass `#5A3F2A`, gold wheels and red accents are gone); the model is the Khronos Car Concept, see `blender/car/concept/README.md` |
| Police | red `#FF2030`, blue `#2A5CFF`, white body `#F4F6FA`, livery blue `#1E4FB8` |
| UI | cyan `#19E6FF`, magenta `#FF2BD6`, text `#F2F6FF`, panel glass `#0A0F1E` @ 70 %, warning `#FFCC00` |

## 4. Lighting recipe (Godot, Forward+) — the environment unit owns the implementation
- Tonemap **AgX**, exposure 1.0; glow on (levels 2–5, intensity 0.8, bloom 0.05, HDR threshold 1.1).
- Sky: dark gradient sky + a night-city HDRI at low energy for reflections only.
- Fog: depth fog `#1B1530` (density 0.0012) + volumetric fog (density 0.01, falloff with height,
  `#9AA3C7`) on high/ultra; light shafts from street lamps come for free.
- SSR on medium+ (wet roads), SSAO on, glow on all presets. Reflection probes at landmarks.
- Real lights are budgeted (≤ 48 shadowless omni/spot near the camera, pooled); everything else
  glows through emissive materials + fake light cones / ground light decals.
- Rain (medium+): camera-near streak particles, ripple normals in puddles, wet roughness.

## 5. Materials (minimums; every visible surface)
- **No flat untextured surface anywhere the camera can see.** Each material has (a) a texture or
  procedural base, (b) roughness breakup (grime/wetness), (c) a normal map, (d) edge wear or dirt
  where physical. Big tiling surfaces add macro variation (world-space noise tint) and decals.
- Wet asphalt: dark base (albedo ≈ `#1A1B1F`), roughness 0.35 dry patches → 0.05 puddles via mask,
  normal map, SSR. Lane markings: white `#E8E8E0` / yellow `#F2C200` with retro-reflective sheen.
- Concrete (piers, parapets, decks): stained and streaked (vertical rain streaks), cooler grey.
- Glass towers: dark reflective curtain wall + lit-window pattern shader (per-window random:
  off / warm `#FFD7A0` / cool `#CFE6FF` / TV-blue flicker; 15–30 % lit in clustered floors; floors and
  mullions visible; never a uniform polka-dot grid).
- Neon: emissive tubes with a darker unlit backing and mounting brackets; slight flicker on some.
- Holograms: additive, scanlines, chromatic edge, gentle jitter; never fully opaque.
- Car paint: pearl white, clear-coat, metallic flake normal at close range (shader `SH_car_paint`).
- Texel density: hero car ≥ 2048 px for the body set + decals; props ≥ 512 px/m; street-level
  tiling ≥ 512 px/m; distant buildings may use trim sheets/atlases ≥ 128 px/m.

## 6. Detail density rule
Detail is highest where the camera is: the road surface, the 10 m beside it, and the car. Street
level needs scale cues: bus stops, barriers, bikes/e-scooters, bins, AC units, laundry poles,
traffic lights, sign gantries, cables, manholes, puddles, posters, cones. Distant blocks may be
simpler but must still read as Shanghai (setbacks, rooftop signs, antenna, lit crowns).

## 7. Text and branding
Chinese first (简体), English second, real words only (no fake glyph soup). Parody brands only —
never real logos/trademarks: e.g. 中石华 (gas), 申城闪充 (charging), 东方霓虹, 浦江电讯, 申城快递.
Fonts (free licences): 思源黑体 / Noto Sans SC, 站酷快乐体, 得意黑 Smiley Sans; check each licence.

## 8. Don't
Pure black or pure white surfaces; uniform neon everywhere; bloom that washes out the frame;
grey-box shapes; repeated identical buildings in a row; textures stretched or visibly tiling;
floating or sunken objects; z-fighting decals; random gibberish text; real trademarks.

## 9. Research authority
`ref/art/DOSSIER.md` holds the verified numbers (palette tokens §2, emission tiers §2.3, value targets §2.4,
lighting §3, material recipes §4, texture IDs §5, decals §6, typography §7) and `ref/art/lookdev/` has
verified shaders + `env_recipe.gd`. Use them. Where this file and the dossier differ, this file wins.

## 10. Art critic checklist (every visual review)
1. Value structure readable in greyscale? Car stands out?  2. Palette per §3, ≤ 15 % neon?
3. Texture detail at 5 m / 20 m / 100 m — no flat or stretched surfaces?  4. Tiling hidden?
5. Silhouettes and scale correct (lane 3.5 m, parapet 1.1 m, deck 8–12 m high)?  6. Emissives
balanced, no blown-out areas?  7. Shanghai recognisable?  8. Edges/bevels catch light?
9. No floating/z-fighting/missing faces?  10. Would this frame look good as a store screenshot?  11. Lit density per §11 at 120 m?

## 11. Night lighting density (added 10-20 after the first whole-city captures)
The first captures (captures/lead_view1_*.jpg, lead_view2_*.jpg) read as a dead grey city. Targets:
- **Lujiazui is the hero skyline**: every landmark tower wears its real LED signature, bright enough
  to be the second-brightest thing on screen after the player car — Oriental Pearl: magenta/violet
  spheres with LED dot chasing + lit columns and the small spheres; Shanghai Tower: twisting LED
  lines up the facade + lit crown; SWFC: the top opening outlined in blue-white LED + vertical edge
  lines; Jin Mao: warm gold-white tiered crown and banding. Generic Pudong towers: cool white
  LED edge/crown lines on 50 % of them, red aviation beacons blinking 1 Hz on every roof > 100 m.
- Office towers: 20–30 % lit windows in clustered floors (whole floor bands + scattered), cool white.
  Residential: 15–25 % warm, scattered, with curtains/TV-blue variety. Bund: floodlit, windows warm.
- Ground and lots: dark (wet asphalt, paving, grass) — never a pale grey plane. From 120 m altitude
  the street grid must show as lines of sodium/LED dots (lamp emissives visible at distance).
- Street level: shop fronts lit (glazed, warm interiors), signs every 10–20 m on commercial streets.

