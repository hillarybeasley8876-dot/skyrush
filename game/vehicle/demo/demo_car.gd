extends Node3D
## A small demo scene for the vehicle unit: the sandbox test track, the player car and a simple
## chase camera. It exists so the windowed evidence shots show the car without the menu, the HUD
## or the other units in the way.
##
## Run: tools/godot.sh shot --scene=res://vehicle/demo/demo_car.tscn --spawn=0,0.2,0,0 ...

const SandboxScene := preload("res://core/sandbox/sandbox.tscn")
const CarScene := preload("res://vehicle/player_car.tscn")
const DebugOverlay := preload("res://core/debug_overlay.gd")
## The environment of the environment unit (the night sky, the moon and the fog).
const EnvironmentScene := preload("res://world/env/environment.tscn")

## The chase camera: 7 m behind the car, 2.6 m up.
const CHASE_BACK := 7.0
const CHASE_UP := 2.6
const CHASE_LOOK_UP := 0.9
const CHASE_FOV := 62.0
## The chase camera follows the car with this rate (1/s): the lag is the speed / the rate.
const CHASE_RATE := 12.0
## The rear camera (the evidence of the wing and the brake light).
const REAR_BACK := 3.4
const REAR_UP := 1.5
## The side camera (the evidence of a jump: the car is seen from the side).
const SIDE_OFFSET := 7.0
const SIDE_UP := 2.0
## The lamp that follows the car.
const LAMP_ENERGY := 3.0
const LAMP_RANGE := 18.0
const LAMP_HEIGHT := 6.0

## The car.
var car: ArcadeCar = null
## The chase camera.
var chase: Camera3D = null

var _look_at: Vector3 = Vector3.ZERO
## True when the camera sits close behind the car (the evidence of the wing).
var _rear_cam: bool = false
## True when the camera sits at the side of the car (the evidence of a jump).
var _side_cam: bool = false


func _ready() -> void:
	var world: Node3D = SandboxScene.instantiate() as Node3D
	world.name = "Sandbox"
	add_child(world)
	# The environment of the environment unit: the evidence has to show the hero car in the
	# night city, not in a flat grey box.
	add_child(EnvironmentScene.instantiate())
	car = CarScene.instantiate() as ArcadeCar
	add_child(car)
	car.reset_to(_spawn_transform())
	Game.player = car
	chase = Camera3D.new()
	chase.fov = CHASE_FOV
	chase.near = 0.1
	chase.far = 4000.0
	add_child(chase)
	chase.current = true
	_rear_cam = Game.option("rearcam") != ""
	_side_cam = Game.option("sidecam") != ""
	_look_at = car.global_position + Vector3.UP
	_build_lights()
	if Game.option("debug") != "":
		add_child(DebugOverlay.new())


## The environment scene brings the night sky and the moon; the demo only adds the lamp that
## follows the car, so the paint reads in the shots.
func _build_lights() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_energy = LAMP_ENERGY
	lamp.omni_range = LAMP_RANGE
	lamp.light_color = Color(0.8, 0.9, 1.0)
	add_child(lamp)


## The spawn from --spawn=x,y,z,yaw_deg, the sandbox spawn otherwise.
func _spawn_transform() -> Transform3D:
	var parts: PackedStringArray = Game.option("spawn").split(",", false)
	if parts.size() >= 3:
		var yaw: float = deg_to_rad(float(parts[3])) if parts.size() >= 4 else 0.0
		return Transform3D(Basis(Vector3.UP, yaw),
				Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0))


func _physics_process(delta: float) -> void:
	if car == null or chase == null:
		return
	# A simple chase camera: 7 m behind, 2.6 m up, looking at the car. The side camera
	# (the evidence of a jump) stands next to the car.
	var basis: Basis = car.global_transform.basis
	var back: Vector3 = basis.z * (REAR_BACK if _rear_cam else CHASE_BACK)
	var up: Vector3 = Vector3.UP * (REAR_UP if _rear_cam else CHASE_UP)
	if _side_cam:
		back = basis.x * SIDE_OFFSET
		up = Vector3.UP * SIDE_UP
	var target: Vector3 = car.global_position + Vector3.UP * CHASE_LOOK_UP
	var wanted: Vector3 = car.global_position + back + up
	# The follow is frame rate independent: the lag is the speed / CHASE_RATE.
	var blend: float = 1.0 - exp(-CHASE_RATE * delta)
	chase.global_position = chase.global_position.lerp(wanted, blend)
	_look_at = _look_at.lerp(target, blend)
	chase.look_at(_look_at, Vector3.UP)
	var lamp: OmniLight3D = get_node_or_null(^"OmniLight3D") as OmniLight3D
	if lamp != null:
		lamp.global_position = car.global_position + Vector3.UP * LAMP_HEIGHT
