class_name SkyLane
extends Path3D
## A flight corridor (飞行航道, ref/gameplay/DOSSIER.md §5.6). Built by the world unit: keep this
## node at the identity transform so `curve` points are world positions along the lane centre.
## A child Area3D named "LaunchPad" marks the launch ramp at the start; touching it emits
## Events.sky_lane_launch and the vehicle unit decides whether the car can take off (speed, N₂)
## and then flies it along the curve inside the tube. Ring gates/holograms are visuals owned by
## the world unit (one every `ring_spacing` metres from the start).

@export var label: String = "飞行航道"
@export var tube_half_width: float = 7.0
@export var tube_up: float = 5.0
@export var tube_down: float = 3.0
@export var min_entry_kmh: float = 120.0
@export var min_n2: float = 25.0
@export var cruise_kmh: float = 200.0
@export var ring_spacing: float = 40.0
## Offsets (m along the curve) of N₂ refill rings (+40 N₂ each).
@export var n2_ring_offsets: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var pad := get_node_or_null(^"LaunchPad") as Area3D
	if pad == null:
		push_error("SkyLane %s has no LaunchPad Area3D child" % name)
		return
	pad.collision_layer = 1 << 3
	pad.collision_mask = 1 << 1
	pad.monitorable = false
	pad.body_entered.connect(_on_pad_body_entered)


func length() -> float:
	return curve.get_baked_length() if curve != null else 0.0


## Lane frame at an offset: origin on the centre line, -Z along the lane, Y up (no roll).
func frame_at(offset: float) -> Transform3D:
	var p := curve.sample_baked(offset, true)
	var ahead := curve.sample_baked(minf(offset + 2.0, length()), true)
	if ahead.is_equal_approx(p):
		ahead = p + (p - curve.sample_baked(maxf(offset - 2.0, 0.0), true))
	return Transform3D(Basis.IDENTITY, p).looking_at(ahead, Vector3.UP)


func _on_pad_body_entered(body: Node3D) -> void:
	var vehicle := body as VehicleBase
	if vehicle != null:
		Events.sky_lane_launch.emit(vehicle, self)
