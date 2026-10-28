# road-furniture-sidewalks — checkpoint

## Plan
1. Measure: how many props the junction cuts of the city take (a driver script in the scratch
   folder, `furniture_only.py` / `counts.py` / `edge.py`).
2. Rewrite the offsets in `blender/city/roads/furniture.py`: each side of a road gets its own
   kerb (`profiles.layout`: `asphalt_fwd` / `asphalt_back`), and the prop goes into that side's
   sidewalk (tree 1.2 m, lamp 0.6 m, shelter in the middle).  A road without a sidewalk has no
   place for them.
3. Exclude the junction zones: the cut of `junction_holes.road_holes` plus the kerb return
   (one path sample more on each side), and the carriageway of another road.
4. Traffic lights and street-name signs of a junction: on the kerb of their arm, the mast
   reaching over the lanes of its own road.
5. Full build + the checkers + the three Godot tests.

## Done
- `blender/city/roads/furniture.py`: the props of a street stand on the sidewalk of their own
  side (the wrong offset was `lanes_fwd * lane_width * 0.5 + median * 0.5 + 1.6`, the middle of
  the outer lane, and it used the fwd count on both sides).
- The props of the cut of a junction are left out (`_cut`), and a prop that would stand on the
  carriageway of another road is left out too (`_clearance_ok(..., carriageway=True)`).
- The lamps of a one-way deck stand on the barrier (they stood in the middle of its carriageway);
  the lamps of a road with a median are still in the median.
- The traffic lights and the street-name signs of a junction stand on the kerb of their arm
  (they stood 1.5 m inside the carriageway), and the mast reaches over the lanes of its own road.
- The noise walls stay where they were: the deck of the Yan'an Elevated runs right above the
  Yan'an surface road, so the parapet belongs to the junction of that road and the world drops
  every wall that stands on it (see "Requests").
- Densities: trees every 5.25 m (was 7.0), lamps every 22 m (was 30), shelters every 320 m
  (was 400): the junction zones take the props that the old spacing put there.
- The file was at the 400-line limit: the unused `SIGN_TEXTS` list is gone, the docstrings are
  shorter and the functions are separated by one blank line.

## In progress / next
Nothing.  All eight acceptance commands pass.

## How to test (exact commands)
    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/road-furniture-sidewalks/tiles --data F:/dev/skyrush-out/tmp/road-furniture-sidewalks/full
    python tools/city/check_furniture_ground.py F:/dev/skyrush-out/tmp/road-furniture-sidewalks/tiles F:/dev/skyrush-out/tmp/road-furniture-sidewalks/full/road_furniture.json --max-asphalt 600 --min tree=16500,lamp=4300,bus_stop=480,traffic_light=300
    python -c "import shutil; shutil.copyfile('F:/dev/skyrush-out/tmp/road-furniture-sidewalks/full/road_furniture.json', 'game/world/data/road_furniture.json'); print('INSTALLED')"
    python tools/gd.py test res://tools/furniture_dump.gd -- --dump=F:/dev/skyrush-out/tmp/road-furniture-sidewalks/dump.json --stub=audio,menu,hud,traffic,police,rivals
    python tools/city/check_furniture_ground.py game/assets/city/roads F:/dev/skyrush-out/tmp/road-furniture-sidewalks/dump.json --max-asphalt 100 --min tree=16500,lamp=3900,bus_stop=480
    python tools/gd.py test res://world/tests/test_junction_mouths.gd -- --timeout=900
    python tools/gd.py test res://world/tests/test_prop_alignment.gd -- --timeout=900
    python tools/gd.py test res://world/tests/test_world_quality.gd -- --timeout=900

## Evidence (key output lines)
- The build: `DONE in 249.9 s`.
- The build's ground: `26075 solid props, 179 of them on the asphalt (0.7 %)` → `FURNITURE_GROUND OK`
  (the old build: 30949 solid props, 25246 on the asphalt, 81.6 %).
  The counts of the build: tree 17473, lamp 4730, bus_stop 534, traffic_light 360, sign 2909.
- The dump: `FURNITURE DUMP OK: 43916 entries`; the world places `tree 17306, lamp 4346,
  bus_stop 520, sign 2760, noise_wall 15` and moves `0 off the carriageway` (before: 27487).
- The dump's ground: `25192 solid props, 58 of them on the asphalt (0.2 %)` → `FURNITURE_GROUND OK`
  (before: 841 of 27709 on the asphalt).
- `test_junction_mouths`: `PASS the city keeps its trees and lamps (22637 judged)`,
  `PASS no tree, lamp or shelter stands in the box of a junction (0: )`,
  `PASS the mouth of Fuzhou Rd on the Bund is free of trees and lamps`.
- `test_prop_alignment`: `PASS the city keeps its bus shelters (520)`, `PASS and its noise walls (15)`,
  `PASS bus_stop: the long axis lies along the road (98 %)`, `PASS noise_wall: ... (100 %)`,
  `PASS no more than 5 long boxes reach into a lane (0: )`.
- `test_world_quality`: `PASS 0 of 43916 furniture props stand on the carriageway`,
  `PASS 0 of 262 traffic-light masts stand in the carriageway`, `PASS 0 props stand inside each
  other`, `PASS all 131 checks`.

## Known issues
- The 19 noise walls of the Yan'an Elevated still stand in the carriageway of the deck (94.7 % of
  them on the asphalt in the checker).  The world moves them to the parapet (that is what it does
  today), but the parapet of that deck is 1.8 m above the Yan'an surface road, and the junction
  box of that road claims every prop that stands there: the world drops the walls that stand on
  the parapet (only 7 of 19 survived) and `test_prop_alignment` wants 12 of them.
- The props of a junction (the traffic lights and the name signs) are on the kerb of their arm,
  not on the band of the kerb return: the band is 3 m wide and follows the arc of the fillet, and
  the fillet is a chamfer (a single point, no band) in a third of the junctions.

## Requests
- `game/world/build/furniture_filter.gd` (world unit): a prop that stands on the parapet of a
  deck above a surface road is dropped, because the mouth of that surface road covers the deck.
  The filter should ignore the roads that are more than a storey below the prop (it only compares
  the heights of the lanes it looks at).  With that, the roads unit can put the noise walls on
  the parapet where they belong.
- The checker `tools/city/check_furniture_ground.py` looks the plan of a triangle up as (x, y)
  and the height as z, but the glTF tiles are Y-up (the plan is (x, z)): the barycentric test of
  `ground_at` should use z3 and the target's z.  The test is a shear of the triangle, so a prop
  that stands 1.5 m outside the carriageway is reported on the asphalt about 0.5 % of the time
  (at the plan centre of a triangle the test gives l = 168, -260, 93 instead of 1/3, 1/3, 1/3).
