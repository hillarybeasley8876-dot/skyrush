# Job: repair the five sky lanes (the flight corridors of the "飞天" feature)

Read `briefs/improve/_map-common.md` first: how the generator is run, how `one_rule.py` and the gate work, what you may touch.

## Goal
All five sky lanes must pass the validator rule **"sky lanes"** (launch pad on a lane centre with 300 m of straight run-up, the
lane starting exactly at the pad and heading the way the pad points, a gentle pitch, 10 m clear of every building, landing over a
drivable lane) and keep their character (the shape check below). The game's flight mode (hop, hover, rails flight in a 14 x 8 m
tube) uses these lanes: a lane that starts 21 m away from its pad cannot be entered.

## Evidence (current generator output: `python tools/city/one_rule.py data/city/city.json "sky lanes"`)
```
huangpu_jump:   only 200 m of run-up behind the pad | the run-up turns 4.8 deg over 300 m | the lane starts 21.1 m from the pad
                | 32 m over a lot of 36 m at (-339, 218)
dragon_stack:   the lane starts 3.3 m from the pad
century_canyon: the run-up turns 8.9 deg over 300 m | the lane starts 9.1 m from the pad | the first segment heads 110 deg, the pad 121
bund_riverside: the run-up turns 12.1 deg over 300 m | the first segment heads 356 deg, the pad 168 | 42 m over a lot of 160 m at (431, -739)
nanpu_cables:   (passes)
```
11 failing items. The rules are in `tools/city/city_rules_routes.py` (`_pad_fails`, `_run_up_fails`, `_lane_fails`, `_clearance_fails`): read
them, they are short. Constants: run-up 300 m with at most 3 deg of turn, pad within 0.5 m of a lane centre and 10 deg of its heading,
the lane's first point within 1 m of the pad, no 60 m+ segment steeper than 20 deg, lane at least 10 m above the top of every lot it flies over.

## What the code does (`tools/city/city_marks.py` is the only file you own)
`build_sky_lanes(by_id, blocks)` defines five lanes with a local helper `make(...)`:
road + station `s_pad` + direction + lane index choose the **pad**; `waypoints` are plan positions the lane flies through; an end road/station
is the landing. `_lane_profile` computes the height at each plan point: climb from the pad, cruise, descend, never below `lot height + 10`,
then a forward and a backward pass enforce a maximum slope of 0.34. `straight_runup(road, direction, lo, hi)` finds the station with the straightest
300 m approach on a road (it exists and is **not used** by `build_sky_lanes`).
Read `_nearest_s`, `_lane_at` and `_height_at` too. `_nearest_s` is also used by `city_marks_routes.py` (another job): do not change its behaviour.

## Likely causes (verify with probes, do not assume)
- **Pad stations are hand-picked** (for example `huangpu_jump` pad at 200 m on a 200+ m road): a pad needs 300 m of road behind it.
  Use `straight_runup` over the road's usable range, or pick another road/direction for the pad.
- **The lane's first point is not the pad**: the backward slope pass can raise `y[0]` above the pad height when a tall building lies shortly after the
  pad; the start must stay exactly at the pad, so the pad has to be where a 0.34 climb can reach the height needed, or the first waypoints must move.
- **The first waypoint is not ahead of the pad**: `bund_riverside` leaves at 356 deg while its pad faces 168 deg (it flies backwards). The first
  leg must follow the pad heading (a lead-in point 60-120 m ahead along the pad heading), then curve toward the waypoints.
- **The lane is only checked at its plan points**, but the rule samples every 5 m along each segment: a long segment can pass over a tall lot between two
  points. Densify the plan (a point at least every 10 m) before computing the profile.
- **Tall lots on the way** (160 m tower at (431, -739)): route the waypoints around the tower's footprint instead of lifting the whole lane; `blocks`
  gives every lot polygon and height (`_block_index`, `_height_at`).

## Plan to follow
1. Generate to your scratch path; list the failing items with `one_rule.py`.
2. Write a probe that, per lane, prints: pad (x, y, z, heading), run-up straightness found by `straight_runup`, first-segment heading, `y[0]` versus the pad
   height, and the lots under the lane that are too high. It shows which failure belongs to which cause.
3. Fix one lane at a time (they are independent). After each lane re-run `one_rule.py` and the shape check.
4. When the rule is clean, run the gate and update `status/improve/city-skylanes.md`.

## Acceptance (the runner executes these itself, in order)
1. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-skylanes/city.json` succeeds.
2. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-skylanes/city.json --baseline tools/city/rules_baseline.json --target "sky lanes"` prints `ACCEPT_RULES OK`.
3. `python tools/city/check_skylanes_shape.py F:/dev/skyrush-out/tmp/city-skylanes/city.json` prints `SKYLANES_SHAPE OK`: the same five lane ids, each at least
   300 m long, the first point exactly at the pad, `huangpu_jump` and `bund_riverside` fly at least 200 m over the Huangpu and land on the far bank, every lane keeps an N2 ring.

## Pitfalls
- Shortening a lane to a stub, deleting a lane, or removing the tall buildings from the blocks list to pass the clearance: the shape check and the lead's diff review catch them.
- Raising the whole lane to 200 m to clear towers: the lane must stay a gentle corridor (cruise 60-120 m, pitch limit 20 deg); go around towers.
- Changing the validator constants or `_nearest_s`.
- A lane that passes the rule but whose landing point is over water or a building: the rule checks the end is within 7 m of a lane and 15 m above it at most; look at it.
