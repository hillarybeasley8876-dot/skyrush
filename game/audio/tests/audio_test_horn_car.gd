extends RigidBody3D
## A test double for a traffic car: it carries the horn signal of the traffic unit
## (game/ai/traffic/traffic_car.gd :: horn_requested) and a telemetry for the hum pitch.

signal horn_requested(car: Node3D)

var telemetry := CarTelemetry.new()


func _ready() -> void:
	add_to_group(&"traffic")
	freeze = true


## Sounds the horn (the traffic unit calls this).
func horn() -> void:
	horn_requested.emit(self)
