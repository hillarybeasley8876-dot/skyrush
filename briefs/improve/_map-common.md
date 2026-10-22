# Map jobs: what every worker on the city generator must know

## How the map is made
`python tools/city/build_city.py --out <file.json>` writes the whole map in about 15 seconds. It is deterministic: the
same code gives the same bytes. **Never hand-edit a city.json**; change the generator module that creates the thing.

| what | where |
|---|---|
| arterial roads, bridges, tunnel | `city_roads.py`, `city_roads_east.py`, `dragon.py`, `dragon_ramps.py` |
| lattice street grid, dead-end list | `city_grid.py`, `city_corridor.py` (already fast) |
| surface ramps, how a ramp meets its parent | `city_ramps.py`, `city_attach.py` |
| junctions | `city_junctions.py` |
| building lots | `city_blocks.py`, `city_raster.py`, `city_landmarks.py` |
| POIs and sky lanes | `city_marks.py` |
| routes and spawns | `city_marks_routes.py` |
| assembly | `build_city.py` (read-only for you) |
| shared helpers | `citylib.py`, `city_geom.py` (read-only unless your brief says otherwise) |

Frame: metres, X east, Z south, Y up. Heading 0 = north (-Z), 90 = east. Schema: `data/city/SCHEMA.md`.

## How the map is judged
The 17 rules of `tools/city/validate.py` (rules live in `city_rules*.py`). They are **read-only for you**: never edit a
rule, a tolerance or an exemption to make a failure go away. Fix the geometry.

Two commands you will use:

1. **Fast inner loop (seconds)**: print only the failing items of one rule.
   `python tools/city/one_rule.py <city.json> "part of the rule name"` (add `--time` for timings)
   Rule names: schema fields, grades, vertical curvature, deck clearance, no road in the water, ramps attach to their
   parent, junctions meet their roads, key levels, no dead ends, blocks clear of the roads, blocks clear of the decks,
   spawns on the lane centres, route checkpoints on the lanes, sky lanes, pois, the lots cover the land, the lots run
   counter-clockwise.
2. **The gate (about 2 minutes)**: run it when a change is ready.
   `python tools/city/accept_rules.py <city.json> --baseline tools/city/rules_baseline.json --target "<rule name>"`
   It exits 0 only if (a) the target rule has no failing item and (b) **no other rule has a failing item that the
   baseline did not have**. An item is its message with the numbers blanked, so a failure that merely moves a few
   metres is the same item, but a failure on a road that passed before is NEW and fails the gate. Read its table: the
   `new` column must be 0 everywhere except your target rule.

## Inner loop to follow
1. Generate to your scratch folder: `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/<your job id>/city.json`.
2. Look at the failing items of your rule with `one_rule.py`.
3. Find the **cause** in the generator (print what the code computes for one failing item; do not guess).
4. Change the generator module you own, regenerate, run `one_rule.py` again.
5. When your rule is clean run the gate once. If it reports a regression, find which of your changes caused it.

## Rules of the road for these jobs
- Determinism: no unseeded randomness; do not let `set`/`dict` iteration order change the output (sort when order matters).
- No new dependencies (no numpy). Python 3.10. Functions at most 60 lines, files under 400 lines.
- Fix causes, not symptoms: do not delete the thing that fails (a road, a lot, a checkpoint) unless the brief says that is the fix.
- Do not make other rules worse. If a fix cannot avoid that, still keep the gate green and explain under `## Requests`.
- Keep your edits small and local to the files you own. Another job is changing other modules at the same time.
- Print nothing new in the generator's normal output except where your brief asks (warnings go to stderr).

## What the lead will check after you pass (so do these properly)
- the diff: every changed line is explained, no leftover debug code, no commented-out blocks;
- the gate and the other acceptance commands, re-run by the lead on a clean checkout;
- the map itself, rendered or sampled where it makes sense.
