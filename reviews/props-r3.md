# props review round 3 — VERDICT: FAIL

## Scores (0-10): function 5.5, visual 4, code 6

Real progress since r2. The four tileable families and the UV-in-metres fix removed the wood grain everywhere,
including in the game (`captures/review_props_r3_game_tl.jpg`). The contract nodes, the budgets and the texel
density all pass. The share bikes, the VMS board and every sign now read well.

The game still does not look the way the unit intends:
- Two material-setup bugs: Godot reads roughness from the wrong channel, and every painted or plastic part is
  set up as metal.
- The two hero sites are blown-out white slabs over a white floor.
- The toll plaza puts every booth on the driver's right.
- Several close-up props are still grey-box.

Two lead notes are not met in-engine: PR-ART2 (green bays, value structure, reads at 100 m) and PR-INT2
(steel roughness 0.45). The user asked for refined textures and materials everywhere
("贴图纹理什么都要细化"). Fix every item below in order, re-measure in Godot rather than Blender, and keep
status/props.md factual.

## MUST-FIX

1. **In the engine every prop surface has roughness 1.0: Godot reads the wrong texture channel.**
   - The four external materials `game/assets/props/materials/prop_{metal,mineral,panel,bark}.tres`
     (written by `blender/props/godot_assets.py`) set `roughness_texture` but not `roughness_texture_channel`.
     Godot therefore uses RED. My probe (`tmp/review/props_r3_probe.gd`) prints `rough_ch=0` for all four.
   - `_tex/prop_*_rough.png` stores roughness in GREEN (glTF layout). For example, metal G has mean 0.391 and
     σ 0.095, while R is 1.000 with σ 0.000.
   - Result: every family surface renders at a uniform roughness 1.0. The metal "σR 0.095" in status exists
     only in Blender, and the mast cannot reach PR-INT2's "steel rough 0.45".
   - **Do:** set `roughness_texture_channel = 1` (TEXTURE_CHANNEL_GREEN) in all four .tres, written by
     godot_assets.py. The other option is grayscale roughness PNGs with channel GRAYSCALE.
   - **Verify:** add a test that loads each family .tres and fails unless the channel matches the image
     layout. Take a 5 m Godot capture of the gas column and the mast that shows specular breakup.

2. **Paint and plastic render as metal (metallic 0.8), so the white booths, dispensers and posts read dark grey.**
   - `blender/props/atlas.py:35-57` maps these surfaces to the `metal` family: white_paint, red_paint, hi_vis,
     yellow, orange, teal, charge_teal, blue, green, gold, plastic, white_plastic, black.
   - `prop_metal.tres` has `metallic = 0.8`, so a #EDEDE8 painted booth mirrors the night sky. Its wall
     measures #636166 at 5 m directly under the lit canopy (`captures/review_props_r3_toll_booth5.jpg`).
   - The dispensers and charge posts also read grey, and the mast reads near-black in game.
   - **Do:** separate dielectric finishes from bare metal. Pick one:
     - (a) a 5th material `Prop_Paint`: same maps as metal, `metallic 0.0`, roughness from G scaled to
       about 0.35–0.55. Merge parts so street props stay at ≤ 3 static surfaces and sites at ≤ 8.
     - (b) a unit-local shader `game/assets/props/materials/prop_family.gdshader` that reads metallic from
       `COLOR_0.a`: write 0 for paint/plastic and 0.8–1.0 for galv `#8E9297`, steel `#5A5F66`,
       alu `#D7DADD` and chrome. Surface counts do not change.

     Add paint chips that show grey primer on the painted finish (r2 item 2).
   - **Verify:**
     - 5 m captures under the toll canopy: the lit booth wall is ≥ #B4B4B4.
     - Gas dispensers read red `#E60012` and white.
     - Charge posts read white `#F2F2F2`.
     - In-game `tl` cam (`-267,1.6,107:-261,3.6,115:66`): the mast reads silver-grey with a specular line,
       not black.

3. **Both canopies are blown out and hide the ground (PR-ART2 and the value structure).**
   - `prop_soffit.tres` is uniformly emissive (E2, no `emission_texture`), so the panel seams and diffusers
     vanish. At 5 m the soffit is #E7E4E1 with σL 2.9, a flat white plane.
   - `prop_lightpool_{gas,charge}.tres` use E2.0 (r2 asked for E0.6–0.8) with blend MIX and the white pool
     image as albedo. That paints an opaque white sheet over the forecourt.
   - Measured on my captures:
     - Under the canopies (`review_props_r3_{gas_col5,gas_disp,charge_post}.jpg`): P50 0.869–0.889,
       P95 0.912–0.929.
     - From 7 m up (`review_props_r3b_{gas,charge}_hop7.jpg`): P95 0.897–0.908.
     - The art dossier §2.4 target is P50 0.10–0.24 and P95 0.40–0.78.
   - The forecourt concrete, any stain and the bay paint are invisible. The forecourt looks like a lit white
     stage floor (`captures/review/props/r3/row2_hop.jpg`, bottom row).
   - **Do** (art dossier §4.10):
     - (a) Soffit: white panels `#E8E8E6`, roughness 0.5, non-emissive (or ≤ E0.3), with recessed LED panels
       as an `emission_texture` mask at E3 `#FFF6ED`. Gas: the 24 square downlights of dossier §8.1. Charge:
       one panel per bay plus a perimeter line. Toll: troffers over every lane.
     - (b) Light pool: `blend_mode = ADD`, `shading_mode = UNSHADED`, black albedo, the pool image as
       emission at E0.6–0.8 in the centre. It must add light to the ground, not cover it.
     - (c) A real forecourt under it: mineral concrete about `#8F8C86`, oil-stain decals at the pumps and
       chargers, tyre-polish paths.
   - **Verify:**
     - Driver views: forecourt mean luminance 110–170/255.
     - 5 m frames: P50 ≤ 0.45, P95 ≤ 0.85, clipped (L > 0.94) ≤ 2 % (only the LED panels).
     - Soffit: σL ≥ 8 with distinct LED panels.
     - Each site still reads as a pool of light at 100 m.

4. **The charging bays are invisible and their numbers render as black tiles (PR-ART2).**
   - The green bays sit at z 0.012 (`blender/props/charge.py:94`), under the light pool at z 0.02 (`:166-167`),
     which paints them white.
   - `BayNumbers` (`:97`, z 0.022, opaque `Prop_SignLit`) draw as dark squares with white digits on the white
     floor (`captures/review/props/r3/details.jpg`, bottom-left).
   - The 12 bays fill only x −9…+9 of a 70 m canopy, so 75 % of it stands over empty white floor.
   - At 100 m the cyan line is thin and the frame has SAT 0.0 % (`review_props_r3_charge_100.jpg`). PR-ART2
     says it "must pop at 100 m".
   - **Do:**
     - Put the pool under everything (z 0.005, additive, item 3).
     - Paint the bays `#1E9E5A` with 0.15 m white edge lines.
     - Make the numbers white glyphs with alpha (MASK) on the green, with no dark tile.
     - Spread the bays along the canopy (for example 2 rows × 6 at 5.5 m pitch, with posts and dispensers
       between them).
     - Turn the 7 m totem's bolt face toward the approach.
     - Raise the cyan line (0.55 m, the `billboard_cyan` cell, `charge.py:56`) from E3 to E4, the hero sign
       of the frame. Give it its own LED material: `Prop_SignLed` is shared with the signal faces and
       the VMS. It is the only saturated element, so with the lit bays and the totem it carries the
       100 m read.
   - **Verify:**
     - Charge driver view at 25 m: green bays with readable white numbers.
     - 100 m view: SAT ≥ 1 % and the bays visible.
     - A capture that shows the bolt from the approach road.

5. **Toll plaza: booths on the driver's right, westbound signals at the exit, mirrored text** (r2 item 5).
   - **Island side.** Godot +Z is the driver's right for +X traffic and the left for −X traffic.
     - Lane 1 (eastbound, +X, centre z 3.6): `Island_1` spans z 5.2…7.4 and `Booth_1` z 5.4…7.2, so they are
       on the driver's right.
     - Lane 11 (westbound, centre z −3.6): its island is at z −6.3, also on the driver's right.
     - Cars in China are left-hand drive, so the booth window must be on the driver's left. Status says
       "always on the driver's left"; that is wrong.
   - **Westbound signals.** `LaneSignal_11..20` sit at x −9.92/−9.95. That is the downstream face for −X
     traffic. r2 asked for x +10.05 facing +X.
   - **Mirrored text.** Every glTF material is exported `doubleSided: true`. Eastbound drivers therefore see
     the backs of those labels mirrored: "工人/CTE", "用专 CTE" (`captures/review/props/r3/details.jpg`,
     bottom-right; `review_props_r3b_toll_hop7.jpg`).
   - **Do:**
     - Islands and booths on the −Z side of eastbound lanes (centre lane_z − 2.7) and on the +Z side of
       westbound lanes (lane_z + 2.7), with each barrier hinge on that island.
     - Keep each arm along its node's local +Z, rotating the `Barrier_<n>` node about Y as needed, so
       `world/build/toll_plaza.gd::_lift()` still raises it. Tell the world unit in Requests.
     - Westbound signal boxes and labels at x +10.05, facing +X.
     - Export closed meshes and sign quads single-sided, and give every sign a back panel. Keep
       double-sided only for cards (foliage, basket, spokes).
   - **Verify:** extend `test_props.gd`:
     - The island AABB centre lies on the driver's left: eastbound z_island < z_lane, westbound
       z_island > z_lane.
     - Westbound `LaneSignal_*` x > +9.5.
     - No `Prop_Sign*` material is double-sided.

     Then take a lane-1 driver capture with no mirrored text in frame.

6. **The close-up props are still grey-box.** The brief says "modelled and textured in detail". References:
   dossier §7.2 and §8.1, art dossier §4.10.
   - **Toll island noses** are flat yellow boxes (`review_props_r3_toll_lane.jpg`).
     **Do:** a segmented crash cushion about 0.9 × 0.8 × 2.5 m in yellow `#F5C400` with black 45° stripes,
     20 cm wide (art dossier §4.10). Add a reflective chevron end face and bolted end plates.
   - **Toll booths** are boxes glazed on one side.
     **Do:**
     - glazing on all four sides in the upper 1.4 m, with mullions;
     - a door;
     - a roof overhang with the red `#D9161C` band;
     - a roof AC unit;
     - a lit ceiling panel `#FFD7A0` at E1.5 that is visible through the glass.
   - **Gas dispensers** are 0.90 × 1.80 × 0.70 m crude boxes (collider `Dispenser_1_1`). Dossier §8.1 says
     2.3 m tall, 1.0 × 0.5 m.
     **Do:** a rounded white `#E8E8E6` cabinet with a red brand panel, a lit topper, 2 nozzle holsters per side
     with looping hoses, and a green LED price window.
     **Gas columns:** silver `#D7DADD` cladding panels with a red base skirt
     (`08_fuel_and_charging/sinopec_hangzhou_2018.jpg`).
   - **planter_pot_bougainvillea / _privet** read as 2–3 upright pink cards on a bare box
     (`review_props_r3_planter.jpg`, `captures/props_close_planter.jpg`).
     **Do:**
     - 6–10 cards tilted 30–70° outward, so foliage covers ≥ 80 % of the box top;
     - cascading bracts that overhang ≥ 40 % of the long faces (dossier §2.4: parapet flower boxes);
     - stay ≤ 300 tris.
   - **Plane-tree bark** (`tools/signs/families.py:286 bark_family`, "sharp camo plates": Voronoi cells with
     3 random colours) reads as military camouflage at 4 m (`captures/review/props/r3/crops_5m.jpg`,
     top-right). This trunk is drawn 19 587× in the city.
     **Do:**
     - domain-warp the cells into irregular exfoliating patches of 5–30 cm;
     - soft 1–2 cm transitions with a thin peeled rim;
     - colours cream `#CFC7A8`, olive `#7D7A5A`, grey `#9A9A8E`;
     - a vertical fibre micro-normal;
     - darker grime 0–0.6 m above the ground.

     Ask the lead in status for the CC0 sets `bark_platanus` and `japanese_sycamore` (art dossier §4.9).
   - **sky_lane_pad** is a 30 m ribbon ramp with no structure (182 static tris; Blender sheet
     `captures/review/props/r3/skylane.jpg`).
     **Do:**
     - a 0.4 m thick deck with side skirts and a steel substructure;
     - LED edge strips;
     - an anti-slip textured deck with painted "飞行航道 SKY LANE" and arrows.

     **Chevrons** (pad and gate) are flat untextured colour at **E9**; art dossier §2.3 allows E4 at most, for
     1–2 hero signs.
     **Do:** an LED-segment emission texture at E3–E4.
   - **Verify:** Godot 5 m captures of each item, side by side with the named reference photo.

7. **Foliage is alpha-blended and single-sided.** Art dossier §4.9 asks for "alpha scissor 0.5, cull disabled".
   - `Prop_Foliage` has alphaMode BLEND and doubleSided false in `plane_tree_1..3` and both planters.
   - The world draws plane_tree_1 19 587× through MultiMeshes. Blended cards are not depth-sorted per card,
     which causes canopy sort errors, overdraw and no depth for fog/SSR. Back-facing cards vanish.
   - The atlas's plane-leaf quadrant averages lime `#A4B537`. The dossier's October mix is 70 % `#6A7A2E` +
     30 % `#9C8A3A`.
   - **Do:**
     - glTF MASK with `alphaCutoff` 0.5, double-sided;
     - an external `prop_foliage.tres` with alpha scissor, `alpha_antialiasing_mode` ALPHA_TO_COVERAGE and
       backlight `#6E7A2A`;
     - retint the leaves toward the dossier mix.
   - **Verify:** a probe prints ALPHA_SCISSOR and cull disabled, plus an in-game capture of the junction trees.

8. **Status and evidence must be factual** (asked in r2 as well).
   - `status/props.md` contradicts itself:
     - Evidence gives forecourts of 137.5 / 124.2 / 87.2.
     - Known issues gives "194 and 192" and "toll 90/255".
     - The metal "roughness σ 0.095" is the G channel, which Godot does not read (item 1).
   - `jobs/props/result.md` says "Round 2" and cites `captures/pros_*.jpg`, which does not exist.
   - `captures/blender/r8_prop_sheet.jpg` is squeezed about 3× horizontally, so the trees and lamps are
     distorted. Keep the aspect ratio in every sheet.
   - **Do:** re-measure everything in Godot after items 1–7 and replace the numbers.

## SHOULD-FIX
- **Toll fascia.**
  - The green name panel rises above the roof line (`review_props_r3b_toll_hop7.jpg`). Fit it inside the
    2.4 m fascia or mount it as a sign box on visible brackets.
  - Add the green "ETC" LED text strip (dossier §7.1) and a lit accent along the bull-nose's lower edge. The
    `#A7ACB1` fascia is invisible against the night sky.
- **Toll plaza pavement.** The 4 m joints render as about 10 cm black stripes. Make them 15–20 mm dark-grey
  sealant lines, and add tyre-polish paths, oil drips, patched slabs, and lane arrows and "ETC" paint before
  the islands.
- **Wet-after-rain roughness.** Mineral σR is 0.030 and panel 0.021. Add a puddle/wet mask (roughness
  0.15–0.35) on horizontal mineral surfaces (ART §1, §5b).
- **Bus stop.** The back panel reads as opaque stained concrete (`captures/review/props/r3/crops_5m.jpg`,
  bottom-right). Make it glass with dirt and a glass roof, per `09_street_details/bus_shelter_2026.jpg`.
- **Sky lane gate and gantry.** The ring shows polygon facets: use ≥ 64 segments. The gantry is 2 posts + 2
  rails: use a 0.9 m box truss like the guide gantries.
- **Gas store.** It is still a dark box at 20 m. Give it a lit glazed front with an interior (shelves,
  ceiling panels) behind the EZ-JOY band.
- **Spike strip.** The accordion deploy from r2 is still open.
- **Code.**
  - `class_name PropDensity` (`tests/prop_density.gd`) breaks CONTRACTS §3 ("class_name only for contract
    classes"). Use a `preload` const.
  - `test_props.gd` has magic numbers in its logic: 1.6, 2.6, `1.1 - 0.4`, 0.7, 5.49, 1.2, 0.05. Make them
    named constants.
  - `FAMILY_MATERIALS` is duplicated in `test_props.gd` and `prop_density.gd`.
  - `preview_props.gd` hard-codes light energies and ranges (6.0, 60.0, 5.0, 34.0, 62.0). Make them
    constants.
  - `test_props.gd` is at 395 lines; split it before adding the item 5 checks.

## Verified OK
- **Check:** `tools/godot.sh check --only=res://assets/props/` → `CHECK 11 files, 0 failed, 0 engine errors,
  0 warnings`.
- **Test:** `tools/godot.sh test res://assets/props/tests/test_props.gd` → 128 PASS lines,
  `PASS props contract (0 failures)`.
- **Budgets (PR-INT1 met):**
  - street props: 1–3 static surfaces;
  - sites: 5–7 static surfaces;
  - toll plaza: 6 static + 60 dynamic (20 `Barrier_*` + 40 `LaneSignal_*`);
  - tris: street max 2 896 (bike_share), plane trees 1 148, planters 170, sites 326–8 726.
- **Texel density:** 0.0–3.0 % of each glb is below 300 px/m (e_scooter is the worst). r2 item 1 is fixed: no
  stretched or streaked UVs in my 5 m captures, and no wood-grain masts in game (`review_props_r3_game_tl.jpg`).
- **Family textures:** 1024² (roughness 512²). My measured σL: metal 8.8, mineral 10.2, panel 12.8, bark 31.4,
  matching status.
- **IMPORT-CHURN met:** `_tex/` holds 22 files (5.4 MB), the unit is 11 MB, 4 boards are left in `textures/`,
  and there is no scratch in `game/` or `/tmp`.
- **Contract nodes and data:**
  - `Lens_R/A/G` (Ø 0.30 m, shipped dark);
  - `Barrier_1..20`: hinge origin, a 3.0 m arm covering ≥ 2.6 m of its own lane, 0.5 m red/white bands
    visible, posts downstream (x ±2.4);
  - `LaneSignal_*_Red/_Green`;
  - `Support_1..6` under the gas `Canopy`; `Support_1/2` on the billboard;
  - `Spikes` + `Deploy`, `Chevron_*`;
  - `ChargeArea` extras;
  - `Light_*` markers: gas 18, charge 14, toll 10.
- **Second ETC gantry:** x +40.
- **Dimensions:**
  - pylon 2.2 × 9.0 m;
  - store 25 × 12 × 4.5 m;
  - charge dispensers 2.2 m, posts 0.34 × 0.60 × 1.90 m, totem 7.0 m;
  - plane trees 10.6–11.9 m canopy, top 14.8 m;
  - 3 tree variants differ.
- **Sign text is correct:**
  - the gantry atlas cell reads 飞行航道 SKY LANE ▲ 300 m (`captures/review/props/r3/details.jpg`);
  - 申城西收费站 SHENCHENG WEST TOLL;
  - 中国石华 SINOPEX repeated with logo end caps;
  - VOLTA and 500 kW, readable at 5 m;
  - VMS 前方拥堵 注意减速 SLOW;
  - the bus route board 七莘路 → 天山路 and the 08 arrival screen.
- **PR-ART1 met:** the magnolia's 9 cup shades read separately with no clipping (P99 0.772, clipped 0 %).
- **Close-up wins:** bike_share reads as two step-through share bikes (torus tyres, baskets). The VMS board,
  the heritage lamp and the traffic-light head with its yellow back plate read well.
- **Code and ownership:**
  - The worker log since 11:10 shows 53 Write/Edit calls on 29 files, all in owned paths, `tmp/props/` or
    status.
  - No source file is over 400 lines, and no Python or GDScript function is over 60 lines.
  - GDScript is statically typed, and the tests `extends Node`.
- **Blender preview:** the only UNTEXTURED flags are the `-convcolonly` proxies (counts equal the colliders:
  charge 22, gas 18, toll 61), `SH_hologram` (replaced at runtime) and the flat `Prop_Chevron_*` (item 6).

## Evidence
- **Tests:** `tools/godot.sh check …` and `test …` as above (log `tmp/review/props_r3_test.log`).
- **Material probe:** `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/props_r3_probe.gd` prints:
  - `prop_metal rough_ch=0 metallic=0.80`;
  - `prop_soffit … emis=2.00` with no emission texture;
  - `prop_lightpool_gas blend=0 shading=1 emis=2.00`;
  - the toll static mesh uses `prop_metal.tres` etc. with `rough_ch=0`.
- **Roughness PNG channels:** metal R 1.000 σ 0 / G 0.391 σ 0.095. Mineral G σ 0.052, panel 0.035,
  bark 0.014.
- **Geometry and stats scripts:**
  - `python3 tmp/review/glbnodes.py <glb> <prefix>`: islands, booths, signals, dispensers and colliders
    (numbers in items 4–6);
  - `tmp/review/props_r2_stat.py -v`: surfaces, tris, materials, E9 chevrons;
  - `tmp/review/props_r3_signquads.py`: sign quads and UVs.
- **Value stats:** `python3 tmp/review/props_r3_lum.py captures/review_props_r3*.jpg`. The machine load
  average was 47–56 during my runs, so my fps (39–55 preview, 23–59 in game) are not perf evidence.
- **My preview captures** (`--quality=ultra --env-only`, 0 errors):
  - `captures/review_props_r3_{toll_lane,toll_booth5,toll_100,gas_20,gas_col5,gas_disp,gas_100,
    charge_20,charge_post,charge_100,mast_close,tree_trunk,magnolia,street,bus_stop,planter}.jpg`;
  - `captures/review_props_r3b_{row2a,row2b,guide_close,toll_hop7,gas_hop7,charge_hop7}.jpg`.
- **In game:** `--scene=res://main.tscn --skip-menu --env-only`:
  - `captures/review_props_r3_game_{tl,charge_a,charge_b,gas_a,toll_drv,toll_hop}.jpg`;
  - the script errors come from `ui/menu/widgets/title_stage.gd` and fx, not props.
- **Sheets:** `captures/review/props/r3/{toll_lane,gas_20,charge_20,close_sites,close_street,far,game,
  cmp_ref,street,row2_hop,crops_5m,skylane,details,worker_r8_sheet}.jpg`.
- **Reference comparison:** `cmp_ref.jpg` compares `toll_g4_xinyang_2023`, `sinopec_hangzhou_2018`,
  `byd_flash_1000kw_2025` and `yongkang_road_planetrees` against my captures.
- **Blender previews:** `tools/blender.sh preview game/assets/props/sites/<site>.glb review_props_r3_<site>
  --views front34 --light night` for the 3 sites + 3 sky-lane pieces (`captures/blender/review_props_r3_*`).
