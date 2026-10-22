# Job: the dragon-pillar interchange: ramps must pass over and under each other, not through each other

Read `briefs/improve/_map-common.md` first: how the generator is run, how `one_rule.py` and the gate work, what you may touch.

## Goal
At the 龙柱 (dragon pillar) interchange of the Yan'an elevated and the N-S elevated, eight ramps (`ramp_l3_*`, `ramp_l4_*`, `ramp_rt_*`) cross each other and the viaduct. The rule **"deck clearance"** says two roads that
cross in plan must be separated vertically by 5.5 m plus the depth of the upper structure (7.1 m under a ramp of level 3/4, 7.5 m under `ramp_rt_*`, 7.3 m under `yanan_elevated`). Today **12 items of that rule fail inside the
interchange: in several places a ramp passes through another ramp or through the viaduct deck** (worst -5.2 m: a deck 5 m inside another). Make them all pass, without breaking anything else.

## Evidence (`python tools/city/one_rule.py data/city/city.json "deck clearance"`, the interchange part)
```
ramp_rt_wb_nb x ramp_l4_sb_eb:   3 samples, worst -5.2 m (need 7.1) at (-1032, 554)
ramp_l3_eb_nb x ramp_rt_eb_sb:   2 samples, worst -4.0 m (need 7.5) at (-1588, 742)
yanan_frontage_n x ramp_l4_nb_wb: 6 samples, worst -3.4 m (need 7.1) at (-1816, 701)
ramp_rt_wb_nb x ramp_l3_wb_sb:   3 samples, worst -3.2 m (need 7.1) at (-1150, 612)
yanan_elevated x ramp_rt_nb_eb: 11 samples, worst -3.2 m (need 7.5) at (-915, 469)
ramp_l4_sb_eb x ramp_rt_nb_eb:   8 samples, worst -1.9 m (need 7.5) at (-961, 522)
... and the mirrored pair of each (the same crossing seen from the other road): 12 items in all.
```
How to read an item: `<upper-or-lower road> x <other road>`: `samples` = how many 2 m samples of the first road are too close to the second one, `worst` = the smallest vertical gap found (negative = the first road is BELOW the other),
`need` = the required gap, `at (x, z)` = where. Both orders of a pair are listed; both must disappear.

## Design facts you must respect
- Frame: metres, X east, Z south, Y up. The interchange stacks: Yan'an elevated about 9 m, ramp level 3 (`ramp_l3_*`) about 16.5 m, ramp level 4 (`ramp_l4_*`) about 23.9 m, N-S elevated 31 m at the pillar (`city_rules.check_key_levels` fixes
  the key levels: Yan'an 9.0 m and N-S 31.0 m at the pillar PASS today and must keep passing). Pillar axis at (-1299, 687).
- Maximum grade 5 % (`grades` rule), vertical curvature at most 0.5 % per 10 m (`vertical curvature` rule). A ramp that must drop 22 m needs at least 440 m of length at 5 %.
- Attach rules: ramps meet their parent's carriageway EDGE at the parent's height (`ramps attach to their parent` is 0 failing today: keep it). Do not move attach points, do not change a ramp's start and end heights
  unless the attached parent has the same height there; the heights at the two ends of every ramp are fixed by the roads they join.
- Rule "key levels" and "no road in the water" and "junctions meet their roads" must stay clean; "blocks clear of the roads/decks" must not get new items.

## Where the interchange is generated (you own `tools/city/dragon.py` and `tools/city/dragon_ramps.py`)
`dragon_ramps.py`: `MOVES` lists the eight ramps (id, from-road, direction, station, to-road, direction, station, ...); `_left_plan` and `_right_plan` build the plan curves; `_road(rid, name, plan, anchors, lanes, attach_start, attach_end, notes)` creates the road with
**anchors** (height control points: `("start", y, ...)`, `("p", x, z, y, ...)`, `("end", y, ...)`) from which `city_road.Road.build()` computes the height profile under the grade limit. `dragon.py`: the frame, pillar and levels.
Read `city_road.py` (read-only) to see how anchors become a profile (`max_grade`, `kink` handling).

## Plan
1. Generate to your scratch path, list the 12 items. For each failing pair, write a probe that prints: the plan crossing point(s), the station along both roads, both heights there, the gap, and which road is meant to be on top.
   Draw conclusions: is the ramp ABOVE or BELOW where it should be? Is it merely not high/low enough (need +4 m), or does it cross at the wrong place?
2. Decide per ramp which levers exist: (a) move height anchors (an extra `("p", x, z, y)` anchor near the crossing raises/lowers that stretch, the profile solver smooths it under the grade limit), (b) lengthen the ramp (larger radius, longer
   lead-in) so it has room to climb/descend, (c) change which side the ramp crosses on. Prefer (a), then (b). Keep ramps recognisable: same ids, same attach roads, same lane counts, plan changes small.
3. Fix one ramp at a time, regenerate (15 s), run `one_rule.py "deck clearance"` (6 s) and `one_rule.py "grades"`, `"vertical curvature"`, `"key levels"`, `"ramps attach"` (a second each). Keep a table in your status file of what each change did to the 12 items.
4. When all 12 are gone, run the gate (below). Update `status/improve/city-dragon-clearance.md`.

## Acceptance (the runner executes these itself, in order)
1. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-dragon-clearance/city.json`.
2. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-dragon-clearance/city.json --baseline tools/city/rules_baseline.json --target "deck clearance" --clear "ramp_(l3|l4|rt)_|yanan_frontage"` prints `ACCEPT_RULES OK`: no clearance item
   that mentions a dragon ramp or the frontage road remains, the clearance rule gains no new item, and **no other rule gets a new failing item** (grades, curvature, key levels, attach, blocks ...).
3. `python tools/city/check_network_size.py F:/dev/skyrush-out/tmp/city-dragon-clearance/city.json` prints `NETWORK_SIZE OK`.
4. `python tools/city/selftest_attach.py F:/dev/skyrush-out/tmp/city-dragon-clearance/city.json` prints `selftest_attach: 0 case(s) wrong`.

## Pitfalls
- Raising everything: clearing a crossing by lifting a ramp 8 m breaks the grade rule or the attach height. Look at the actual heights first.
- Moving the pillar, the viaduct levels, or an attach point.
- Fixing a pair by making the OTHER road of the pair fail with a third road (the rule is a whole system of crossings; run the clearance rule after every change and read the whole list).
- Raising `max_grade` or editing the rule/exemptions.
- The Nanpu streets and the tunnel portal items of the same rule are other jobs; do not try to fix them and do not make them worse.
