# Lead notes for npc_cars (mandatory) — from the lead's look at lineup_34
IMPORT-CHURN (lead, 08:40, mandatory): Godot imports are now the team-wide bottleneck (934 textures, 3.8 GB import cache, 25+
  callers queued behind the import lock). For your unit: (1) write generated textures/meshes ONLY when their bytes change
  (generate to memory/tmp, compare with the existing file, skip identical) so rebuilds do not touch unchanged files; (2) small
  props and parts use 1024² (or 512²) maps and shared atlases/trim sheets — 2048² only for hero surfaces; (3) never write
  scratch images inside game/ (use tmp/<unit>/); (4) report your texture count + total MB in status.
N-ART5 (lead, after r2: "8 cars share one slab body with black rectangles stuck on") — MANDATORY APPROACH CHANGE.
  Build every car body with ONE parametric lofted-body generator (`blender/npc_cars/body_loft.py`), not boxes:
  a) Parameters per model (metres, Blender frame +Y forward, origin ground centre between axles): L, W, H, wheelbase, front
     overhang, tyre radius, track, nose_z, hood_z (at cowl), cowl_y, roof_front_y, roof_rear_y, deck_y, deck_z, tail_z,
     belt_z (front/rear), roof half-width, tumblehome, plan corner radius front/rear, side bulge, ground clearance.
  b) Side profile = top(y) polyline nose→hood→windshield→roof→backlight→deck→tail (smoothed), belt(y), bottom(y); plan =
     half-width(y) with rounded corners (circle arcs of the corner radius).
  c) 28 stations along Y; each station = the SAME 12-point half-section (bottom centre, floor edge, rocker, lower side, side max
     (bulge), shoulder, belt, glass base, glass top, roof edge, roof shoulder, top centre); outside the cabin the glass points
     lie ON the hood/deck surface (spaced, never coincident). Mirror → closed ring; bridge rings with geo.loft.
  d) Subdivision Surface level 2 + edge creases (0.8) on the belt and shoulder rows → smooth car surfaces with character lines.
  e) Glass = faces between "glass base" and "roof edge" rows inside the cabin stations, minus A/B/C pillar strips (2 faces wide)
     → separate object `Glass` (SH_glass_tinted). Door seams = thin normal-map lines / 4 mm grooves at the B-pillar and door
     cuts. Wheel arches = boolean cylinders at the axles (r + 0.04) + black arch liners; tyres fill the arches.
  f) Lights from the surface: front DRL light bar following the nose section at ~nose_z−0.04 (emissive #EAF2FF E6), rear
     light bar at the tail section (emissive RED #FF2030 E4 — the r2 tail lights glow WHITE: fix), plates recessed and
     visible (no opaque quads in front of them).
  g) Variants by parameters: sedan (fastback), suv (tall, flat roof, longer greenhouse), hatch (short, rounded), taxi
     (sedan + roof sign), police (sedan/suv + light bar), interceptor (low/wide coupe), robotaxi (pod: tall glasshouse,
     short overhangs), van/truck cabs (vertical fronts, raked windshield). Show a 5-car lineup side view vs. a 1.75 m figure.
1. Silhouettes are too boxy/toy-like at 30–80 m. Each car needs a distinct real-EV silhouette: sedan = long fastback/
   notchback greenhouse with a clear A/C-pillar rake and short overhangs; SUV = taller with a flatter roof and
   chunkier arches; hatch = rounded city car; police interceptor = low and wide. Model wheel arches as real cut-outs
   with black liners, tyres fill the arches (no floating wheels), visible side windows (dark tinted glass), door seams.
2. Chinese 2026 EV light signatures: full-width front DRL light bar + thin full-width rear light bar on most cars
   (emissive), plus brake-light segments. They must glow in the night previews.
3. Bus: modern Chinese battery bus look — rounded front cap, huge windshield, black window band, LED route sign
   (amber "申城公交 71路") front and side, doors with glass. Truck/van: cabs with real windshield rake and mirrors.
4. In the lineup render, show each car in a different paint from the art-dossier traffic mix (white/black/silver/blue/grey)
   so the lead can judge materials; police must read clearly as police at 50 m (navy band + light bar + 天巡 SKYPOL text).

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## LEAD-NPCBODY (10-20 09:45) — the lead wrote the car body generator; round 4 must switch to it
The r3 bodies scored visual 2.5 (faceted, stepped DLO, plank roofs). The lead wrote a core generator that
takes YOUR spec dicts unchanged: `blender/lib/car_body.py` (+ `lib/car_profile.py`, `lib/wells.py`).
Evidence: captures/blender/lead_cb2_{sedan_ev,suv_ev,hatch_ev,robotaxi,police_interceptor,police_suv}_studio.jpg,
lead_cb4_*.jpg (bodies only, placeholder wheels). Test script the lead used: tmp/lead/test_car_body.py.

    from lib import car_body
    parts = car_body.build(spec, col, materials=[paint, trim, glass, gloss_black], levels=2)
    parts["body"]   # Body: slots PAINT 0 / TRIM 1 (underbody, rocker cladding) / PILLAR 3 (B pillar, mirror sail)
    parts["glass"]  # Glass object (windscreen, side glass, backlight; wrap=True -> glass roof)
    parts["liners"] # ArchLiners (black well liners + lips; 6 cm cladding when arch_clad)
    parts["anchors"]  # wheels [(x,y,z)], front_face/rear_face {y,hw,z0,z1}, mirror (x,y,z), roof {y0,y1,z}

Must do in round 4:
1. Every `kind == "car"` model uses car_body.build. Delete body_loft.py's body/glass code (no dead code); keep
   details that still fit (lamps, grille, plates, mirrors, door shut lines ray-cast onto the NEW body, liveries).
   `lib.car_profile.Profile(spec)` has the same belt_z/top_z/half_width/floor_z/dlo_rows semantics as your profile.py.
2. Spec values tested by the lead (put them in spec.py):
   sedan_ev / taxi / police_patrol: roof_rear_y=-0.75, roof_drop=0.05, crown_y=0.10, deck_y=-1.78, deck_z=1.04,
     dlo_rear=-0.85, dlo_rail_end=-1.10 (fastback teardrop DLO, lead_cb4_sedan_b) — the r3 "limo" roof is gone.
   hatch_ev: dlo_rear=-1.02, dlo_rail_end=-1.10 (near-vertical D pillar; the default made a hooked sliver).
   police_interceptor: roof_rear_y=-0.55, roof_drop=0.04, crown_y=0.0, deck_y=-1.75, dlo_rear=-0.98, dlo_rail_end=-0.60.
   DLO rule: `dlo_rail_end` = where the glass top ends, `dlo_rear` = where the glass bottom leaves the belt.
   Fastbacks: rear = rail_end + 0.25 (teardrop). Hatch/SUV/MPV: rear = rail_end + 0.06..0.10 (upright pillar).
   Side glass starts 0.10 m behind the cowl (the black mirror sail) unless dlo_front is set.
3. Wheels must not read as black holes: bright alloy (albedo #B9BDC3, metallic 1, rough 0.25) or gunmetal for
   police, 5 twin spokes with real depth (spoke face 2 cm proud of the barrel), dark gaps showing a brake disc
   (#5B5D61 rough 0.4) and a caliper, tyre with rounded shoulders, sidewall lettering ring (normal map), tread on
   the contact face. Centre each wheel on parts["anchors"]["wheels"], radius = spec wr, width = spec ww.
4. Front and rear fascias on the smooth body: headlamp units with an inner reflector + LED strip (emissive
   white 6500 K) that follow the nose shape, a lower grille/intake (black, honeycomb normal), fog lamps, the
   plate recess; tail lamps as a red LED bar + side units, reverse lamps, a black diffuser. Lights must sit ON
   the surface (ray-cast against the body like your door lines), never float or sink.
5. Box vehicles (bus/van/truck) stay on boxcar.py but fix every r3 item: rounded body edges (bevel ≥ 0.12 m on
   the bus roof/front corners), the bus wheels at real size (1.0 m tyres, 0.29 m wide) in arches with liners,
   the window band as flush dark glass with black frames and pillars every 1.2–1.5 m, the LED route sign at
   its true aspect, bumpers on the body (not floating at 2.7 m).
Verification: a lineup render in Blender AND in Godot (tools/godot.sh shot of your preview scene at night)
with every model; triangle counts per model in status (target ≤ 30 k tris for cars incl. wheels; Godot LODs on).
