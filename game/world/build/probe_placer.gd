extends Node
## Reflection probes along the roads (ref/art/DOSSIER.md §3.5): one probe every 150 m of road,
## the box rotated to the road tangent. Only the four probes nearest the camera (within 400 m)
## are enabled, so the reflection atlas stays small (GODOT.md §5: ≤ 4 probes).
##
## The city has more than a thousand probe places, but a probe is a node with a cubemap: the
## places are kept in a grid and a pool of sixteen probes is moved to the places that are
## needed.

const Spline := preload("res://world/api/spline_util.gd")

## The distance between two probes on a road.
const SPACING := 150.0
## Only the probes this close to the camera are enabled.
const RANGE := 400.0
## How many probes may be enabled at the same time.
const MAX_ACTIVE := 4
## The number of probes in the pool (the four that are active and a few that wait).
const POOL_SIZE := 16
## The probe box: the road width plus the margin, 40 m high and one segment long.
const EXTRA := 40.0
const SIZE_Y := 40.0
const CHECK_INTERVAL := 0.5
## The size of the cells of the probe index.
const CELL := 128.0

## The places of the probes: {"position", "basis", "size", "interior"}.
var _places: Array[Dictionary] = []
## The pool of probes (only the four that are active are enabled).
var _pool: Array[ReflectionProbe] = []
var _timer := 0.0
## The places in a grid of cells, so only the ones around the camera are looked at.
var _cells: Dictionary = {}
## The places that are enabled right now.
var _active: Array[int] = []


func build(roads: Array) -> void:
	for road in roads:
		if not road is Dictionary:
			continue
		for place in _road_places(road as Dictionary):
			_places.append(place)
	for i in _places.size():
		_insert(_places[i]["position"], i)
	for i in POOL_SIZE:
		var probe := ReflectionProbe.new()
		probe.name = "Probe_%d" % i
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.intensity = 1.0
		probe.blend_distance = 4.0
		probe.box_projection = true
		probe.visible = false
		add_child(probe)
		_pool.append(probe)


## The places of the probes of a road: one every 150 m, the box turned with the road.
func _road_places(road: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var line := Spline.road_line(road)
	if line.size() < 2:
		return out
	var width := float(road.get("lane_width", 3.75)) \
		* (float(road.get("lanes_fwd", 2)) + float(road.get("lanes_back", 2)))
	var tunnel := str(road.get("kind", "surface")) == "tunnel"
	var length := Spline.total_length(line)
	var count := maxi(int(length / SPACING), 1)
	for i in count:
		var distance := (float(i) + 0.5) * SPACING
		if distance > length:
			break
		out.append({
			"position": _point_at(line, distance),
			"basis": _basis_along(_tangent_at(line, distance)),
			"size": Vector3(width + EXTRA, SIZE_Y, SPACING),
			"interior": tunnel,
		})
	return out


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_update_probes()


## Moves the pool to the four places nearest the camera and enables them. Only the probes whose
## state changes are touched, so the update does not walk the whole list.
func _update_probes() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.global_position
	var near: Array[Dictionary] = []
	for index in _candidates(origin):
		var place: Dictionary = _places[index]
		var distance := origin.distance_to(place["position"])
		if distance <= RANGE:
			near.append({"index": index, "distance": distance})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"]))
	var wanted: Array[int] = []
	for i in mini(near.size(), MAX_ACTIVE):
		wanted.append(int(near[i]["index"]))
	for i in _pool.size():
		var probe := _pool[i]
		if i < wanted.size():
			_place_probe(probe, _places[wanted[i]])
			probe.visible = true
		else:
			probe.visible = false
	_active = wanted


## Puts a probe of the pool on a place.
func _place_probe(probe: ReflectionProbe, place: Dictionary) -> void:
	probe.global_position = place["position"]
	probe.global_basis = place["basis"]
	probe.size = place["size"]
	probe.interior = bool(place["interior"])


## The places in the cells around a point.
func _candidates(origin: Vector3) -> Array[int]:
	var out: Array[int] = []
	var span := maxi(int(ceil(RANGE / CELL)), 1)
	var cx := int(floor(origin.x / CELL))
	var cz := int(floor(origin.z / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := "%d_%d" % [cx + dx, cz + dz]
			if not _cells.has(key):
				continue
			for index in _cells[key] as Array:
				if not out.has(index):
					out.append(index)
	return out


func _insert(position: Vector3, index: int) -> void:
	var key := "%d_%d" % [int(floor(position.x / CELL)), int(floor(position.z / CELL))]
	if not _cells.has(key):
		_cells[key] = []
	var list: Array = _cells[key]
	if not list.has(index):
		list.append(index)


## A basis whose -Z points along the road.
static func _basis_along(tangent: Vector3) -> Basis:
	var direction := tangent
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return Basis.IDENTITY
	direction = direction.normalized()
	return Basis.looking_at(direction, Vector3.UP)


static func _point_at(points: PackedVector3Array, distance: float) -> Vector3:
	return Spline.point_at(points, distance)


static func _tangent_at(points: PackedVector3Array, distance: float) -> Vector3:
	return Spline.tangent_at(points, distance)
