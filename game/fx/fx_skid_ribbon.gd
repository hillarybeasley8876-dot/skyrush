extends Node3D
## Global skid-mark ribbon pool (art DOSSIER §6.2: "runtime ArrayMesh ribbon ... drift = long
## arcs"). One strip per rear wheel: consecutive quads share their cross-section, so the mark is
## one continuous ribbon with no saw-tooth gaps and no double-darkened overlaps. The ribbon
## follows the road (height and normal from a raycast) and fades out after 20 s.
##
## The fade is computed on the CPU and written into the vertex colours, so the shader only has
## to mix the baked tyre track with the rubber colour.

const TUNE := preload("res://fx/fx_tuning.gd")
const TEXTURES := preload("res://fx/fx_textures.gd")
const SHADER := preload("res://fx/fx_skid.gdshader")
const PALETTE := preload("res://fx/fx_palette.gd")

const MAX_QUADS := TUNE.SKID_MAX_QUADS
const WHEELS := 2
const NEVER := 1.0e9
const FADE_STEP := 0.2  ## seconds between the fade updates

var _mesh: ArrayMesh
var _material: ShaderMaterial
var _verts: PackedVector3Array
var _normals: PackedVector3Array
var _uvs: PackedVector2Array
var _colors: PackedColorArray
var _indices: PackedInt32Array
var _births: PackedFloat32Array
var _starts: PackedFloat32Array
var _ends: PackedFloat32Array
var _next: int = 0
var _dirty: bool = false
var _time: float = 0.0
var _last_time: float = 0.0
var _fade_timer: float = 0.0
var _last: Array[Dictionary] = []  ## per wheel: the current cross section


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"track_tex", TEXTURES.tyre_track())
	_material.set_shader_parameter(&"rubber", Vector3(PALETTE.RUBBER.r, PALETTE.RUBBER.g, PALETTE.RUBBER.b))
	_material.set_shader_parameter(&"fade_time", TUNE.SKID_FADE)

	_verts.resize(MAX_QUADS * 4)
	_normals.resize(MAX_QUADS * 4)
	_uvs.resize(MAX_QUADS * 4)
	_colors.resize(MAX_QUADS * 4)
	_indices.resize(MAX_QUADS * 6)
	_births.resize(MAX_QUADS)
	_starts.resize(MAX_QUADS)
	_ends.resize(MAX_QUADS)
	for q in MAX_QUADS:
		var v := q * 4
		_indices[q * 6 + 0] = v
		_indices[q * 6 + 1] = v + 1
		_indices[q * 6 + 2] = v + 2
		_indices[q * 6 + 3] = v
		_indices[q * 6 + 4] = v + 2
		_indices[q * 6 + 5] = v + 3
		for i in 4:
			_verts[v + i] = Vector3(0.0, -1000.0, 0.0)
			_colors[v + i] = Color(1.0, 1.0, 1.0, 0.0)
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays())
	var mi := MeshInstance3D.new()
	mi.name = "SkidMarks"
	mi.mesh = _mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	add_child(mi)
	for i in WHEELS:
		_last.append({})


## Adds a contact point of a rear wheel. `point` is on the road, `normal` its surface normal and
## `right_hint` the right side of the car (the width of the first quad of a strip comes from it).
## A ribbon point is only added after TUNE.SKID_MIN_STEP of travel.
##
## `max_gap` is the biggest travel that still belongs to the same strip: the rig scales it with
## the speed of the car, so a fast car does not cut a new strip on every frame.
func add_point(wheel: int, point: Vector3, normal: Vector3, right_hint: Vector3,
		max_gap: float, time: float) -> void:
	if wheel < 0 or wheel >= WHEELS:
		return
	var section: Dictionary = _last[wheel]
	if section.is_empty():
		_last[wheel] = _cross_section(point, normal, right_hint, 0.0)
		return
	var previous: Vector3 = section["point"]
	var travelled: float = previous.distance_to(point)
	if travelled > max_gap:
		# The wheel was lifted and put down again: a new strip starts here.
		_last[wheel] = _cross_section(point, normal, right_hint, float(section["v"]))
		return
	if travelled < TUNE.SKID_MIN_STEP:
		return
	var direction := (point - previous).normalized()
	var right := direction.cross(normal)
	if right.length() < 0.5:
		right = Vector3(section["axis"])
	else:
		right = right.normalized()
		# The width of a strip may never flip over: a folded quad reads as a black blob.
		if right.dot(Vector3(section["axis"])) < 0.0:
			right = -right
	# Both edges of the ribbon are lifted above the road: a quad that cuts through the asphalt
	# only survives the depth test as a sliver.
	var lift := normal * TUNE.SKID_LIFT
	var left := point - right * TUNE.SKID_HALF_WIDTH + lift
	var right_point := point + right * TUNE.SKID_HALF_WIDTH + lift
	var v0: float = section["v"]
	var v1: float = v0 + travelled
	var quad := _emit(section["left"], section["right"], right_point, left, v0, v1, normal,
			time, float(section["start"]), float(section["start_v"]))
	_last[wheel] = {
		"point": point,
		"normal": normal,
		"left": left,
		"right": right_point,
		"axis": right,
		"v": v1,
		"start": section["start"],
		"start_v": section["start_v"],
		"quad": quad,
	}


## Ends the strip of a wheel (the wheel lifted or the slip stopped): the ribbon fades out.
func break_strip(wheel: int) -> void:
	if wheel < 0 or wheel >= WHEELS:
		return
	var section: Dictionary = _last[wheel]
	if section.is_empty():
		return
	_last[wheel] = {}
	if section.has("quad"):
		# The end of the strip fades out over SKID_END_FADE seconds.
		_ends[int(section["quad"])] = _now()
		_dirty = true


## The width of the widest live quad in metres (the test hook: the mark is 24 cm wide). The
## first quad of a strip starts from a point, so it has no width yet.
func quad_width() -> float:
	var widest := 0.0
	for q in MAX_QUADS:
		if _births[q] <= 0.0:
			continue
		widest = maxf(widest, _verts[q * 4].distance_to(_verts[q * 4 + 1]))
	return widest


## The width of the narrowest live quad in metres. Every quad of a strip is 24 cm wide, also
## the first one: a strip never starts with a hairline.
func narrowest_quad_width() -> float:
	var narrowest := INF
	for q in MAX_QUADS:
		if _births[q] <= 0.0:
			continue
		narrowest = minf(narrowest, _verts[q * 4].distance_to(_verts[q * 4 + 1]))
	return narrowest


## The corners of the live quads (the test hook: every vertex has to be above the road).
func live_vertices() -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in MAX_QUADS:
		if _births[q] <= 0.0 or _time - _births[q] >= TUNE.SKID_FADE:
			continue
		for i in 4:
			out.append(_verts[q * 4 + i])
	return out


## The number of ribbon quads that are still alive.
func live_count() -> int:
	var live := 0
	for q in MAX_QUADS:
		if _births[q] > 0.0 and _time - _births[q] < TUNE.SKID_FADE:
			live += 1
	return live


## Advances the fade clock (unscaled real time), retires the expired quads and uploads the
## geometry when it changed.
func update(now: float) -> void:
	_time = now
	_fade_timer -= now - _last_time
	_last_time = now
	for q in MAX_QUADS:
		var birth := _births[q]
		if birth <= 0.0 or now - birth <= TUNE.SKID_FADE:
			continue
		_births[q] = 0.0
		for i in 4:
			_verts[q * 4 + i] = Vector3(0.0, -1000.0, 0.0)
			_colors[q * 4 + i] = Color(1.0, 1.0, 1.0, 0.0)
		_dirty = true
	if _dirty or _fade_timer <= 0.0:
		_fade_timer = FADE_STEP
		_dirty = false
		_update_fade(now)
		_mesh.clear_surfaces()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays())


func clear() -> void:
	for q in MAX_QUADS:
		_births[q] = 0.0
		for i in 4:
			_verts[q * 4 + i] = Vector3(0.0, -1000.0, 0.0)
			_colors[q * 4 + i] = Color(1.0, 1.0, 1.0, 0.0)
	_next = 0
	_dirty = true
	for i in WHEELS:
		_last[i] = {}


## The fade of every quad, written into the vertex colours.
func _update_fade(now: float) -> void:
	for q in MAX_QUADS:
		if _births[q] <= 0.0:
			continue
		var age := now - _births[q]
		var fade := clampf(1.0 - age / TUNE.SKID_FADE, 0.0, 1.0)
		var born := clampf((now - _starts[q]) / 0.25, 0.0, 1.0)
		var ended := clampf(1.0 - (now - _ends[q]) / TUNE.SKID_END_FADE, 0.0, 1.0)
		var a := fade * born * ended
		for i in 4:
			_colors[q * 4 + i] = Color(1.0, 1.0, 1.0, a)


func _emit(left0: Vector3, right0: Vector3, right1: Vector3, left1: Vector3,
		v0: float, v1: float, normal: Vector3, time: float, start: float,
		start_v: float) -> int:
	var q := _next
	_next = (_next + 1) % MAX_QUADS
	var v := q * 4
	var corners := [left0, right0, right1, left1]
	var us := [0.0, 1.0, 1.0, 0.0]
	# The first metres of a strip are darker: the tyre bites into the road.
	var travelled := (v1 - start_v) * TUNE.SKID_UV_METRES
	var bite := 1.0
	if travelled < TUNE.SKID_BITE_METRES:
		bite = 1.0 / TUNE.SKID_BITE_DARK
	for i in 4:
		_verts[v + i] = corners[i]
		_normals[v + i] = normal
		_uvs[v + i] = Vector2(us[i], v0 / TUNE.SKID_UV_METRES if i < 2 else v1 / TUNE.SKID_UV_METRES)
		_colors[v + i] = Color(bite, bite, bite, 1.0)
	_births[q] = time
	_starts[q] = start
	_ends[q] = NEVER
	_dirty = true
	return q


## The cross section of a strip: both edges are at the full width of the tyre, lifted above the
## road, so the very first quad of a strip is already a full 24 cm mark.
func _cross_section(point: Vector3, normal: Vector3, right_hint: Vector3, v: float) -> Dictionary:
	var axis := right_hint
	if axis.length() < 0.1:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	var lift := normal * TUNE.SKID_LIFT
	return {
		"point": point,
		"normal": normal,
		"left": point - axis * TUNE.SKID_HALF_WIDTH + lift,
		"right": point + axis * TUNE.SKID_HALF_WIDTH + lift,
		"axis": axis,
		"v": v,
		"start": _time,
		"start_v": v,
	}


func _arrays() -> Array:
	var arrays: Array[Variant] = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	return arrays


## The clock of the ribbon (the same one the director uses).
static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
