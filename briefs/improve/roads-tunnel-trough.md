# Job: the tunnel is a bore only where it is covered: an open trough with walls and parapets near its ends, a street at grade

Blender road builder (`blender/city/roads/`). No Godot needed: your checks are offline Python scripts (seconds) after a Blender
road build (about 4.5 minutes).

## Goal
The Yan'an tunnel (`yanan_tunnel`, the only road of `"kind": "tunnel"` in `data/city/city.json`) goes down from the street,
runs 28 m under the river and comes up again. Its height profile has just been changed so that no street crosses it where it
is shallow. Along the road there are now three kinds of stretches (the depth is d = -y of the road, in metres):

| kind | depth | where (station s along the road, m) | what it has to look like |
|---|---|---|---|
| AT GRADE | d <= 0.3 | 0..26 (Puxi end, a junction at s 0), 1292..1363 (Pudong end, the Lujiazui Ring Rd junction at s ~1324 and the Century Ave junction at the end) | a street: asphalt, kerbs, markings; nothing of the tunnel |
| OPEN (the trough) | 0.3 < d < 5.98 | 28..154 (Puxi), 1162..1290 (Pudong) | open to the sky: a concrete wall on each side of each carriageway from under the road up to the ground, a parapet 1.0 m over the ground on the two outer walls, a fence across the trough where it meets the bore |
| COVERED (the bore) | d >= 5.98 | 156..1160 | the bore as it is drawn today |

`python tools/city/check_tunnel_portals.py data/city/city.json` prints these stretches (AT_GRADE / OPEN / COVERED).

Today `blender/city/roads/tunnel.py` builds the bore along the WHOLE road: at both ends the white enamel walls and the arch
stand on the street (a 6 m wall across the Lujiazui Ring Rd: the traffic there stood still and a car hit it at 133 km/h), the
walls of the trough stop 4 m over the road (a car on the street falls into the trough where it is deeper), there is no parapet,
no asphalt in the whole tunnel (5,209 lane metres without it), and the ceiling lights of the tunnel hang in the open air at both
ends (56 of them). There is also an old drawing bug: `_zone_profiles` joins the two separate pieces of a zone (the right wall and
the left wall) into ONE polyline, so `build_bores` sweeps a white enamel sheet from the top of one wall (3.2 m) diagonally down to
the foot of the other (0.5 m) right across the carriageway, and a dark one near the road; the cars drive through them
(`HEADROOM_DRAWN`: 5,582 lane metres).

## Evidence (measured on a build of the current city.json with the current tunnel.py)
`python tools/city/check_tunnel_build.py F:/dev/skyrush-out/tmp/portal-base/tiles F:/dev/skyrush-out/tmp/portal-base/data data/city/city.json --quiet`:

    BORE_ABOVE_GROUND    6478   BORE_NOT_COVERED   7424   TROUGH_OUTER_OPEN  236   TROUGH_INNER_OPEN   74
    TROUGH_NOT_DRAWN      144   PORTAL_OPEN          32   HEADROOM             0   HEADROOM_DRAWN    5582
    FLOOR_COLLIDER          0   FLOOR_ASPHALT      5209   STREET_BLOCKED       0   LIGHT_NOT_COVERED   56
    TUNNEL_BUILD FAIL 9

Read the docstring of `tools/city/check_tunnel_build.py`: it says exactly what every check measures (rays and boxes, at which
offsets and heights). Your job is done when every count is 0.

## The geometry you work with (read `tunnel.py` first)
- `road.path[i]` is in Blender space: x east, y NORTH (= -Godot z), **z up**. The depth of sample i is `-road.path[i].z`.
  `road.frames[i] = (tangent, right, up)`. A profile passed to `meshkit.sweep(bm, prof, path, closed_profile=True)` is a list of
  (across, up) points in the road's local frame: across = metres to the right of the centre line, up = metres over the road.
  A profile may also be a function `prof(i, along)` that returns the list for sample i (see `build_wall_colliders`): that is how
  a wall gets a different height at every sample. In that local frame **the ground is at up = depth(i)**.
- `bore_offsets(lay)` = the middle of each carriageway, +-7.25 m. `half = min(ROADWAY * 0.5, BORE_RADIUS - 0.6)` = 3.75.
  The walls of a bore are centred at `sign * (half + 0.35) + offset`, 0.6 m thick (`build_wall_colliders`): from the centre line of
  the road the outer walls are 11.05..11.65 m out, the inner walls 2.85..3.45 m. The ground of the game is cut exactly between
  them (game/world/build/tunnel_trench.gd: 3.8 m either side of the middle of a carriageway), so keep the walls where they are.
- `bore_crown(half)` = 5.98: the crown of the bore over its road. COVER = 5.98 is the depth where the bore fits under the ground.
- Collision goes into a closed mesh added with `builder.add_named("concrete-colonly", bm, surface="concrete")`; what is seen goes in
  with `builder.add(MATERIAL, bm)` (`CONCRETE` = "SH_concrete_pier" for the trough). A wall needs both: the collider and the drawn wall.
- `build_road()` in `build_roads.py` calls `tunnel.build(road, run, builder, lay)` per tile run (`run` = the sample indices in one
  tile), and `tunnel.build_portal(road, builder, lay, at_end)` at the two ends of the road. `excluded` there holds the samples inside
  the junctions (`junctions.trim_indices`); `tiles.split_runs(run, excluded)` gives the runs outside them.

## What to build
1. **Split by depth.** In `tunnel.build`, cut `idx` into runs of the three kinds (neighbouring runs share their boundary sample so
   the meshes meet). Build each kind with its own function.
2. **COVERED**: the bore exactly as today (`build_bores`, `build_stripe`, `build_luminaires`, `build_fixtures`,
   `build_wall_colliders`), with `_zone_profiles` fixed: a zone that is made of several separate pieces gives several polylines,
   and each is swept on its own (never a segment from the end of one piece to the start of the next).
3. **OPEN**: `build_trough(...)`: for each carriageway (`bore_offsets`) and each side, a wall at the same place as the bore wall
   (`x = sign * (half + 0.35) + offset`, 0.6 m thick), from 0.5 m under the road up to the ground (up = depth(i)); the OUTER walls
   (the side away from the centre line of the road: `sign * offset > 0`) go on up to depth(i) + 1.0 (the parapet). Collider AND
   drawn mesh. Only on samples that are not in `excluded` (the trough must not stand in a junction).
4. **The portal face** (where an OPEN run meets a COVERED run): across each carriageway, from the inner wall to the outer wall, a
   beam 0.6 m thick along the road at the boundary sample, from up = max(depth - 0.3, 5.0) to up = depth + 1.0: a car on the ground
   over the bore must not drive into the trough. Collider and drawn mesh.
5. **The floor**: asphalt under the whole tunnel (every kind): `surface.build_asphalt(road, idx, builder, lay)` does it for a
   street, it works for the tunnel's carriageways too.
6. **AT GRADE**: nothing of the tunnel (the asphalt of step 5, and the kerbs, markings and median the generic code builds already).
7. **The height-limit gantry** (`build_portal`): not at the two ends of the road (they are junctions at grade now) but at each
   portal face (step 4), put into the tile of its point (`tileset.builder_at(point)`). Change the call in `build_roads.py`.
8. **The ceiling lights** (`furniture.tunnel_lights`, they become `tunnel_light` records of `road_furniture.json`): only where the
   tunnel is COVERED.

## Files you own
`blender/city/roads/tunnel.py`; in `blender/city/roads/build_roads.py` only the lines that call `tunnel.*`; in
`blender/city/roads/furniture.py` only the function `tunnel_lights`. Everything else is read-only (you may CALL functions of
`surface`, `meshkit`, `profiles`, `tiles`, `collision`). Do not touch `tools/`, `data/`, `game/`.

## Where the build writes (never into the repo)

    python tools/gd.py blender run blender/city/roads/build_roads.py -- --out F:/dev/skyrush-out/tmp/roads-tunnel-trough/tiles --data F:/dev/skyrush-out/tmp/roads-tunnel-trough/data

About 4.5 minutes, prints `DONE in`. To look at one tile only while you work, add `--only tx,tz` (Godot tile keys:
`floor(x / 512)`, `floor(z / 512)`; the Puxi trough is in tile -1,0, the Pudong trough in tile 1,-1) and run the checker on the
full build at the end (the checker reads every tile it needs).

## Plan
1. Read `tunnel.py`, `build_roads.build_road`, `surface.build_asphalt`, `meshkit.sweep` and `tools/city/check_tunnel_build.py`.
2. Write your plan into `status/improve/roads-tunnel-trough.md`.
3. Implement steps 1-8, build, run the checker, read which checks still fail and where (it prints the first places). Repeat.
4. Run all the acceptance commands and put the numbers before / after into the status file.

## Acceptance (the runner executes these itself, in order)
1. The build above prints `DONE in`.
2. `python tools/city/check_tunnel_build.py F:/dev/skyrush-out/tmp/roads-tunnel-trough/tiles F:/dev/skyrush-out/tmp/roads-tunnel-trough/data data/city/city.json --quiet`
   prints `TUNNEL_BUILD OK`.
3. No lane of the city is walled off: `python tools/city/check_path_blockers.py F:/dev/skyrush-out/tmp/roads-tunnel-trough/tiles --lanes F:/dev/skyrush-out/tmp/roads-tunnel-trough/data/lanes.json --max-bad 25 --max-barrier-area 395000`
   prints `PATH_BLOCKERS OK` (25 blocked points today, none of them at the tunnel).
4. The open deck edges do not grow: `python tools/city/check_open_edges.py F:/dev/skyrush-out/tmp/roads-tunnel-trough/tiles F:/dev/skyrush-out/tmp/roads-tunnel-trough/data/lanes.json --max-regular 181 --max-connector 14 --top 0` prints `OPEN_EDGES OK`.
5. The road surface does not lose coverage: `python tools/city/check_surface_coverage.py F:/dev/skyrush-out/tmp/roads-tunnel-trough/tiles F:/dev/skyrush-out/tmp/roads-tunnel-trough/data/lanes.json --max-bad 4187` prints `bad samples` and exits 0.
6. The lanes are untouched: `python -c "import filecmp,sys; sys.exit(0 if filecmp.cmp('F:/dev/skyrush-out/tmp/roads-tunnel-trough/data/lanes.json','F:/dev/skyrush-out/tmp/portal-base/data/lanes.json',shallow=False) else 1)"` exits 0
   (lanes.json is byte for byte the one of the baseline build).

## Pitfalls
- The depth changes along every run: compute it per sample (`-road.path[i].z`), never once per run.
- A wall whose top is fixed at 4.0 m (the old `min(4.0, depth)`) leaves a gap under the ground where the trough is deeper than 4 m:
  `TROUGH_INNER_OPEN` / `TROUGH_OUTER_OPEN` show it. In the COVERED part the walls stay 4 m (inside the bore).
- The rays of the checker run at heights between 0.5 m over the road and 0.9 m over the ground: a gap between the top of a wall
  and the bottom of the parapet, or a parapet that stops 0.5 m short of the portal face, is found.
- Do not build anything across the carriageway between 0.3 and 4.2 m over the road (`HEADROOM`, `HEADROOM_DRAWN`): the portal-face
  beam starts at least 5.0 m over the road, the gantry bar is at 4.2 m.
- The trough walls must stop where the junction trim starts (`excluded`): the connectors of the junctions at grade run there, and
  `STREET_BLOCKED` / `HEADROOM` watch them.
- Do not change the lane graph, the widths of the road, `profiles.py`, `collision.py`, or any limit of a check.
