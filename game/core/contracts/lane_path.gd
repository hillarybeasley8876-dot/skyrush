class_name LanePath
extends Resource
## One drivable lane for AI (traffic, police, rivals): a Curve3D in world space along the lane centre,
## pointing in the driving direction. Produced by the world unit.

@export var curve: Curve3D
@export var speed_limit_kmh: float = 80.0
@export var lane_width: float = 3.5
@export var road_id: StringName = &""
@export var elevated: bool = false
## Lane indices this lane can continue into at its end (indices into WorldBase.get_lane_paths()).
@export var next_lanes: PackedInt32Array = PackedInt32Array()
