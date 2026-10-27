# Job: the circuit of the test city can be driven (test_world_api: the route test_loop)

The test city `data/city/test_city.json` (a development sample, not the real map) and one Godot test (about 4 minutes). Read
`briefs/improve/_map-common.md` first for the city description (roads, junctions, routes).

## Goal
    python tools/gd.py test res://world/tests/test_world_api.gd -- --timeout=600

prints `FAIL 2 of 667 checks` today:

    [world] route test_loop: the legs [2, 3, 4] have no forward path on the lane network
    [world] route test_loop: the legs [2, 3, 4] cannot reach their gate on the lane network
    FAIL route test_loop: 12 reversals in the racing line
    INFO route test_loop: 2005 samples, 114 off the lane (94.3 % on the lane), 12 reversals
    FAIL route test_loop: 94.3 % of the line is on a lane

Make it print `PASS all N checks`, with no "no forward path" and no "cannot reach" line, by changing the test city only.

## Why it fails (measured by the lead)
`test_loop` is a race (`"kind": "race"`, 2 laps): a circuit, the racing line closes from the last gate back to the first. The
lane graph of the test city has no circuit at all:

    main_ew     surface  3+3 lanes  (-500, 0, 0) -> (500, 0, 0)
    cross_ns    surface  2+2        (0, 0, -300) -> (0, 0, 300)
    south_ew    surface  2+2        (-500, 0, 140) -> (600, 0, 140)
    elev_ew     elevated 2+2        (-480, 0, 60) -> (480, 0, 60)   (its two ends lie on the ground and meet nothing)
    off_ramp_e  ramp     1+0        from elev_ew (eastbound, right) down to south_ew (eastbound)
    junctions   j_center (main_ew x cross_ns), j_south (cross_ns x south_ew)

Every road end is a map edge: main_ew, cross_ns and south_ew form a tree, the elevated road is reached only from nowhere, and its
ramp goes down only. Gates of today (x, y, z, heading): (-400,0,-5,90), (0,0,-5,90), (400,0,-5,90) on main_ew eastbound,
(0,10,64,270) on the elevated road westbound, (-400,0,140,270) on south_ew westbound. Leg 2 (main_ew to the elevated road), leg 3
(the elevated road to south_ew) and the closing leg 4 (south_ew back to main_ew) have no way without a U-turn, so the line turns
round on the lanes (the reversals) and cuts across where there is no lane (the samples off the lane).

## What to change
Add to the test city the roads (and the junction records of their crossings) that close the circuit, and place the gates of
`test_loop` on it:
- `test_loop` stays a race with 2 laps, at least 4 gates, and at least one gate on the elevated road `elev_ew` (y >= 8: the race
  tests the elevated road); its grid stays at (-450, 0, -5, 90) (the player spawn).
- A way onto the elevated road is needed (for example a ground street that meets an end of `elev_ew`, or an on-ramp like
  `off_ramp_e` the other way round), and a way back to `main_ew` from where the race leaves the elevated road.
- Keep everything else of the test city as it is (the roads above, the off ramp, the sky lane, the spawns, the blocks, the pois).
  You may add roads and junctions; do not delete or move the existing ones.
- How the game builds the lanes of a city that `lanes.json` does not describe: `game/world/build/world_builder.gd`
  (`_build_lanes`: `LaneGraphBuilder`, `LaneLinks` with the junctions of the city). A junction record lists the roads that meet
  (`{"id", "x", "z", "roads": [...], "signals"}`); an attach is the way a ramp joins a road (`off_ramp_e`).

## Files you own
`data/city/test_city.json`. Everything else is read-only (`game/`, `tools/`, `data/city/city.json`).

## Commands
    python tools/gd.py test res://world/tests/test_world_api.gd -- --timeout=600     (about 4 minutes)

The test prints the legs of every route and, per route, `INFO route <id>: <samples>, <off the lane>, <reversals>`. Look at the
`[world] route test_loop` lines for the legs that have no way.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py test res://world/tests/test_world_api.gd -- --timeout=600` prints `PASS all` and none of
   `no forward path`, `cannot reach`.
2. `python -c "import json; c=json.load(open('data/city/test_city.json',encoding='utf-8')); r=[x for x in c['routes'] if x['id']=='test_loop'][0]; ok=r['kind']=='race' and r['laps']==2 and len(r['checkpoints'])>=4 and any(p[1]>=8 for p in r['checkpoints']) and r['grid']==[-450,0,-5,90]; print('TEST_LOOP_SHAPE OK' if ok else 'TEST_LOOP_SHAPE FAIL')"` prints `TEST_LOOP_SHAPE OK`.

## Pitfalls
- The real city (`data/city/city.json`) is checked by the same test: its routes pass today and must stay so (you do not touch it).
- A gate stands on a lane, faces along the race, and the shortest lane path between two gates is the racing line: a gate just past
  a junction on the wrong side makes the line turn round.
- JSON: keep the file valid UTF-8 with LF line endings and the formatting of the file (one road per few lines, as today).
