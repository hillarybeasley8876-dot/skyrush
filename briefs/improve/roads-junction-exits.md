# Job: a car can turn off every two-way road at every junction it passes (no lanes that run through a junction)

Blender road builder (`blender/city/roads/`), the lane graph. No Godot needed: your checks are offline Python scripts after a
Blender build (lanes only: about 30 s; the full build at the end: about 4.5 minutes).

## Goal
`python tools/city/check_junction_exits.py data/city/city.json game/world/data/lanes.json` (read its docstring):

    17 two-way roads run through a junction that enters them (no lane of theirs leaves it)
    THROUGH j_st_d1_ns_3_st_d2_ew_4_st_henan_rd: st_henan_rd
    THROUGH j_st_d4_ew_9_st_d4_ns_6_yanan_rd_surface: yanan_rd_surface
    THROUGH j_st_d4_ns_5_yanan_rd_surface: yanan_rd_surface
    THROUGH j_st_d6b_ns_3_st_fujian_rd_yanan_rd_surface: yanan_rd_surface
    THROUGH j_nanpu_pudong_loop_pudong_south_rd: pudong_south_rd
    THROUGH j_pudong_south_rd_st_d8_ew_6_st_d8_ns_3: pudong_south_rd
    THROUGH j_st_d3_ns_9_st_fuzhou_rd: st_fuzhou_rd
    THROUGH j_bund_zhongshan_e1_st_beijing_e_rd: st_beijing_e_rd
    ... (17)
    JUNCTION_EXITS FAIL 17

At these junctions the side streets turn onto the road (their connectors lead into its lanes), but the road's own lanes are not
cut there: no car on it can turn off, and a race whose route turns there cannot be driven as laid out (Henan Rd -> st_d2_ew_4 ->
Nanjing E Rd, the way of three race routes to the Bund). Make every one of them an approach of its junction: `JUNCTION_EXITS OK`.

## The cause seen first (check it, and find the cause of every other case: they may differ)
`lanes._junction_holes` cuts a road where `junctions.trim_indices` says it lies inside the junction: the path samples within
`road_radius(arms, road)` of the **centre of the junction**. A side street that ends at the kerb of a main road puts the centre of
the junction beside the main road: at `j_st_d1_ns_3_st_d2_ew_4_st_henan_rd` (city.json x -389.5, z -500.0) the centre is 18.5 m east
of the centre line of Henan Rd (x -408), and the radius of Henan Rd there is less than that, so no sample of Henan Rd is inside: no
hole, no cut, no lane end. Measure for each case: the distance of the junction centre from the road's centre line, the radius, the
samples inside (print them from the build: `trim_indices`, `road_radius`, `arm_geometry` for that junction and road).

Other things to look at for the cases that are not offset: a junction of a road with one of its own ends, a road that is cut by
another junction a few metres away (the merged junctions of `load.City._merge_junctions`), an arm that `levels.dominant` drops.

## What to build
A road of a junction whose lanes pass the junction gets its hole where the junction is **on the road**: for a road whose centre line
does not come within the radius of the centre, measure the inside samples around the point of the road nearest to the centre (the
projection of the centre on the road), not around the centre itself. Keep everything else of the junction as it is (its fill, its
kerb returns, its centre). Then `lane_links.link_junctions` builds the movements of the new approaches by itself.

## Files you own
`blender/city/roads/junctions.py`, `blender/city/roads/lanes.py`. Everything else is read-only (`lane_links.py`, `load.py`,
`collision.py`, `levels.py`, `tools/`, `data/`, `game/`).

## Where the build writes (never into the repo)

    python tools/gd.py blender run blender/city/roads/build_roads.py -- --lanes-only --data F:/dev/skyrush-out/tmp/roads-junction-exits/data
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-junction-exits/tiles --data F:/dev/skyrush-out/tmp/roads-junction-exits/full

## Plan
1. Run the lanes-only build on the current code and the checker on it (17 THROUGH: the baseline).
2. For three cases (Henan Rd, one of Yan'an Rd and Pudong South Rd at the Nanpu loop) measure why the road is not cut; write the
   numbers into `status/improve/roads-junction-exits.md`.
3. Implement, rebuild the lanes, re-run the checker; repeat for the cases that are left.
4. Run the full build and every acceptance command; numbers before / after into the status file.

## Acceptance (the runner executes these itself, in order)
1. The full build above prints `DONE in`.
2. `python tools/city/check_junction_exits.py data/city/city.json F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json` prints `JUNCTION_EXITS OK`.
3. No duplicate connectors: `python tools/city/check_lane_dupes.py F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --quiet` prints `LANE_DUPES OK`.
4. `check_lane_graph.py .../full/lanes.json --quiet` prints `LANE_GRAPH OK`; `check_chain_links.py .../full/lanes.json --quiet` prints `CHAIN_LINKS OK`.
5. Every race route is drivable: `python tools/city/check_routes_drivable.py data/city/city.json F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json` prints `ROUTES_DRIVABLE OK`.
6. The surface: `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-junction-exits/tiles F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --max-bad 3895` exits 0.
7. No lane walled off: `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-junction-exits/tiles --lanes F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --max-bad 25 --max-barrier-area 395000` prints `PATH_BLOCKERS OK`.
8. The open deck edges do not grow: `python tools/city/check_open_edges.py F:/dev/skyrush-out/tmp/roads-junction-exits/tiles F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --max-regular 181 --max-connector 14 --top 0` prints `OPEN_EDGES OK`.

## Pitfalls
- A hole moved along the road moves the end of the road's surface and kerbs there too (`build_road` uses the same `trim_indices`
  for the kerbs: `junctions.trim_indices` and `tiles.split_runs(run, excluded)`): the surface coverage check (6) and the blockers (7)
  catch a road that loses its surface or gets a kerb across a lane.
- Do not change how the junction records are merged or how the junction fill is drawn.
- Do not raise a limit of a check.
