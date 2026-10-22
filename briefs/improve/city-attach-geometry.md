# Job: fix the ramp attach geometry the validator still rejects (Nanpu spiral, Pudong loop, one dragon ramp)

Read `briefs/improve/_map-common.md` first: how the generator is run, how `one_rule.py` and the gate work, what you may touch.

## Goal
The validator rule **"ramps attach to their parent"** must pass (4 items today), and the rule **"vertical curvature"** must pass (1 item today).
These are real geometry defects: a car driving the Nanpu lower loop meets the upper loop at a 35 degree kink, in the middle of its median.

## Evidence (`python tools/city/one_rule.py data/city/city.json "ramps attach"` and `... "vertical curvature"`)
```
nanpu_spiral_lower attach_end: ends on the centre-line of the two-way parent nanpu_spiral_upper, not on its edge
nanpu_spiral_lower attach_end: 35.0 deg tangent error
nanpu_pudong_loop  attach_end:  9.0 deg tangent error      (tolerance 8)
ramp_l3_wb_sb      attach_end:  8.6 deg tangent error
nanpu_pudong_loop: 1.059 % per 10 m at 1610 m              (vertical curvature, limit 0.5 %)
```

## How a ramp must attach (the design rule, `tools/city/city_attach.py`: read its docstring and `attach_point`)
A ramp never meets a **two-way** parent on its centre-line. It meets the **edge of the carriageway it serves**:
`lateral = direction * (asphalt_half(parent) + asphalt_half(ramp))`, measured to the right of the parent's direction of travel (direction +1 = the ramp runs
with the parent's points, side "right"; -1 = against them, side "left"). At that point the ramp's heading must equal the parent's travel direction within 8 degrees
and the heights must match within 5 cm. A ramp may also end **on the centre-line** (end to end) when the parent is one-way (`lanes_back == 0`) or when the attach is at the very
start or end of the parent. The validator rule is `check_attaches` in `city_rules_attach.py` (read it, it is short, it is read-only for you).

## What is wrong in each case
1. **`nanpu_spiral_lower`** (`city_roads.py`, function `nanpu_spiral_lower`): a one-way 2-lane ramp on a concentric circle (R 100) that is blended into the **centre-line** of the
   two-way upper loop (`nanpu_spiral_upper`, R 150, 2+2 lanes, median 1.0): `merge = spiral_point(SPIRAL_C, SP_UPPER_R, 290.0)` and `tangent = [...]`.
   It should instead end on the **inner carriageway edge** of the upper loop (use `city_attach.asphalt_half` for both roads to get the radius to aim for, and note that the
   loop runs counter-clockwise so "left of travel" is toward the circle centre), with the ramp's end heading equal to the loop's travel direction there. The height at the merge
   (`merge_y`) and the grade limit (`max_grade=0.038`) must stay valid; the CONNECTIONS entry for this ramp is in `build_city.py` (read-only, shows the intended target).
   Look at `blend_path` (in `city_geom.py`/`citylib`) to see how it builds the curve from a position and tangent to another.
2. **`nanpu_pudong_loop`** (`city_roads.py`): the end blends into `pudong_south_rd` at (1690, 1280) with a fixed tangent `(0, -1)` (north). `pudong_south_rd` does not run exactly north
   there, hence 9 degrees. Use the parent's real heading at that point (compute it from the road's points the way the validator does: over 10 m).
   The vertical-curvature item at 1610 m is where the loop's descent meets the exit curve: smooth the height profile (anchors/`max_grade`) so the grade changes by at most 0.5 % per 10 m.
3. **`ramp_l3_wb_sb`** attach_end into `ns_elevated`: 8.6 degrees against the 8 allowed (`dragon_ramps.py`, see `fix_attaches(ramp, frame)` and the ramp's anchors).
   A small adjustment of the final approach is enough; do not move the attach point (the other 7 dragon ramps pass).

## Files you own
`tools/city/city_roads.py` (only the three functions `nanpu_spiral_lower`, `nanpu_pudong_loop`, and what they call for the profile), `tools/city/dragon_ramps.py`, `tools/city/selftest_attach_geometry.py` (optional new test).
Another job works on the Nanpu **street** crossings and the dragon **clearance** at the same time in other files: do not edit `dragon.py`, `city_grid.py` or `city_ramps.py`.

## Plan
1. Generate to your scratch path. Print for the three ramps: the end point, the parent's point/heading/lateral offset there (reuse `city_attach.project`), and the heading error. Understand each number.
2. Fix `nanpu_spiral_lower` first. After each change regenerate (15 s) and run `one_rule.py "ramps attach"`.
3. Then `nanpu_pudong_loop` (tangent and curvature), then `ramp_l3_wb_sb`.
4. Run the gate with both targets. The usual regressions: "deck clearance" (a changed ramp now crosses something at the wrong height: the rule lists the pair), "grades", "key levels", "no road in the water", "blocks clear of the roads" (a ramp moved over a lot).
5. `python tools/city/selftest_attach.py data/city/city.json` must still print `selftest_attach: 0 case(s) wrong`.

## Acceptance (the runner executes these itself, in order)
1. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-attach-geometry/city.json` succeeds.
2. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-attach-geometry/city.json --baseline tools/city/rules_baseline.json --target "ramps attach" --target "vertical curvature"` prints `ACCEPT_RULES OK`
   (both rules clean, no other rule has a new failing item).
3. `python tools/city/check_network_size.py F:/dev/skyrush-out/tmp/city-attach-geometry/city.json` prints `NETWORK_SIZE OK`.
4. `python tools/city/selftest_attach.py F:/dev/skyrush-out/tmp/city-attach-geometry/city.json` prints `selftest_attach: 0 case(s) wrong`.

## Pitfalls
- Moving the attach point or the parent to make the ramp fit: the parent roads are shared by other ramps and by the key levels (Yan'an 9.0 m, N-S 31.0 m at the pillar).
- Fixing the tangent by making the last metres of the ramp a sharp bend: the validator measures the heading over 10 m, and a 1 m kink is an accident waiting to happen in the game: keep the curve smooth.
- Raising `max_grade` limits or the tolerances. The grade rule (spiral at most 4 %) is part of the design.
- Changing the roads' ids, kinds or lane counts.
