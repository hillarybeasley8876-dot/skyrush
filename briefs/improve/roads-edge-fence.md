# Job: a car cannot fall off a deck (fence the open edges at the ramp attaches)

Blender road builder (`blender/city/roads/`). No Godot needed: your checks are offline Python scripts (5 to 60 seconds) after a Blender build (about 7 minutes).
Read `briefs/improve/roads-lips-port.md` first for the structure of the files (the lead merged it: `attaches.py` keeps the gore, the gaps and the lane-driven rules,
`deck.py` the acceleration strip, `collision.py` the colliders and the paving).

## The defect (the lead measured it with real cars and with a new checker; reproduce it first)
`python tools/city/check_open_edges.py <tiles dir> <lanes.json>` (new, read its docstring) sends a ray sideways from every lane point of every deck (6 m apart, both sides, 12 m reach)
and asks: does a barrier collider (parapet, concrete barrier, rail) stop a car before the road surface ends? On the current tiles it prints
`1128 open edges: 903 on the regular lanes, 225 on the connector lanes`; the worst roads are ns_elevated 310, yanan_elevated 234, ramp_rt_eb_sb 72, ramp_rt_sb_wb 69, ramp_rt_nb_eb 59, nanpu_pudong_loop 50,
ramp_l4_sb_eb 47, nanpu_bridge 46, ramp_l3_eb_nb 44. They are NOT spread over the decks: they come in clusters of 20 to 90 m around the ramp attaches, for example
`yanan_elevated_4_fwd0..2` at x -1529 .. -1438, z 716 .. 740 (y 9; between the attaches of ramp_l3_eb_nb at x -1578 and ramp_rt_eb_sb at x -1474),
`ns_elevated_5_back0..2` at (-1207..-1165, y 28..24, z 790..880), `yanan_elevated_2_back2` at x -1774 .. -1678, `ns_elevated_5_fwd1` at (-1396..-1381, y 24..28, z 496..589).
Real cars confirm it (`tools/run_follow.py` drives a car along a path with the game's autopilot): on ramp_l4_sb_eb.attach_end the car runs along the right-most lane of the deck at (-919, 10, 493), the deck
ends 3.0 m to the right of the lane centre and no parapet stands there: the car drives off the edge and falls 10 m to the street (its y goes 9.5 -> 0.5 in 0.9 s). Three other ramp attaches do the same
(ramp_l3_eb_nb.attach_start at (-1584, 10, 746), ramp_l4_nb_wb.attach_start at (-1164, ?, 844), ramp_rt_eb_sb.attach_start at (-1474, 9, 751)). A player who drifts 3 m to the side at an on-ramp falls off the viaduct.

## Where it comes from (found by the lead; verify with your own prints)
`attaches.parapet_gaps(city, road)` removes the parapet and its collider from the edge of a deck wherever a ramp's traffic crosses it: the stations of the gore wedge (`_gore_rows`), the stretches of the
connector lanes outside the deck (`_outside_stretch`) and the median crossings, each widened by `GAP_MARGIN`. A gap is only right where a paved surface carries on beyond the edge (the ramp's deck, the gore). The
acceleration strip (`deck.build_acceleration`, 6 m wide over 150 m before the attach) has no parapet on its outer edge at all, and the parent's parapet is gone beside it. So on the stretches where the gap is
longer than the ramp deck that lies next to it, and along the outer edge of the strip, the deck ends in thin air with nothing in front of it.
The screenshot of ramp_l4_sb_eb (a ramp deck that runs along the parent) shows a low grey kerb where the one-metre parapet should be.

## What to do
1. Reproduce: build the roads into your scratch folder (command below), run `check_open_edges.py` with `--csv` and read the clusters; put the numbers into `status/improve/roads-edge-fence.md`.
2. For two or three clusters print what the builder decided there: the gap stretches of the parent (`parapet_gaps`), the rows of the gore and of the acceleration strip, and where the ramp's own deck is.
3. Fix the causes: (a) the gap of the parent's parapet covers only the stretches where the paved surface of the ramp (gore wedge, ramp deck, strip) really lies beside the edge or where a lane crosses it;
   everywhere else the parapet stands (visible mesh AND collider, both are cut by the same gaps); (b) the outer edge of the acceleration strip and of the gore gets a parapet like the deck edge (the same
   profile, `profiles.parapet_profile()`, and its collider); (c) at the end of a gap the parapet has to close properly (no free-standing end that a car can slip behind: keep the gap margin small).
   Keep what the earlier jobs achieved: the traffic of every attach must still drive through (step 3 of the acceptance, `check_path_blockers`, is the proof), the colliders must not become invisible walls
   (a collider has a visible parapet at the same place) and no surface may be removed.
4. Build, run the checks, fix, repeat.

## Files you own
`blender/city/roads/attaches.py`, `blender/city/roads/deck.py`, `blender/city/roads/collision.py`, `blender/city/roads/profiles.py`, `blender/city/roads/build_roads.py`. Everything else is read-only (the checkers are the lead's).

## Acceptance (the runner executes these itself, in order; scratch folder `F:/dev/skyrush-out/tmp/roads-edge-fence`)
1. `python tools/gd.py blender run blender/city/roads/build_roads.py -- --city data/city/city.json --out F:/dev/skyrush-out/tmp/roads-edge-fence/tiles --data F:/dev/skyrush-out/tmp/roads-edge-fence/data` prints `DONE in` (about 7 minutes).
2. `python tools/city/check_open_edges.py F:/dev/skyrush-out/tmp/roads-edge-fence/tiles F:/dev/skyrush-out/tmp/roads-edge-fence/data/lanes.json --max-regular 90 --max-connector 225` prints `OPEN_EDGES OK`
   (the regular lanes from 903 down to at most 90, the connectors not worse than now).
3. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-edge-fence/tiles F:/dev/_scratch/attach_paths_v3 --lip 0.25 --max-lips 12 --max-bad 0 --min-barrier-area 290000 --max-barrier-area 345000` prints `PATH_BLOCKERS OK`
   and the same for `F:/dev/_scratch/chain_paths_v3` with `--max-lips 0`: the traffic of the 19 ramp attaches and the 12 chain joints still drives through (and the barriers neither vanish nor grow without bounds).
4. `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-edge-fence/tiles --lanes F:/dev/skyrush-out/tmp/roads-edge-fence/data/lanes.json --max-bad 40 --min-barrier-area 290000 --max-barrier-area 345000` prints `PATH_BLOCKERS OK`
   (no lane of the whole city is walled off: the open-edge fix must not put a parapet across a lane).
5. `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-edge-fence/tiles F:/dev/skyrush-out/tmp/roads-edge-fence/data/lanes.json --tol 0.4 --max-bad 5100 --max-area 2560000` exits 0 (the road surface is not touched).
6. `python tools/city/check_lane_graph.py F:/dev/skyrush-out/tmp/roads-edge-fence/data/lanes.json --quiet` prints `LANE_GRAPH OK`; `python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-edge-fence/data/lanes.json --quiet` prints `CHAIN_LINKS OK`.

## Pitfalls
- Satisfying step 2 with walls that are not parapets (a huge slab, a fence along the middle of a lane): step 4 (no lane blocked) and `--max-barrier-area` catch the worst; the lead reads the diff and drives the four failing ramps.
- A parapet collider without its visible parapet (an invisible wall), or the other way round: both are cut by the same gaps, keep them in step.
- A gap so short that the ramp's traffic hits the parapet: step 3.
- Editing a checker, a path file or a threshold.
