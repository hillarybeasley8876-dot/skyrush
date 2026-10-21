extends Node
## The takedown rules of dossier 3.5: the player rams a car at 25 m/s, the victim is wrecked
## and the player gets the credit.

const Kit := preload("res://damage/tests/damage_test_kit.gd")
const Rules := preload("res://damage/damage_rules.gd")

var _failures: int = 0
var _takedowns: Array = []
var _stunts: Array = []


func _ready() -> void:
	Events.takedown.connect(_on_takedown)
	Events.stunt.connect(_on_stunt)
	Kit.make_floor(self)
	var director := Kit.make_director(self)
	var player := Kit.make_car(VehicleBase.Team.PLAYER, 100.0, 1900.0)
	player.add_to_group(&"vehicles")
	add_child(player)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 0.0))
	Game.player = player
	var victim := Kit.make_car(VehicleBase.Team.POLICE, 60.0, 1900.0)
	victim.add_to_group(&"vehicles")
	add_child(victim)
	victim.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, -6.0))
	# The player runs into the back of the parked car. 26 m/s, not 25: at 25 m/s the hit is
	# worth exactly the 60 HP of the patrol (dossier 7.3) and the physics drag of the floor
	# would leave the victim with a fraction of a HP.
	player.linear_velocity = Vector3(0.0, 0.0, -26.0)
	await Kit.wait_frames(get_tree(), 3)
	# The contact: the normal points out of the victim, towards the player.
	Events.vehicle_collided.emit(player, victim, 1900.0 * 26.0, Vector3(0.0, 0.6, -3.0),
			Vector3(0.0, 0.0, 1.0))
	await Kit.wait_frames(get_tree(), 2)

	_expect("the victim is wrecked", victim.is_wrecked)
	_approx("the victim lost all its health", victim.health, 0.0)
	_approx("the player took half the damage (the front-ram bonus)", player.health, 67.0, 0.5)
	_expect("one takedown was emitted", _takedowns.size() == 1)
	if _takedowns.size() == 1:
		_expect("the takedown is a police takedown", _takedowns[0] == &"police")
	_expect("the stunt was emitted", _stunts.size() == 1)
	if _stunts.size() == 1:
		_approx("the takedown is worth 50 points", float(_stunts[0]), 50.0)
	_expect("the streak counts one", director.streak() == 1)

	# The vertical takedown: the player lands on the roof of a car at 6 m/s.
	var roof := Kit.make_car(VehicleBase.Team.RIVAL, 100.0, 1900.0)
	roof.add_to_group(&"vehicles")
	add_child(roof)
	roof.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 0.0))
	await Kit.wait_frames(get_tree(), 2)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0))
	player.linear_velocity = Vector3(0.0, -6.0, 0.0)
	await Kit.wait_frames(get_tree(), 2)
	# The contact: the normal points out of the car on the ground, towards the player above.
	Events.vehicle_collided.emit(player, roof, 1900.0 * 6.0, Vector3(0.0, 1.2, 0.0),
			Vector3.UP)
	await Kit.wait_frames(get_tree(), 2)
	_expect("the car under the player is wrecked", roof.is_wrecked)
	_expect("the vertical takedown counts", _takedowns.size() == 2)
	if _takedowns.size() == 2:
		_expect("it is a rival takedown", _takedowns[1] == &"rival")

	# A wreck that the player never touched gets no credit.
	var other := Kit.make_car(VehicleBase.Team.POLICE, 60.0, 1900.0)
	other.add_to_group(&"vehicles")
	add_child(other)
	other.global_transform = Transform3D(Basis.IDENTITY, Vector3(60.0, 0.1, 0.0))
	await Kit.wait_frames(get_tree(), 2)
	other.wreck(player)
	await Kit.wait_frames(get_tree(), 2)
	_expect("a far away wreck gets no takedown", _takedowns.size() == 2)

	print(("FAIL" if _failures > 0 else "PASS") + " takedown (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _on_takedown(_victim: VehicleBase, kind: StringName) -> void:
	_takedowns.append(kind)


func _on_stunt(kind: StringName, points: int, _label: String) -> void:
	if kind == &"takedown":
		_stunts.append(points)


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
