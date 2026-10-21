class_name StuntGate
extends Area3D
## Invisible volume over an obstacle (gas station canopy, toll plaza, police roadblock...). When the
## player's car passes through it while airborne it awards a named stunt once per pass.
## Placed by the world unit; scoring/HUD react to Events.stunt.

@export var kind: StringName = &"fly_over_gas"
@export var points: int = 800
@export var label: String = "飞跃加油站!"
@export var cooldown: float = 6.0

var _next_ok: float = 0.0


func _ready() -> void:
	collision_layer = 1 << 3
	collision_mask = 1 << 1
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var vehicle := body as VehicleBase
	if vehicle == null or vehicle.team != VehicleBase.Team.PLAYER or not vehicle.is_airborne():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_ok:
		return
	_next_ok = now + cooldown
	Events.stunt.emit(kind, points, label)
