extends Node
## The wreck flow of dossier 7.8: the player is wrecked, gets the crash cam and respawns on
## the nearest lane with 60 HP and a 2 s ghost.

const Kit := preload("res://damage/tests/damage_test_kit.gd")
const WreckFlow := preload("res://damage/wreck_flow.gd")

var _failures: int = 0
var _respawned: int = 0
var _focused: int = 0
var _toasts: Array = []


func _ready() -> void:
	Events.player_respawned.connect(_on_respawned)
	Events.camera_focus.connect(_on_focus)
	Events.toast.connect(_on_toast)
	var sandbox: Node = (load("res://core/sandbox/sandbox.tscn") as PackedScene).instantiate()
	add_child(sandbox)
	await Kit.wait_frames(get_tree(), 2)
	_expect("the sandbox is the world", Game.world != null)
	var director := Kit.make_director(self)
	var player := Kit.make_car(VehicleBase.Team.PLAYER, 100.0, 1900.0)
	player.add_to_group(&"vehicles")
	add_child(player)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	Game.player = player
	# A police car drives into the player at 32 m/s.
	var attacker := Kit.make_car(VehicleBase.Team.POLICE, 60.0, 1900.0)
	attacker.add_to_group(&"vehicles")
	add_child(attacker)
	attacker.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.0, -12.0))
	attacker.linear_velocity = Vector3(0.0, 0.0, 32.0)
	await Kit.wait_frames(get_tree(), 3)
	var crash_position := player.global_position
	# The contact: the normal points out of the player, towards the attacker.
	Events.vehicle_collided.emit(attacker, player, 1900.0 * 32.0, Vector3(0.0, 0.6, -2.0),
			Vector3(0.0, 0.0, -1.0))
	await Kit.wait_frames(get_tree(), 2)
	_expect("the player is wrecked", player.is_wrecked)
	_expect("the crash cam was asked for", _focused == 1)
	_expect("the wreck banner was shown", _toasts.has("撞车 WRECKED"))
	_expect("the player was not respawned yet", _respawned == 0)

	# The crash cam runs for 2.2 s of game time, then the player is back on the road. The
	# wait is on the scene tree's clock, like the wreck flow itself.
	await get_tree().create_timer(2.4, true, false, true).timeout
	await Kit.wait_frames(get_tree(), 4)
	_expect("the player respawned", _respawned == 1)
	_approx("the player has 60 HP", player.health, 60.0)
	_expect("the player is back on the road",
			player.global_position.distance_to(crash_position) > 5.0)
	_expect("the player drives again", player.linear_velocity.length() > 5.0)
	_expect("the ghost ignores the cars", (player.collision_mask & 2) == 0)
	_expect("the ghost still hits the world", (player.collision_mask & 1) == 1)
	# The player must be able to take damage again after the respawn.
	_expect("the player is not wrecked any more", not player.is_wrecked)
	await _hit_wall(player, 20.0)
	_approx("a 20 m/s hit costs 16.9 HP", 60.0 - player.health, 16.9, 0.5)

	# The ghost: a car drives through the player, and is blocked when the ghost is over.
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var ghost_car := _make_driver(player.global_position - forward * 8.0, forward)
	await Kit.wait_frames(get_tree(), 40)
	_expect("the ghost lets the car through",
			ghost_car.global_position.distance_to(player.global_position) > 4.0)
	await get_tree().create_timer(2.2, true, false, true).timeout
	await Kit.wait_frames(get_tree(), 2)
	var solid_car := _make_driver(player.global_position - forward * 8.0, forward)
	await Kit.wait_frames(get_tree(), 40)
	_expect("the car is blocked when the ghost is over",
			solid_car.global_position.distance_to(player.global_position) > 2.0)
	await _test_head_on()
	await _test_ghost_alpha()
	await _test_doors()
	print(("FAIL" if _failures > 0 else "PASS") + " respawn (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## A head-on at 30 m/s each way: the player comes back at 70 % of its own speed, not at the
## speed of the whole impact (dossier §7.8).
func _test_head_on() -> void:
	var player := Kit.make_car(VehicleBase.Team.PLAYER, 100.0, 1900.0)
	player.add_to_group(&"vehicles")
	add_child(player)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	Game.player = player
	var attacker := Kit.make_car(VehicleBase.Team.POLICE, 60.0, 1900.0)
	attacker.add_to_group(&"vehicles")
	add_child(attacker)
	attacker.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.0, -12.0))
	# Both cars drive at 30 m/s into each other.
	player.linear_velocity = Vector3(0.0, 0.0, -30.0)
	attacker.linear_velocity = Vector3(0.0, 0.0, 30.0)
	await Kit.wait_frames(get_tree(), 3)
	Events.vehicle_collided.emit(attacker, player, 1900.0 * 60.0, Vector3(0.0, 0.6, -2.0),
			Vector3(0.0, 0.0, -1.0))
	await Kit.wait_frames(get_tree(), 2)
	_expect("the player of a head-on is wrecked", player.is_wrecked)
	await get_tree().create_timer(2.4, true, false, true).timeout
	await Kit.wait_frames(get_tree(), 4)
	var speed := player.linear_velocity.length()
	_approx("the player comes back at 21.0 m/s", speed, 21.0, 0.5)
	# The car must drive along the road, not against it.
	var road_forward := -player.global_transform.basis.z
	road_forward.y = 0.0
	if road_forward.length() > 0.01:
		road_forward = road_forward.normalized()
		var drive := player.linear_velocity
		drive.y = 0.0
		if drive.length() > 0.01:
			drive = drive.normalized()
			_expect("the player drives along the road (%.3f)" % drive.dot(road_forward),
					drive.dot(road_forward) > 0.99)


## The ghost of the player fades in and out: its alpha reaches 0.35 and 0.65 in the 2 s.
func _test_ghost_alpha() -> void:
	var player := Kit.make_car(VehicleBase.Team.PLAYER, 100.0, 1900.0)
	player.add_to_group(&"vehicles")
	add_child(player)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	Game.player = player
	var attacker := Kit.make_car(VehicleBase.Team.POLICE, 60.0, 1900.0)
	attacker.add_to_group(&"vehicles")
	add_child(attacker)
	attacker.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.0, -12.0))
	attacker.linear_velocity = Vector3(0.0, 0.0, 32.0)
	await Kit.wait_frames(get_tree(), 3)
	Events.vehicle_collided.emit(attacker, player, 1900.0 * 32.0, Vector3(0.0, 0.6, -2.0),
			Vector3(0.0, 0.0, -1.0))
	await Kit.wait_frames(get_tree(), 2)
	await get_tree().create_timer(2.4, true, false, true).timeout
	await Kit.wait_frames(get_tree(), 4)
	var lowest := 1.0
	var highest := 0.0
	for i in 40:
		await Kit.wait_frames(get_tree(), 3)
		var alpha := _transparency_of(player)
		lowest = minf(lowest, alpha)
		highest = maxf(highest, alpha)
	_expect("the ghost fades to %.2f (at most 0.35)" % lowest, lowest <= 0.35)
	_expect("the ghost brightens to %.2f (at least 0.65)" % highest, highest >= 0.65)


## The transparency of the meshes of the car.
func _transparency_of(car: VehicleBase) -> float:
	var visual := car.get_visual_root()
	if visual == null:
		return 0.0
	var value := 0.0
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		value = maxf(value, (child as GeometryInstance3D).transparency)
	return value


## A door that sprang open is closed again by the respawn.
func _test_doors() -> void:
	var player := (load("res://vehicle/player_car.tscn") as PackedScene).instantiate() as VehicleBase
	player.set("player_controlled", false)
	player.add_to_group(&"vehicles")
	add_child(player)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	Game.player = player
	var door := player.get_visual_root().find_child("Door_L", true, false) as MeshInstance3D
	if door == null:
		_expect("the car has a door to test", false)
		return
	var rest := door.transform
	# A hit on the side: the door springs open.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 8.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, -12.0))
	player.linear_velocity = Vector3(-20.0, 0.0, 0.0)
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(player, wall, 1900.0 * 20.0, Vector3(-0.9, 0.6, 0.0),
			Vector3(1.0, 0.0, 0.0))
	await Kit.wait_frames(get_tree(), 2)
	var opened := door.transform.basis.get_euler().y
	_expect("the door sprang open (%.1f degrees)" % rad_to_deg(opened),
			absf(rad_to_deg(opened)) > 5.0)
	Events.player_respawned.emit()
	await Kit.wait_frames(get_tree(), 2)
	var back := door.transform.basis.get_euler().y
	_expect("the door is back at rest (%.1f degrees)" % rad_to_deg(back), absf(back) < 0.01)
	_expect("the door is at its place", door.transform.is_equal_approx(rest))


## A car that drives towards the player at 10 m/s.
func _make_driver(position: Vector3, forward: Vector3) -> VehicleBase:
	var car := Kit.make_car(VehicleBase.Team.TRAFFIC, 40.0, 1500.0)
	car.add_to_group(&"vehicles")
	add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, position)
	car.linear_velocity = forward * 10.0
	return car


## A head-on hit of the car into a wall in front of it.
func _hit_wall(car: VehicleBase, speed: float) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 8.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	# The wall is in front of the car, so the hit is a front hit (the ram bonus).
	var forward := -car.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	# The wall is in front of the car and the normal points out of it, towards the car.
	wall.global_transform = Transform3D(Basis.IDENTITY, car.global_position + forward * 12.0)
	car.linear_velocity = forward * speed
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(car, wall, 1900.0 * speed,
			car.global_position + forward * 2.0, -forward)
	await Kit.wait_frames(get_tree(), 2)


func _on_respawned() -> void:
	_respawned += 1


func _on_focus(_target: Node3D, _duration: float) -> void:
	_focused += 1


func _on_toast(text: String, _style: StringName) -> void:
	_toasts.append(text)


func _expect(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)


func _approx(label: String, got: float, want: float, tolerance: float = 0.05) -> void:
	if absf(got - want) > tolerance:
		_failures += 1
		print("FAIL %s: got %.3f, want %.3f" % [label, got, want])
	else:
		print("PASS %s (%.3f)" % [label, got])
