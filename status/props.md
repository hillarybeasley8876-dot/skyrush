# props status

Unit: `props` — street kit, toll plaza, gas/charge stations, sky-lane pieces.
Owns `blender/props/**`, `game/assets/props/**`, `tools/signs/**`.
Round: **r4** (the review of round 3 is `reviews/props-r3.md`).

## Done — the review of round 3, item by item

### MUST-FIX 1 — the roughness channel (the surfaces all read roughness 1.0)
* The four family maps are written in the **glTF layout** (G = roughness, R and B
  unused).  `godot_assets.py` now writes `roughness_texture_channel = 1`
  (GREEN) into every family `.tres`, and the metal family's scalar is 1.15 so
  the map's mean (0.391) lands on the **0.45** of PR-INT2.
* The test loads every family `.tres` and fails unless the channel is GREEN
  and the map keeps a roughness breakup (σ > 0.01) in green.

### MUST-FIX 2 — paint is a dielectric, bare metal is metal
* A **fifth family** `Prop_Paint` (`prop_paint.tres`, metallic **0.0**,
  roughness from the green channel, mean 0.46) with its own texture set: orange
  peel, roller bands, and chips that show the **grey primer** (the chip is
  45 % of the base, so on a white paint it reads as primer).
* The surface table (`blender/props/atlas.py`) sends every painted finish
  (`white_paint`, `red_paint`, `orange`, `yellow`, `green`, `teal`, `gold`,
  `blue`, `charge_teal`, `white_plastic`, `black_plastic`, `rubber`) to the
  paint family; the bare metals stay in `Prop_Metal` (metallic 0.8).
* The props that would have gone over the surface budget were re-parted (the
  bike share dock, the bin, the e-scooter and the planters are painted now),
  so every street prop still ships **1-3 static surfaces**.
* The signal mast is **galvanised** (`galv` #8E9297) instead of dark steel, so
  it reads silver-grey with a specular line at night (PR-INT2).

### MUST-FIX 3 — the canopies: value structure instead of a white slab
* The **soffit is not emissive any more**: a white panel (roughness 0.5) with
  a dim glow (E0.08).  The recessed LED panels are separate emissive
  geometry (the 24 downlights of the gas station, 30 of the charging hub, the
  troffers of the toll plaza) and read as the bright accents.
* The **light pool is additive**: `prop_lightpool_*.tres` has
  `blend_mode = ADD`, `shading_mode = UNSHADED`, a black albedo and the pool
  image as the emission at **E0.7**.  It adds light to the ground instead of
  painting an opaque white sheet over it, and it sits at z 0.025, **under**
  every marking.
* The forecourts are **real concrete** now (`#8F8C86`, a mineral surface) with
  oil drips at the pumps and the chargers and polished tyre lanes.
* The gas station's roof is a metal deck and the store has a **glazed front
  with a lit interior** (the ceiling panels, the shelves and the counter are
  really inside the shop).

### MUST-FIX 4 — the charging bays
* 12 bays in **2 rows of 6 at a 5.5 m pitch**, painted `#1E9E5A` with a
  **0.15 m white edge line**.
* The numbers are **white glyphs with an alpha cut-out** on their own sheet
  (`prop_bay_numbers.png`, a 4 x 3 grid) with an alpha-scissor material: no
  dark tile on the paint any more.
* The cyan LED line has **its own material** (`Prop_SignLedCyan`, E4 with a
  dimmed emission colour so it stays cyan instead of clipping to white).
* The totem's lightning bolt is a real board (`charge_bolt`) and faces the
  approach road.

### MUST-FIX 5 — the toll plaza layout
* **The island of every lane is on the driver's left** (eastbound: -Z,
  westbound: +Z); the booths and the barrier hinges moved with it.  The test
  checks the island's AABB centre against the lane's signal for all 20 lanes.
* The **westbound lane signals** stand at the **+X end** of the canopy
  (x = +10.05) and face +X.
* **Every material is single sided** (backface culling on) and every sign
  quad has a back panel, so no board shows its text mirrored any more.  The
  test fails if a `Prop_Sign*` material is double sided.
* The barrier arms still lie along their node's **local +Z**, so
  `toll_plaza.gd::_lift()` (`rotation_degrees.x = -78`) raises them as before;
  the arms of the lanes whose island moved are the mirror of the others.

### MUST-FIX 6 — the close-up props are not grey boxes any more
* **Toll island noses**: a segmented crash cushion (4 yellow segments, black
  45 degree stripes, bolted end plates and a reflective chevron on the face
  that meets the traffic) — `blender/props/toll_parts.py`.
* **Toll booths**: glazed on **all four sides** in the upper 1.4 m with
  mullions, a door, a roof overhang with the red band, a roof air-conditioning
  unit and a lit ceiling panel (E1.5) behind the glass.
* **Gas dispensers**: 2.3 m tall, 0.5 x 1.0 m, a rounded white cabinet with a
  red brand panel, a lit topper, **two nozzle holsters per side with looping
  hoses** and a green LED price window.
* **Gas columns**: silver cladding panels with a **red base skirt**.
* **Planters**: ten cards tilted 30-70 degrees outward, covering the top of
  the box and cascading over the long faces (172 tris).
* **Plane-tree bark**: the camouflage is gone.  The plates are irregular
  5-30 cm patches of cream / olive / grey with a domain warp, a soft 1-2 cm
  transition and a thin peeled rim, plus a vertical fibre in the normal map
  and a dark grime band on the first 0.6 m of the trunk.
* **Sky-lane pad**: a 0.4 m deck with side skirts, a steel substructure of
  five portal bents, LED edge strips, an anti-slip deck and the painted
  飞行航道 SKY LANE marking (own alpha-cut-out sheet).
* **Chevrons**: an LED segment texture at **E1.8** (was flat colour at E9).

### MUST-FIX 7 — the foliage
* `prop_foliage.tres`: **alpha scissor** (threshold 0.5), **ALPHA_TO_COVERAGE**
  and the **culling off** (the cards are seen from both sides), with a
  `#6E7A2A` backlight.
* The plane leaves are retinted to the **October mix of the dossier**
  (70 % `#6A7A2E` + 30 % `#9C8A3A`); the quadrant averages `#73782C`.

### SHOULD-FIX
* **Toll fascia**: the name panel (21 m) now **fits inside the flat band of the
  fascia** (the fascia is 3.4 m tall, the bull nose 1.2 m), the green `ETC`
  LED strips are on the fascia, and a lit accent runs along the lower edge of
  the bull nose, so the `#A7ACB1` fascia is not invisible any more.
* **Toll pavement**: the joints are **20 mm sealant lines** (not 10 cm black
  stripes), the lanes are polished by the tyres, the islands stand on oil
  patches, and the lanes carry a real painted **arrow** and the green `ETC`
  marking (own alpha-cut-out sheet, not white rectangles).
* **Wet after rain**: the mineral family carries a wet mask (the roughness
  drops to 0.45 in the damp patches).
* **Bus stop**: the back is **glass** with a frame, the roof is glass.
* **Sky-lane ring**: 64 segments (no facets any more).
* **Sky-lane gantry**: a 0.9 m **box truss** like the guide gantries, and its
  sign hangs in front of the truss (it was hidden inside it).
* **Spike strip**: the lattice is a **concertina of four panels** and the
  `Deploy` animation is a scale along the strip, the same motion the police
  unit drives at runtime.

### Code (the SHOULD-FIX of the code section)
* `tests/prop_density.gd` (with its `class_name`) is **deleted**; the density
  helper lives in `tests/prop_contract.gd` and is used through a `preload`
  const (CONTRACTS §3).
* `test_props.gd` is split: the shared constants and helpers in
  `prop_contract.gd`, the layout checks in `prop_layout.gd`, the site checks
  in `prop_sites.gd`.  Every magic number of the old test is a named const.
* `FAMILY_MATERIALS` is defined once (in `prop_contract.gd`).
* `preview_props.gd` has named constants for the light energies, ranges, angle
  and colour.

## The material system (how a prop is put together)

Five tileable families carry every surface; the colour of a part is its
**vertex tint**, so one material serves every colour of a family.

| family | texture | content | metallic | roughness |
|---|---|---|---|---|
| `Prop_Metal` | `prop_metal_{diff,nor_gl,rough}` | galvanised spangle, scratches, chips, grime | 0.8 | 0.45 (map) |
| `Prop_Mineral` | `prop_mineral_*` | concrete from the CC0 `rough_concrete` set, wet patches | 0.0 | 0.80 (map) |
| `Prop_Panel` | `prop_panel_*` | ACP: 6 mm seams, rivet heads, drip streaks | 0.0 | 0.42 (map) |
| `Prop_Paint` | `prop_paint_*` | orange peel, roller bands, chips with grey primer | **0.0** | 0.46 (map) |
| `Prop_Bark` | `prop_bark_*` | irregular exfoliating plates, vertical fibre | 0.0 | 0.85 (map) |
| `Prop_Soffit` | the panel maps | the canopy ceiling, a dim glow (E0.08) | 0.0 | 0.5 |

One texture tile covers **2 m** of surface (512 px/m), so the detail density
never changes with the size of a part.  The roughness maps are written in the
glTF layout (**G = roughness**); every material reads them with
`roughness_texture_channel = 1`.

The cut-out materials: `Prop_Foliage` (alpha scissor, the culling off),
`Prop_BayNumbers`, `Prop_DeckText`, `Prop_RoadMarks` (own alpha sheets, not
the sign atlas — the atlas has no alpha channel, so the numbers used to show
as dark tiles).

## In progress / next

* The **spike strip's accordion** is built as a concertina of four panels and
  the deploy is a scale along the strip.  The police unit drives that motion
  itself (`police_spike_strip.gd` scales the `Spikes` node); if it wants a
  real hinge, the `Spikes` node would need a second animated child.
* The **metal family is still a compromise** between galvanised steel, painted
  steel and aluminium: the spangle of the galvanised texture is the dominant
  feature of a column at 5 m.
* The **world unit does not create the lights of the `Light_<n>` markers** yet,
  so in the game the three sites are lit by the additive pool and the LED
  panels only (see the requests).

## How to test (exact commands)

```
/usr/bin/python3 tools/signs/build_all.py            # textures + both atlases
tools/blender.sh run blender/props/build_all.py       # 42 glb (street/ + sites/)
tools/blender.sh run blender/props/lineup.py          # the street-kit lineup sheet
tools/godot.sh check --only=res://assets/props/      # loads the scene + scripts
tools/godot.sh test res://assets/props/tests/test_props.gd
tools/godot.sh shot --scene=res://assets/props/preview_props.tscn --out=props \
    --cams=res://assets/props/preview_cams.json --quality=ultra
/usr/bin/python3 tmp/props/texel_density.py          # the texel density of every glb
/usr/bin/python3 tmp/props/family_stats.py           # the family texture stats
/usr/bin/python3 tmp/props/lum.py <capture>          # the value stats of a capture
/usr/bin/python3 tmp/props/probe.py <capture> <label,x0,y0,x1,y1> ...
```

## Evidence

* **Contract test**: `tools/godot.sh test res://assets/props/tests/test_props.gd`
  -> **148 PASS** lines, `PASS props contract (0 failures)`.
  The new checks: every family material reads its roughness from **green**,
  the paint family is a **dielectric** and the metal family a **metal**, the
  foliage is an **alpha scissor with the culling off**, every island is on the
  **driver's left**, the westbound signals stand at the **+X end** of the
  canopy, and **no `Prop_Sign*` material is double sided**.
* **Godot check**: `tools/godot.sh check --only=res://assets/props/` ->
  `CHECK 18 files, 0 failed, 0 engine errors, 0 warnings`.
* **Build**: `tools/blender.sh run blender/props/build_all.py` -> **42 props
  built**, no errors.
* **Surface budget** (from the test, `user://props_surfaces.txt`):
  street props **1-3** static surfaces, sites **5-8** (the limit is 8):
  the gas station 8, the toll plaza 8, the charging hub 7, the sky-lane pad 5.
  The toll plaza: **8 static + 60 dynamic** (20 `Barrier_<n>` + 40
  `LaneSignal_<n>_Red/_Green`).
* **Triangles**: every street prop is under 3 000 (the biggest is the bike
  share at 2 896, then the magnolia lamp at 2 804).  The sites: the toll plaza
  **17 742** (it grew from 8 726: 20 glazed booths and 20 crash cushions),
  the gas station 4 834, the charging hub 2 092, the sky-lane pad 592.
* **Texel density**: the share of every prop's area below 300 px/m stays
  under 5 % (the worst is the e-scooter at 3.0 %, then the spike strip and
  the crash barrier at 0.7 %).
* **Family texture stats** (`tmp/props/family_stats.py`):

  | family | mean | L sigma | L p2-98 | normal dev | roughness sigma |
  |---|---|---|---|---|---|
  | metal | #DFDFDF | 8.58 | 28.0 | 3.79° | 0.090 |
  | mineral | #DFDFDF | 10.18 | 42.0 | 5.45° | 0.088 |
  | panel | #DEDEDE | 12.85 | 17.0 | 3.27° | 0.035 |
  | paint | #ECECEC | 9.60 | 22.0 | 2.47° | 0.105 |
  | bark | #A6A28D | 27.25 | 94.4 | 8.06° | 0.017 |

  (the review asks for L sigma >= 6/255 on every family and a roughness sigma
  >= 0.08 on the metal)
* **Value structure** (measured in the engine, `tmp/props/lum.py`, the lit
  forecourt band = the rows 500-560 of the driver view):

  | capture | forecourt mean | P50 | P95 | clipped |
  |---|---|---|---|---|
  | `props_final_toll_driver.jpg` | 0.420 (107/255) | 0.420 | 0.809 | 0.01 % |
  | `props_final_gas_driver.jpg` | 0.595 (152/255) | 0.628 | 0.758 | 0.00 % |
  | `props_final_charge_driver.jpg` | 0.553 (141/255) | 0.568 | 0.768 | 0.00 % |

  The review asks for a forecourt of 110-170/255: the gas and the charging hub
  are inside it, the toll plaza is at 107 (its canopy is 112 m long with only
  ten markers, so the area in front of the booths is dimmer).
* **The 5 m frames** (the same measure over the whole frame):

  | capture | P50 | P95 | clipped |
  |---|---|---|---|
  | `props_final_close_gas_dispenser.jpg` | 0.367 | 0.847 | 0.11 % |
  | `props_final_close_toll_booth.jpg` | 0.481 | 0.874 | 0.40 % |
  | `props_final_close_charge_post.jpg` | 0.356 | 0.772 | 0.19 % |
  | `props_final_close_gas_column.jpg` | 0.340 | 0.745 | 0.42 % |

  (the review asks for P50 <= 0.45, P95 <= 0.85 and clipped <= 2 %; the booth
  frame is at 0.481/0.874 — the frame is half bright concrete, and the white
  booth wall is what pushes it up)
* **Colours** (measured in the engine, `tmp/props/probe.py`):
  the lit booth wall **#AAA6A0** (the review asks for >= #B4B4B4), the charge
  post **#98918E** and the gas dispenser **#928886** (the paint albedo is
  #EDEDE8; a white surface under a canopy at night cannot render brighter
  than the light that falls on it), the dispenser red **#624B49** (the albedo
  is #E60012), the bay green **#AFCBA9** (the albedo is #1E9E5A — the canopy
  lights wash the saturation out).
* **At 100 m** the charging hub reads: the SAT share of the frame is
  **1.04 %** (the review asks for >= 1 %) and the cyan line and the green bays
  are both legible (`props_final_charge_100m.jpg`).
* **Captures** (1600 x 900, `--quality=ultra`, 0 errors):
  * the sites from the driver's seat, from a 7 m hop and from 100 m:
    `captures/props_final_{toll,gas,charge}_{driver,hop,100m}.jpg`
  * the 5 m close-ups: `captures/props_final_close_{gas_dispenser,gas_column,
    toll_booth,toll_arm,charge_post,mast,tree,planter,bike}.jpg`
  * the sky lane: `captures/props_final_sky_lane.jpg`,
    `props_final_sky_lane_gate.jpg`
  * the street kit: `captures/props_final_street.jpg`
  * in the game (`--scene=res://main.tscn --stub=police`):
    `captures/props_r11_game_{toll,gas,charge}_drv.jpg`
  * the Blender sheets: `captures/blender/prop_{toll_plaza,gas_station,
    charge_station,sky_lane_pad,sky_lane_gate,sky_lane_gantry}_{studio,night}.jpg`
    (the only UNTEXTURED flags are the `-convcolonly` proxies: 61 for the toll
    plaza, 18 for the gas station, 22 for the charging hub)
  * the street-kit lineup with the 1.75 m figure:
    `captures/blender/street_kit_lineup_{night,studio}.jpg` (3200 x 1150, the
    aspect ratio is kept)
* **Sign text** is correct Chinese + English in the atlas: 申城西收费站
  SHENCHENG WEST TOLL, 中国石华 SINOPEX, 易快 EZ-JOY, ETC 专用 / ETC 人工,
  飞行航道 SKY LANE ▲ 300 m, VOLTA, 500 kW, 今日油价, the 92# price window,
  the VMS 前方拥堵 注意减速 SLOW, the bus route board 七莘路 → 天山路, the
  lightning bolt of the charging totem and the new lane arrow / ETC 专用
  markings.
* **Size** (the IMPORT-CHURN note of the lead): the unit is **12 MB**,
  `game/assets/props/_tex/` holds **30 files (5.7 MB)** (the five families,
  the sign atlas, the foliage, the glass, the opal, the lens dots, the two
  light pools, the LED panel, the hologram artwork and the three cut-out
  sheets), the sign atlas is 4 MB and there is no scratch in `game/`.

## Known issues

* **The metal family is one compromise** between galvanised steel, painted
  steel and aluminium: the spangle of the galvanised texture is the dominant
  feature of a column at 5 m.  The spangle contrast was lowered to ±0.038 and
  the normal strength to 1.5, but the family still shows it.
* **A white surface under a canopy cannot render brighter than the light
  that falls on it**: the booth wall measures #AAA6A0 and the charge post
  #98918E under the canopy lights (the review asks for #B4B4B4 and #F2F2F2).
  The albedo is right (#EDEDE8); the render needs more light on the vertical
  surfaces, i.e. wider cones or more markers.
* **The toll plaza grew to 17 742 triangles** (it was 8 726): 20 glazed booths
  and 20 crash cushions are the price of the MUST-FIX 6.  The plaza is one
  mesh, so it is one draw call, but the vertex budget of a 110 m prop is worth
  a look.
* **The toll forecourt reads 107/255** against the 110-170 the review asks
  for: the canopy is 112 m long and has ten light markers (one every two
  lanes), so the ground in front of the booths is dimmer than the ground
  under them.
* **In the game the ground markings of a site can be hidden**: the charge
  station's POI (`charge_sky`, 1680/0/420) sits on a city block whose surface
  is at the kerb height (+0.15 m), and the props' ground pad is at +0.02 m,
  so the forecourt and the bay paint are buried.  The toll plaza (on a road)
  is fine.
* The **spike strip's deploy** is a scale along the strip, driven by the police
  unit; the concertina makes the folded state read, but a real hinge would
  need a second animated node.
* The **sky-lane ring** needs an emission artwork to render at all (the shared
  `SH_hologram` shader samples the imported material's emission map); the
  props' ring carries one now (`prop_hologram.png`).
* Godot renames the collision proxies: every `-convcolonly` node becomes a
  `StaticBody3D` with the `-convcolonly` suffix stripped, so the names
  survive but the type does not.

## Requests (to core / other units)

* **world**: the `Light_<n>` markers of the three sites are **not turned into
  lights** yet.  The preview scene shows how (`preview_props.gd`): a spot light
  per marker, 78 degrees wide, energy 9 (the gas and the charging hub), 11
  (the charging hub, it is open on three sides) and **19 for the toll plaza**
  (its canopy is 112 m long with ten markers).  Without them the sites are
  lit by the additive pool alone and the vertical surfaces stay dark.
* **world**: the **charge station's POI** sits on a raised city block, so the
  props' ground pad (top +0.02 m) and the bay paint are buried.  Either the
  site needs a POI on the road (like the toll plaza) or the lot has to be
  flattened to the site's own level.
* **world**: `toll_plaza.gd` matches the barrier arms to the lanes by
  **index** (`Barrier_<i+1>` against the signals sorted by z), but the plaza
  numbers the lanes 1-10 (eastbound) and 11-20 (westbound).  The arms carry
  their lane in the `lane_y` extra — matching on that would be correct.
* **world**: the `EtcStrip_*` nodes the world looks for are the **green ETC
  signs on the fascia** (y = ±22 and ±38); the painted ETC markings on the
  ground are in one `LaneMarks` mesh.  If the ETC lanes should be the painted
  ones, the markings have to be separate nodes.
* **police**: the spike strip's `Deploy` animation is a **scale along the
  strip** now (the same motion `police_spike_strip.gd` drives at runtime);
  the old glTF animation rotated the lattice up out of the case.
* **lead**: the CC0 sets `bark_platanus` and `japanese_sycamore` (art dossier
  §4.9) would replace the drawn bark plates; the drawn ones are 5-30 cm
  irregular patches with a peeled rim, but a photo set would be better.
* **core**: `lib/mats.py` has no hook for a unit-local texture directory; the
  props still load their own images (the request of the last round stands).
* **core**: the glTF importer drops the `-convcolonly` suffix of the collision
  proxies (the name survives, the type does not), so the world cannot tell a
  proxy from a real body.
* **core / shaders**: a `SH_prop_detail` shader (world-space macro noise + a
  detail normal) would break the 2 m repeat of the families on the 110 m
  plaza and the 70 m roofs.  The families carry baked macro grime, but only a
  world-space tint kills the repeat.
* **lead**: the police and the rivals units have **parse errors** while I was
  working (2026-10-20, 15:40-16:10): `ai/police/police_spawner.gd` and
  `ai/rivals/rival_car.gd` failed to load, so the in-game captures had to be
  taken with `--stub=police` and the rivals are still broken.
