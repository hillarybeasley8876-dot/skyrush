# roads-junction-exits — a car can turn off every two-way road at every junction it passes

## Plan
1. Baseline: lanes-only build + `check_junction_exits.py` → 17 THROUGH. (done)
2. Measure every case: junction centre vs road centre line, `road_radius`, `trim_indices`, the
   fill ring, the arms' exits/approaches, the movements. (done — 8 causes found)
3. Fix the cut of a road that a junction does not reach in `junctions.py`: cut it where the
   junction stands on the road, and draw the fill of the junction on the road too. (done)
4. Let the cuts of two junctions on the same road share the road between them. (done)
5. Rebuild the lanes, re-run the checker and the other checks; then the full build. (done)

## Done
- `junctions.trim_indices` now works per road (`junctions.road_holes`): the samples every junction
  of a road takes are computed together, so the cuts of two junctions cannot eat each other.
- A road that a junction does not reach (its centre line stays further from the centre of the
  junction than the radius in which the road is cut) is cut anyway, where the junction stands on
  the road: a small cut (one sample each way) at the projection of the centre on the road.
- That cut is only made when the lanes of the road do not end near the junction already: a road
  whose lanes reach a neighbouring junction close by turns off there, and a second cut would
  break the road in two (it broke the racing line of the Lujiazui ring route).
- The fill of a junction that stands beside a road is drawn on that road (`junctions.boundary`):
  the cross-section of the arm lies on the road's own centre line, not on the centre of the
  junction. Without that the fill stopped 3.5 m short of Henan Rd, the movement of the new
  approach drove over bare ground, and the surface coverage lost 177 samples.
- The cuts of two junctions that stand on the same stretch of road no longer eat each other: the
  earlier cut stops two samples before the next one starts, so the road keeps a stretch of lane
  between them.
- Elevated roads are not cut that way: they land at a junction and their lanes end there.
- `check_junction_exits.py`: 17 → 8. `check_surface_coverage.py`: 4072 → 3879 (the baseline is
  3895). `check_lane_dupes.py`, `check_lane_graph.py`, `check_chain_links.py`,
  `check_routes_drivable.py`, `check_path_blockers.py`, `check_open_edges.py`: OK.
- `junctions.py` stays under 400 lines (398).

## In progress / next
- The eight cases that are left: see "Known issues". Their fixes are in `lane_links.py`,
  `buildingcut.py`, `load.py` and the city file, none of which this job owns.

## How to test (exact commands)
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --lanes-only --data F:/dev/skyrush-out/tmp/roads-junction-exits/data
    python tools/city/check_junction_exits.py data/city/city.json F:/dev/skyrush-out/tmp/roads-junction-exits/data/lanes.json
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-junction-exits/tiles --data F:/dev/skyrush-out/tmp/roads-junction-exits/full
    python tools/city/check_junction_exits.py data/city/city.json F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json
    python tools/city/check_lane_dupes.py F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --quiet
    python tools/city/check_lane_graph.py F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --quiet
    python tools/city/check_chain_links.py F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --quiet
    python tools/city/check_routes_drivable.py data/city/city.json F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json
    python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-junction-exits/tiles F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --max-bad 3895
    python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-junction-exits/tiles --lanes F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --max-bad 25 --max-barrier-area 395000
    python tools/city/check_open_edges.py F:/dev/skyrush-out/tmp/roads-junction-exits/tiles F:/dev/skyrush-out/tmp/roads-junction-exits/full/lanes.json --max-regular 181 --max-connector 14 --top 0

## Evidence (key output lines)
- baseline: `17 two-way roads run through a junction that enters them` / `JUNCTION_EXITS FAIL 17`
- now: `8 two-way roads run through a junction that enters them` / `JUNCTION_EXITS FAIL 8`
- Henan (the case of the brief): the centre (-389.5, 500.0) is 18.5 m from the centre line of
  Henan Rd (x = -408) and the radius of Henan Rd there is 6.4 m: no sample of Henan Rd was
  inside the junction, so the road was not cut there at all. With the cut at the place where
  the junction stands on the road, Henan Rd is an approach of the junction again and the
  movements are built (`j_st_d1_ns_3_st_d2_ew_4_st_henan_rd` is no longer in the list).
- the same cause, fixed: yanan_rd_surface (three junctions), pudong_south_rd, st_d6_ns_14,
  st_d7b_ns, st_d7_ns_9, st_jiujiang_rd, st_fujian_rd, st_guangdong_rd, st_chongqing_rd,
  and the junctions whose cuts ate each other (st_fuzhou_rd, st_d8_ew_17).
- the full build: `DONE in 393.8 s`; `PATH_BLOCKERS OK` (worst road 16 of at most 25, barrier
  collider area 384042 m2 of at most 395000); `OPEN_EDGES OK (regular 181 of at most 181,
  connectors 14 of at most 14)`; `ROUTES_DRIVABLE OK` (5 routes, 0 bad, 0 reversals);
  `LANE_DUPES OK`; `LANE_GRAPH OK`; `CHAIN_LINKS OK`.
- `SURFACE_COVERAGE bad samples: 3879 (1.30 %)` — the baseline is 3895, so the new cuts do not
  cost any surface (the fill of a junction now reaches the road it should meet).

## Known issues
The eight cases that are left, with the cause of each (measured with the scripts in
`F:/dev/skyrush-out/tmp/roads-junction-exits/diag*.py`):
1. `j_bund_zhongshan_e1_st_beijing_e_rd: st_beijing_e_rd` — the road starts at the junction
   (`idx=0`, its first sample is the centre of the junction): it has no lane that arrives at
   the junction, so no traffic of it can turn off there. The junction enters it (the Bund's
   traffic turns onto it), and the check counts that as a road that runs through the junction.
2. `j_bund_zhongshan_e1_st_d0_ew_4: st_d0_ew_4` — the movement of the street is built, but
   `buildingcut.apply` drops it again: a point of the connector lies in a building box. The
   connector starts at the lane end of the Bund's road, which is at the kerb return, and the
   buildings of the Bund stand right behind that kerb.
3. `j_lujiazui_ring_rd_st_d7_ew_11: st_d7_ew_11` — the cuts of the two junctions of the road
   leave one sample between them (the hole of the junction is 0..3, the hole of the next one
   5..9): the stretch between them is one sample long and carries no lane.
4. `j_nanpu_pudong_loop_pudong_south_rd: pudong_south_rd` — the other arm of the junction is the
   ramp, a one-way road (lanes_fwd 2, lanes_back 0) that ends there: it has no lane that leaves
   the junction, so the approach of pudong_south_rd has no movement to take. The traffic of
   pudong_south_rd has nowhere to go at the end of the road.
5. `j_st_d7_ew_26_st_link_25: st_link_25` — the road is cut twice at the same place: the record
   `j_st_d7_ew_26_st_d7_ns_9_st_link_25_1` of the crossing (the `_1` record was not merged into
   the first by `load.City._merge_junctions`) takes the samples 0..6, and the junction
   `j_st_d7_ew_26_st_link_25` stands 21.6 m off the road, so its own cut would land inside
   that hole. The cut there is skipped, because the lanes of the road already end at the other
   junction, and the road has no lane of its own at this one.
6. `j_st_d7b_ew_17_st_d7b_ns_11_st_d8_ew_17_st_link_92: st_d8_ew_17` — three junctions 20 m
   apart on the road, the holes 0..3, 2..5 and 6..9 leave no stretch with a lane between them.
7. `j_st_d8_ew_17_st_link_92: st_link_92` — the same pair of records as 5: the cut of the
   junction that comes second is built, the first one has none.
8. `j_st_d9_ns_yanan_frontage_n: st_d9_ns` — the other arm is yanan_frontage_n, a one-way road
   (lanes_fwd 0) that ends there: like 4, the approach of st_d9_ns has no movement to take.

The cuts of two junctions a few metres apart were changed twice: the earlier cut stops two
samples before the next one starts (the road keeps a stretch of lane between them) — that
repairs the cases whose cuts overlapped (`JUNCTION_EXITS FAIL 8`, the surface coverage 3879) —
and it also lets the cuts that only left one sample between them be repaired, but then the
earlier cut of a road moves the lane ends of that junction and the movements that follow them
drive over the gap between the road and the fill: the surface coverage goes from 3879 to 4025,
over the limit of 3895. Only the rule for the cuts that overlap is therefore in the diff.

## Requests
- `blender/city/roads/lane_links.py`: a road that ends at a junction cannot be "left" there: the
  arms of a junction only offer their own exits to the other arms, so the approach of a road
  whose other arm is a one-way road (4 and 8) has no movement at all. A turn onto the lanes of
  the same road (a U-turn at the end of it) would be the way out.
- `blender/city/roads/buildingcut.py`: the streets of the Bund that run into the buildings lose
  their movements (2), so the roads of the junctions in the row of the buildings can no longer
  be left there. The connector starts at the lane end of the Bund's road, which is at the kerb
  return, and the buildings stand right behind that kerb.
- `blender/city/roads/load.py`: the two records of the crossing of `st_link_25` and
  `st_link_92` are 20 m apart and are not merged (`_merge_junctions` keeps them apart), so the
  road is cut twice at the same place and has no lane between the cuts (5 and 7).
- `blender/city/roads/junctions.py` (this file): two junctions a few metres apart on one road
  cannot both have a lane of the road: the stretch between them has to carry the lane that
  ends at one and starts at the other (3 and 6). The cut of a junction would have to give way
  to the next one along the road, but the lane ends that move with it leave the movement over
  the gap between the road and the fill (the surface coverage).
- `data/city/city.json`: the streets that start at a junction (st_beijing_e_rd at
  j_bund_zhongshan_e1_st_beijing_e_rd) have no traffic of their own that could turn off there;
  the check counts them as roads that run through the junction (1).
