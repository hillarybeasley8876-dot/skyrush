extends RefCounted
## The rigs of the cars: one per vehicle, with the distance tier that decides how many effects it
## runs (brief §1).
##
## The manager owns the cars and their rigs; the director hands it the shared pools and the
## particle quality. The distance tiers follow the brief: FULL for the player and the three
## nearest other cars inside 60 m, REDUCED for everything else inside 150 m, OFF beyond that.
##
## The manager also hands out the emitter budget: at most 8 smoke and fire emitters run at the
## same time (gameplay DOSSIER §7.7), the nearest cars first, and at most 12 cars may run the
## wet spray.

const CarRig := preload("res://fx/fx_car_rig.gd")
const Dev := preload("res://fx/fx_dev.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

var _rigs: Dictionary[int, CarRig] = {}  ## vehicle instance id -> rig
var _vehicles: Dictionary[int, VehicleBase] = {}  ## vehicle instance id -> vehicle
var _contacts: Dictionary[int, Dictionary] = {}  ## vehicle instance id -> last contact
var _skid: CarRig.SKID_RIBBON = null
var _spark: CarRig.SPARK_POOL = null
var _debris: CarRig.DEBRIS_POOL = null
var _lights: CarRig.LIGHT_POOL = null
var _quality: float = 1.0
var _tree: SceneTree = null
## The dev switches of the unit (--fx-no-*).
var dev: Dev = null


## Hands the manager the shared pools and the particle quality.
func setup(skid: CarRig.SKID_RIBBON, spark: CarRig.SPARK_POOL, debris: CarRig.DEBRIS_POOL,
		lights: CarRig.LIGHT_POOL, quality: float, tree: SceneTree) -> void:
	_skid = skid
	_spark = spark
	_debris = debris
	_lights = lights
	_quality = clampf(quality, 0.2, 1.3)
	_tree = tree


## Attaches a rig to a car (idempotent: a pooled car keeps its rig).
func attach(vehicle: VehicleBase) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var id := vehicle.get_instance_id()
	if _rigs.has(id):
		return
	# Reuse a rig that is already on the car (a pooled car may be re-added).
	var rig: CarRig = null
	for child in vehicle.get_children():
		if child.name == "FxRig" and child is CarRig:
			rig = child as CarRig
			break
	if rig == null:
		rig = CarRig.new()
		rig.name = "FxRig"
		vehicle.add_child(rig)
	rig.setup(vehicle, _skid, _spark, _debris, _lights, _quality)
	rig.set_dev(dev)
	_rigs[id] = rig
	_vehicles[id] = vehicle
	if not vehicle.tree_exiting.is_connected(_on_vehicle_gone):
		vehicle.tree_exiting.connect(_on_vehicle_gone.bind(vehicle))
	# The new car may change the ranking: refresh the tiers right away.
	update_lod()


## Drops a car that is leaving the tree.
func remove(vehicle: VehicleBase) -> void:
	if vehicle == null:
		return
	var id := vehicle.get_instance_id()
	_rigs.erase(id)
	_vehicles.erase(id)
	_contacts.erase(id)


## The distance tiering (brief §1): the player and the three nearest other cars inside 60 m run
## the full effect set, everything else inside 150 m a reduced set, beyond that nothing.
func update_lod() -> void:
	var viewer := _viewer_position()
	var ranked: Array[Array] = []
	for id in _vehicles:
		var vehicle: VehicleBase = _vehicles[id]
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		ranked.append([viewer.distance_to(vehicle.global_position), id])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	# The nearest NON player cars inside the full range get the full effect set.
	var full_ids: Dictionary[int, bool] = {}
	var taken := 0
	for entry: Array in ranked:
		if taken >= TUNE.NEAR_CARS:
			break
		var vehicle: VehicleBase = _vehicles.get(int(entry[1]))
		if vehicle == null or vehicle == Game.player:
			continue
		if float(entry[0]) > TUNE.FULL_RANGE:
			break
		full_ids[int(entry[1])] = true
		taken += 1
	var tiers: Dictionary[int, int] = {}
	for entry: Array in ranked:
		var id := int(entry[1])
		var distance := float(entry[0])
		var vehicle: VehicleBase = _vehicles.get(id)
		var rig: CarRig = _rigs.get(id)
		if rig == null or vehicle == null:
			continue
		var tier := CarRig.Tier.OFF
		if vehicle == Game.player or full_ids.has(id):
			tier = CarRig.Tier.FULL
		elif distance <= TUNE.OFF_RANGE:
			tier = CarRig.Tier.REDUCED
		tiers[id] = tier
		rig.set_tier(tier)
	_grant_budgets(ranked, tiers)


## Hands out the emitter budget: the nearest cars may run their smoke and their spray.
##
## The budget is counted per emitter: a car wants one for its tyre smoke, a wrecked car one
## for its column and one more for its fire. The nearest cars are served first.
func _grant_budgets(ranked: Array, tiers: Dictionary[int, int]) -> void:
	var smoke: Dictionary[int, bool] = {}
	var wreck: Dictionary[int, bool] = {}
	var fire: Dictionary[int, bool] = {}
	var spray: Dictionary[int, bool] = {}
	var used := 0
	# Three passes: the full cars first, then the wrecked cars, then the nearest reduced cars.
	for phase in 3:
		for entry: Array in ranked:
			var id := int(entry[1])
			var tier := int(tiers.get(id, CarRig.Tier.OFF))
			if tier == CarRig.Tier.OFF:
				continue
			var rig: CarRig = _rigs.get(id)
			if rig == null or not is_instance_valid(rig):
				continue
			var wrecked := rig.is_wrecked()
			var wanted := false
			if phase == 0:
				wanted = tier == CarRig.Tier.FULL
			elif phase == 1:
				wanted = wrecked and tier != CarRig.Tier.FULL
			else:
				wanted = tier == CarRig.Tier.REDUCED and not wrecked
			if not wanted or used >= TUNE.MAX_ACTIVE_EMITTERS:
				continue
			if wrecked:
				# The column of the wreck, and its fire if there is budget left for it.
				wreck[id] = true
				used += 1
				if used < TUNE.MAX_ACTIVE_EMITTERS and rig.emitter_cost() > 1:
					fire[id] = true
					used += 1
			else:
				smoke[id] = true
				used += 1
	# The spray has its own budget: the full cars and the nearest reduced cars.
	for entry: Array in ranked:
		if spray.size() >= TUNE.MAX_SPRAY_CARS:
			break
		var id := int(entry[1])
		var tier := int(tiers.get(id, CarRig.Tier.OFF))
		if tier == CarRig.Tier.OFF:
			continue
		var rig: CarRig = _rigs.get(id)
		if rig != null and rig.is_wrecked():
			continue
		spray[id] = true
	for id in _rigs:
		var rig: CarRig = _rigs[id]
		if rig != null and is_instance_valid(rig):
			rig.set_grants(smoke.has(id), wreck.has(id), spray.has(id), fire.has(id))


## The rig of a car (null when the car has none).
func rig_of(vehicle: VehicleBase) -> CarRig:
	if vehicle == null:
		return null
	return _rigs.get(vehicle.get_instance_id())


## The last contact point and normal of a car (used by the takedown burst). The contact is only
## fresh for half a second: after that the takedown uses the side of the victim.
func contact_of(vehicle: VehicleBase) -> Dictionary:
	if vehicle == null:
		return {}
	return _contacts.get(vehicle.get_instance_id(), {})


## Caches the last contact point and normal of a car.
func set_contact(vehicle: VehicleBase, point: Vector3, normal: Vector3) -> void:
	if vehicle == null:
		return
	_contacts[vehicle.get_instance_id()] = {
		"point": point,
		"normal": normal,
		"time": _now(),
	}


## The number of cars that currently have a rig.
func count() -> int:
	return _rigs.size()


## The rigs (for the budget report).
func rigs() -> Dictionary:
	return _rigs


## Where the tiers are measured from: the camera, or the player when there is no camera.
func _viewer_position() -> Vector3:
	if _tree != null:
		var cam := _tree.root.get_camera_3d()
		if cam != null:
			return cam.global_position
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player.global_position
	return Vector3.ZERO


func _on_vehicle_gone(vehicle: VehicleBase) -> void:
	remove(vehicle)


static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
