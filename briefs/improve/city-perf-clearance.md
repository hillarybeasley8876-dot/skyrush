# Job: make the deck-clearance validator rule 5x faster without changing a single result

Read `briefs/improve/_map-common.md` first (the generic rules). This job is different: it changes a validator file, and the only thing it may change is *speed*.

## Goal
`python tools/city/one_rule.py <city.json> "deck clearance" --time` takes about 83 seconds. Make it finish in **15 seconds or less** with output that is
**exactly identical** (every line, same order) to today's.

## Why
Every map job runs the validator through the gate; this rule is 80 of its 120 seconds and the jobs that fix decks and ramps will run it dozens of times.

## Where the time goes (read `check_clearance` in `tools/city/city_rules_attach.py`)
For every road, every 2 m sample `p` is compared with every other road whose centre-line is within `width/2 + 40` m (`_within(...)` index), and for each such
pair of (sample, nearby road) the code calls `_height_at(other, x, z)`, which **scans every point of the other road** to find the closest one. Arterials have
thousands of points, there are hundreds of thousands of (sample, neighbour) pairs: that is the cost.
`_gore`, `_exempt` and `citylib.road_points(road, 2.0)` / `citylib.road_width` are called per sample as well; check whether they repeat work.

## Ideas (you decide)
- Cache per road what `_height_at` needs (a sorted/grid index of its points, or the road's points as parallel lists), built once per `check_clearance` call.
- Hoist per-road values (`width`, `other_w`, `deck_depth`) out of the inner loop and memoise per road id.
- Skip a neighbour early when the plan distance already exceeds `width * 0.5 + other_w * 0.5` before computing the height.
`_height_at` returns the height of the **closest point of the other road's point list** (ties: the first one): keep that exact semantics, including ties and
the fact it uses the other road's own points and not an interpolation.

## Files you own
`tools/city/city_rules_attach.py` (only the performance of `check_clearance` and the helpers it calls), `tools/city/city_rules_index.py` (optional new helper module),
`tools/city/selftest_clearance.py` (optional new test). Do not change any rule's verdict, tolerance, exemption, message text or ordering.
`tools/city/city_rules_attach.py` also holds `check_attaches` and `check_junctions`: leave them alone.

## Plan
1. Record the reference output **before touching anything**: run `python tools/city/one_rule.py data/city/city.json "deck clearance" --max 1000 > F:/dev/skyrush-out/tmp/city-perf-clearance/reference.txt`
   (about 83 s) and also on `F:/dev/_scratch/head_check/city.json` if you like. Keep the file; it is your oracle.
2. Build a quick equality test first (`selftest_clearance.py`): load the map, run the **old** and the **new** `check_clearance` side by side on the whole map **and** on at least two
   perturbed copies (for example every elevated road raised or lowered by 1 m, and one with a ramp's points shifted 3 m sideways) and require identical lists.
   Copy the old implementation into the test as the reference. A rule that always passes in one version is the classic way to "optimise" wrongly.
3. Implement the speed-up in small steps, running the self-test after each.
4. Time it. Update `status/improve/city-perf-clearance.md`.

## Acceptance (the runner executes these itself)
1. Speed: `python tools/city/one_rule.py data/city/city.json "deck clearance" --time --max 0` shows `(<seconds> s)` of at most 15.0 for the rule.
2. Identical: `python tools/city/one_rule.py data/city/city.json "deck clearance" --max 1000` equals the stored baseline text exactly
   (`tools/city/clearance_reference.txt`, 39 failing items, created by the lead).

## Pitfalls
- Changing which pairs are examined, the 20 m dedupe key, or the order of the final list: all alter the output.
- Floating-point reordering that changes a printed value (`%.1f` boundaries): the oracle compares text.
- Caching on `id(city)` across calls with different cities, or leaving the mutable `_length` side effect out (the code writes `road["_length"]`; other code may read it).
