# game/ai/common — shared AI driving helpers

Generic, unit-agnostic helpers for every AI driver in SKYRUSH (traffic, police, rivals). Nothing
here knows about Shanghai, about the traffic director or about a specific car: the units own their
own behaviour and reuse these pieces.

| File | What it gives you |
|---|---|
| `lane_graph.gd` (`LaneGraph`) | Lane adjacency and geometry built from a world's `Array[LanePath]`: left/right neighbours and the distance between their centres, continuations at lane ends, baked lengths, position / tangent / right sampling, signed lateral offset. |
| `lane_links.gd` (`LaneLinks`) | The continuations of a lane: the link is only kept when the two lanes really meet (the entry is within 20 m, on the same level, the turn is under 100°), the entry point is stored and a cubic Hermite **connector** curve leads through the junction box. |
| `lane_neighbours.gd` (`LaneNeighbours`) | The lanes that run side by side: same level (a deck above is not a neighbour), same direction, one lane width apart. |
| `lane_sampler.gd` (`LaneSampler`) | The baked points of one lane and the fast sampling of them (binary search instead of `Curve3D.sample_baked`, which scans the points linearly and is far too slow for the traffic). |
| `lane_follower.gd` (`LaneFollower`) | The lane state of one car: which lane, how far along it, the lateral offset, the lane-change S-curve (2.5 s, smoothstep) and the weighted next-lane choice at a lane end (`TURN_CHANCE` against "straight on"). |
| `lane_hash.gd` (`LaneHash`) | Cars bucketed per lane, so leader and follower are found without an O(n) scan. A flat list with a linked list per lane: nothing is allocated while the index is filled. |
| `lane_grid.gd` (`LaneGrid`) | A static grid of the lane samples: "which lanes are near this point" without walking the lanes of the city (the traffic needs it every tick, the ring every two seconds). |
| `idm.gd` (`IDM`) | The Intelligent Driver Model (Treiber) with the SKYRUSH game values (T 1.2 s, a 2.0 m/s², b 3.0 m/s², s0 2.5 m, 8 m/s² emergency cap) plus the MOBIL-lite lane-change test (`should_change_lane`). |
| `steering.gd` (`AISteering`) | Heading error, yaw rate, pure-pursuit steer and the lateral correction that pulls a car back onto its lane centre. |
| `drive_context.gd` (`DriveContext`) | The per-tick bundle (graph, hash, player, world, clock) the units hand to their cars, so no unit has to reference another unit's class. |

## Conventions
- Metres, seconds, radians. Godot: Y up, −Z forward, +X right.
- A lane's *lateral offset* is signed against the driving direction: positive = to the right.
- A positive heading error / yaw rate means "turn left" (right-hand rule about +Y).
- `LanePath.curve` points along the driving direction of the lane; the lane's speed limit is
  `speed_limit_kmh`, its width `lane_width`.

## The queries a driver asks the graph
| Question | Answer |
|---|---|
| Where am I on the lane? | `position_at(lane, s)`, `tangent_at(lane, s)`, `right_at(lane, s)` |
| Which lane is next to mine? | `left[lane]`, `right[lane]`, `left_gap[lane]`, `right_gap[lane]` |
| How far is the neighbour, where I am? | `neighbour_gap(lane, neighbour, s)` - the distance between the two centres at the place of the car, not the average of the lane |
| Which point of the neighbour lies beside me? | `aligned_offset(lane, neighbour, s)` - the two lanes do not run for the same length, so the same number of metres is not the same place on the road |
| Where does the lane end and what comes next? | `next_lanes[lane]`, `straight_next[lane]`, `turn_next[lane]` |
| Where do I enter the next lane? | `entry_offset(lane, next)` - the distance along the next lane where the car enters it |
| How do I turn through the junction? | `connector_of(lane, next)` - the Hermite curve through the junction box, `connector_length(lane, next)` its length |
| Does the road end here? | `is_dead_end(lane)` - a lane with no continuation that is not a loop |
| Is this lane built twice? | `is_duplicate(lane)` - the world builds a few roads twice, and two cars on the twin lanes drive through each other |

## How a unit uses them
```gdscript
var graph := LaneGraph.new()
graph.build(world.get_lane_paths())          # once per world

var follower := LaneFollower.new()
follower.setup(graph, lane_index, 0.0, seed) # per car

# every tick:
var gap := ctx.hash.leader_gap(follower.lane, follower.index_s(), car_length)
var accel := IDM.acceleration(speed, v0, gap, speed - leader_speed)
```
`follower.index_s()` is the place of the car in the per-lane index: on a junction connector that
is the end of the lane the car came from plus the distance it has driven on the connector, so the
car never finds **itself** as its own leader.
