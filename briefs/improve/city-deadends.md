# Job: remove the dead-end streets of the map

Read `briefs/improve/_map-common.md` first: how the generator is run, how `one_rule.py` and the gate work, what you may touch.

## Goal
The validator rule **"no dead ends"** must pass: every road end is connected to something (an attach, a junction within 45 m, another road
under the end) or lies within 40 m of the map window edge. Dead-end streets are bad for an open world: traffic cars drive into them and
jam, police and rivals path-find into nothing, and the player meets roads that stop in the middle of the city.

## Evidence (`python tools/city/one_rule.py data/city/city.json "no dead ends"`: 44 items)
Almost all are lattice streets `st_d<district>_ns/ew[_n]` whose end stops in the open, plus the east end of `century_ave` at (1725, 51) and
`st_hankou_rd` at (-959, -209) and two `st_link_*` at (-518, -1157). Many ends lie on straight lines: x = 500, 850, 1500 and z = 1150, 1669 are
district lattice borders, so a street runs up to the border and the neighbouring district has no street there.

## What the code does (you own `tools/city/city_grid.py` and `tools/city/city_snap.py`)
`city_grid.build_streets(main_roads)` builds the named streets, then the district lattices (`_district_lattice`, cut by `city_corridor` so no lattice
street enters an arterial's corridor), then `_snap_ends(streets, main_roads, reach=400.0)`:
- every street end looks for a road along its own line (`city_snap.snap_end`: reach 400 m, crossing streets end on the centre-line, streets running along
  a road end at its edge);
- ends that find nothing are `loose`; `_link_ends` joins them to the nearest road with a link street (`st_link_*`);
- a second pass retries; what still has no road is returned as `dead` (build_city.py prints this list in its notes);
- finally streets whose two ends are closer than 25 m are dropped.
So the generator **already knows** these 44 ends (`dead`), it just leaves them.

## Policy to implement (decide by looking at the data, one rule per case)
For each end in `dead` choose, in this order, the first that works and does not create a new rule failure:
1. **Extend** the street along its own line to the first road, even beyond the 400 m reach, up to about 900 m, if the extension stays on land (`on_land`)
   and does not cut across a deck or tunnel.
2. **Link** it to the nearest road or street end with a short connecting street (as `_link_ends` does) when that link is at most about 250 m, stays on land and meets
   the target at a sensible angle.
3. **Trim** the stub: remove the dangling part back to the last junction when the dangling piece is shorter than about 250 m and the remaining street still
   connects at its other end.
Every road end that is within 40 m of the window edge is legal as it is.

## Plan
1. Generate to your scratch path and list the 44 items. Group them: ends at a lattice border, ends in the middle of a district, ends near water, `century_ave`, `st_hankou_rd`, `st_link_*`.
2. Write a probe that prints, for each dead end, what `snap_end` found and why not (no road ahead within 400 m? water? angle?). The reason decides the policy.
3. Implement the policy step by step; after each step re-run `one_rule.py "no dead ends"` and `check_network_size.py`.
4. Run the gate. The usual regression suspects: "blocks clear of the roads" (a new street through a lot), "junctions meet their roads", "deck clearance" (a street under a deck).
5. Update `status/improve/city-deadends.md`.

## Acceptance (the runner executes these itself, in order)
1. `python tools/city/build_city.py --out F:/dev/skyrush-out/tmp/city-deadends/city.json` succeeds.
2. `python tools/city/accept_rules.py F:/dev/skyrush-out/tmp/city-deadends/city.json --baseline tools/city/rules_baseline.json --target "no dead ends"` prints `ACCEPT_RULES OK`.
3. `python tools/city/check_network_size.py F:/dev/skyrush-out/tmp/city-deadends/city.json` prints `NETWORK_SIZE OK` (at least 340 roads and 173 km: you may trim stubs, you may not delete the network).

## Pitfalls
- Passing the rule by deleting streets: the size check and the lead's diff review catch it; trimming is only for short stubs.
- Extending a street through water, over the Huangpu or across a landmark: use `on_land` and look at the result.
- A new link street that crosses another street without a junction: junction generation (`city_junctions.py`) is not yours; check the "junctions meet their roads" rule.
- Making `snap_end`'s reach huge for every street: it changes streets that are fine today; special-case the dead ends.
