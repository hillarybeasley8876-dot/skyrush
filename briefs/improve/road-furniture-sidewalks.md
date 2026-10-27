# Job: the street furniture stands on the sidewalk, and none of it in a junction (the roads unit places it right)

Blender road builder, `blender/city/roads/furniture.py` (it writes `road_furniture.json`: the trees, lamps, bus shelters,
traffic lights, signs of the roads). Offline checks after a Blender build (about 5 minutes), then three Godot tests (a few
minutes each). Read `briefs/improve/_map-common.md` first.

## Goal
    python tools/city/check_furniture_ground.py game/assets/city/roads game/world/data/road_furniture.json   (read its docstring)

    30949 solid props, 25246 of them on the asphalt (81.6 %)
      tree            19115  sidewalk   0.4 %  asphalt  99.4 %
      lamp             5018  sidewalk   0.5 %  asphalt  94.7 %
      traffic_light     360  sidewalk   5.0 %  asphalt  81.1 %
      lamp_heritage      64  asphalt  96.9 %;  noise_wall 19  asphalt 94.7 %;  bus_stop 552  asphalt 25.9 %;  sign 5821  asphalt 16.9 %

Nearly every tree and lamp the roads unit places stands in the outer lane of its road. The game's furniture filter
(`game/world/build/furniture_filter.gd`, `place` / `_relocate`) pushes such a prop out onto the sidewalk of its road at every load
(23,000 props). Where there is no sidewalk to push it to, in a junction, it stays on the asphalt: of the props the game places
(`game/tools/furniture_dump.gd`, then the checker on the dump), 841 solid props stand on asphalt, 817 of them within 30 m of a
junction. In the game: the tree of `st_d3_ew_25` at (-514.0, 58.7) stands in the asphalt of its junction with Fujian Rd, 2.65 m
from the centre of a turning lane (a car that turns there hits it). Place the furniture where it belongs in the roads unit.

## The cause seen first (check it)
- `trees()`: offset `lanes_fwd * lane_width * 0.5 + median * 0.5 + 1.6`. A road of 2+2 lanes of 3.5 m has its kerb at 7.0 m +
  the shoulder (0.5 m) from the centre line; the tree stands at 5.1 m: in the outer lane. `lamps()` (+ 2.0) and `bus_stops()`
  (+ 2.4) the same way. A road with `lanes_back` different from `lanes_fwd` uses the forward count on both sides.
- The props go on every few metres along the whole road, through the junctions: the cut of a road at a junction
  (`junction_holes.road_holes`) has no sidewalk, the prop lands on the cross street or the fill of the junction.
- `junction_furniture()`: the traffic light masts stand at `a["half"] - 1.5` from the axis of their arm: inside its carriageway.

## What to build
1. Each prop of a side at the sidewalk of that side: the edge of the carriageway of that side (its lanes x `lane_width` + half
   the `median` + the `shoulder`), then into the sidewalk (`sidewalk` m wide): a tree about 1.2 m behind the kerb, a lamp about
   0.6 m, a bus shelter in the middle of the sidewalk. A road without a sidewalk: look at what the game does with its props today
   (`furniture_filter._relocate`: the paved shoulder) and do the same, or leave the prop out.
2. No tree, lamp, bus shelter or noise wall in the cut of a junction (`junction_holes.road_holes(city, road)`: the path samples
   each junction of the road takes) or in its kerb returns (the sidewalk width further), and none on the carriageway of another
   road (a street that crosses it or runs beside it).
3. The traffic light masts and the street-name signs of a junction at the kerb corner of their arm, outside the lanes.
4. Keep the rest as it is: the heights, `_clearance_ok` (no prop through a deck), the lamps in the median of an elevated road
   (`mount: median`), the gantries (they span the road on purpose), the tunnel lights, the cable anchors, the piers.

## Files you own
`blender/city/roads/furniture.py`, and `game/world/data/road_furniture.json` **only as the output of your build** (acceptance 3
copies it in). Everything else is read-only (`junction_holes.py`, `junctions.py`, `lanes.py`, the game code and its furniture
filter, `tools/`, `data/`).

## Commands
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/road-furniture-sidewalks/tiles --data F:/dev/skyrush-out/tmp/road-furniture-sidewalks/full
    python tools/city/check_furniture_ground.py F:/dev/skyrush-out/tmp/road-furniture-sidewalks/tiles F:/dev/skyrush-out/tmp/road-furniture-sidewalks/full/road_furniture.json
    python tools/gd.py test res://tools/furniture_dump.gd -- --dump=F:/dev/skyrush-out/tmp/road-furniture-sidewalks/dump.json --stub=audio,menu,hud,traffic,police,rivals
The full build takes about 5 minutes; `--lanes-only` does not write the furniture. A faster loop for the furniture alone is yours
to write (a driver script under `F:/dev/skyrush-out/tmp/road-furniture-sidewalks/`, not in the repo).

## Acceptance (the runner executes these itself, in order)
1. The full build above prints `DONE in`.
2. `check_furniture_ground.py .../tiles .../full/road_furniture.json --max-asphalt 600 --min tree=16500,lamp=4300,bus_stop=480,traffic_light=300`
   prints `FURNITURE_GROUND OK` (at most 600 of about 30,000 on the asphalt; the city keeps its trees and lamps).
3. The build's `road_furniture.json` is copied into `game/world/data/` (prints `INSTALLED`).
4. `furniture_dump.gd` (above) prints `FURNITURE DUMP OK`.
5. `check_furniture_ground.py game/assets/city/roads .../dump.json --max-asphalt 100 --min tree=16500,lamp=3900,bus_stop=480`
   prints `FURNITURE_GROUND OK` (what the game places: at most 100 solid props on the asphalt, 841 today).
6. `test_junction_mouths.gd`: `PASS the city keeps its trees and lamps`, `PASS no tree, lamp or shelter stands in the box of a
   junction`, no `FAIL`.
7. `test_prop_alignment.gd`: no `FAIL` (the shelters along their road, out of the lanes).
8. `test_world_quality.gd`: `PASS all`.

## Pitfalls
- Do not delete props to pass: the minimum counts of acceptance 2 and 5 are there for that. A prop that has no place on its
  sidewalk (a junction, a ramp) is left out; a prop of a normal stretch of road gets its place on the sidewalk.
- The heading of a prop stays the heading of its road (the game turns the long boxes along the lanes, test_prop_alignment).
- Coordinates: Godot space (x east, y up, z south); `road.at(s)` gives the point, the tangent and the right vector of the road.
