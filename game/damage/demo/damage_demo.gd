extends Node3D
## The crash demo of the damage unit: the player rams a parked police car at 32 m/s.
## The impact is at t = 0.9 s; the capture tool shoots the sequence at 0.9 / 1.1 / 1.4 / 1.9 s
## (the crash, 0.2 s, 0.5 s and 1.0 s after the impact).
##
## The stage is a wet neon street built here (the environment unit owns the real one), the
## cars are the real ones (the Roadster of the vehicle unit, the police car of the npc_cars
## unit) and the effects come from the fx unit.

const CRASH_SPEED := 32.0
const START_DISTANCE := 32.0
## The camera stands 9 m from the crash and watches it side on.
const CAMERA_POSITION := Vector3(8.2, 1.70, 4.6)
const CAMERA_LOOK := Vector3(0.0, 0.70, 1.0)

var _victim: VehicleBase = null
var _camera: Camera3D = null
var _reported: bool = false
var _frames: int = 0
var _crash_frame: int = -1
var _director: Node = null


func _ready() -> void:
	_build_stage()
	# The fx unit first, so it finds the cars when they arrive. "--nofx" shoots without it.
	if not _has_arg("--nofx"):
		var fx := (load("res://fx/fx_director.tscn") as PackedScene).instantiate()
		if fx != null:
			add_child(fx)
	_director = (load("res://damage/damage_director.tscn") as PackedScene).instantiate()
	add_child(_director)
	_build_cars()
	_build_camera()


## True when the command line holds the flag.
func _has_arg(flag: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == flag:
			return true
	return false


# --- the stage -----------------------------------------------------------------------------------
func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.014, 0.035)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.26, 0.42)
	environment.ambient_light_energy = 1.4
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.1
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.55, 0.62, 0.85)
	sun.light_energy = 0.35
	sun.rotation_degrees = Vector3(-35.0, 140.0, 0.0)
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.93, 0.82)
	lamp.light_energy = 9.0
	lamp.omni_range = 34.0
	lamp.shadow_enabled = false
	add_child(lamp)
	lamp.position = Vector3(0.0, 7.0, 0.0)
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	road.mesh = plane
	var asphalt := load("res://shaders/materials/SH_wet_asphalt.tres")
	if asphalt != null:
		road.material_override = asphalt
	add_child(road)
	# The road needs a body, or the cars fall through it.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(200.0, 2.0, 200.0)
	ground_shape.shape = ground_box
	ground_shape.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(ground_shape)
	add_child(ground)
	_build_neon(-7.0, Color(1.0, 0.17, 0.84))
	_build_neon(7.0, Color(0.10, 0.90, 1.0))
	_build_skyline()


## The dark city around the street: building masses with a few lit windows, so the frame has
## a depth and a value structure (ART.md 2).
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var distance := rng.randf_range(26.0, 62.0)
		var height := rng.randf_range(14.0, 42.0)
		var width := rng.randf_range(8.0, 18.0)
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, height, width)
		block.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.035, 0.038, 0.060)
		material.roughness = 0.9
		block.material_override = material
		block.position = Vector3(side * distance, height * 0.5, rng.randf_range(-60.0, 40.0))
		add_child(block)
		# A few lit window bands.
		for band in 3:
			var window := MeshInstance3D.new()
			var strip := BoxMesh.new()
			strip.size = Vector3(width * 0.55, 0.35, 0.2)
			window.mesh = strip
			var glow := StandardMaterial3D.new()
			glow.albedo_color = Color(0.55, 0.5, 0.4)
			glow.emission_enabled = true
			glow.emission = Color(0.8, 0.72, 0.55)
			glow.emission_energy_multiplier = 1.1
			window.material_override = glow
			window.position = block.position + Vector3(0.0, height * (0.25 + 0.22 * band),
					-side * (width * 0.5 + 0.1))
			add_child(window)


## A neon strip along the street and the light it throws.
func _build_neon(x: float, colour: Color) -> void:
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.12, 70.0)
	strip.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 6.0
	strip.material_override = material
	strip.position = Vector3(x, 0.12, 0.0)
	add_child(strip)
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 3.0
	light.omni_range = 22.0
	light.position = Vector3(x * 0.6, 4.0, 0.0)
	add_child(light)


# --- the cars ------------------------------------------------------------------------------------
func _build_cars() -> void:
	var player := (load("res://vehicle/player_car.tscn") as PackedScene).instantiate() as ArcadeCar
	player.player_controlled = false
	add_child(player)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, START_DISTANCE))
	player.linear_velocity = Vector3(0.0, 0.0, -CRASH_SPEED)
	player.add_to_group(&"vehicles")
	Game.player = player
	_victim = _make_victim()
	add_child(_victim)
	_victim.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))
	_victim.add_to_group(&"vehicles")


## A parked police car: a plain rigid body with the police glb as its visual.
func _make_victim() -> VehicleBase:
	var car := VehicleBase.new()
	car.team = VehicleBase.Team.POLICE
	car.max_health = 60.0
	car.mass = 1800.0
	car.collision_layer = 2
	car.collision_mask = 7
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.45, 4.6)
	shape.shape = box
	shape.position = Vector3(0.0, 0.72, 0.0)
	car.add_child(shape)
	var visual := Node3D.new()
	visual.name = "Visual"
	car.add_child(visual)
	var model := (load("res://assets/cars/npc/police_patrol.glb") as PackedScene).instantiate()
	visual.add_child(model)
	MaterialLibrary.apply(model)
	return car


# --- the camera ----------------------------------------------------------------------------------
func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 52.0
	add_child(_camera)
	var position := CAMERA_POSITION
	var look := CAMERA_LOOK
	# "--cam=front" shoots the dent on the victim from the other side of the crash.
	for arg in OS.get_cmdline_user_args():
		if arg == "--cam=front":
			position = Vector3(6.4, 1.55, -6.2)
			look = Vector3(0.0, 0.70, -1.6)
	_camera.global_position = position
	_camera.look_at(look, Vector3.UP)


## The camera looks at the wreck, so the wreck stays in the frame while it tumbles.
func _process(_delta: float) -> void:
	_frames += 1
	if _camera == null or _victim == null or not is_instance_valid(_victim):
		return
	var look := _victim.global_position + Vector3(0.0, 0.1, -1.0)
	_camera.look_at(look, Vector3.UP)
	_report()


## The state of the crash, once (the printout is the evidence of the capture).
func _report() -> void:
	if _reported or _director == null:
		return
	var state = _director.call("state_of", _victim)
	if state == null or state.detached.is_empty():
		return
	# The report comes a quarter of a second after the crash, when the debris is in the air.
	if _crash_frame < 0:
		_crash_frame = _frames
		return
	if _frames < _crash_frame + 30:
		return
	_reported = true
	var flying := 0
	var highest := 0.0
	var pool := _director.get_node_or_null("DebrisPool")
	if pool != null:
		for body: Node in pool.get_children():
			var rigid := body as RigidBody3D
			if rigid == null or not rigid.visible:
				continue
			flying += 1
			highest = maxf(highest, rigid.global_position.y)
	print("REVIEW the crash: detached=%s debris=%d highest=%.2f m hp=%.1f" % [
		state.detached.keys(), flying, highest, _victim.health])
