# Lead notes for environment (mandatory; from the lead's look at lookdev_*.jpg, round 1 in progress)
E1. `SH_soffit_blue` must not be a flat emissive: emission ≈ E0.9 with a gradient across the wing (100 % at the outer
    edge → ~55 % toward the girder), slight concrete texture showing through (albedo #6E6C68 × texture), plus support for
    the thin LED tube strip (E3–E5, `#5A3DFF`). Under-deck frames currently read as a solid blue ceiling.
1. The haze/fog reads warm brown/orange (dusty) around the car and down the street. ART + art dossier: depth fog #2A2638 (cool violet), volumetric albedo #9AA0B8; any warm tint comes only from lamps lighting it. Check `fog_light_color`, volumetric fog albedo/emission and the sky's horizon colour; re-measure with screenshot_stats.
2. Wet road reflections are good — keep. Make sure every bright sign within 40 m streaks on the road (SSR + probe), and that puddles do not mirror the HDRI's golden Bund ("gold foil" rule).
3. Lookdev placeholder boxes with the brown wood-like texture should use the real facade shaders/materials so the lookdev judges real materials (the facade presets, concrete_stained, granite).
4. Provide a lookdev camera that frames the Roadster glb (when it exists) at the chase-cam distance (6 m back, 1.9 m up) on the wet road with neon — this is the hero shot the lead reviews for SH_car_paint and SH_glass_gold.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## INT3 — lead integration drive 10-20 09:00 (evidence: captures/lead_int3_t2_0.jpg / _t6_0 / _t10_0 / _t14_0 (lead integration drive 10-20 09:00, `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --debug --shots=2,6,10,14 --out=lead_int3`, all 13 units real))
E-INT1: in the real game (main.tscn, Bund at spawn) the wet road reads MATTE BLACK: no reflections of the uplit Bund facades, no
  streetlight streaks, no neon in puddles (t2). SH_wet_asphalt is applied and skyrush_wetness = 0.85, so check SSR / reflection
  probes / exposure in the integrated scene, not the look-dev scene: a reflection probe set along the Bund + Yan'an deck, SSR at
  high, and make sure the streetlights actually light the carriageway (lamps every 30–35 m, warm 3,000 K, shadows off). Gate: a
  `tools/godot.sh shot` of main.tscn at the spawn shows long vertical light streaks under every uplit facade.

## ART-NIGHT + SETTINGS (10-20 10:20, evidence: captures/lead_view1_{bund,lujiazui,dragon,yanan,spiral,sky,toll,charge}.jpg, captures/lead_view2_{pudong,pearl,pillar}.jpg (main.tscn --skip-menu --env-only))
EN-1: the r4 finding that `user://settings.cfg` was written as low by another unit is fixed in core: every
  tools/godot.sh run now passes `--quality=high` (unless the caller sets one) and Settings neither reads nor
  writes the player file when --quality is given. Re-check E-INT1 (wet road reflections in main.tscn) at high.
EN-2: the night must read lit (ART.md §11): check exposure/glow so landmark LEDs bloom softly and the far
  street-lamp dots read from 120 m; the river should mirror the Lujiazui lights (lead_view1_lujiazui shows
  white light blobs on a grey promenade instead).
