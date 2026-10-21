# props review round 1 — VERDICT: FAIL

## Scores (0-10): function 4, visual 2.5, code 6

The contracts (node names, extras, files) are in place and the tests pass, but the unit is grey-box
quality: generic blurred-noise textures that tile visibly, crude models, blown-out or hidden emissives,
two broken toll-plaza layouts, and none of the three lead notes is done. The user asked for refined
textures everywhere ("贴图纹理什么都要细化"). Fix every item below, re-run all evidence, and update
status/props.md with a per-prop table (surfaces, tris, materials, texture px/m).

## MUST-FIX

1. **PR-INT1 (lead, mandatory): one mesh node per material family.** Every static part is still its own
   node. Render surfaces today (`tmp/review/glbstat.py`): toll_plaza **411**, charge_station **129**,
   gas_station **100**, guide_gantry_34/27/19 **77/65/47**, scaffold 34, bike_share 32, lamp_heritage 24,
   metro_entrance 24, plane_tree_1..3 24, lamp_magnolia 21, bus_stop 20, traffic_light_mast 20,
   spike_strip 20, roadblock_barrier 15, ac_unit 14, crowd_barrier 14, ... cone 4. All exceed the budget
   (≤ 3 street props, ≤ 8 gantries/sites). Street props also carry up to 7 materials (bike_share, bus_stop,
   traffic_light_mast).
   Do: (a) in `blender/props/kit.py` add `Prop.finalize(keep=("Lens_", "Barrier_", "LaneSignal_",
   "Support_", "Spikes", "Chevron_", "Canopy"))`, called from `build.py` before export: join every other
   mesh part into ONE object named after the prop (e.g. `LampDeckDouble`), leave `-convcolonly` proxies and
   Empties untouched. (b) Cut materials: one shared `Prop_Metal` (neutral greyscale detail set) tinted per
   part by vertex colour (galv `#8E9297`, dark steel `#3A3D42`, white `#EDEDE8`, red `#E60012`, cast iron
   `#1C1C1E`) or a 2048² trim sheet; emissives of one prop share one material/atlas. (c) Traffic light:
   merge `Lens_R`+`Lens_R2` into one `Lens_R` node (same for A, G) — the contract is one node per colour.
   (d) Gas station: roof + soffit + fascia + signs + downlights become ONE `Canopy` node (the world unit
   drops it as one body when `Support_1..6` break). Sites: ≤ 8 static surfaces plus the dynamic nodes
   (toll: + 20 `Barrier_*` + 20 `LaneSignal_*`).
   Verify: add `_check_surface_budget()` to `game/assets/props/tests/test_props.gd`: per glb, sum
   `mesh.get_surface_count()` over MeshInstance3D not starting with a dynamic prefix; FAIL if > 3 (street)
   or > 8 (gantries, sites). Put the table in status.

2. **Toll barrier arms are built in the wrong place and plane** (`blender/props/toll.py:67-85`
   `_barrier_arm`). Barrier_1 post AABB (Godot) x −0.22…0.22, z 52.08…52.52 = the middle of lane 1 (lane
   centre z 52.3): the post and motor box stand in the driving line (see
   `captures/review_props_r1_toll_5m.jpg`, left of centre). The arm spans x −0.99…0.07, y 0.93…3.82 with
   0.12 m in z, i.e. it rotates about Blender Y in the traffic plane: lowered, it would lie along the lane.
   Do: post + motor on the island edge (`lane_y ± (LANE_W/2 + 0.35)`, booth side); arm 3.0 m along
   Blender **Y** (across the lane), hinge at the post top, raised pose = rotation about Blender **X**
   (traffic axis); keep the `Barrier_<n>` origin on the hinge.
   Verify (add to the test): with the node rotation reset, the arm AABB spans ≥ 2.8 m in Godot Z and
   ≤ 0.2 m in X; the post AABB lies inside its island AABB.

3. **ETC gantry runs along the median instead of across the road** (`toll.py:198-211`). EtcTruss AABB
   x −53.9…−2.1, z −0.15…0.15; both posts on z = 0; cameras/antennas every 8.5 m along the traffic
   direction (it is the long cable in `captures/props_toll_driver.jpg`). Do: one 0.9 × 0.9 m box truss
   spanning the whole carriageway (Blender Y −57…57) at x = −40 (30 m before the canopy front x = −10),
   posts outside the plaza at |y| = 57, one camera + antenna per lane above each lane centre (20),
   facing upstream (−X). Unique node names (today `EtcPost` + `EtcPost.001`).
   Verify: Godot AABB of the truss spans ≥ 112 m in Z and ≤ 1.2 m in X.

4. **Texture detail fails ART.md §5 and dossier §15** (`captures/review/props/tex_surfaces.jpg`). All 14
   surface sets from `tools/signs/prop_surfaces.py` are 512² fbm "clouds" with no physical features: metals
   are the same blurred noise in another colour (the "hairline scratches" in `paint_metal` do not exist),
   concrete and pavement are smooth blobs, the bark is blurred clouds, normals are near-flat
   (`prop_bark_nor_gl.jpg` 16 KB). Repeated every 1 m they form an obvious quilt grid on the gas and charge
   canopy roofs/soffits, the store walls and the plaza (`captures/review/props/blender_close.jpg`,
   `captures/review_props_r1_toll_pave.jpg`). No edge wear, dirt, seams, rain streaks or macro variation.
   Do:
   a) Concrete/asphalt: use the shared 2k CC0 sets already in `game/assets/textures/`: plaza
      `concrete_pavement` (1.8 m) + your 4 m joint grid, islands/kerbs/bases `rough_concrete` or
      `Concrete046`, aprons/ramp `Asphalt031` or `asphalt_02`, tinted to the dossier hex
      (`#BDB9B1` plaza, `#2B2C30` asphalt).
   b) Metals/bark: write in status `## Requests` that the lead fetch (tools/textures/fetch.py) Poly Haven
      `bark_platanus`, `blue_metal_plate`, `metal_plate_02` and ambientCG `PaintedMetal001`, `Metal009`
      (do not download yourself). Until then rewrite the generators at 1024² per 2 m (512 px/m) with real
      features: galvanised spangle (Voronoi cells 5–20 mm, ±6 % value), hairline scratches, chipped paint
      edges, drip streaks; ACP canopy panels 1.2 × 0.6 m with 6 mm dark seams and rivet heads; London-plane
      bark as sharp-edged camo plates 0.1–0.4 m in `#CFC7A8` / `#7D7A5A` / `#9A9A8E` with a fissured normal.
   c) Hide tiling on every surface > 10 m: bake 2–8 m macro variation (±10 % value) and a grime/rain-streak
      mask into unique-UV 2048² textures for canopy roof, soffit, fascia band and store façade; or request a
      `SH_prop_detail` shader (world-space macro noise + detail normal) from the shaders unit.
   d) Wear where physical (ART §5d, dossier §15 canopies): scuff/dirt band 0–1 m on columns, posts, booths,
      dispensers; rain streaks under canopy edges (alpha decal quads from `Leaking004`/`Leaking016A`).
   Verify: new surface contact sheet + Godot captures at 5 m / 20 m / 100 m of canopy, plaza, column,
   booth and tree trunk: no repeat visible at 20 m, structured normals, wear visible at 5 m.

5. **PR-ART1 (lead, mandatory): lamp heads bloom into discs.** Magnolia = 9 plain 0.8 m spheres in a ring
   (`Globe_1..9`, `Prop_LED_Warm`), white blobs in `captures/props_street.jpg`; other heads: `LED_Heritage`
   E9.0 (heritage, shikumen), `LED_White` E6.0 (deck/street lamps), `Troffer` E4.5 (toll bars blown white in
   `captures/review_props_r1_toll_5m.jpg`). Do: magnolia heads as 9 petal/bud-shaped opal shades
   (≈ 0.35 × 0.8 m, opening upward on curved arms, 1 top + 8 around) in opal `#F4F1EA`, 3000 K
   (`#FFD9A8`, not the 4000 K deck colour), emission E2–3 with an opal gradient texture (bright core,
   dimmer rim, petal seams). All lamp heads and troffers E2–3 with a diffuser/gradient texture.
   Verify: Godot captures at 10 m and 40 m: petals readable, no white discs, no blown troffer bars.

6. **PR-ART2 (lead, mandatory): the charging hub and gas station are dark at 100 m**
   (`captures/review/props/sites_100m.jpg`: the hub is a black line with a few dots). Root cause for the
   cyan line: `LedLine_±12` sits at z ±11.69, INSIDE the 0.3 m fascia box (`Fascia_-12` spans z
   11.7…12.0), so it is occluded from outside, and it is only 0.12 m tall. The soffits use
   `Prop_white_paint` and render dark grey. Do: LED line on the OUTER fascia face (+0.01 m), 0.30 m tall,
   full 70 m both sides, `#00E5FF` E3; soffit = white emissive panels E2 at 5500 K (`#FFF4E8`) with a panel
   seam/diffuser texture; bays `#1E9E5A` with white numbers readable from the driver's view; red "VOLTA"
   lit; kW readouts glowing; 7 m totem with a lit lightning bolt. Gas: soffit `#F4F4F4` lit (E2 panels) with
   the 24 downlights, fascia red `#E60012` readable. Verify: captures from 100 m and from the driver's view.

7. **Wrong or broken sign content** (brief: "Text on every sign is correct").
   a) `roadname_xianggang/nanjing/shenchang.png`: the English line is clipped by the bottom edge — the "g"
      descenders still have dark pixels in the last row (y 511, x 635–747 and 880–932). Fit the line with
      ≥ 6 % bottom margin.
   b) Fuel dispensers `Dispenser_*_Price` and `hologram_projector` `Screen` use `charge_kw_500` ("500 kW").
      A fuel pump needs its own green LED readout (e.g. "92#  ¥7.28/升" + amount/litres digits); give the
      projector its own content.
   c) `gas_fascia.png`: characters ≈ 40 % of the band height, "SINOPEX" pushed to the far right, bright
      white grid seams. Reference `ref/shanghai/img/08_fuel_and_charging/sinopec_hangzhou_2018.jpg`: name and
      Latin word adjacent, ≈ 60 % of band height, seams are thin dark lines. Same for `toll_fascia.png`
      (name ≈ 1/6 of the panel width, reads tiny in `captures/review_props_r1_toll_20m.jpg`).
   Verify: sign contact sheet + captures at 20 m.

8. **Plane trees are placeholders** (`blender/props/greens.py:18-58`): 308 tris of a 6 000 budget, 12
   square cards in three rings, 5 straight branch tubes, half the branches bare
   (`captures/blender/prop_plane_tree_1_studio.jpg`), a low-poly yellow blob in
   `captures/review_props_r1_street_tree.jpg`; the leaf atlas is flat clip-art polygons (13 KB).
   Reference `09_street_details/yongkang_road_planetrees.jpg`. Do: 3-order tapered branch skeleton
   (trunk Ø 0.6 m → 4–5 limbs → 15–25 branches); 150–250 leaf-cluster cards (1.2–2.5 m) filling an
   ellipsoid 10 m wide between 7 and 14 m, card normals bent outward from the canopy centre; 2048² leaf
   atlas with 5-lobed plane leaves (veins, value variation), October `#B7A84A` mixed with green; bark per
   item 4b. ≤ 6k tris, ≤ 2 surfaces. Same quality bar for the planter plants (dossier §2.4/§15:
   bougainvillea bracts are pink triangles today). Verify: studio sheet + Godot captures at 10 m and 30 m.

9. **Crude kit pieces the camera passes at 2–20 m.**
   - `bike_share`: frames are box bars, wheels are octagonal half-arches sunk into the dock
     (`captures/blender/prop_bike_share_studio_close_front34.jpg`). Round tubular frames, torus tyre + rim +
     spoke alpha card, saddle, bars, basket, dock screen.
   - `spike_strip`: a 0.72 × 0.26 m box with 14 cones 14 cm tall; it cannot cover a lane. And the brief's
     "animated deploy pose" is missing: the glb has **no animation**. Model a 3.6–4.5 m accordion lattice
     with 60+ short hollow spikes (4–5 cm), and export a glTF animation `Deploy` (case → extended, ~0.6 s).
   - `sky_lane_pad` / `sky_lane_gate` `Chevron_*` are plain rectangles (3.2 × 1.6 m, 1.6 × 0.55 m), not
     chevrons: use chevron (">") geometry or an alpha-masked chevron texture pointing along travel.
   Verify: per-prop close sheets; `animations` present in `spike_strip.glb`.

10. **Guide gantry clearance.** Truss is 5.5–6.46 m and `guide_sign` (4.2 × 2.4 m) has its pivot at the
    panel centre, so mounted on the truss its bottom is ≈ 4.8 m — dossier §2.6 requires sign bottom
    ≥ 5.5 m (and the Big Hop flies at 7.8 m). Raise the truss (centre ≈ 6.7 m), add Empties
    `SignMount_<n>` per lane (facing traffic), and export one gantry with signs mounted for the preview.

11. **Evidence is not reviewable.** The "night" lineup equals the studio one (mean abs diff 3.7/255);
    Godot captures are taken from 50–150 m; preview_props.gd `_build_ground()` is an untextured plane
    (albedo ≈ `#080809`, ART §5 "no flat untextured surface"); per-prop sheets crop the lamp heads.
    Do: real night lineup; for each site a driver's view at 15–25 m and a 7 m hop apex ≤ 30 m away;
    textured ground (`Asphalt031` or `SH_wet_asphalt`); sheets framed on the whole prop.

## SHOULD-FIX
- `LaneSignal_<n>` is fixed red (7) or green (13): the world unit cannot switch. Ship both states
  (`LaneSignal_<n>_Red` / `_Green` children, or a 2-tile atlas).
- Traffic-light lenses use the white-paint albedo, so they look white when switched off. Dark tinted
  lenses (`#3A0A0A`, `#3A2A05`, `#06301A`, roughness 0.1) with an LED-dot normal.
- Texel density of the big signs: toll name panel 3072×205 on 24 × 1.6 m = 128 px/m, gas name panel
  171 px/m (ART §5: props ≥ 512 px/m). Split the name panel (~8 m @ 2048×410) from a tiled ACP band.
- Booths read as solid grey boxes; dossier §7.2 wants 50 % glass, white `#EDEDED`, red stripe `#D9161C`.
  Upper 60 % glass with mullions and a simple lit interior.
- Gas and charge stations ship no `-convcolonly` proxies (columns, dispensers, islands, posts, pylon,
  store); cars will drive through them.
- Delete the 15 orphan extracted images (51.9 MB) left from older builds, e.g.
  `game/assets/props/sites/toll_plaza_asphalt_02_nor_gl.jpg`, `street/bin_bus_route.png` (+ `.import`).
- Every glb embeds its own copy of the shared sets (the galv set is imported ~30×). Consider shared
  external materials via the `.glb.import` `_subresources` (`use_external` → `res://assets/props/materials/`).
- `lamp_deck_double` has one `Light` marker on the pole for two heads 5 m apart: `Light_1`, `Light_2`.
- `sky_lane_pad` chevrons share one material; give per-row materials `Chevron_1..N` (or a UV-scroll
  material) so the world unit can animate them.
- Code: `toll.py` `toll_plaza()` is 115 lines (rule ≤ 60): split into canopy / lanes / ETC / masts helpers.
  Name dimension literals as dossier constants (ETC `-53.9`, `-2.1`, `6.60`, `51.8 / 17.0`). Blender
  auto-suffixed node names in the glbs (`EtcPost.001`, `Foot.001`, `Brace2.001`, `Mount0.001`) → unique
  PascalCase names.
- Process: the run wrote `game/tools/probe/probe.gd` (core-owned `game/tools/**`) and `/tmp/testlamps.py`;
  both are gone now, but scratch goes to `tmp/props/` only.

## Verified OK
- `tools/godot.sh check --only=res://assets/props/` → 3 files, 0 failed, 0 engine errors, 0 warnings.
- `tools/godot.sh test res://assets/props/tests/test_props.gd` → 33 PASS lines, "PASS props contract
  (0 failures)"; the test `extends Node`, typed GDScript; all source files ≤ 400 lines (max 357).
- 36 street + 6 site glbs; names `Lens_R/A/G`, `Barrier_1..20`, `LaneSignal_1..20`, `Support_1..6`,
  `Support_1/2` (billboard), `Spikes`, `ChargeArea` extras (centre, size 40 × 18 × 2.4, id), `SH_hologram`.
- Tri budgets: street ≤ 1 924 (guide_gantry_34), planters 144, sites 206–22 332.
- Dimensions: toll canopy 112 × 20 m, islands 2.2 × 30 × 0.25 m, booths 1.8 × 3.0 × 2.8 m, 4 × 30 m
  masts, 57 colliders; gas canopy 60 × 30 m, underside 6.0, fascia 1.4 m, store 25 × 12 × 4.5 m, pylon
  9 × 2.2 m; hub canopy 70 × 24 m, underside 5.0 m, 12 bays 3.0 × 5.5 m, totem 7 m; ring Ø 14.3 m; pad
  30 m long, 3 m rise. All `Light*` markers point down. Free-standing street props sit on the ground (min Y 0).
- Sign strings are correct Chinese + English: 申城西收费站 SHENCHENG WEST TOLL, 中国石华 SINOPEX,
  易快 EZ-JOY, 延安高架路 / 南北高架路, 西藏中路 出口 500 m, 飞行航道 SKY LANE ▲ 300 m, ETC 专用,
  公安 POLICE, VOLTA, 今日油价 board.
- No scratch files left in `tmp/props/`.

## Evidence
- `python3 tmp/review/glbstat.py game/assets/props/*/*.glb` → surfaces/materials/tris table (item 1).
- `python3 tmp/review/glbnodes.py <glb> Barrier_1 EtcTruss LedLine ...` → AABBs quoted in items 2, 3, 6.
- Godot captures (mine, `--quality=ultra --env-only`, 0 errors): `captures/review_props_r1_{toll_5m,
  toll_20m,toll_100m,toll_pave,gas_5m,gas_20m,gas_100m,charge_5m,charge_100m,street_bus,street_tree}.jpg`;
  sheets `captures/review/props/{mine_toll,mine_sites,sites_100m}.jpg`.
- Reference vs capture: `captures/review/props/cmp_toll_gas.jpg` (toll_g4_xinyang_2023 / sinopec_hangzhou_2018).
- Textures: `captures/review/props/{tex_surfaces,signs}.jpg`; Blender close renders
  `captures/blender/review_props_r1_{gas,tl}_night*.jpg`, sheet `captures/review/props/blender_close.jpg`.
- Worker evidence reviewed: `captures/review/props/{worker_godot,lineup,sheets_street1,sheets_misc}.jpg`.
- Preview fps in the near-empty preview scene: 73–83 at the street strip (1600×900 ultra) — re-check
  after the merge.
