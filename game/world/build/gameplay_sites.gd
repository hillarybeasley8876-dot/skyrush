extends RefCounted
## Gameplay sites built from the city.json points of interest: flash-charging bays, gas
## stations (with their pursuit breaker), the toll plaza, hiding spots and roadblock sites.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const Heading := preload("res://world/api/heading.gd")
const TollPlazaScript := preload("res://world/build/toll_plaza.gd")
const BreakerScript := preload("res://world/build/pursuit_breaker.gd")
const BreakerSites := preload("res://world/build/breaker_sites.gd")
const CitySites := preload("res://world/build/city_sites.gd")
const GasStation := preload("res://world/build/gas_station.gd")
const LaneSpatial := preload("res://world/api/lane_spatial.gd")

const CHARGE_GLB := "res://assets/props/sites/charge_station.glb"
const BILLBOARD_GLB := "res://assets/props/street/billboard_pole.glb"
const SCAFFOLD_GLB := "res://assets/props/street/scaffold.glb"

## The distance between two billboards on a road.
const BREAKER_SPACING := 700.0
## The distance between two scaffolds on a road.
const SCAFFOLD_SPACING := 900.0
## How far the breakers stand from the centre line.
const BREAKER_OFFSET := 16.0
const MAX_BILLBOARDS := 24
const MAX_SCAFFOLDS := 10
const CHARGE_COLOR := Color("00e5ff")
const GAS_CLEARANCE := 6.0
const TOLL_CLEARANCE := 7.0
## The size of the stunt gate over a roadblock.
const ROADBLOCK_WIDTH := 24.0
const ROADBLOCK_HEIGHT := 4.0
const ROADBLOCK_DEPTH := 4.0

var roadblock_sites: Array[Transform3D] = []
var charge_stations: Array[ChargeStation] = []
var stunt_gates: Array[StuntGate] = []
var breakers: Array[Node] = []
## The signs of the sites that need a generated texture.
var _sign_texts: Array[Dictionary] = []
## The billboards and the scaffolds that are pursuit breakers.
var _breakers: Array[Node] = []
## The sign factory of the world (the signs of the sites).
var signs: Node
## The boxes of the buildings of the city (a site steps out of them).
var _boxes: Array[AABB] = []
## The buildings of the city that are not fuel sites.
var _sites := CitySites.new()


func build(parent: Node3D, pois: Array, roads: Array = [], lanes: Array[LanePath] = [],
		grid = null, boxes: Array[AABB] = []) -> void:
	_boxes = boxes
	for poi in pois:
		if poi is Dictionary:
			_build_poi(parent, poi as Dictionary, grid)
	_breakers = BreakerSites.new().build(parent, roads, pois)
	_sign_texts = _sign_texts + _sites.sign_texts


## The signs of the sites that need a generated texture.
func sign_texts() -> Array[Dictionary]:
	return _sign_texts
func _build_poi(parent: Node3D, poi: Dictionary, grid: LaneSpatial = null) -> void:
	match str(poi.get("kind", "")):
		"charge":
			_build_charge(parent, poi)
		"gas":
			_build_gas(parent, poi)
		"toll":
			_build_toll(parent, poi)
		"hiding_spot":
			_sites.build_hiding(parent, poi)
		"roadblock_site":
			_build_roadblock(parent, poi, grid)
		"police_station":
			_sites.build_police_station(parent, poi, _clear_position(poi))


## 申城闪充: a drive-through bay; driving through it at 60 km/h or more refills N2 and battery.
func _build_charge(parent: Node3D, poi: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "ChargeStation_" + str(poi.get("id", "poi"))
	root.position = _position(poi)
	root.rotation.y = Heading.yaw_from_heading(float(poi.get("heading_deg", 0.0)))
	parent.add_child(root)
	var size: Array = poi.get("size", [24.0, 10.0])
	var width := float(size[0]) if size.size() > 0 else 24.0
	var depth := float(size[1]) if size.size() > 1 else 10.0
	var area := _charge_area(root)
	if not bool(area.get("loaded", false)):
		_charge_bay_visual(root, width, depth)
	else:
		width = float(area["size"].x)
		depth = float(area["size"].z)
	var station := ChargeStation.new()
	station.name = "ChargeArea"
	station.label = str(poi.get("label", "申城闪充"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 6.0, depth)
	shape.shape = box
	shape.position = Vector3(0, 3.0, 0)
	station.add_child(shape)
	if bool(area.get("loaded", false)):
		station.position = area["position"]
	root.add_child(station)
	charge_stations.append(station)


## The charge station of the props unit: the glb and its "ChargeArea" empty. The gltf extras
## arrive in the meta "extras" and hold the centre and the size in Blender axes.
func _charge_area(root: Node3D) -> Dictionary:
	if not ResourceLoader.exists(CHARGE_GLB):
		return {"loaded": false}
	var packed := load(CHARGE_GLB) as PackedScene
	if packed == null:
		return {"loaded": false}
	var model := packed.instantiate() as Node3D
	if model == null:
		return {"loaded": false}
	MaterialLibrary.apply(model)
	root.add_child(model)
	var marker := model.find_child("ChargeArea", true, false) as Node3D
	if marker == null:
		return {"loaded": true, "position": Vector3.ZERO, "size": Vector3.ZERO}
	var extras: Dictionary = marker.get_meta("extras", {})
	var centre := _blender_to_godot(extras.get("charge_area_centre", []))
	var size := _blender_size(extras.get("charge_area_size", []))
	return {"loaded": true, "position": centre, "size": size}


## A Blender vector (x, y, z, z up) in Godot axes (x, z, -y).
static func _blender_to_godot(raw: Variant) -> Vector3:
	if not raw is Array or (raw as Array).size() < 3:
		return Vector3.ZERO
	var list := raw as Array
	return Vector3(float(list[0]), float(list[2]), -float(list[1]))


## The size of a Blender box (x, y, z) in Godot axes: (x, z, y).
static func _blender_size(raw: Variant) -> Vector3:
	if not raw is Array or (raw as Array).size() < 3:
		return Vector3.ZERO
	var list := raw as Array
	return Vector3(float(list[0]), float(list[2]), float(list[1]))


func _charge_bay_visual(root: Node3D, width: float, depth: float) -> void:
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = ProcMeshes.box(Vector3(width, 0.4, depth + 3.0))
	canopy.material_override = ProcMeshes.material("metal")
	canopy.position = Vector3(0, 5.4, 0)
	root.add_child(canopy)
	var strip := MeshInstance3D.new()
	strip.name = "Strip"
	strip.mesh = ProcMeshes.box(Vector3(width, 0.12, depth + 2.4))
	strip.material_override = ProcMeshes.glow(CHARGE_COLOR, 3.0)
	strip.position = Vector3(0, 5.15, 0)
	root.add_child(strip)
	for i in 2:
		var post := MeshInstance3D.new()
		post.name = "Post_%d" % i
		post.mesh = ProcMeshes.box(Vector3(0.5, 5.4, 0.5))
		post.material_override = ProcMeshes.material("metal")
		post.position = Vector3((float(i) * 2.0 - 1.0) * (width * 0.5 - 1.5), 2.7, 0)
		root.add_child(post)
	var sign := MeshInstance3D.new()
	sign.name = "Sign"
	sign.mesh = ProcMeshes.box(Vector3(width * 0.7, 1.4, 0.2))
	sign.material_override = ProcMeshes.glow(Color("0a1a2a"), 0.5)
	sign.position = Vector3(0, 6.6, 0)
	root.add_child(sign)


## A gas station (中石华): canopy, dispensers, pylon and the pursuit breaker over the canopy.
func _build_gas(parent: Node3D, poi: Dictionary) -> void:
	var station := GasStation.new()
	var built := station.build(parent, poi)
	var root: Node3D = built["root"]
	var width: float = built["width"]
	var depth: float = built["depth"]
	var structure: Node3D = built["structure"]
	_stunt_gate(root, &"fly_over_gas", 800, "飞跃加油站!", Vector3(depth, 4.0, width), GAS_CLEARANCE)
	var breaker := BreakerScript.new()
	breaker.name = "Breaker"
	root.add_child(breaker)
	breaker.setup(structure)
	breakers.append(breaker)


## The node the Support_* columns hang under (the canopy of the gas station).
static func _support_parent(model: Node3D) -> Node3D:
	for child in model.find_children("Support_*", "Node3D", true, false):
		var parent := child.get_parent()
		if parent != null:
			return parent as Node3D
	return model


## The bounding box of the meshes whose name contains `filter` (all of them when it is empty).
static func _model_aabb(node: Node3D, filter: String) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if filter != "" and not String(mi.name).contains(filter):
			continue
		var box := mi.global_transform * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


## A place for a site that is not inside a building: the position of the point of interest,
## moved out of the buildings of the city.
func _clear_position(poi: Dictionary) -> Vector3:
	var position := _position(poi)
	if _boxes.is_empty():
		return position
	var size: Array = poi.get("size", [0.0, 0.0])
	var half := Vector2(float(size[0]) if size.size() > 0 else 20.0,
		float(size[1]) if size.size() > 1 else 20.0) * 0.5
	for step in range(0, 21):
		var offset := float(step) * 2.0
		for direction: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1),
				Vector3(0, 0, -1)]:
			var candidate := position + direction * offset
			if not _in_a_building(candidate, half):
				return candidate
	return position


## True when the point is inside one of the buildings of the city.
func _in_a_building(position: Vector3, half: Vector2) -> bool:
	var probe := AABB(position - Vector3(half.x, 4.0, half.y),
		Vector3(half.x * 2.0, 8.0, half.y * 2.0))
	for box in _boxes:
		if box.intersects(probe):
			return true
	return false


## A roadblock site: the stunt gate over the roadblock and the transform of the site, snapped
## onto the lane the roadblock stands on.
func _build_roadblock(parent: Node3D, poi: Dictionary, grid: LaneSpatial) -> void:
	var position := _position(poi)
	var tangent := Vector3.FORWARD
	if grid != null:
		var near: Dictionary = grid.query(position, 20.0)
		var best := -1
		var best_distance := INF
		for index in near.keys():
			var info: Dictionary = near[index]
			if float(info["distance"]) < best_distance:
				best_distance = float(info["distance"])
				best = index
		if best >= 0:
			var info2: Dictionary = near[best]
			position = info2["point"]
			tangent = info2["tangent"]
			if tangent.length_squared() < 0.0001:
				tangent = Vector3.FORWARD
	roadblock_sites.append(Transform3D(Basis.looking_at(tangent, Vector3.UP), position))
	var gate := StuntGate.new()
	gate.name = "StuntGate_roadblock"
	gate.kind = &"fly_over_roadblock"
	gate.points = 500
	gate.label = "飞跃路障!"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ROADBLOCK_WIDTH, ROADBLOCK_HEIGHT, ROADBLOCK_DEPTH)
	shape.shape = box
	shape.position = Vector3(0, ROADBLOCK_HEIGHT * 0.5, 0)
	gate.add_child(shape)
	gate.transform = Transform3D(Basis.looking_at(tangent, Vector3.UP), position)
	parent.add_child(gate)
	stunt_gates.append(gate)


## The toll plaza and the stunt gate over its canopy.
func _build_toll(parent: Node3D, poi: Dictionary) -> void:
	var plaza := TollPlazaScript.new()
	plaza.name = "TollPlaza_" + str(poi.get("id", "poi"))
	parent.add_child(plaza)
	plaza.setup(poi)
	_stunt_gate(plaza, &"fly_over_toll", 800, "飞跃收费站!", Vector3(20.0, 4.0, 56.0), TOLL_CLEARANCE)


## An invisible volume over an obstacle: passing through it airborne awards the stunt.
func _stunt_gate(parent: Node3D, kind: StringName, points: int, label: String,
		size: Vector3, clearance: float) -> StuntGate:
	var gate := StuntGate.new()
	gate.name = "StuntGate_" + String(kind)
	gate.kind = kind
	gate.points = points
	gate.label = label
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, clearance + size.y * 0.5, 0)
	gate.add_child(shape)
	parent.add_child(gate)
	stunt_gates.append(gate)
	return gate


static func _position(poi: Dictionary) -> Vector3:
	return Vector3(float(poi.get("x", 0.0)), float(poi.get("y", 0.0)), float(poi.get("z", 0.0)))


## -Z of the transform faces the oncoming player traffic.
static func _transform(poi: Dictionary) -> Transform3D:
	return Transform3D(Heading.basis_from_heading(float(poi.get("heading_deg", 0.0))),
		_position(poi))
