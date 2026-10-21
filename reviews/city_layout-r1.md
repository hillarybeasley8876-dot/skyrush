# city_layout review round 1 — VERDICT: FAIL

Reviewer: Opus (art director / strict review). Round 1 of `data/city/city.json` + `tools/city/**`.
The validator itself exits 1 (4/12 FAIL), and my independent checks show that 4 of the 8 "PASS" rules
are hollow. Several headline claims in `status/city_layout.md`, `jobs/city_layout/result.md` and the
JSON `notes` are false (measured numbers below). The lead notes (C-INT1, 1, 2, 3) are all unmet.

## Scores (0-10)
- **function: 2** — 86 road conflicts (18 deck clashes down to 1.4 m vertical gap), 9 grade + 17
  curvature failures, 72 dead ends, ~40 % of the land empty, D2 has no lots, interchange / routes /
  pads / spawns wrong.
- **visual/feel: 2** — one global axis-aligned lattice for Puxi *and* Pudong (SimCity look), the dragon
  interchange is not a stack, the spiral loops nearly coincide, `profiles.png` is unreadable, `map.png`
  has no sky-lane / pad / route labels.
- **code: 4** — clean module split, deterministic, stdlib, all files ≤ 366 lines; but lenient/hollow
  rules that print only 6 items, dead code, magic numbers, misleading docstrings, false claims.

## MUST-FIX
Reviewer cross-check scripts (read-only for you, run them to confirm your fixes):
`python3 tmp/review/city_layout/scripts/{grades,overlap,blocks,routes}.py data/city/city.json`.
Your own validator must reach the same verdicts — they are the acceptance test for items 1–7.

### A. Make the validator tell the truth (do this first)
1. **Truncated output hides failures.** Every rule prints `sorted(...)[:6]`; `check_curvature` also
   `break`s after the first hit per road. Grades shows 6 failures but **9** roads fail (hidden:
   `ramp_xizang_on` 7.52 %, `ramp_rt_wb_nb` 6.09 %, `yanan_east_ramp` 5.28 %); curvature shows 6 but
   **17** fail. Do: print `N failing` plus every id with its worst value and location (full list).
   Also delete the false docstring in `check_grades` ("first and last 15 m are skipped") and the unused
   `_trim`. Verify: output lists 9 + 17 on today's file.
2. **Clearance rule is hollow** (`check_clearance`). Today it (a) compares *surface* heights with 5.5 m,
   ignoring the deck structure; (b) tests sample points inside a fixed 22 m radius, not footprints;
   (c) skips every point with y < 3 m; (d) exempts everything within 250 m of *any* merge point and the
   last 250 m of every ramp; (e) never checks tunnels or surface×surface overlaps. Do:
   - conflict when plan distance < half-width A + half-width B (`citylib.road_width`);
   - required surface-to-surface gap = 5.5 m + depth of the upper structure: standard elevated box
     girder 2.0 m (§2.2), interchange L2 1.8 m / L3–L5 1.6 m (§1.3), Nanpu edge girder 2.5 m (§3.2);
   - a tunnel lane must be ≥ 6.0 m (4.5 m headroom + 1.5 m roof) below any road crossing above it;
   - surface×surface overlap allowed only inside a declared junction whose `roads` lists both;
   - exempt only the attach pair (child, parent) inside its gore (≤ 150 m of child length from the
     attach point) — no radius blankets.
   Verify: on today's file it FAILs with ≥ 18 vertical clashes, e.g. `ramp_l3_wb_sb`×`ramp_rt_sb_wb`
   1.4 m @(−1196,1025); `ramp_chongqing_off`×`ramp_chongqing_on` 1.6 m @(−1227,728);
   `ramp_xizang_on`×`st_ew_08_67` 1.6 m @(−697,67); `ramp_l3_eb_nb`×`ramp_rt_eb_sb` 3.1 m @(−1587,725);
   `yanan_elevated`×`yanan_rd_surface` 1.0 m @(−1964,728); `lujiazui_ring_rd`×`yanan_tunnel` 1.0 m
   @(716,−454); `st_henan_rd_2`×`yanan_tunnel` 1.1 m @(−408,194); plus 68 at-grade overlaps without a
   junction (see item 15).
3. **Block rule tests only polygon vertices** and skips lots under decks (`if oy > top + 1.0: continue`).
   Do: test edges and interior (road sample inside the polygon, or segment distance < half-width + 1 m).
   Add the **lead note 2 rule**: every lot ≥ 2 m from every elevated/ramp/bridge deck footprint (deck
   width incl. wings); the only exemptions are `plaza` lots whose `notes` are `landmark:dragon_pillar`,
   `landmark:nanpu_tower_w|e` — print them as exemptions. Verify it catches today: `park_peoples_square`
   crossed by `st_ns_07_14`, `st_jiujiang_rd_2`, `st_fuzhou_rd_2`; `park_shikumen_park` crossed by
   `st_xizang_rd_3`, `st_ew_11_76` and lying under `ramp_xizang_off`/`ramp_xizang_on_wb`;
   `plaza_peace_hotel_n` / `plaza_oriental_pearl` / `plaza_shanghai_tower` only 0.1–0.5 m from a road.
4. **Attach rule accepts 20 m plan error.** The brief says attach points *lie on* the parent: plan
   ≤ 0.10 m, height ±0.05 m, tangent ±8°. Today: `century_ave` start 26.6 m off, `bund_zhongshan_e1`
   tangent 73.5°, `ramp_chongqing_off` 55.5° and −0.77 m, `ramp_chongqing_on` −0.92 m,
   `nanpu_spiral_lower` 0.09 m.
5. **Lane graph is wrong** (`_graph`): attach edges are added both ways (one-way ramps become two-way),
   and roads are joined only at their *end points* (X and T crossings in mid-road are not nodes). Build a
   directed graph split at every junction, attach and crossing; ramps one-way; `laps` routes must
   close (last checkpoint → first).
6. **Pad / sky-lane rules check nothing real.** `check_pads` claims a run-up check that does not exist;
   `check_sky_lanes` tests only the 5–7 control points and sees landmarks as 0 m tall. Add: pad heading
   within 10° of the lane direction of its road; pad on a lane centre (±0.5 m); ≥ 300 m straight run-up
   on the same road before the pad (heading change ≤ 3°); first lane segment within 10° of the pad
   heading; lane end over a drivable lane (≤ 7 m lateral, ≤ 15 m above it, heading ±15°); |pitch| ≤ 20°
   per 50 m; clearance sampled every 5 m against block `height_m` max (with real landmark heights,
   item 18).
7. **New rules** (C-INT1 is a lead MUST): every spawn (player, police, route grids, rival grids) and
   every checkpoint within 0.5 m of a lane centre-line at lane height, heading within 10° of the lane
   direction; checkpoints 300–500 m apart along the driven path; dead ends: every road end connects
   (junction / attach / connection) or lies within 40 m of the window edge and is listed in a
   `dead_ends` note; key levels: Yan'an Y 9.0 ± 0.05 within 150 m of the pillar, N–S Y 31.0 ± 0.05 at
   the pillar; spiral loops ≤ 4.0 %.

### B. Road geometry
8. **Grades and kinks are real, not a spline artefact.** Peak grade (Catmull-Rom 2 m / straight
   segments between your own control points): `ramp_xizang_on` 7.52/6.64 %, `nanpu_pudong_loop`
   6.26/6.11, `ramp_l4_nb_wb` 6.12/6.03, `ramp_rt_wb_nb` 6.09/5.48, `ramp_rt_eb_sb` 5.50/4.78,
   `yanan_east_ramp` 5.28/5.28, `ramp_chongqing_off` 5.04/4.66, `ramp_l4_sb_eb` 5.02/4.58,
   `nanpu_spiral_upper` 5.02/4.91 (limit 4 %). `ramp_l4_nb_wb` has perfectly uniform 12 m spacing and
   still 6.1 % — the profiles themselves are illegal. Kinks (grade change per 10 m, limit 0.5 %):
   `ramp_xizang_on` 8.62, `ramp_rt_wb_nb` 5.60, `ramp_rt_nb_eb` 4.18, `ramp_chongqing_on` 4.00,
   `ramp_l4_sb_eb` 3.85, `nanpu_pudong_loop` 3.83, `ramp_rt_eb_sb` 3.81, `ramp_chongqing_off` 3.04,
   `ramp_l4_nb_wb` 2.47, `ramp_l3_eb_nb` 2.20, `ramp_l3_wb_sb` 2.01, `ramp_rt_sb_wb` 1.60,
   `yanan_east_ramp` 1.50, `nanpu_bridge` 0.82, `nanpu_spiral_upper` 0.71, `nanpu_spiral_lower` 0.65,
   `ns_elevated` 0.55. Do: one profile builder for every road = constant-grade tangents joined by
   parabolic vertical curves of length L ≥ max(40 m, 2000 m × |Δg|) (Δg 0.046 → 92 m); design grades
   ≤ 4.6 % (spiral ≤ 3.8 %) for margin; lengthen ramps that cannot fit (10 m at 4.6 % with two 92 m
   curves needs ≥ 310 m — `ramp_xizang_on` is 217 m). Emit every curved road as uniform 2.0 m
   arc-length control points (today `ns_elevated` spacing is 2.8–52.4 m, `nanpu_spiral_lower` 1.8–36.8,
   `nanpu_spiral_upper` 2.0–30.6, `nanpu_pudong_loop` 2.0–24.5). Withdraw the core request to change
   `blender/lib/geo.py` — the fix is in your data. Verify: `grades.py` prints 0 and 0.
9. **N–S Elevated misses L5.** Max Y is 28.56 m (28.5 at the pillar, 3.17 m from the axis) although
   `PROFILES["ns_elevated"]` asks for 31.0 at the pillar point — your profile fitter does not hit its
   key heights. Do: key heights exact (±0.05 m): 12.0 at (−1402.0, 202.3), **31.0 flat for ±40 m around
   the pillar point (−1301.1, 688.8)**, 12.0 at (−1228.0, 1256.5), 10.0 at (−1122.5, 1510). Yan'an:
   **9.0 flat within 150 m of the pillar** (today it wanders 9.1–9.6 there).
10. **Dragon interchange: rebuild per dossier §1.3.** Measured: the four left-turn ramps pass
    **116–141 m** from the pillar axis (`ramp_l3_eb_nb` 141.2, `ramp_l3_wb_sb` 130.5, `ramp_l4_nb_wb`
    116.4, `ramp_l4_sb_eb` 121.9) — the JSON notes and status say "within 3 m": false.
    Measured along the N–S (pillar at s 1940): `ramp_l4_nb_wb` leaves NB 118 m *after* the pillar,
    `ramp_l4_sb_eb` leaves SB 224 m after it, `ramp_rt_sb_wb` diverges 401 m south and `ramp_rt_nb_eb`
    401 m north of it — they turn back through the junction, hence the 1.4–6.3 m deck gaps. The two
    L4 ramps merge into Yan'an 600 m from the pillar (`ramp_l4_nb_wb` at Y 4.1 on the at-grade climb).
    See `captures/review/city_layout/diag_dragon.jpg`.
    Rebuild (pillar P = (−1299, 687); right-hand traffic: EB lanes south of Yan'an, NB lanes east of N–S):
    - **4 left turns** (1 lane, 8.0 m deck): diverge from the right edge of the main line 300 m before
      P, 90° arc R = 70 m whose mid-point is over P, merge from the right into the target line 300–450 m
      after P (pick the distance that keeps ≤ 4.6 % incl. vertical curves). EB→NB and WB→SB cross P
      heading NE/SW on **L3 Y 16.5**; NB→WB and SB→EB cross P heading NW/SE on **L4**. The two ramps of
      a level are anti-parallel at P: two R 70 circles touching at P overlap for ±24 m, so put their arc
      mid-points on opposite sides of the axis at 4.0–4.5 m (decks abut on one 0.5 m barrier). "≤ 3 m"
      cannot hold for two 8 m decks on one level — record this deviation in status.
    - Use **L4 = 23.9** (not 24.0): with the §1.3 deck depth 1.6 m, L5 31.0 − 1.6 − 24.0 leaves 5.4 m
      clearance; 23.9 gives 5.5 m. L2 9.0 → L3 16.5 → L4 23.9 → L5 31.0. Record it in status.
    - **4 right turns**, R = 120 m, in the quadrant *before* the junction: EB→SB in SW, SB→WB in NW,
      WB→NB in NE, NB→EB in SE; ≥ 450 m long; heights taken from the parents at the attach points;
      every point ≥ 51 m from P (T-pier 45 m + half deck 4 m + 2 m).
    - Where two ramps diverge from / merge into the same side of a main line, space them ≥ 150 m apart
      (or merge ramp into ramp first). Acceptance = the strict clearance rule (item 2) plus a printed
      table: ramp id, min distance to the P axis, Y there, start/end s on the parents.
11. **Clashes outside the interchange** (all at ≤ 7.1 m surface gap or at grade):
    - Yan'an west end: `g50_west` (z 728) and `yanan_rd_surface` (z 740) overlap at grade for
      x −2200…−1990; then `yanan_elevated` rises from Y 0 on top of the surface road (1.0 m gap at
      x −1964, 6.3 m over `st_ns_02_03` at x −1813). Do: offset the surface road (split it into two
      one-way frontage roads) so its edge is ≥ 2 m outside the deck footprint until the deck reaches
      7.5 m surface gap (~x −1800); this also creates the gas-station frontage road at z 752 (§8.1).
    - Tunnel troughs: the Puxi trough lies inside the `yanan_rd_surface` footprint from the portal on
      (0.3 m deep at (−451, 187), 2.8 m at (−380, 211)); `st_henan_rd_2` 1.1 m, `lujiazui_ring_rd`
      1.0 m, `st_ns_16_30` 3.5 m above the tunnel; no junction lists `yanan_tunnel`. Do: no road may cross the tunnel where it is < 6.0 m
      deep; put each portal U-trough in the median of a split surface road (the two surface directions
      as one-way roads passing the trough ≥ 1 m clear) or move the crossing streets.
    - Spiral: `nanpu_spiral_lower` starts *on* `zhongshan_e2_s` (1123, 1042) and climbs over it with
      0.5–1.0 m gaps. Dossier §3.3: Zhongshan S Rd passes under the loops at grade, ≥ 5.5 m clearance,
      loop columns outside its 30 m corridor.
    - `ramp_chongqing_on` 3.6 m over `st_ew_12_79`; `ramp_xizang_off`×`ramp_xizang_on_wb` at the same
      height (3.1 m) @(−787,548); `ramp_xizang_off` 6.2 m / `ramp_xizang_on_wb` 6.5 m over `st_ns_07_14`;
      `yanan_east_ramp` 5.2 m over `st_henan_rd_2`; `ramp_l4_nb_wb` 4.1 m over `yanan_rd_surface`.
12. **Yan'an E Rd tunnel** (§4): lowest Y must be **−28.0** (today −25.9, although status says −28);
    grade ≤ 4.5 % (today 4.82 % at s 1345 m); two Ø 11 m bores with centrelines 15 m apart →
    `median` 7.5 m (today 1.0 m → 8 m apart, the bores would intersect).
13. **Nanpu** (§3.3 + brief): lower loop **R 100 ± 5 concentric** (today R 132, only 18 m inside the
    R 150 upper loop — from above the two rings read as one, see the sketch in
    `captures/review/city_layout/sketch_vs_map.jpg`), ¾ turn, 0 → 10 m, merging into the upper loop just
    after its south point with the attach rule (today 0.09 m off). Upper loop ≤ 4.0 % (today 5.02 % at
    s 683 m). Pudong loop ≤ 5 % (6.26 %), exit heading WNW at (1742.5, 1406.7), R 80 right curve, end
    exactly on `pudong_south_rd` at (1690, 1280) (today it ends at (1691, 1240), not attached).
14. **Surface ramp pairs and names.** Xizang Rd "both directions" = 4 ramps: the WB off-ramp is missing.
    Chongqing Rd must be "westbound off / eastbound on" (§10.3); today `ramp_chongqing_off` runs
    *eastbound* ((−1330,716) → (−1080,800)) and `ramp_chongqing_on` *westbound*, both start/end 31–70 m
    from the pillar inside the interchange and clash (1.6 m). Rebuild them east of the interchange
    (diverge/merge x −1080…−900), ≥ 310 m long, ending on Chongqing Rd with a junction. Fix the
    garbled sign names: 西薯路下匧道 / 西薯路上匧道 / 西薯路西向上匧道 / 重庆路下匧道 / 重庆路上匧道 →
    西藏路下匝道 / 西藏路上匝道 / 西藏路西向上匝道 / 重庆路下匝道 / 重庆路上匝道 (薯 = potato, 匧 ≠ 匝).
    Verify: `grep -c '匧\|薯' data/city/city.json` = 0.

### C. Street network and lots
15. **Lead note 1 — no single global grid.** 88 % of the 89.7 km of surface streets are axis-aligned
    within 0.5°; all 91 `st_*` streets are 2-point lines on ONE lattice (x = −2180, −1997 … 1595 every
    ~183 m; z = −1180 … 1591 every 159–189 m) shared by Puxi *and* Pudong. Do, per district (§10.5):
    - **D1**: streets parallel / perpendicular to the Bund centre-line (Bund heading ≈ 334° south of
      z −246, ≈ 353° between z −246 and −524). Guangdong z −110, Fuzhou −230, Hankou (add, ≈ −330),
      Jiujiang −430, Nanjing E −540, Beijing E −703 meet the Bund at ~90° to its local tangent and run
      **to its centre-line** with a junction — today they all stop at x −156, 20–140 m short of it.
    - **D3 / D4** lattices tilted 8–15° (e.g. D3 +10°, D4 −12°) with ≥ 2 diagonal or curved streets;
      **D4 spacing 90–140 m** (today 180–190 m). **D5** its own orientation. **D7** parallel /
      perpendicular to Century Ave (heading 113°) and concentric with the Lujiazui ring. **D6** following
      Zhongshan E-2 (heading ≈ 138°).
    - Verify: `build_city.py` prints a bearing histogram per district; no district except D9 may be at
      exactly 0/90°.
16. **Connectivity.** 72 road ends inside the window connect to nothing, e.g. `st_guangdong_rd_2`
    (−156,−110), `st_fuzhou_rd_2` (−156,−230), `st_beijing_e_rd_10` (−156,−703), `century_ave` both
    ends (748,−489)/(1725,51), `yanan_tunnel` Puxi portal (−460,184), `nanpu_spiral_lower` top
    (1087,1239), all N–S lattice streets ending at z 1164/1364; the creek bridges `st_ns_04_07`,
    `st_ns_05_08`, `st_beijing_e_rd_3` have **both** ends free (isolated bridges). 68 at-grade
    crossings / overlaps have no junction (e.g. Bund × Jiujiang @(−137,−419), Bund × Nanjing E
    @(−140,−521), `century_ave` × `lujiazui_ring_rd` @(1311,−214), `g50_west` × `yanan_rd_surface`).
    Do: snap every street end onto the crossing road's centre-line and add a junction listing both
    roads (incl. the Pearl Ring roundabout and both tunnel portals); creek-bridge segments must join
    their street segments end to end; list the remaining window-edge ends (and the Nanjing Rd
    pedestrian boundary at x −350) in a `dead_ends` note. Verify: dead-end rule (item 7) prints 0.
17. **Lots must fill the map (brief: "every space between roads gets a block").** Lots cover 35.1 % of
    the land; **3.93 km² (~40 % of the land) is neither a lot nor within 12 m of a road** (red in
    `captures/review/city_layout/diag_map.jpg`): the whole south strip z 1150–1800 between x −1800
    and 900, the strip x −1900…−1550 along the N–S, the Pudong riverside x 300–900 (Binjiang Ave
    promenade 25 m wide, §6.3), the Lujiazui core around (1000…1250, 0…300). **D2 has 0 lots**: add
    `neon_street` lots on both sides of Nanjing E Rd from x −900 to −170, the pedestrian section
    x −900…−350 as a 20–25 m `plaza` strip (`notes: pedestrian:nanjing_rd`). Reserve the Bund frontage
    row (façades 16 m west of the Bund centre-line, §5.2) as a declared `plaza` strip
    (`notes: bund_frontage`) for the bund unit; D1 heritage lots = back rows, rotated with item 15.
    Verify: `build_city.py` prints land coverage ≥ 95 % (land minus roads minus water) and lots per
    district (D2 > 0).
18. **Lot integrity.**
    - Roads run through parks: `park_peoples_square` (People's Square, §10.5) is crossed by
      `st_ns_07_14`, `st_jiujiang_rd_2`, `st_fuzhou_rd_2`; `park_shikumen_park` by `st_xizang_rd_3`,
      `st_ew_11_76` → streets end at the park edge with a junction.
    - Landmark plazas are clipped to fragments: `plaza_hsbc_building` 24×22 m (POI 76×70),
      `plaza_swfc` 25×25 (60×60), `plaza_jin_mao` 33×33 (58×58), `plaza_broadway_mansions` 19×13
      (60×40), `plaza_nanpu_tower_e` 2×2 (50×50), `plaza_nanpu_tower_w` 21×21, `plaza_dragon_pillar`
      3×3 (plinth Ø 6.4 m), `plaza_pearl_ring` 21×21 (ring Ø 117.5 m) → each plaza contains the whole
      landmark footprint; bend streets around it instead of clipping it.
    - Every plaza has `height_m` [0, 0], so sky-lane clearance ignores 147–632 m towers → real heights:
      OPT 468, Jin Mao 420.5, SWFC 492, Shanghai Tower 632, Nanpu towers 147 (150 from Y −3), Bund
      buildings per §5.3.
    - POI footprints lie inside building lots: `toll_west` in `b_d9_173`, `gas_sinopex` in `b_d9_174`,
      `charge_sky` in `b_d8_134`/`135`, `charge_bund` in `b_d1_059`, `charge_west` in `b_d4_123`,
      `police_bund` in `b_d1_029`, `police_lujiazui` in `b_d7_062`/`067` — the buildings unit would put
      towers on the gas station. Carve each POI out as its own `plaza` lot (`notes: poi:<id>`).
    - `setback` is 3.0 everywhere; §10.5: 10 m from road edges, 15 m from elevated-deck edges (Bund
      back rows may keep 3 m).

### D. Gameplay data
19. **POIs.** `gas_sinopex`: rect x −1940…−1860, z 760…830 with entry from the frontage road at
    z 752 (§8.1) — no road within 40 m today (item 11 creates it). `charge_sky`: entry from Pudong
    South Rd (§8.2) — today 37 m from a lattice street, not connected. "2 more charge bays + 1 more gas
    station along main roads": `charge_bund` sits on Jiujiang Rd (a 2+2 street), `charge_west` 27 m
    from a lattice street (and labelled 静安 although it is in D4), `gas_petrochino` 62 m from any road
    → place each beside a main road (Yan'an Rd surface, Zhongshan E-2/S, Century Ave, Pudong South Rd)
    with a drive-through lane (SPEC §3: drive through at any speed). Roadblock sites ON their road at
    its height, heading = lane direction: `block_yanan` is 76 m from the Yan'an deck at Y 0 (deck Y 10);
    `block_ns` 130 m from the N–S at Y 0 (it sits on `ramp_rt_sb_wb` at 14 m); `block_spiral` is on
    Zhongshan Rd but labelled 南浦大桥路障. Hiding spots must be under a deck or in the tunnel
    (gameplay §3.4: cooldown ×2 there): `hide_tunnel` is 32 m from the bore (inside rock),
    `hide_under_deck` 33 m from the Yan'an deck, `hide_spiral` in the open centre of the spiral.
    Police stations: `asset` null → `"police_station"`.
20. **Sky lanes** (brief + gameplay §5.6).
    - Pad heading = lane direction of the road under it; today `huangpu_jump` 205° on the Bund whose
      SB tangent is 158° (and the lane leaves NE at 39° — the car would launch backwards),
      `century_canyon` 70° vs 113°, `nanpu_cables` 26° vs 113°, `bund_riverside` 350° vs 3° and 11.7 m
      west of the centre-line (SB side / sidewalk for a NB pad), `dragon_stack` 160° vs 176°.
    - ≥ 300 m straight run-up before every pad: `century_canyon` pad is 55 m after the start of
      Century Ave; `nanpu_cables` pad is 4 m after the curved spiral → put it ≥ 300 m along the straight
      bridge deck (e.g. ~100 m east of the Puxi tower) or ask the lead for an exception in status.
    - Exit over a drivable lane, ≤ 15 m above it (auto-descend 3 m/s): `dragon_stack` exits at Y 28
      over shikumen lots heading 27° (street below runs 0/180°); `nanpu_cables` exits at Y 96, 56 m
      above the Pudong loop; `bund_riverside` exits at Y 40, 244 m from the nearest road.
    - |pitch| ≤ 20°, smooth: today segments climb 48°/35° (`century_canyon`), 27° (`huangpu_jump`,
      `nanpu_cables`) and dive −58° / −59° at the ends.
    - `nanpu_cables` must thread each tower between the deck (Y 44) and the upper crossbeam (Y 128–134),
      e.g. Y 85–110 at the tower planes — today Y 131 at the W tower, Y 129 at the E tower = inside the
      crossbeam that carries 「南浦大桥」.
    - `century_canyon` must be a canyon: Y 40–90 along the 100 m Century Ave corridor, below the
      flanking tower tops, ≥ 10 m horizontal clearance from lots — today it flies at Y 265, above every
      D7 tower (80–240 m).
    - N₂ rings every ~250 m along the whole lane: `huangpu_jump` (936 m) and `century_canyon` (1132 m)
      have only [250, 500].
    - Keep what works: `dragon_stack` passes 2.2 m from the pillar axis at Y ≈ 55 (24 m over L5) ✓.
21. **Routes** (§10.6 + brief).
    - Spacing 300–500 m: today grand_loop 90–1223 m, elevated_sprint 29–532, river_loop 93–957,
      bund_sprint 218–647, lujiazui_ring 215–728 (status says "every 400 m": false).
    - Heading = lane tangent: today headings are quantised to 90°/270°, errors up to 90° (river_loop
      cp00–cp02 49–51° off on Zhongshan E-2, lujiazui_ring cp06 84°).
    - Position = centre of the driven lanes at lane height: most checkpoints sit on the centre-line /
      median; grand_loop grid + cp00 31 m off-road, cp01 61 m, cp13 69 m, cp18 42 m, cp20 61 m, cp24
      111 m, cp27 73 m; elevated_sprint cp04 77 m off, cp05/06/12/13 float 7.5–9.3 m above surface roads.
    - Itineraries: grand_loop jumps cp02 (Xizang ramp) → cp03 (Inner Ring), skipping the Yan'an
      Elevated, the dragon interchange and the N–S, never uses Pudong South Rd / Century Ave, and
      detours west on lattice streets (cp17–cp27 to x −1460). Follow §10.6 exactly: Bund S → Yan'an E
      Rd → Yan'an Elevated W → dragon left-turn ramp → N–S S → Inner Ring E → spiral → Nanpu → Pudong
      loop → Pudong South Rd N → Century Ave W → Pearl Ring → tunnel W → Henan Rd N → Nanjing E Rd E →
      Bund (≈ 12 km). elevated_sprint drives backwards (cp02 272° on `ramp_l4_nb_wb`, cp03 273° at Y 4.1)
      → toll → Yan'an E → dragon → Bund (≈ 3.5 km). river_loop skips Pudong South Rd + Century Ave.
    - Grids on a straight, on a lane centre (river_loop grid heads 90° on a 139° road).
    - Print per route: driven length on the lane graph, spacing min/max, ordered road ids.
22. **C-INT1 (lead, mandatory).** Player spawn (−123.5, 0, −300.5, 90°) is on the Bund centre-line
    (1.74 m from the nearest lane centre) and faces **east**; the SB lane there runs 169°. Put it on a
    southbound lane centre near (−100…−120, 0, −250), heading = that lane's tangent (≈ 160–170°).
    Police spawns: police0 (−255, −760) on the Sichuan Rd centre-line (1.75 m off a lane centre),
    police1 2.25 m off, police2 (−1253, 0, 692.7) heads 0° where the lanes run 64°/244°. Snap all to
    lane centres + lane headings and add the rule (item 7). (Lead: the game spawned the player at
    (−131.7, 0, 298.2) — opposite Z sign to city.json's −300.5; a consumer may be flipping Z.)

### E. Hero cross-sections, renders, reporting
23. **Bund and Waibaidu cross-sections.** 中山东一路 is 2+2 / 24 m; SPEC §6 + dossier §5.2: 6 lanes
    (2+2 × 3.5 m + 2 turn/bus lanes = 20 m carriageway), west sidewalk 6 m → 3+3 lanes at 3.33 m,
    sidewalk 6. Waibaidu bridge is 1+1 / 8 m; §5.5: carriageway 11.2 m (3 lanes) + 2 × 3.0 m
    sidewalks, 4 % deck grade (+2.1 m at mid-span) → 2+1 lanes at 3.73 m, sidewalk 3.0, humped profile.
24. **Lead note 3 — map.png must show everything at a glance.** Today sky lanes are unlabeled thin cyan
    lines (same cyan family as bridges (96,200,255) and route 4 (0,229,255)), pads are unlabeled squares
    without heading, routes are dots + a title at cp0 (no path, order, direction or grid); elevated
    roads are 1–2 px and vanish among the lattice (compare the dossier sketch in
    `captures/review/city_layout/sketch_vs_map.jpg`). Draw: elevated/ramps ≥ 4 px, each sky lane dashed
    #00E5FF with `id 标签` at its midpoint, pad = arrow along its heading + `PAD id`, each route as a
    polyline grid → cp0 → … in its own colour with numbered checkpoints, arrowheads every ~500 m, a grid
    marker and `title (length)`; POI legend. Verify on a 1280 px downscale: every label readable.
25. **profiles.png is unreadable** (solid bars, no curves). `draw_profiles()` measures distance in the
    (x, y) plane (`[[p[0], p[1]] ...]`) instead of (x, z), resets `s = 0.0` at every point and mixes
    pixel with world coordinates; printed lengths are wrong (`ns_elevated` "581 m" vs 2,821 m,
    `nanpu_spiral_upper` "450 m" vs 847 m). Do: cumulative x–z arc length of the Catmull-Rom 2 m
    samples, a polyline y(s) per row, y grid at 0/10/20/30/40 m, dashed L2 9 / L3 16.5 / L4 23.9 / L5 31
    on the dragon rows, attach points as ticks, over-limit segments in red, the tunnel row included.
26. **Honest status.** status/result/JSON `notes` claim: left-turn ramps within 3 m of the pillar
    (measured 116–141 m), N–S 31 at the pillar (28.56), tunnel Y −28 (−25.9), checkpoints every 400 m
    (29–1223 m), "profile legal, Catmull-Rom artefact" (control-point grades up to 6.64 %), and present
    hollow PASSes as passes. Next round: quote only numbers printed by the strict validator, list every
    remaining failure, drop the geo.py request, restate the landmarks pillar request for the rebuilt
    geometry (L3/L4 decks pass over the pillar axis at 16.5 / 23.9 m — pillar must stop below 14.9 m or
    get deck collars; lead decides).

## SHOULD-FIX
1. Dead code (global rule: no dead code): `city_grid.py` `WINDOW`, `DISTRICT_STYLE`, `_runs`,
   `_creek_bridges`; `city_ramps.py` `s_at_z`; `city_road.py` `refresh_heights`, `y_at`, `heading_at`,
   `xz_at`, `make_ramp`, `_smooth`; `city_roads.py` `LAYOUT`; `city_rules.py` `_trim`; `citylib.py`
   `TAU`; `validate.py` `STEP`; `build_city.py` `KEY_INDICES`. Keep the citylib API the brief asks for
   (`edge_polylines`, `offset_polygon`, `polygons_overlap`) and use it in the rules.
2. Magic numbers in the rules (22.0, 250.0, 30.0, 20.0, 3.0, 40.0, 70.0, 25.0, 18.0) → named
   constants with a comment naming the brief/dossier rule they implement.
3. Noise walls derived from adjacent residential / shikumen lots for every elevated road; today
   `yanan_elevated` has [1500, 2100] on a 1676 m road and `ns_elevated` / `inner_ring` have none.
4. Length: the brief expects "60–120 km of lanes"; you have 107.1 km of road / 334 km of lanes. Print
   both in `validate.py` and justify the density in status (the lead decides).
5. Century Ave is a 100 m corridor (§6.3): reserve 30 m north / 15 m south green-sidewalk strips as
   `park` lots; today lots start 1 m from the 49 m road.
6. District heights vs §10.5: D3 up to 40 storeys (~140 m; today max 60), D4 add 2–3 thirty-storey
   towers (~100 m), D6 add 25-storey riverside apartments (~80 m).
7. N–S inside the interchange is 2+2 on L5 (§1.3); today 3+3 throughout.
8. Spiral loops + Nanpu deck: §3.3 asks for the §3.2 deck-edge LED line (#3D7BFF) so the spiral reads as
   glowing rings; today the loops carry `soffit_led` #5A3DFF and only the Pudong loop #3D7BFF — make
   the Nanpu family consistent.

## Verified OK
- Determinism: a scratch rebuild (copy of `tools/city`, run outside the repo) produced the identical
  `city.json` MD5 `c685c4e3c83f52987e357438ae4adeab`; JSON 0.57 MB (< 5 MB).
- `citylib.catmull_rom` matches `blender/lib/geo.py catmull_rom` (reflected ends, n = ceil(seg/step)).
- Python 3.9.6, all 16 files ≤ 366 lines, `citylib.py` stdlib only; ownership clean: `git status` shows
  only `data/city/city.json` and `tools/city/**`; `tmp/city_layout/` was cleaned.
- Plan of the main lines follows §10.3 (Yan'an, N–S, Inner Ring, Bund, Zhongshan E-2/S, Century Ave,
  Lujiazui Ring, Pudong South Rd, tunnel portals at (−459.8, 184.4) / (759.0, −462.4)); Yan'an starts
  climbing at x −1990 (peak 4.02 %); Inner Ring Y 10; Nanpu deck 42.5 → 45.3 m (§3.2 45.5).
- Spiral circulation counter-clockwise seen from above (lower +270°, upper +334°, Pudong +567°); upper
  loop R 150 / 334° ends at (956, 1260).
- Huangpu polygon closed outside the window, Suzhou Creek width 70 m, no road in the water.
- Nanjing E Rd not drivable west of x −350. Planter parapets + `#5A3DFF` soffit on every elevated/ramp,
  `median_double` lamps on the main lines.
- POI counts match the brief (toll 1, gas 2, charge 3, police 2, hiding 4, roadblock 4, landmark 14);
  5 sky lanes 595–1132 m long (§5.6: 400–1500 m); 5 routes with the brief's ids.

## Evidence
- `python3 tools/city/validate.py data/city/city.json` → exit 1, `12 rules, 4 failed`:
  `FAIL grades ... nanpu_pudong_loop 6.3%; ... ramp_l4_nb_wb 6.1%; ramp_rt_eb_sb 5.5%`,
  `FAIL vertical curvature ... ns_elevated @2571m; ...`, `FAIL ramps attach ... century_ave attach_start
  off parent by 26.59 m; ramp_chongqing_off attach_end tangent 55.5 deg ...`, `FAIL route checkpoints
  reachable ... elevated_sprint cp off road (-1462,563) ...`, `drivable length: 107.1 km of road`.
- Scratch rebuild in `tmp/review/city_layout` (deleted after use): `drivable : 107.1 km of road
  (334.0 km of lanes)`, MD5 identical to the committed file.
- `tmp/review/city_layout/scripts/grades.py` → `GRADE FAILS: 9`, `CURVATURE FAILS: 17` (lists in item 8).
- `tmp/review/city_layout/scripts/overlap.py` → `conflicts: 86` (68 at-grade without junction, 18
  vertical; lists in items 2, 11, 16).
- `tmp/review/city_layout/scripts/blocks.py` → 5 lots intruding ground roads, 3 lots under/within 2 m
  of a deck (`plaza_dragon_pillar`, `plaza_nanpu_tower_e` = landmark exemptions, `park_shikumen_park`
  under both Xizang ramps), `land cells 26702, in blocks 35.1 %`, `empty land ... 3.93 km2`.
- `tmp/review/city_layout/scripts/routes.py` → checkpoint/pad/spawn offsets and heading errors (items
  20–22); inline checks: 72 unconnected road ends; N–S max Y 28.56; left-turn ramp min distance to the
  pillar 116.4–141.2 m; tunnel min Y −25.9; landmark plazas `height_m` [0, 0].
- Images (all under `captures/review/city_layout/`): `map_1280.jpg` (worker map), `map_crop_bund.jpg`
  (no lane/pad/route labels), `profiles_1280.jpg` (broken chart), `diag_map.jpg` (reviewer render: red
  = empty land, red X = deck clash, yellow x = at-grade overlap without junction), `diag_dragon.jpg`
  (deck heights, pillar, §1.3 R 70 arcs), `sketch_vs_map.jpg` (dossier `map_sketch_v1.png` vs map.png).
- Godot (roads unit tiles built from this city.json, `res://assets/city/roads/preview_roads.tscn`,
  `CAPTURE errors=0`): `captures/review_city_layout_r1_{pillar_close,ramp_clash,chongqing_clash,
  spiral_close,yanan_west,henan_portal,dragon,spiral}.jpg`; brightened contact sheet
  `captures/review/city_layout/godot_close_sheet.jpg` shows deck-through-deck clashes at the Chongqing
  ramps and the dragon ramps, and the Yan'an deck starting on top of the surface road. The two high
  views (`dragon`, `spiral`) are lost in night fog (luminance std 12 / 0.8) — use plan renders for
  layout review.
