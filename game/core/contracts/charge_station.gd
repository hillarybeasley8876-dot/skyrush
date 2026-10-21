class_name ChargeStation
extends Area3D
## Drive-through flash-charging bay (申城闪充, ref/gameplay/DOSSIER.md §3.4). Entering at ≥ min_kmh
## starts a flash; after flash_time Events.charge_finished fires and the vehicle unit refills N₂ to
## 200, the battery to 1.0 and adds +20 HP for its own car. Per-vehicle cooldown. Placed by the
## world unit (which also builds the visual bay).

@export var label: String = "申城闪充"
@export var min_kmh: float = 60.0
@export var flash_time: float = 0.6
@export var cooldown: float = 30.0

var _ready_at: Dictionary = {}  # VehicleBase instance id -> time (s) when it may charge again


func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 1 << 1
	monitorable = false
	body_entered.connect(_on_body_entered)


## Seconds until this vehicle may charge again (0 = ready). HUD/minimap may show it.
func cooldown_left(vehicle: VehicleBase) -> float:
	return maxf(float(_ready_at.get(vehicle.get_instance_id(), 0.0)) - _now(), 0.0)


func _on_body_entered(body: Node3D) -> void:
	var vehicle := body as VehicleBase
	if vehicle == null or vehicle.is_wrecked or vehicle.get_speed_kmh() < min_kmh:
		return
	if cooldown_left(vehicle) > 0.0:
		return
	_ready_at[vehicle.get_instance_id()] = _now() + cooldown
	Events.charge_started.emit(vehicle, self)
	await get_tree().create_timer(flash_time, false).timeout
	if is_instance_valid(vehicle):
		Events.charge_finished.emit(vehicle, self, 1.0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
