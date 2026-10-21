# Brief: car_model — the hero Tesla Roadster (Rocket trim) in Blender

## Goal
Build the player car procedurally in Blender 5.2 so it is instantly recognisable as the Roadster
revealed on 2026-10-15, with game-ready topology, named parts for animation/damage, and richly
detailed textures. Output: `game/assets/cars/roadster/roadster.glb`.

## You own
`blender/car/**` (scripts, generated textures, a README) and `game/assets/cars/roadster/**`.

## Read first (all of it)
1. `ref/roadster/DOSSIER.md` — sections 2–8 are your spec. Section 8.1 is the build order.
2. `ref/roadster/roadster_loft.json` — load it in code; never retype numbers.
3. `ref/roadster/img/INDEX.md` + photos 01, 03, 06, 08, 09, 12, 13, 16, 17, 18, 21–24 (≤ 8 per look,
   downscale first). `ref/roadster/scripts/validate_loft.py` and `loft_check.py`.
4. `ART.md` §3 (palette), §5 (materials), `CONTRACTS.md` §1, §2, §6. `blender/lib/*.py` (use it).

## Lead decisions (override the dossier where they differ)
- Trim = **Rocket**: 4 rear nozzles + 6 perimeter nozzles; cockpit = 1 driver seat, and in the
  passenger space a white carbon-wrapped **COPV tank** (cylinder Ø 0.42 m, length 0.95 m, lying
  along X behind/right of the driver, white #E8E8EA with a thin red #FF2A2A band and fine filament
  winding normal). It is visible through the gold glass — make it look good.
- Paint Ano White #ECEDEF (material name **`SH_car_paint`** so Godot swaps in the clear-coat
  shader; give it a correct base colour anyway). Glass material **`SH_glass_gold`** (base #5A3F2A,
  metallic 0.3, roughness 0.03, alpha 0.85, BLENDED). All other materials normal Principled.
- No real logos/text: wheel centre cap = dark hexagon with a fine engraved concentric pattern, no
  "T". Tyre sidewall text "SKYRUSH TROFEO  295/30 R20" / "335/30 R21" (normal-map relief).
  Rear plate = Chinese new-energy plate 0.48 × 0.14 m, white→green vertical gradient
  (#F4FBF6 top → #48C77E bottom), black text **沪A·D2049R** (font `game/assets/fonts/NotoSansSC-Variable.ttf`,
  bold weight) generated as a PNG with Python+PIL (`/usr/bin/python3` has PIL 11). Plate centre
  (0, −2.092, 0.66), slightly recessed.
- Node/marker names: CONTRACTS §6 plus dossier §8.2. Nozzle **meshes** are `NozzleMesh_R1`…; the
  **markers** are Empties `Nozzle_R1`…`Nozzle_R4`, `Nozzle_P1`…`Nozzle_P6` created with
  `common.empty(name, location, direction=<jet direction>)` (Blender local +Y = jet direction).
  Also Empties `Light_Front` (0, 2.30, 0.44) dir +Y, `Light_Rear` (0, −2.10, 0.85) dir −Y,
  `Camera_Hood` (0, 1.0, 1.05), `Seat_Driver` (−0.30, 0.0, 0.45), `Fan_Intake` (0, 2.15, 0.13).
- Root object: Empty `Roadster` at the origin; every part parented to it. Wheel objects have their
  origin at the wheel centre (spin about local X). Doors pivot per dossier; Wing pivot at its main
  element leading edge; `HeadlampPanel_L/R` hinged.
- Detachable panels for the damage system are separate objects: `Bumper_F` (black lower front
  fascia + splitter), `Bumper_R` (black rear valance with the nozzles' bezel plate — the nozzle
  meshes stay on the body), `Hood` (vent hood Y 1.61→1.80), `Door_L/R`, `Wing`, `Skirt_L/R`,
  `Diffuser` (strakes). Behind each detachable panel put a dark inner surface (#141416) so the
  body never shows a hole when a panel flies off.
- Budget LOD0 60k–150k triangles total (wheels may take 30 %). Godot makes LODs.

## Detail and textures (the user explicitly demands refined textures everywhere)
- Body: bake from the bevelled mesh a 4096² **panel-gap normal + AO** map (gaps 4 mm wide per
  dossier §7.1 list) on a clean UV unwrap of Body (smart project, 2 % margin, no overlaps); assign it
  as the normal map of `SH_car_paint` (Godot copies the textures into the shader). Orange-peel
  is done by the Godot shader, not you.
- Black trim: satin #111113 with a fine-grain normal (library texture, e.g. ambientCG
  `Plastic` / `PaintedPlastic` set — fetch with `tools/textures/fetch.py`), arch lips slightly glossier.
- Carbon: diffuser strakes, splitter, fan shrouds — 2×2 twill (ambientCG carbon set), tow 4 mm.
- Tyres: separate 2048×512 tread+sidewall normal map you generate (numpy or bake): 2 grooves, sipes,
  raised lettering at 25 % white; rubber #161616 roughness 0.85; thin glossier ring near the rim.
- Wheels: 6-spoke star per photo 13: white aero blades #E6E6E8 with chamfer highlight, dark satin
  spokes #2A2B2E, brushed gold accents #B08458, hex centre cap. Carbon-ceramic discs (#3A3A3C
  mottled, drilled ring) + bronze calipers behind the spokes (`Caliper_*`, not spinning).
- Nozzles: titanium bezel ring #9B958E (80 mm OD), gold throat #B08458 → #2A1A0E inside, recessed
  30 mm. Fans: 11 dark blades + 6 mm hex grille. Light bars: emissive (`M_LightBarRear` #FF1A2A
  strength 10 with an LED-segment emission texture 6 mm pitch; front bar #F2F6FF strength 8; amber
  markers). Interior: white seat fabric weave, grey microsuede, black dash, yoke, horizontal screen
  (emissive dark-red UI texture), red ambient strips.
- Every material must show image or procedural texture detail in `tools/blender.sh preview`
  stats — no `<-- UNTEXTURED` lines except pure emissive light bars.

## Milestones (checkpoint in `status/car_model.md` after each; render previews each time)
1. **Body loft** from the JSON (dossier §8.1 steps 1–4), wheel wells cut, glass separated.
   Run `ref/roadster/scripts/validate_loft.py` (or your own equivalent) and make an **overlay
   check**: render pure orthographic side/top/rear silhouettes at the photo scale and composite
   them semi-transparently over photos 01, 12 and 08 (PIL) → `captures/car_model/overlay_*.jpg`.
   Side centreline within 2 cm, plan/rear within 3 cm.
2. Wheels, tyres, brakes, arch liners and lips, sills/skirts. Ride height correct (tyres touch z=0).
3. Front/rear details: light bars, headlamp panels + jewels, nozzles R1–R4 and P1–P6, fans,
   diffuser strakes, plate, camera, side markers, panel gaps, markers (Empties).
4. Wing (main + slat + endplates + struts) with pose data in a custom property
   `poses` = {"stowed": deg, "low_drag": deg, "high_downforce": deg, "air_brake": deg} on `Wing`;
   doors and headlamp panels with pivots; detachable panels + inner surfaces.
5. Interior (seat, COPV tank, yoke, screen, dash, red strips) — simplified but tidy.
6. UVs, bakes, library textures, final materials; export with `blender/lib/export.py`.
7. Godot check: `tools/godot.sh shot` a test scene you create under `game/assets/cars/roadster/`
   (e.g. `preview_roadster.tscn` with the glb, a ground plane and `core/stubs/stub_environment.tscn`):
   front34, rear34, side, close rear — confirm materials/textures survive import.

## Acceptance (the lead checks all of these)
- `tools/blender.sh preview game/assets/cars/roadster/roadster.glb roadster --target-height 1.147`:
  bbox ≈ 1.98 × 4.38–4.49 × 1.147 m (wing stowed), no UNTEXTURED materials, tris 60k–150k.
- All node names listed above exist (print them). Wheels spin about X at their centres.
- Overlays within tolerance; the car reads as the reveal car in studio AND night previews from
  front34, rear34, side, rear, top; close-ups of nozzles, wheel, rear bar look crafted.
- Godot screenshots show the same materials (gold glass, white paint, black base, red bar glow).

## Pitfalls
- Do not subdivide/auto-smooth the shell: flat facets + crisp bevels (dossier §8.4).
- The glass must read dark bronze-gold, never transparent-clear or black-plastic.
- Keep every Write/Edit ≤ 120 lines; split the build into modules (`blender/car/build_body.py`,
  `build_wheels.py`, `build_details.py`, `build_interior.py`, `textures.py`, `build_all.py`).
- Baking: Cycles, 64 samples is enough; bake at 4096 only for the body; others 2048/1024.
