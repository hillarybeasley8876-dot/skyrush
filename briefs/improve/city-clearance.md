# Job: repair 22 of the 25 deck clearance violations (Nanpu streets, Lujiazui, the Puxi elevated landing)

Python map generator (`tools/city/`). No Godot, no Blender. Your build takes 25 to 40 seconds, the rule gate about 90 seconds.

Read `briefs/improve/_map-common.md` first: how the generator is run, how `one_rule.py` and the gate work, what you may touch.

## Goal
The rule "deck clearance >= 5.5 m" lists **25 failing items** on the committed `data/city/city.json`: places where a road passes under another road with less headroom than a car needs (a ramp 1.2 m above a street, a street crossing a shallow tunnel). In the game the cars drive through the upper deck.
A research pass (read-only, done by the lead, nothing was committed) found a package of small changes that removes 22 of them without breaking any other rule. Your job is to **apply it as real source edits, one step at a time, and prove each step with the numbers below**. The remaining 3 items (a group around the shallow Puxi tunnel mouth) stay for a later job: do not try to fix them.

The research left its working files in `F:/dev/_scratch/clr_research/` (read-only for you; do not copy the monkey-patching style: edit the real generator). Useful ones: `exps.py` (the exact patches as code), `exp_common.py` (`trim_under_decks`), `clr.py` (a clearance checker), `exp_<name>.json` (cities built with a patch alone).

## Your five steps (each one ends with a build and a count; stop and report if a count is not what is written here)
Count with `python tools/city/one_rule.py <city.json> "deck clearance"` (first line: `FAIL deck clearance >= 5.5 m: N failing`). Build with `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-clearance/city.json`.

**Step 1 - E: the lower Nanpu loop climbs a little earlier.** `tools/city/city_roads.py`, function `nanpu_spiral_lower()`: its `Road(...)` has the anchors `[("start", 0.0, 0.0), ("end", p[1], 0.0)]`. Insert between them the anchor `("s", 330.0, 8.2, 0.0265)` (station 330 m, height 8.2 m, grade 2.65 %). Effect alone: the street `st_d7b_ew_10` (2 items) gets 8.18 m of headroom. Expected count after this step alone: **23**. The grade of the ramp may rise to 3.31 % (the limit is 4 %); `accept_rules` shows if a grade or curvature item appears.

**Step 2 - F: trim the streets under the Nanpu ramps.** Streets cannot be lowered, and the two ramps cannot be raised, so the lattice streets are cut where a ramp passes too low over them.
- New file `tools/city/city_trim.py` with the function `trim_under_decks(streets, main_roads, only_decks)`. The reference implementation is `trim_under_decks` in `F:/dev/_scratch/clr_research/exp_common.py` (read it completely; it cuts a street at every station that a deck point within the rule's reach (street width + deck width)/2 passes over with a gap of 1.0 m up to `5.5 + deck depth - 0.05` m, plus 2 stations either side, keeps the pieces of 25 m or more, the first piece keeps the id, the next pieces get the id plus `b`, `bb`, ...). Port it, with a doc comment, without the verbose prints (one line per cut street to stderr is fine).
- Hook: at the END of `city_grid.build_streets(main_roads)`, after the snapping and the dead-end repair (earlier hooks are undone by `snap_end`): `streets = city_trim.trim_under_decks(streets, main_roads, only_decks=("nanpu_spiral_lower", "nanpu_pudong_loop"))`. Only these two decks: a general trim would also remove `st_d6b_ns_3`, which the rule exempts.
- Expected effect alone: the streets `st_d7b_ns_4` (402 m -> pieces 56 + 306 m), `st_d8_ns_7` (573 -> 132 + 403) and `st_d8_ew_15` (433 -> 353) are cut; count alone **17**. After step 1 and step 2 together: **17** (the `st_d7b_ew_10` items are fixed by both). The network must not shrink: `check_network_size.py`.

**Step 3 - C: the Lujiazui ring road moves 3 m.** `tools/city/city_roads_east.py`, function `lujiazui_ring_rd()`: in `plan`, the first point `(727.6, -498.9)`, the last point `(727.6, -498.9)` and the point `(707.2, -412.2)` get +3.0 in x (`(730.6, -498.9)` twice and `(710.2, -412.2)`). Closed loop: first and last stay equal. Count alone: **24** (-1: the ring road no longer grazes the tunnel mouth).

**Step 4 - D: the Lujiazui West Rd crosses the tunnel further west.** `tools/city/city_roads_east.py`, function `lujiazui_w_rd()`: the plan point `(600.0, -480.0)` becomes `(540.0, -480.0)`. At the new crossing the tunnel is deeper (6.28 m of cover against the 6.0 m needed). Count alone: **23** (-2). Side effects you must handle:
- about 14 lattice streets change, `st_d7_ns_21` disappears and `st_link_73` appears (that is fine);
- `tools/city/city_marks.py`, table `SKY_LANES`: the row `"century_canyon"` has `"st_d7_ns_16"` as its pad street; it must become `"st_d7_ns_15"` (otherwise three sky lane items appear). The rows `huangpu_jump` and `bund_riverside` land on `lujiazui_w_rd` at stations 400 and 500: check that `selftest_skylanes.py` and `check_skylanes_shape.py` stay green; if a landing station is wrong now, adjust that row's station and say so in the status file.

**Step 5 - A: the Yan'an elevated road lands on Yan'an Rd earlier (the big one: -11).** `tools/city/city_roads.py`, function `yanan_elevated()`:
- the `plan` tail `(-560.0, 185.0), (-460.0, 165.0), (-380.0, 152.0), (-320.0, 146.0), (-287.0, 144.0)` is replaced by `(-580.0, 229.0), (-515.66, 219.57)` (so the plan ends `... (-1040.0, 581.0), (-666.0, 235.0), (-580.0, 229.0), (-515.66, 219.57)`);
- the anchor `("p", -666.0, 235.0, 10.0, 0.0)` is replaced by `("near", -515.66, 219.57, -312.0, 10.0, 0.0)` (10 m high 312 m before the end point; 312 m is the shortest legal descent: 311 fails), the `("end", 0.0, 0.0)` anchor stays;
- `tools/city/build_city.py`, `CONNECTIONS`: the entry `("yanan_elevated", "attach_end", "yanan_rd_surface", None, (-287.0, 144.0))` gets the target `(-515.66, 219.57)`;
- update the notes of the road ("The east end descends to grade at (-515.66, 219.57) over 312 m").
Count alone: **14** (-11: every item where `yanan_elevated` is the upper road). Risks that `accept_rules` / the checks show: the margin to Xizang Rd is only +0.17 m; a ramp `ramp_xizang_on` may appear for other alignments (do not change the numbers above to "improve" them); four dragon ramps move by under 1 m (the dragon selftest must stay green).

**Expected count after all five steps: 3.** Write the count after every step into `status/improve/city-clearance.md`. The three items that stay are crossings of surface roads (`yanan_rd_surface`, `st_henan_rd`) over the shallow start of `yanan_tunnel` near (-395..-390, 190..210).

## Files you own
`tools/city/city_roads.py`, `tools/city/city_roads_east.py`, `tools/city/city_marks.py`, `tools/city/city_grid.py`, `tools/city/city_trim.py` (new), `tools/city/build_city.py` and, if you add one, `tools/city/selftest_trim.py`. Everything else is read-only (the rules, the checkers, `rules_baseline.json`).

## Acceptance (the runner executes these itself, in order)
1. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-clearance/city.json` succeeds.
2. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-clearance/city.json --baseline tools/city/rules_baseline.json --target "deck clearance" --max-target 3` prints `ACCEPT_RULES OK` (at most 3 clearance items, no other rule worse than the baseline).
3. `python tools/city/check_routes_shape.py F:/dev/skyrush-out/tmp/city-clearance/city.json` prints `ROUTES_SHAPE OK` and `python tools/city/check_network_size.py F:/dev/skyrush-out/tmp/city-clearance/city.json` prints `NETWORK_SIZE OK`.
4. `python tools/city/check_skylanes_shape.py F:/dev/skyrush-out/tmp/city-clearance/city.json` prints `SKYLANES_SHAPE OK` (read its last line) and `python tools/city/selftest_skylanes.py F:/dev/skyrush-out/tmp/city-clearance/city.json` has no `FAIL` line.
5. `python tools/city/check_lots_kept.py F:/dev/skyrush-out/tmp/city-clearance/city.json F:/dev/skyrush-out/baselines/lots_cur.json --keep 0.0 --total 0.99` prints `LOTS_KEPT OK` (a road that moves re-forms and renumbers the lots around it: only the total area, the number of vanished lots, the winding and the minimum size are judged).
6. `python tools/city/selftest_attach.py F:/dev/skyrush-out/tmp/city-clearance/city.json` and `python tools/city/selftest_dragon.py F:/dev/skyrush-out/tmp/city-clearance/city.json` print no `FAIL` and `selftest_dragon: 0 case(s) wrong`.

## Pitfalls
- Changing a number of the package "a bit" to make a margin bigger: every number was found by search; the margins are thin by design. If a step does not give its count, report which items remain; do not tune.
- Doing step 5 before steps 1 to 4: the order above is the order of the least risk.
- Hooking the trim earlier than the end of `build_streets` (the snapper re-extends the cut ends back across the ramp).
- Applying the trim to all decks.
- Editing the rules, the checkers or the baseline.
