extends Node3D
## The acceptance shot of the damage unit: the real Roadster and a police car are hit three
## times each (side 16 m/s, front 22 m/s, rear 14 m/s) and the camera watches from 6 m, so
## the dent, the scrape and the paint can be read.
##
## The hits land on a PANEL (not on the middle of the car), so the dent is really on the
## surface that was hit. The scene runs under the environment of the game, so the dents are
## judged under the reflections of the city.
##
## "--heavy" adds a fourth hit (a rear hit at 18 m/s) and looks at the Roadster from the
## other side. "--close" frames the dented panel from 2 m. "--dents-only" and "--mask-only"
## switch the layers off, so the dent and the scrape can be judged apart.

## One hit: the time, the velocity of the car, the normal of the contact and the point of
## the contact in the space of the car.
const HITS: Array = [
	[1.3, Vector3(-16.0, 0.0, 8.0), Vector3(1.0, 0.0, 0.0), Vector3(-0.95, 0.62, 0.75)],
	[1.6, Vector3(0.0, 0.0, -22.0), Vector3(0.0, 0.0, 1.0), Vector3(0.10, 0.60, -2.20)],
	[1.9, Vector3(0.0, 0.0, 14.0), Vector3(0.0, 0.0, -1.0), Vector3(0.05, 0.62, 2.05)],
]
const HEAVY_HIT: Array = [2.15, Vector3(0.0, 0.0, 18.0), Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, 0.66, 2.05)]

var _cam: Camera3D = null
var _roadster: VehicleBase = null
var _police: VehicleBase = null
var _wall: StaticBody3D = null
var _director: Node = null
var _t: float = 0.0
var _step: int = 0
var _close: bool = false
## True when the cars are frozen: the shot must be the same every time.
var _frozen: bool = false
## The place of the cars before the hits, by the id of the car.
var _rest: Dictionary = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_close = args.has("--close")
	# The environment of the game: the dents are judged under its reflections.
	var environment := (load("res://world/env/environment.tscn") as PackedScene).instantiate()
	add_child(environment)
	for z: float in [-4.0, 4.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.93, 0.82)
		lamp.light_energy = 4.0
		lamp.omni_range = 16.0
		lamp.position = Vector3(3.5, 5.0, z)
		add_child(lamp)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	floor.mesh = plane
	floor.material_override = load("res://shaders/materials/SH_wet_asphalt.tres")
	add_child(floor)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(100.0, 2.0, 100.0)
	gs.shape = gb
	gs.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(gs)
	add_child(ground)
	_wall = StaticBody3D.new()
	add_child(_wall)
	_director = (load("res://damage/damage_director.tscn") as PackedScene).instantiate()
	add_child(_director)
	_roadster = (load("res://vehicle/player_car.tscn") as PackedScene).instantiate() as VehicleBase
	_roadster.set("player_controlled", false)
	add_child(_roadster)
	_roadster.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, -4.0))
	_roadster.add_to_group(&"vehicles")
	Game.player = _roadster
	_police = _make_police()
	_rest[_roadster.get_instance_id()] = _roadster.global_transform
	_rest[_police.get_instance_id()] = _police.global_transform
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.make_current()


func _make_police() -> VehicleBase:
	var car := VehicleBase.new()
	car.team = VehicleBase.Team.POLICE
	car.max_health = 60.0
	car.health = 60.0
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
	add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 4.0))
	car.add_to_group(&"vehicles")
	return car


func _process(delta: float) -> void:
	_t += delta
	var hits: Array = HITS.duplicate()
	if OS.get_cmdline_user_args().has("--heavy"):
		hits.append(HEAVY_HIT)
	if _step < hits.size() and _t >= float(hits[_step][0]):
		var h: Array = hits[_step]
		_step += 1
		for car: VehicleBase in [_roadster, _police]:
			_hit(car, h[1], h[2], h[3])
	# The cars stand still once they have been hit: the shot must be the same every time.
	if _step >= hits.size() and not _frozen:
		_frozen = true
		for car: VehicleBase in [_roadster, _police]:
			car.freeze = true
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			car.global_transform = _rest[car.get_instance_id()]
	var after := _t >= 2.4
	var on_roadster := (_t < 0.7) or (after and _t < 3.0)
	var args := OS.get_cmdline_user_args()
	# "--close" frames the dented panel from 2 m: the door of the Roadster (the side hit)
	# or the door of the police car.
	if _close:
		if args.has("--police"):
			_look(Vector3(-2.9, 1.05, 1.6), Vector3(-0.9, 0.70, 4.2))
		elif args.has("--front"):
			_look(Vector3(1.4, 0.95, -7.0), Vector3(0.1, 0.62, -6.2))
		else:
			_look(Vector3(-2.75, 1.00, -4.75), Vector3(-0.92, 0.67, -3.25))
	elif after and args.has("--heavy"):
		_look(Vector3(3.4, 1.25, -8.9), Vector3(0.2, 0.75, -4.6))
	elif on_roadster:
		_look(Vector3(4.6, 1.6, -8.4), Vector3(0.6, 0.55, -4.6))
	else:
		_look(Vector3(4.6, 1.6, 8.6), Vector3(0.6, 0.6, 4.6))
	if _step >= 3 and _t >= 2.3 and _t - delta < 2.3:
		for car: VehicleBase in [_roadster, _police]:
			var st = _director.call("state_of", car)
			if args.has("--dents-only") or args.has("--mask-only"):
				st.painter.set_damage_enabled(not args.has("--mask-only"),
						not args.has("--dents-only"))
			print("REVIEW %s hp=%.1f tier=%d dents=%d mask=%.5f uploads=%d detached=%s" % [
				car.name, car.health, st.tier, st.painter.dent_count(),
				st.painter.mask_coverage(), st.painter.upload_count(), st.detached.keys()])


## A hit on a panel of the car: the car is moved with the velocity of the hit, the contact
## is reported at the point of the panel.
func _hit(car: VehicleBase, velocity: Vector3, normal: Vector3, panel_point: Vector3) -> void:
	var keep := car.global_transform
	car.linear_velocity = velocity
	await get_tree().physics_frame
	await get_tree().physics_frame
	var contact := car.global_transform * panel_point
	Events.vehicle_collided.emit(car, _wall, car.mass * velocity.length(), contact, normal)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = keep



func _look(pos: Vector3, target: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(target, Vector3.UP)
