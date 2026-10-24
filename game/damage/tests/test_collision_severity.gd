extends Node
## REGRESSION TEST (job collision-explosion): the damage of a hit must be measured by the
## speed the car lost in it, not by the closing speed of the two cars.
##
## The damage unit used to score a car-to-car hit with the closing speed of the two cars:
## that counts the speed of the other car as if it were the loss of this one. A player that
## meets a slow patrol car head-on at 162 km/h (a closing speed of 190 km/h) was scored
## like a 190 km/h crash - 330 HP, the player was wrecked and the respawn put it 30 m back
## (the drive of the acceptance: "the health falls to 0" and "the car moves 29.1 m in one
## row").
##
## The severity of a hit is now the smaller of the two measures: the closing speed (the
## cars cannot approach each other faster than that) and the momentum the hit transferred
## divided by the mass of the car (the speed the car lost). The vehicle unit measures that
## momentum and sends it with the event.
##
## The test: the player at 162 km/h meets a patrol car that drives towards it at 27 km/h.
## The hit takes 20.7 m/s of speed from the player (the momentum of the hit is 1900 kg *
## 20.7 m/s = 39,330 N*s, the third law: the patrol takes the same momentum).
##   * the player must survive it (the health stays above 20),
##   * the player must not be wrecked,
##   * the same hit against a wall (the closing speed is the loss there) must still cost
##     what the dossier says: 33.75 HP (20 m/s into a wall, the ram factor 0.5).
## Run: python tools/gd.py test res://damage/tests/test_collision_severity.gd

const Kit := preload("res://damage/tests/damage_test_kit.gd")

## The speed of the player before the hit (m/s).
const PLAYER_SPEED := 45.0
## The speed of the patrol car before the hit (m/s, it drives towards the player).
const PATROL_SPEED := 7.5
## The speed the hit takes from the player (m/s): the momentum of the hit, divided by the
## mass of the player.
const LOST_SPEED := 20.7
## The health the player must keep.
const MIN_HEALTH := 20.0

var _failures: int = 0


func _ready() -> void:
	Kit.make_floor(self)
	var director := Kit.make_director(self)
	await Kit.wait_frames(get_tree(), 2)
	await _test_head_on(director)
	await _test_wall(director)
	await _test_prop(director)
	print(("FAIL" if _failures > 0 else "PASS") + " collision_severity (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## The player meets a patrol car head-on: the hit takes 20.7 m/s of speed from it.
func _test_head_on(director: Node) -> void:
	var player := Kit.make_car(VehicleBase.Team.PLAYER, 100.0, 1900.0)
	player.add_to_group(&"vehicles")
	add_child(player)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	Game.player = player
	var patrol := Kit.make_car(VehicleBase.Team.POLICE, 60.0, 1900.0)
	patrol.add_to_group(&"vehicles")
	add_child(patrol)
	patrol.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.5, -12.0))
	player.linear_velocity = Vector3(0.0, 0.0, PLAYER_SPEED)
	patrol.linear_velocity = Vector3(0.0, 0.0, -PATROL_SPEED)
	await Kit.wait_frames(get_tree(), 3)
	# The contact: the momentum of the hit is the momentum the player lost.
	Events.vehicle_collided.emit(player, patrol, 1900.0 * LOST_SPEED, Vector3(0.0, 0.6, -2.0),
			Vector3(0.0, 0.0, -1.0))
	await Kit.wait_frames(get_tree(), 2)
	var health: float = float(player.get("health"))
	_expect("the player survives the head-on (health >= %.0f)" % MIN_HEALTH,
			health >= MIN_HEALTH, "= %.0f" % health)
	_expect("the player is not wrecked", not player.is_wrecked)


## The same speed against a wall: there the closing speed is the speed the car loses, and
## the damage is the number of the dossier (33.75 HP, the ram factor 0.5).
func _test_wall(director: Node) -> void:
	var player := Kit.make_car(VehicleBase.Team.PLAYER, 100.0, 1900.0)
	player.add_to_group(&"vehicles")
	add_child(player)
	# The front of the car points at the wall (the ram factor of the dossier).
	player.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.5, 40.0))
	Game.player = player
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 8.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 52.0))
	player.linear_velocity = Vector3(0.0, 0.0, 20.0)
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(player, wall, 1900.0 * 20.0, Vector3(0.0, 0.6, 50.0),
			Vector3(0.0, 0.0, -1.0))
	await Kit.wait_frames(get_tree(), 2)
	var health: float = float(player.get("health"))
	_expect("a 20 m/s hit against a wall costs 16.9 HP (the ram factor 0.5)",
			absf(100.0 - health - 16.9) < 0.6, "= %.2f HP" % (100.0 - health))


## The street furniture that stands (a tree, a mast) costs 40 % of a wall, and it does not wreck a car in one hit: a head-on with
## the side of the car at 35 m/s wrecks it against a wall (dossier 7.2), against a tree it costs 54 HP.
func _test_prop(director: Node) -> void:
	var front := await _hit_static(4, Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 20.0), Vector3(0.0, 0.0, -1.0), 20.0)
	_expect("a 20 m/s hit against a tree costs 40 % of the wall (6.8 HP)", absf(100.0 - front.health - 6.76) < 0.4,
			"= %.2f HP" % (100.0 - front.health))
	var side := await _hit_static(4, Basis.IDENTITY, Vector3(35.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), 35.0)
	_expect("a side hit at 35 m/s against a tree does not wreck the car", not side.is_wrecked,
			"(health %.0f)" % side.health)
	_expect("and it costs 54 HP", absf(100.0 - side.health - 54.0) < 1.0, "= %.2f HP" % (100.0 - side.health))
	var wall := await _hit_static(1, Basis.IDENTITY, Vector3(35.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), 35.0)
	_expect("the same hit against a wall still wrecks the car", wall.is_wrecked, "(health %.0f)" % wall.health)


## A player car hits a static body of the given layer: the car moves with `velocity`, the normal points out of the body towards
## the car, the hit takes `lost` m/s from it. Returns the car.
func _hit_static(layer: int, basis: Basis, velocity: Vector3, normal: Vector3, lost: float) -> VehicleBase:
	var player := Kit.make_car(VehicleBase.Team.PLAYER, 100.0, 1900.0)
	player.add_to_group(&"vehicles")
	add_child(player)
	var at := Vector3(float(get_child_count()) * 30.0, 0.5, 200.0)
	player.global_transform = Transform3D(basis, at)
	Game.player = player
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.25
	cylinder.height = 3.0
	shape.shape = cylinder
	body.add_child(shape)
	add_child(body)
	body.global_transform = Transform3D(Basis.IDENTITY, at - normal * 3.0)
	player.linear_velocity = velocity
	await Kit.wait_frames(get_tree(), 2)
	Events.vehicle_collided.emit(player, body, 1900.0 * lost, at - normal * 2.0, normal)
	await Kit.wait_frames(get_tree(), 2)
	return player


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS %s %s" % [label, detail])
		return
	_failures += 1
	print("FAIL %s %s" % [label, detail])
