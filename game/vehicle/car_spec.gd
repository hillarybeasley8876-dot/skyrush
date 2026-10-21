class_name CarSpec
extends Resource
## Per-vehicle data (mass, geometry, grip, top speed, visual). Every car in the game — player,
## rivals, police, traffic — is one ArcadeCar driven by one of these presets, so a new car is a
## .tres file, not a new scene. Physics *constants* live in vehicle/tuning/; only
## per-car differences belong here.

const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")

@export var id: StringName = &"roadster"
@export var display_name: String = "Roadster"

# --- body ---------------------------------------------------------------------------------------
@export var mass: float = 1900.0
## Centre of mass in body-local space (origin on the ground between the axles).
@export var center_of_mass: Vector3 = Vector3(0.0, 0.42, -0.05)
## Diagonal inertia: x = pitch, y = yaw, z = roll.
@export var inertia: Vector3 = Vector3(3400.0, 3200.0, 900.0)
@export var body_size: Vector3 = Vector3(1.95, 0.80, 4.38)
## Height of the body box centre above the origin.
@export var body_center_y: float = 0.62
@export var max_health: float = 100.0

# --- wheels -------------------------------------------------------------------------------------
## Probe mount points in body-local space, order FL, FR, RL, RR. The mount is the top of the
## suspension travel; the wheel centre hangs REST_LEN below it.
@export var wheel_mounts: Array[Vector3] = [
	Vector3(-0.78, 0.686, -1.4125), Vector3(0.78, 0.686, -1.4125),
	Vector3(-0.815, 0.710, 1.4125), Vector3(0.815, 0.710, 1.4125),
]
## Tyre radii, same order.
@export var wheel_radii: Array[float] = [0.3425, 0.3425, 0.367, 0.367]
@export var steered: Array[bool] = [true, true, false, false]
@export var driven: Array[bool] = [false, false, true, true]

# --- suspension (per car, so every preset settles on its wheels) ---------------------------------
## The spring rate per wheel (N/m). It is mass * g / 4 / STATIC_SAG, so the static sag is the
## same for every car and a heavy one does not sit on its bump stops.
@export var spring_k: float = 70000.0
## The damper rates (N*s/m), scaled with sqrt(k * m) so the damping ratio stays the same.
@export var damp_bump: float = 4600.0
@export var damp_rebound: float = 6300.0
## The anti roll bar rates (N/m), scaled with the spring rate.
@export var arb_front: float = 28000.0
@export var arb_rear: float = 20000.0
## The bump stop (N/m) and the ceiling of the suspension force (N), scaled with the spring rate.
@export var bumpstop_k: float = 300000.0
@export var susp_max: float = 60000.0
## The unloaded anchor -> wheel centre distance (m) and the travel before the bump stop (m).
@export var rest_len: float = 0.41
@export var travel: float = 0.20

# --- performance --------------------------------------------------------------------------------
@export var top_speed: float = 69.44      ## m/s (250 km/h)
@export var accel: float = 14.0           ## m/s^2 at standstill
@export var brake_accel: float = 16.0     ## m/s^2
@export var mu_front: float = 1.45
@export var mu_rear: float = 1.40

# --- presentation --------------------------------------------------------------------------------
## Path of the imported glb, e.g. "res://assets/cars/roadster/roadster.glb". Empty = placeholder.
@export var visual_scene_path: String = ""
## Wing / panel pose metadata. extras.poses = {name: {"angle": deg, "height": m}}.
@export var extras: Dictionary = {}


## Loads the visual scene, or null when the glb is missing (the car then builds a placeholder).
func load_visual() -> PackedScene:
	if visual_scene_path.is_empty() or not ResourceLoader.exists(visual_scene_path):
		return null
	return load(visual_scene_path) as PackedScene


## True when the wheel index steers.
func is_steered(index: int) -> bool:
	return index >= 0 and index < steered.size() and steered[index]


## True when the wheel index is driven by the motor.
func is_driven(index: int) -> bool:
	return index >= 0 and index < driven.size() and driven[index]


## Pose metadata for the active wing pose, or an empty dictionary.
func pose(name: StringName) -> Dictionary:
	var poses: Dictionary = extras.get("poses", {}) as Dictionary
	return poses.get(name, {}) as Dictionary


## The suspension of a car with the given mass: the spring keeps the static sag of the roadster
## at every mass, the dampers follow sqrt(k * m) (the damping ratio stays the same) and the
## anti roll bars and the bump stops follow the spring rate.
static func suspension_for(mass: float) -> Dictionary:
	var k: float = mass * SuspensionTuning.GRAVITY / 4.0 / SuspensionTuning.STATIC_SAG
	var ratio: float = k / SuspensionTuning.SPRING_K
	var damp: float = sqrt(k * mass) / sqrt(SuspensionTuning.SPRING_K
			* SuspensionTuning.REFERENCE_MASS)
	return {
		"spring_k": k,
		"damp_bump": SuspensionTuning.DAMP_BUMP * damp,
		"damp_rebound": SuspensionTuning.DAMP_REBOUND * damp,
		"arb_front": SuspensionTuning.ARB_FRONT * ratio,
		"arb_rear": SuspensionTuning.ARB_REAR * ratio,
		"bumpstop_k": SuspensionTuning.BUMPSTOP_K * ratio,
		"susp_max": SuspensionTuning.SUSP_MAX * ratio,
		"rest_len": SuspensionTuning.REST_LEN,
		"travel": SuspensionTuning.TRAVEL,
	}
