# Job: make the city generator 5x faster without changing its output by a single byte

## Goal
`python tools/city/build_city.py` takes about 300 seconds. 95 % of that time is wasted in one place. Make the generator
finish in 90 seconds or less while producing a `city.json` that is **byte-for-byte identical** to today's output.

## Why it matters
Every later map-fixing job runs this generator after each change. At 5 minutes per run, the whole improvement pass crawls.

## Evidence (a real profile of the current code, already measured)
Total 587 s under the profiler (298 s without it). Where it goes:

| function | calls | cumulative |
|---|---|---|
| `city_grid.build_streets` → `_district_lattice` → `_cut` | 247 | 560 s |
| `city_corridor.inside_corridor` | 34 298 | 560 s |
| `city_corridor._nearest` | 894 074 | 560 s |
| `city_corridor._point_seg_distance` | **396 290 111** | 384 s |

Everything else in the generator together is under 30 s. So the whole job is `city_corridor.py`.

## What the slow code does (read `tools/city/city_corridor.py`, about 200 lines)
- A *corridor* is a dict `{"points": [(x, z), ...], "half": metres, ...}`: an arterial road's centre-line polyline plus the half-width of the strip around it that lattice streets must not enter.
- `inside_corridor(point, corridors)` walks every corridor in order and returns `(entry, nearest_point)` for the **first** corridor whose polyline is closer than `entry["half"]` to `point`, otherwise `(None, None)`.
- For each corridor it calls `_nearest(points, point)`, which measures the distance to **every segment** of the polyline. Arterials have hundreds of segments and there are about 26 corridors, so each point costs thousands of segment-distance calculations. `trim()` calls this for every 4 m sample of every street.

## The idea (you decide the details)
Most corridors are nowhere near a given point, and within a corridor most segments are nowhere near it.
- **Level 1 (cheap, exact):** for each corridor remember a bounding box of its points grown by `half`. If the point is outside that box, the distance is certainly `>= half`, so the corridor cannot match: skip it without touching its segments.
- **Level 2 (bigger win):** for each corridor build a grid of its segments (bucket the segments into square cells, for example 50 m). To test a point, only measure segments in cells within `half` of the point.

Results must stay **exactly** the same, which has traps:
- `inside_corridor` returns the first corridor in list order that matches: keep that order.
- Within a corridor `_nearest` keeps the first segment that reaches the minimum (it uses `d < best`, strictly). If you only visit candidate segments, visit them in their original order so ties resolve identically.
- The returned point must be computed with the same arithmetic as today. Do not "simplify" the maths.
- A corridor with no candidate segment within `half` simply does not match.
- Other code may call `_nearest` directly (for example `dogleg`). Leave `_nearest` itself working exactly as before and add the fast path next to it.

Where to cache the index: the corridor dicts are created elsewhere (`city_grid.py`, read-only for you). Do not change their contents in a way that can leak into the output; a module-level cache keyed by `id(entry["points"])`, or private keys that are never written to JSON, are both fine. Think about what happens if the same list object is mutated later (check how `city_grid.py` builds and uses `corridors`).

## Files you own (the only files you may edit or create)
- `tools/city/city_corridor.py`
- `tools/city/city_corridor_index.py` (optional new helper module; keep each file under 400 lines)
- `tools/city/selftest_corridor.py` (optional new test)
- `status/improve/city-perf-corridor.md` (your checkpoint)

Read-only, but read them: `tools/city/city_grid.py` (callers of `trim` / `inside_corridor` / `dogleg`), `tools/city/build_city.py`.
Do NOT edit `build_city.py`, `validate.py` or any `city_rules*.py`.

## Plan to follow
1. Read `city_corridor.py` completely, then find every caller: `grep -n "inside_corridor\|_nearest\|trim(\|dogleg(" tools/city/*.py`.
2. Write your plan into `status/improve/city-perf-corridor.md` with the verification command for each step.
3. **Build a fast equality test first** (do not use the 5-minute generator as your inner loop): create `tools/city/selftest_corridor.py` that
   (a) copies today's `inside_corridor` + `_nearest` + `_point_seg_distance` verbatim into the test as the *reference*,
   (b) builds 6 or more realistic corridors (random polylines of 50 to 500 segments with different `half` values, some crossing, some far apart),
   (c) tests 50 000 random points including points exactly on the polyline, on vertices, and near corridor borders,
   (d) requires `inside_corridor(point, corridors)` of your new code to equal the reference result **exactly** (same entry object, same point tuple), and prints `OK` or the first mismatch.
   Run it before and after your change.
4. Implement Level 1, run the self-test. Then Level 2, run the self-test again.
5. Run the real generator once to a scratch file and time it (see Acceptance). Fix whatever differs.
6. Update your status file, then report.

## Acceptance (the runner executes these itself; both must pass)
1. **Speed**: `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-perf-corridor/city.json` finishes in at most 90 seconds (the runner measures it).
2. **Identical output**: the sha256 of that file must equal
   `5f53361303dc4160c012ddb28d4dcdd55462195551a2f99adb806f81fe149fc0`.
   If it differs by even one byte your change altered behaviour: find where (compare against the reference output with a diff tool of your own) and fix it.

## Pitfalls
- "Faster" by dropping samples, loosening `half`, rounding, reordering corridors, or caching results across different inputs: all change the output and fail acceptance 2.
- Using `numpy` or any new dependency (not allowed; also changes float results).
- Editing `build_city.py`/`city_grid.py` to call a different function: not allowed, they are not yours.
- Running the full generator after every small edit: each run is minutes. Use the self-test for the inner loop; run the generator only at the end.
- A cache that is built once but the corridor list later changes (different `half`, different points): make sure the key/validation cannot return a stale index.
