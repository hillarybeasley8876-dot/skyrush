# city_layout review round 2 — VERDICT: FAIL

Reviewer: Opus (strict review / art director). Round 2 of `data/city/city.json` + `tools/city/**`.
Real progress: grades/kinks 9+17 → ~1+5, dead ends 72 → 15, L5 31.0 / L2 9.0 / tunnel −28.0 hit, the
player spawn is on the Bund SB lane (C-INT1 data ✓), every district has its own grain, D1 cross
streets meet the Bund at 90°, landmark plazas carry real heights, deterministic build. But the
validator still fails 9/16 rules, and my checks show the network is not drivable as named: **every
one of the 14 Yan'an/N-S ramps serves the EB/SB carriageway only and is attached to the median**, the
dragon interchange is a knot of loops, 4 of the 7 "PASS" rules are hollow (one rule crashes when
called, one has a typo that makes it measure nonsense), lots are 10 m staircases wound clockwise.
The status is stale (it says the left turns pass 116–141 m from the pillar; the data says 4.2 m).

## Scores (0-10)
- **function: 3** — 526 clearance failures (59 road pairs), all ramps on the wrong carriageway/median,
  507 junction records on decks or in the tunnel, routes the world unit cannot route, coverage 72.5 %.
- **visual/feel: 3** — rotated district grids read far better than r1, but lot outlines are 10 m
  sawtooths in every rotated district, the interchange reads as spaghetti (see
  `captures/review/city_layout/r2/diag_dragon2.jpg`), map/profiles labels unreadable at 1280 px.
- **code: 4** — deterministic, stdlib, owned paths only; but 5 files > 400 lines, 7 functions > 60
  lines, 45 unreferenced definitions, a crashing lane graph, a typo'd curvature rule, false docstrings.

Lead notes (mandatory): **C-INT1** data ✓ (spawns on lane centres), rule incomplete → 4g;
**note 1** partly (grain ✓, no diagonal/curved streets, seams) → 9; **note 2** data: 1 lot left
(`plaza_poi_charge_bund`) → 6, rule vertex-only → 4d; **note 3** drawn but unreadable → 11.
Project rules: ✓ (one transient `tmp_val.txt` in the repo root — use tmp/city_layout/).

## MUST-FIX
Acceptance tools (read-only for you — run them, your validator must reach the same verdicts):
`python3 tmp/review/city_layout/scripts/<name>.py data/city/city.json` with name =
`dragon_check` (exit 1 on fail), `attach_dir`, `junctions` (exit 1), `blocks`, `routes`, `pads`,
`coverage`, `stairs`, `dupes`, `codescan`, `grades`, `overlap`. Do the items in this order.

### P1 — the road network (do first)
1. **Every ramp attaches to the median of the wrong carriageway (systemic).** `attach_dir.py`: all
   8 dragon ramps and all 6 Xizang/Chongqing ramps leave/join `yanan_elevated` in its EB (points)
   direction and `ns_elevated` in its SB direction, at lateral **0.00 m** (the centre-line/median),
   `side` "right" on all 16. Examples: `ramp_l4_nb_wb` starts on ns_elevated@1442 flowing 176° (SB)
   and ends on yanan_elevated@182 flowing 90° (EB) = an SB→EB ramp; `ramp_xizang_off_wb` leaves the EB
   side (yanan@1522, 42°); `ramp_xizang_on_wb` merges EB at yanan@722 — at the pillar;
   `ramp_chongqing_off` leaves EB (brief: WB off). The WB and NB carriageways have **no ramp at all**.
   `nanpu_pudong_loop` joins pudong_south_rd's NB lanes (flow 349° vs points 178°) with side "right",
   lateral 0. Cause: dragon.py "Every ramp leaves and meets its parent *on* the parent's centre-line"
   — my r1 item 4 ("plan ≤ 0.10 m") meant *on the carriageway edge*; this item replaces it. The roads
   unit currently patches your data (`blender/city/roads/load.py align_attaches`: "The city file places
   a ramp's end on the parent's centre line …") — fix it at the source. Do:
   - Each ramp serves one parent carriageway: dir +1 (with the parent's points) or −1. The ramp's own
     points run in its traffic direction (lanes_back 0).
   - Ramp end point at lateral = sign × (asphalt_half(parent) + asphalt_half(ramp)) from the parent
     centre-line, sign +1 (right of the parent's points) for dir +1, −1 for dir −1. asphalt_half exactly
     as `blender/city/roads/profiles.py layout()`: two-way = median/2 + 0.5 inner strip (decks with
     median > 0) + lanes_per_side·lane_width + shoulder; one-way = lanes·lane_width/2 + shoulder.
     Yan'an/N-S + 1-lane ramp = **±16.88 m**, + 2-lane ramp = **±18.75 m**. Tolerance ±0.10 m.
   - `side` "right" for dir +1, "left" for dir −1; `at` = parent arc length of the projection (±0.5 m);
     height = parent height there (±0.05 m); tangent within 8° of the *flow* direction (no 180° fold —
     today `check_attaches` takes `min(diff, diff+180)` so a wrong-way ramp passes).
   - Surface/tunnel roads must not use `attach_*`; they meet at junctions: bund_zhongshan_e1 ↔
     zhongshan_e2_s (157° apart), century_ave → yanan_tunnel (37°), yanan_tunnel → yincheng_rd (82°),
     zhongshan_e2_s → lujiabang_rd (44°). The Yan'an east landing (3+3 deck attached end-on to the
     3+3 yanan_rd_surface centre-line at 16°): split yanan_rd_surface into two one-way roads so the
     deck lands between them (dossier §10.3), junction at the landing.
   - Rewrite `check_attaches` to these rules, for every attach (no ramp-only filter).
   Verify: `attach_dir.py` shows every ramp WITH its intended carriageway, lateral ±16.88/±18.75;
   `dragon_check.py` prints no "flows / lateral / side / at" messages.

2. **Dragon interchange: rebuild (dossier §1.3).** `dragon_check.py` → 8/8 FAIL. Measured: lengths
   680–1272 m; loops (`ramp_rt_sb_wb` turns +612° in total, `ramp_rt_wb_nb` −582°, `ramp_l4_nb_wb`
   +274° for a −86° movement); right turns 18.4 m (`rt_eb_sb`) and 32.9 m (`rt_wb_nb`) from the axis
   (need ≥ 51); both L3 ramps cross P heading SE (126°/130°) and overlap at 0.0 m vertical gap at
   (−1312, 674), the L4 pair at (−1294, 687). 319 of the 526 clearance samples are ramp×ramp, 87
   ramp×Yan'an. Only "4.2 m from P at 16.5/23.9" is right — keep that. Build it as a 4-level stack:
   - Each half of each main line carries one left-turn leg (inner) and one right-turn end (outer):
     | half-side | left-turn leg (inner) | right-turn end (outer) |
     |---|---|---|
     | Yan'an S side (EB), west of P | L3 EB→NB diverge | RT EB→SB diverge |
     | Yan'an S side (EB), east of P | L4 SB→EB merge | RT NB→EB merge |
     | Yan'an N side (WB), east of P | L3 WB→SB diverge | RT WB→NB diverge |
     | Yan'an N side (WB), west of P | L4 NB→WB merge | RT SB→WB merge |
     | N-S W side (SB), north of P | L4 SB→EB diverge | RT SB→WB diverge |
     | N-S W side (SB), south of P | L3 WB→SB merge | RT EB→SB merge |
     | N-S E side (NB), south of P | L4 NB→WB diverge | RT NB→EB diverge |
     | N-S E side (NB), north of P | L3 EB→NB merge | RT WB→NB merge |
   - Left turns: leg = the parent's offset polyline (citylib `polyline_offset`) at 16.88 m growing over
     150 m to the arc-tangent offset; ONE circular arc (L3 R 70 m, L4 R 100 m) whose mid-point is
     4.2 m from P on the INSIDE of its own turn (towards its arc centre — offsetting outwards makes the
     two arcs of a level cross), so the two ramps of a level pass P anti-parallel 8.4 m apart (decks
     abut) and diverge from each other; mirrored leg to the merge. Diverge 280–350 m before P; merge
     where the target carriageway's height equals the ramp's (≤ 480 m after P). Crossing headings follow from the main lines at P (Yan'an
     66°, N-S 138°): EB→NB ≈ 12°, WB→SB ≈ 192°, NB→WB ≈ 282°, SB→EB ≈ 102°. Level flat ±0.05 for
     ±40 m around P. Grades ≤ 4.6 % via `city_profile.py`.
   - Right turns: R 120 m arc in their quadrant, diverge ≥ 150 m upstream of the same half-side's
     left-turn diverge, merge ≥ 150 m downstream of its merge, run outside the left-turn leg (≥ 9 m
     further out) where parallel; every point ≥ 51 m from P.
   - `build_city.py` prints a table: ramp, from/to carriageway, attach s + lateral, min distance to P,
     Y and heading there, length, total turn.
   Verify: `dragon_check.py` 8/8 PASS; validator clearance 0 failures for any pair among
   `ramp_l*`, `ramp_rt*`, yanan_elevated, ns_elevated; grades/curvature PASS for all 8.

3. **Xizang / Chongqing ramp pairs (§10.3).** All 6 serve EB only (item 1); `ramp_chongqing_on` is
   977 m long and merges at yanan@1556 (x −616, *east of Xizang Rd*); `ramp_xizang_on_wb` merges at the
   pillar; they clash: `ramp_xizang_off`×`yanan_elevated` 2.9 m [need 7.3] @(−895, 450),
   `ramp_xizang_off`×`yanan_rd_surface` −2.6 m @(−757, 327), `ramp_chongqing_on`×`ramp_rt_nb_eb`
   −7.3 m @(−1004, 572), `ramp_l4_sb_eb`×`ramp_xizang_off` 23 samples down to −3.1 m. Space on the
   Yan'an (arc length s): P 705, Chongqing Rd 936, Xizang Rd 1420; east of s ≈ 1550 the deck already
   descends to grade (8.1 m @1600, 4.7 m @1700, 0 @1891). After item 2 the dragon's legs occupy the EB
   side to s ≈ 1300 and the WB side to s ≈ 1200. With ≥ 150 m between consecutive merge/diverge points
   on one carriageway (no shorter weaves) and ≥ 280 m per surface ramp, most of the 6 cannot fit. Do,
   after item 2: print a ramp-budget table (every ramp end per carriageway: s, kind, gap to the next);
   keep only ramps that pass the weave rule, the attach rule (item 1) and the clearance rule; do **not**
   emit clashing ramps. Write a `## Requests` entry to the lead with the table and options — (A) drop
   the Chongqing pair; Xizang traffic uses the Yan'an east landing + the surface Yan'an Rd; (B) branch
   the Chongqing/Xizang ramps off/into the dragon right-turn ramps (collector-distributor roads).
   Verify: 0 clearance failures involving `ramp_xizang_*`/`ramp_chongqing_*`; the table + request are
   in status.

4. **The validator must tell the truth (r1 A.1–A.7 still open).**
   a. `validate.py` says "a failing rule lists *every* failure" but `MAX_LINES = 40` hides 486
      clearance and 10 block failures. Print one line per road pair / lot-road pair: count, worst
      value, need, location (59 clearance pairs today — see `tmp/review/city_layout/r2/clear_groups.txt`).
   b. **Curvature rule is broken**: `city_rules.py:183` `run = math.hypot(b[0] - a[0], b[2] - a[1] * 0
      + b[2] - a[2])` (= 2·b_z − a_z). Its 3 failures are artefacts (the tunnel at s 532–558 has smooth
      −4.28…−4.36 %); the real ones (2 m points, 10 m window) are `ns_elevated` 0.60 %/10 m @1914,
      `nanpu_spiral_upper` 0.56 @64, `yanan_tunnel` 0.56 @788, `yanan_elevated` 0.55 @264,
      `ramp_xizang_off_wb` 0.51 @280 (+ spline blips from uneven control points: `grades.py`
      `nanpu_pudong_loop` 0.99, see 7). Fix the formula; lengthen those vertical curves (L ≥ 2200·Δg).
   c. **Route reachability is not checked.** `check_routes` claims "reachable in the driving
      direction" but never builds the graph: `build_lane_graph`/`_reachable` are never called, and
      calling `build_lane_graph` **crashes** (`NameError: _angle_diff`, city_rules_graph.py:229). Fix it
      and use it: grid → cp0 → … must be a directed path; spacing = shortest driven path length; every
      lane chain must be in the main strongly connected component except window-edge dead ends.
   d. **Block rules test only polygon vertices** (`check_blocks`, `check_decks`: `min(distance_to(p)
      for p in block["polygon"])`). Test the polygon against the footprint: a road sample inside the
      polygon or edge distance < half-width + 1 m (ground) / + 2 m (deck, y ≥ 1 m); include ramps at
      grade and tunnel troughs (y > −7 m). `blocks.py` finds 77 lot×road pairs (38 lots) incl.
      `b_d0_025`, `b_d7_034`, `b_d7_039` over the tunnel troughs, which your rule misses.
   e. **Coverage rule is hollow**: `check_coverage` subtracts length × (width + 20 m) per road (crossings
      counted twice, decks over streets twice) and passes at 90 %. Use a 5 m raster: window − water −
      road footprints(+1 m); ≥ 95 % of those cells inside a lot. Today `coverage.py`: **72.5 %**, 2.19 km²
      empty.
   f. **Clearance loophole**: surface×surface overlap is exempt if the two roads share a junction
      *anywhere* (`_junction_pair`). Exempt only within (half-widths + 10 m) of that junction's point.
      Example hidden today: `bund_zhongshan_e1`×`st_d0_ns` overlapping at (−116, −265), 84 m from their
      junctions. Junctions on decks (item 5) must not exempt anything.
   g. **Lane model** (`city_rules_lanes.lane_centres`) puts one-way lanes at median/2 + (i+0.5)·w: a
      1-lane ramp's lane at +1.875 m, a 2-lane ramp's 2nd lane at +5.625 m (on the parapet). The
      consumer (`blender/city/roads/profiles.py`, lanes.json) centres them: offset_i = (i + 0.5 − n/2)·w.
      Use that. Today 7 checkpoints on 1-lane ramps are 1.83–1.90 m off the real lane (grand_loop
      cp06/07, elevated_sprint cp02/03/06/07/08 — `routes.py`). Apply the rule to route grids too.
   h. **Sky-lane run-up** compares two headings and clamps at the road start: walk back 300 m along the
      lane graph (through the parent road), max heading change ≤ 3°; and `points[0]` within 1 m of the
      pad (today 10.0 / 27.4 / 10.0 m above the pad for huangpu_jump / century_canyon / bund_riverside).
   i. Delete claims that are not implemented: validate.py "every failure", check_routes "reachable",
      dragon.py "every ramp stays at least 51 m away", "on the parent's centre-line".
   Verify: your rules and my scripts give the same counts on the same file.

5. **Junction records are unusable.** `junctions.py`: 1841 records for 938 places; 207 exact
   duplicates; 179 ids used more than once (213 extra records); 2933 record pairs < 15 m apart (43
   records at (−951, 504), 32 at the pillar); **507 junctions list a road that is > 1 m above/below
   grade there** (ramp 324, elevated 144, bridge 18, tunnel 21) — e.g. `j_nanpu_bridge_zhongshan_e2_s`
   with signals at the 45 m bridge deck, `j_ramp_l3_eb_nb_ns_elevated` at 17 m, 7 junctions between
   `nanpu_pudong_loop` and Pudong streets. The roads unit builds an intersection at every record.
   Do: one record per intersection (merge records within 15 m, union of roads), unique ids, only roads
   at grade (|y| ≤ 0.3 m within 30 m of the point); a ramp foot on a street = one junction; a deck over a
   street = no junction; signals where ≥ 2 roads with ≥ 2 lanes per direction meet. Add the rule.
   Verify: `junctions.py` exit 0 (0 duplicates, 0 pairs < 15 m, 0 off-grade).

### P2 — lots and map content
6. **Lots.**
   - **Staircase outlines** (`stairs.py`): in every rotated district 100 % of lot edge length is
     axis-aligned and 46–82 % of edges are ≤ 10.5 m (D6 mean 40.8 vertices, D5 44.5, D7 33.5) — the
     10 m raster sawtooths every frontage (visible in `captures/review/city_layout/r2/map_crops.jpg`);
     the buildings unit extrudes these into jagged façades. Do: each lot = the polygon between the street
     centre-lines inset by (half-width + 1 m), clipped by deck footprints (+2 m), water and other roads
     with exact polygon ops (`citylib.offset_polygon` + a convex/concave clip), simplified at 0.5 m; merge
     slivers < 400 m² into a neighbour (today 66 lots < 400 m², 11 < 100 m²). The raster may only
     *measure* coverage. Verify: per district ≥ 90 % of lot edge length within 5° of the district's two
     street bearings.
   - **Winding**: all 621 lots are clockwise seen from above (shoelace over (x, z) > 0); SCHEMA and
     `test_city.json` are counter-clockwise (< 0). Reverse them; add a rule.
   - **Coverage ≥ 95 %** with the 4e rule (today 72.5 %).
   - **Lots on roads** (`blocks.py`, 38 lots): POI plazas straddle their roads —
     `plaza_poi_charge_bund` covers the Yan'an×Xizang junction (7 roads) and lies 13.5 m under the Yan'an
     deck; `plaza_poi_police_bund` is 16.6 m into the Bund; `plaza_poi_toll_west` covers g50_west,
     yanan_elevated and both frontage roads; `plaza_poi_charge_sky` 12.8 m into Pudong South Rd;
     `plaza_hsbc_building` 6.9 m into the Bund right at the player spawn (−114, −251);
     `plaza_oriental_pearl` 8.9 m into lujiazui_ring_rd. A POI plaza is only the off-road part of the
     site (booths/canopy come from the POI record), ≥ 1 m from every road edge. Parks crossed by streets:
     `park_shikumen_park` × st_d4_ew_5/6/7, st_d4_ns_5/6; `park_lujiazui_green` × 4 streets;
     `park_century_ave_*` × st_d7_* — streets end at the park edge with a junction. Landmark plazas:
     bend the streets around them (§5.3), never clip the plaza.
   - **D2 / Nanjing Rd**: only 9 `neon_street` fragments (b_d2_003 is 10 × 30 m) and no pedestrian
     street. Add the `plaza` strip 20–25 m wide along Nanjing Rd x −900…−350 (`notes:
     pedestrian:nanjing_rd`) and neon_street lots on both sides from x −900 to −170 (r1 item 17).
   - Bund frontage/promenade strips are confetti (`plaza_bund_promenade_2` 17 m²,
     `plaza_bund_frontage_3/6/7` 24–25 m²) and crossed by `st_d0_ns`/`st_d0_ns_2`: one continuous strip
     per block face, cut only at the cross streets.
   - `setback` is 3.0 on 573 lots and 0.0 on 48: §10.5 = 10 m from road edges, 15 m from deck edges
     (Bund back rows 3 m) — r1 item 18.
   - `plaza_poi_charge_nanjing` at (530, 490) is tagged district D9 (D9 is the industrial west edge).
   Verify: `blocks.py` 0 non-exempt pairs; `stairs.py`; `coverage.py` ≥ 95 %.

7. **Remaining road-rule failures.**
   - Grades: `nanpu_spiral_upper` 4.02 % @609 m (limit 4.0). Kinks: the real list in 4b.
   - Control points: uniform 2.0 m was asked (r1 item 8) but 18 non-surface roads have short segments
     down to 0.03 m (`ramp_chongqing_off`), 0.12 m (`nanpu_bridge`); in `nanpu_pudong_loop` one 1.73 m
     segment at s 980 makes the uniform Catmull-Rom blip −2.92 → −4.55 % (`grades.py` 0.99 %/10 m).
     Redistribute so every segment is 2.0 ± 0.25 m (spread the remainder over the whole road).
   - Tunnel portal: `yanan_rd_surface`×`yanan_tunnel` 1.6 m [need 6.0] @(−376, 187) — split the
     surface road around the Puxi U-trough (r1 item 11); clear lots `b_d0_025`/`b_d7_034`/`b_d7_039`
     from both troughs.
   - Surface roads inside other roads (`dupes.py`, 1.9 km in 32 pairs): `st_d7_ns_6` runs 348 m inside
     Century Ave, `st_d6_ew_2` 204 m inside Zhongshan E-2, `st_d7b_ns_4` 80 m, `st_d7_ns_8` 76 m inside
     lujiazui_ring_rd, `st_link_40`/`st_d0_ew_2` 128 m inside each other — delete or trim lattice streets
     inside an arterial corridor; one street per corridor.
   - Dead ends: 15 (century_ave (1725, 51), st_hankou_rd (−959, −209), st_d4_ew_3 (−112, 362),
     st_link_2/3 …) and the `notes` list is empty ("Dead ends at the window edge: .").
   - **Nanpu bridge WB has no feeder**: the 3+3 bridge ends on the one-way descending
     `nanpu_pudong_loop`, so its WB lanes are only reachable through fake deck-level junctions (item 5).
     Make the Pudong loop 2+2 (like the Puxi upper loop) or add an ascending loop. `nanpu_spiral_lower`
     attach tangent error 35°.
   - Waibaidu bridge is flat (Y 0.00 over 104 m): 4 % humped deck, +2.1 m at mid-span (§5.5, r1 23).
   Verify: validator rules 2, 3, 4, 9 PASS; `dupes.py` 0.

8. **Routes, grids, pads.**
   - Finish gates in the origin junction: grand_loop cp35 and river_loop cp28 (−1.5, 0, 0.7) head 155.6°
     on yanan_rd_surface (lane 227°: **71° off**); elevated_sprint cp11 (1.6, 0, 1.7) heads 46.9° on
     zhongshan_e2_s (lane 133°: **86° off**). Finish on a straight ≥ 60 m from any junction.
   - Grids: elevated_sprint grid at x −2200.0 = the window edge (the 5 rival slots behind it are off the
     map); the grand_loop/river_loop/bund_sprint grid (−149.3, −914.5) sits on the Bund/Waibaidu joint
     with the 1-lane SB bridge behind it. Grids on straights with ≥ 2 lanes in the race direction and
     ≥ 100 m of the same road behind.
   - grand_loop cp05 (Yan'an WB) → cp06 (`ramp_l3_wb_sb`) is undrivable today (that ramp leaves the EB
     side heading 39°); re-place after item 2.
   - The world unit cannot route them (`tools/godot.sh shot` log): "route grand_loop: 2 legs are not
     on the lane network (gates [18, 19])", "river_loop: 2 legs are not on the lane network (gates [11,
     12])", and 8 legs whose gates are > 8 m from the lanes (grand_loop [20], elevated_sprint [0, 2, 3],
     river_loop [13, 25, 26], bund_sprint [8], lujiazui_ring [0]).
   - Pads (`pads.py`): `huangpu_jump` has 100 m of road behind the pad (st_fujian_portal starts there),
     `dragon_stack` 48 m on a curving ramp, `century_canyon` 19.5° of heading change in the 300 m before
     it (Century Ave's start kink), `bund_riverside` 17.1° (the Bund bends). Move each pad to ≥ 300 m of
     straight lane; lane `points[0]` = pad position; fix the 2 lot-clearance failures (huangpu_jump 34 m
     over a 25 m lot at (−339, 219): start the climb over the road/river).
   Verify: `routes.py` / `pads.py` 0 FAIL; the world log shows no "legs are not on the lane network"
   / "more than 8 m from the lanes" lines.

### P3 — character, presentation, code, reporting
9. **Lead note 1 (remainder): street character.** Rotating each district is a big step and D1 is right
   (Guangdong, Fuzhou, Hankou, Jiujiang, Nanjing E, Beijing E meet the Bund at 90°). Still missing
   "a few diagonal or curved streets": every district lattice has exactly two bearings (D3 10°/100°, D4
   80°/170°, D7 20°/110° …) at perfectly uniform spacing (D4 108/114 m, D3 156/157 m, D7 172/175 m) —
   it reads as rotated SimCity. Do: D3 and D4 each ≥ 2 diagonal or curved streets (e.g. one following
   an old creek line, one diagonal joining two arterials); D7 ≥ 2 streets concentric with the Lujiazui
   ring road; vary spacing ±20 % inside each district's range. Seams: `st_d0_ns` crosses the Bund at
   19–21° ((−170, −429), (−131, −348)) and `st_d0_ns_2` at 16–27° — no two roads may meet at < 60°;
   end or bend such streets. Verify: build_city.py prints per district the bearing histogram, the
   number of diagonal/curved streets and the minimum crossing angle (≥ 60°).

10. **POI labels (ART §7: parody brands, real words only).** `gas_petrochino` "中国石由加油站" (石由 is
    not a word — the real 中国石油 minus its 氵 radical) and `gas_sinopex` "中国石华加油站" (one character from
    中国石化). Use the ART brand **中石华加油站** and a second real-word parody (e.g. 申油加油站); the
    three charge bays "SKY 闪充站" → **申城闪充** + location (e.g. 申城闪充·西藏路站) per ART §7 / SPEC §3.
    Verify: `grep -c '石由\|中国石华\|SKY 闪充' data/city/city.json` = 0.

11. **map.png (lead note 3) is not readable at a glance.** At the 1280 px downscale no route, sky-lane
    or pad label can be read; routes are drawn as straight chords between checkpoints (they cut across
    lots, the river edge and the Nanpu circle — `map_crops.jpg` panels 1 and 3); dragon labels overlap.
    Do: draw each route along its driven path (the `segments` centre-lines between checkpoints, offset to
    the driven side), arrowheads every 500 m, numbered checkpoint discs, a chequered grid marker,
    `title (km)`; labels ≥ 20 px at 2400 px with a dark halo and collision-avoiding placement (leader
    lines); add 3× inset panels of the dragon interchange (ramps coloured by level L2/L3/L4/L5, arrows)
    and the Nanpu spiral; keep the legend off the map area. Verify: `sips -Z 1280` copy readable.

12. **profiles.png is still unreadable** (`profiles_1280.jpg`): rows ≈ 70 px for 0–50 m (1.4 px/m), the
    L2–L5 dashed lines on every row swamp the curves, the title overlaps row 1, y labels overlap. Do:
    ≥ 140 px per row, per-row y range 0…max+5 m with a 5 m grid, level lines only on the dragon rows,
    names in a 220 px left gutter, red where grade > limit or kink > 0.5 %/10 m, ticks at attaches;
    split into profiles_1.png / profiles_2.png if taller than 2400 px. Verify: readable at 1280 px.

13. **Code rules** (worker rules: files ≤ 400 lines, Python functions ≤ 60 lines, no dead code).
    - Over 400 lines: city_rules.py 500, city_marks.py 481, city_grid.py 459, city_blocks.py 434,
      citylib.py 428 — split by whole functions, as a separate first step.
    - Over 60 lines: render_map.draw_map 133, city_ramps.surface_ramps 121,
      city_rules_graph.build_lane_graph 117, city_rules_routes.check_sky_lanes 111,
      city_blocks.special_blocks 79, city_marks.build_routes 71, city_junctions.build_junctions 63.
    - Never referenced (`codescan.py`, 45): citylib TAU (r1 asked), COMPACT_KEYS, bbox, grade_series,
      segment_segment_distance, project_polyline, polyline_distance; city_geom arc2d, unit2d, pchip,
      spiral2d, circle_tangent, grade_profile, smooth_path; city_ramps make_ramp, _s_at_point, _ray_road,
      _ray_line, _mid_dir, ELEV_DIR; dragon RAMP_R, RIGHT_R, DECK_DEPTH, turn_sign, _arc; city_marks
      BUND_SPAWN, _road, _densify, SPACING_MIN, SPACING_MAX, route_length; city_snap cut_by_arterials,
      street_crossings; city_blocks BUND_SETBACK, _frontage_lots; city_profile SPIRAL_GRADE,
      PREFER_GRADE; city_roads _flare_points; city_grid _rot; city_rules_graph build_lane_graph,
      _reachable (→ use them, 4c). Delete or use; the brief's citylib API (edge_polylines,
      offset_polygon, polygons_overlap, polyline_offset) stays and gets used by the lots/rules.
    - Inline numbers in rules → named constants: `_junction_at(radius=40.0)`, `check_clearance`
      `+ 40.0`, `check_coverage` `20.0` / `0.90`, `check_sky_lanes` `60.0`.
    Verify: `wc -l tools/city/*.py` ≤ 400 each; `codescan.py` → 0 unreferenced names.

14. **Honest status and notes.** status/result say the left turns pass "116–141 m from the pillar axis"
    (data: 4.2 m — stale), that three sky lanes pass "300 m of straight run-up" (false, item 8), that the
    dead ends "are listed in the map's notes" (the list is empty), and present PASSes from hollow rules
    (4c–4h). Do: paste the validator output and my scripts' summary lines verbatim; list every
    remaining failure; `## Requests`: the Xizang/Chongqing decision (item 3, with the weave table), the
    pillar note for the rebuilt geometry, the drivable length (SHOULD 1).

## SHOULD-FIX
1. **Drivable length**: 180.5 km of road / **452.2 km of lanes** vs the brief's "expect 60–120 km of
   lanes". The 120–220 m spacing rule alone gives > 250 km of lanes on ~10.5 km² of land, so the brief
   is internally inconsistent — print km per district (D6 21.2 km, D7 18.1, D3b 17.1, D4 16.2 of
   lattice) and ask the lead whether to thin D3b/D6 to the 220 m bound. Today the world builds in
   49.5 s (8831 lanes, furniture 11.2 s).
2. Noise walls unchanged since r1: `yanan_elevated` [1500, 2100] runs past its 1891 m end, none on
   `ns_elevated` / `inner_ring` → derive from adjacent residential/shikumen lots.
3. N–S inside the interchange 2+2 on L5 (§1.3) — still 3+3.
4. `nanpu_spiral_lower` turns 225° (brief: ¾ turn = 270°); upper loop 340° (one full turn).
5. `toll_west` size [160, 60]: check §7.2 (a 16-booth plaza is ~80 m across).
6. After item 5, signals only where arterials meet; shikumen (D4) lattice crossings without signals.

## Verified OK
- **Determinism**: scratch rebuild (copy of tools/city + map_layout_v1.json in
  tmp/review/city_layout/r2/build, deleted after) → MD5 `72a7fe91c09dc3c11705e22df8a675e9`, identical to
  data/city/city.json and to the status claim; build 12.5 s; JSON 3.02 MB (< 5 MB).
- **C-INT1 (lead) — data satisfied**: player spawn (−114.4, 0, −250.9, 165.1) is 0.04 m from the inner
  SB lane centre of the Bund in the consumer lane model, heading error 0.1°; police spawns 0.02 / 0.04 m;
  all 5 route grids on a lane centre. (Rule coverage: see 4g.)
- **Lead note 2 — data nearly satisfied**: with a true polygon test only `plaza_poi_charge_bund` is
  under a deck (Yan'an, Xizang/Chongqing ramps); the pillar and Nanpu tower plazas are printed as
  exemptions. The rule itself is vertex-only (4d).
- Key levels: Yan'an Y 9.0 at the pillar (flat s 600–800), N–S Y 31.0 at 2.8 m from the axis, left-turn
  ramps 4.2 m from the axis at 16.5 / 23.9; tunnel lowest Y −28.0, median 7.5 m (bores 15 m apart),
  max grade 4.72 %.
- Grades: 1 failure left (was 9); spawns, roadblocks (on their roads at road height: block_yanan Y 6.1,
  block_ns 18.9, block_spiral 26.2), hiding spots (under the Yan'an/N–S/Inner Ring decks, inside the
  tunnel bore), police assets, POI counts (toll 1, gas 2, charge 3, police 2, hiding 4, roadblock 4,
  landmark 14).
- Landmark plazas now hold the full footprints with real heights (OPT 468, Jin Mao 420.5, SWFC 492,
  Shanghai Tower 632, Nanpu towers 147, pillar 29.4, Bund 50–90).
- District grain per lead note 1: D1/D2 follow the Bund, D3 +10°, D4 −10°, D5 +20°, D6 +40°, D7 along
  Century Ave (20°/110°), D9 0°; D4 spacing 108–114 m (90–140 ✓); dead ends 72 → 15; garbled sign
  names gone (`grep -c '匧\|薯'` = 0).
- Nanpu: upper loop R 152.0 (perfect circle, centre (1021, 1125)), lower loop mean R 105 concentric
  within 9 m; bridge deck 42.5–45.5; `nanpu_cables` threads the tower portal at Y 45–60;
  `century_canyon` flies Y 27–70 between the towers; N₂ rings every 250 m; pitch ≤ 19°.
- Cross-sections: Bund 3+3 × 3.35 m + 6 m sidewalk; Waibaidu 2+1 × 3.73 m + 3 m sidewalks;
  planters/median double lamps/#5A3DFF soffit on the decks, spiral #3D7BFF.
- Nanjing Rd drivable only x −350…−146 (pedestrian west of −350 ✓).
- Ownership: all 116 Write/Edit calls of the round inside tools/city/, data/city/city.json,
  status/city_layout.md, tmp/city_layout/ (cleaned); one transient tmp_val.txt in the repo root
  (removed — use tmp/city_layout/).
- Main-line plan matches the dossier sketch (`captures/review/city_layout/r2/sketch_vs_map_r2.jpg`).

## Evidence
- `python3 tools/city/validate.py data/city/city.json` (105 s) → exit 1, `16 rules, 9 failed`:
  `FAIL grades … nanpu_spiral_upper 4.02 % at 609 m`; `FAIL vertical curvature … 3 failing` (artefacts,
  4b); `FAIL deck clearance >= 5.5 m: 526 failing … and 486 more`; `FAIL ramps attach … 7 failing`
  (nanpu_spiral_lower 35.0°, ramp_chongqing_off 13.2/10.5°, ramp_xizang_off_wb 11.0°, …); `FAIL no
  dead ends: 15`; `FAIL blocks clear of the roads: 50 … and 10 more`; `FAIL blocks clear of the decks:
  2`; `FAIL route checkpoints: grand_loop 1092 m, bund_sprint 656 m`; `FAIL sky lanes: huangpu_jump 34 m
  over a lot of 25 m, bund_riverside 41 m over 34 m`; `drivable: 180.5 km of road (452.2 km of lanes)`.
- Clearance grouped by pair (`tmp/review/city_layout/r2/clear_groups.py` → `clear_groups.txt`): 526
  samples in 59 pairs; ramp×ramp 319, ramp×elevated 105, surface×surface 52 (century_ave×st_d7_ns_6
  41 samples at 0.0 m), ramp×surface 40, surface×tunnel 6 (1.6 m at (−376, 187)).
- `dragon_check.py` → `8 of 8 ramps fail` (lines quoted in item 2); `attach_dir.py` → every ramp
  "WITH points", lateral ±0.00–0.01 m, side right.
- `python3 -B -c "import sys; sys.path.insert(0,'tools/city'); import citylib, city_rules_graph as g;
  g.build_lane_graph(citylib.load_json('data/city/city.json'))"` → `NameError: name '_angle_diff' is not
  defined` (city_rules_graph.py:229).
- `junctions.py` → `junctions 1841 | duplicate ids 213 | exact duplicate records 207 | record pairs
  < 15 m apart 2933`; `junctions listing a road > 1 m off grade: 507 {ramp 324, elevated 144, bridge 18,
  tunnel 21}`.
- `blocks.py` → `LOTS UNDER / < 2 m FROM A DECK (non-exempt): 3 pairs, 1 lots`, `LOTS < 1 m FROM A
  GROUND ROAD EDGE: 77 pairs, 38 lots`; `coverage.py` → `inside a lot: 72.5 %; empty 2.19 km2`;
  `stairs.py` → D3/D3b/D4/D5/D6/D6c/D7b/D8 100 % axis-aligned edge length, D6 mean 40.8 vertices;
  winding: 621/621 lots clockwise (test_city.json: 3/3 counter-clockwise).
- `routes.py` (consumer lane model) → player/police/grids ok; FAIL grand_loop cp06/cp07 (1.89/1.90 m),
  cp35 (71.3°), elevated_sprint cp02/03/06/07/08 (1.83–1.90 m), cp11 (86.3°), river_loop cp28 (71.3°).
  `pads.py` → run-up 100 / 48 / 301 (19.5°) / 300 (2.2° ✓) / 302 (17.1°) m; pad→lane start 10.0 / 0.0
  / 27.4 / 0.0 / 10.0 m.
- `grades.py` → `GRADE FAILS: 1`, `CURVATURE FAILS: 3` (nanpu_pudong_loop 0.99, ramp_xizang_off 0.50,
  ramp_xizang_on 0.60); control-point 10 m window (inline) → ns_elevated 0.60, nanpu_spiral_upper 0.56,
  yanan_tunnel 0.56, yanan_elevated 0.55, ramp_xizang_off_wb 0.51 %/10 m.
- `dupes.py` → `1.9 km in 32 pairs` (st_d7_ns_6 348 m inside century_ave …); `codescan.py` → 7
  functions > 60 lines, 45 unreferenced names.
- Godot: `tools/godot.sh shot --out=review_city_layout_r2 --env-only --stub=traffic,police
  --cams=… --times=2.5` → `CAPTURE errors=0`, world `built in 49.52 s (8831 lanes, 5 routes)` with the
  route warnings quoted in item 8 (the roads unit was re-exporting tiles at the time: 300+ "not imported
  yet" warnings, and static cams in main.tscn are overridden by the chase cam, so the 3 frames show the
  spawn only: `captures/review_city_layout_r2_{dragon,xizang,t2_5}.jpg`, sheet
  `captures/review/city_layout/r2/godot_sheet.jpg` — the car stands on the Bund SB lane ✓).
  `tools/godot.sh shot --scene=res://assets/city/roads/preview_roads.tscn --out=review_city_layout_r2_roads
  --cams=dragon…;xizang…;spiral…` → `CAPTURE errors=0`; sheet `captures/review/city_layout/r2/roads_sheet.jpg`
  (dragon tiles = a knot of decks crossing at all angles; the spiral reads as two rings).
- Plan diagnostics: `captures/review/city_layout/r2/diag_dragon2.jpg` (each dragon ramp coloured, arrows
  = point direction: loops, hairpins, every ramp from/to the EB/SB side), `map_1280.jpg`,
  `map_crops.jpg` (Bund, dragon, Nanpu, Lujiazui at native scale: staircase lots, chord routes),
  `profiles_1280.jpg`, `sketch_vs_map_r2.jpg` (dossier `ref/shanghai/build/map_sketch_v1.png` vs map.png).
- git status: only `data/city/city.json`, `tools/city/**`, `status/city_layout.md` changed by this unit.
