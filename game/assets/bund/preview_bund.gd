extends Node3D
## Night preview of the Bund (bund unit).
##
## Instantiates the exported buildings + promenade, the environment unit's environment and
## the Bund uplights from bund_lights.json (the same sidecar the world unit pools). Only
## the lights nearest the camera are active, with the distance fade the world unit uses,
## so the preview respects the light budget of the art dossier (32 lights).
##
## The preview also stands the ground in place: the carriageway and its sidewalk follow
## the Bund road, the lane markings are painted on the asphalt and the river starts at
## the flood wall, so the driver's view and the view from the water are the real ones.

const LIGHTS_JSON := "res://assets/bund/bund_lights.json"
const MAX_LIGHTS := 24
const DECK_LIGHTS := 8
const RESELECT_INTERVAL := 0.25
const FADE_BEGIN := 60.0
const FADE_LENGTH := 20.0
const DECK_ENERGY := 2.5
const DECK_RANGE := 12.0
const DECK_COLOR := Color(1.0, 0.72, 0.44)
const SPOT_ATTENUATION := 1.0
const SPOT_SPECULAR := 0.4
const ROAD_HALF := 10.0          # the carriageway is 20 m wide
const SIDEWALK := 6.0            # the pavement between the kerb and the facades
const WATER_WEST := 900.0        # how far the river reaches east

var _lights: Array[SpotLight3D] = []
var _deck_lights: Array[OmniLight3D] = []
var _deck_anchors: Array[Vector3] = []
var _timer := 0.0
var _active := -1


func _ready() -> void:
	_enable_ssr()
	_build_ground()
	_build_lights()
	_build_deck_lights()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = RESELECT_INTERVAL
	_select_nearest()


# ---------------------------------------------------------------- the reflections
func _enable_ssr() -> void:
	"""The river has to carry the reflection of the row.

	Screen-space reflections are off by default, so the water would be a flat dark
	plane: the review wants the facades and the flood curtains to streak on it."""
	var world := get_viewport().world_3d
	if world == null or world.environment == null:
		return
	var env: Environment = world.environment.duplicate()
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 3.0
	# The sky of the environment unit carries the glow of the far bank as soft patches,
	# and a smooth river mirrors them as big blurry blobs. The river is left with the
	# screen-space reflection of the row alone, so the water shows the gold of the Bund
	# instead of the sky behind the camera.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world.environment = env


# ---------------------------------------------------------------- the ground
func _build_ground() -> void:
	"""The carriageway, the sidewalk, the lane markings and the river.

	The road belongs to the roads unit; the preview draws its own strip so the driver's
	view is not a void, and the river starts at the flood wall so no canal appears
	between the carriageway and the deck."""
	var data := _sidecar()
	if data.is_empty():
		return
	var road := _poly(data.get("road", []))
	var river := _poly(data.get("river", []))
	if road.size() >= 2:
		_ribbon("BundRoad", road, -ROAD_HALF, ROAD_HALF, 0.0, _asphalt())
		_ribbon("BundSidewalk", road, -ROAD_HALF - SIDEWALK, -ROAD_HALF, 0.14,
				_sidewalk())
		for offset in [-7.0, -3.5, 3.5, 7.0]:
			_ribbon("BundLane", road, offset - 0.09, offset + 0.09, 0.012, _paint())
	if river.size() >= 2:
		_ribbon("BundWater", river, 0.0, WATER_WEST, -3.0, _water())


func _sidecar() -> Dictionary:
	var file := FileAccess.open(LIGHTS_JSON, FileAccess.READ)
	if file == null:
		push_error("bund preview: cannot read " + LIGHTS_JSON)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("bund preview: malformed " + LIGHTS_JSON)
		return {}
	return parsed


func _poly(raw: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in raw:
		if p is Array and p.size() >= 2:
			out.append(Vector2(float(p[0]), float(p[1])))
	return out


func _normals(points: Array[Vector2]) -> Array[Vector2]:
	"""The east normal of every point of the polyline (the road runs south to north)."""
	var out: Array[Vector2] = []
	for i in points.size():
		var a: Vector2 = points[maxi(0, i - 1)]
		var b: Vector2 = points[mini(points.size() - 1, i + 1)]
		var t := (b - a).normalized()
		out.append(Vector2(-t.y, t.x))
	return out


func _ribbon(node_name: String, points: Array[Vector2], off_a: float, off_b: float,
		y: float, material: Material) -> void:
	"""A ribbon that follows the polyline, between two offsets along its east normal."""
	if points.size() < 2 or material == null:
		return
	var normals := _normals(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := absf(off_b - off_a)
	var run := 0.0
	for i in points.size():
		var n: Vector2 = normals[i]
		var p: Vector2 = points[i]
		var a := Vector3(p.x + n.x * off_a, y, p.y + n.y * off_a)
		var b := Vector3(p.x + n.x * off_b, y, p.y + n.y * off_b)
		if i > 0:
			var q: Vector2 = points[i - 1]
			var m: Vector2 = normals[i - 1]
			var pa := Vector3(q.x + m.x * off_a, y, q.y + m.y * off_a)
			var pb := Vector3(q.x + m.x * off_b, y, q.y + m.y * off_b)
			var run1 := run + p.distance_to(q)
			_quad(st, pa, pb, a, b, run, run1, width)
			run = run1
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)


func _quad(st: SurfaceTool, pa: Vector3, pb: Vector3, a: Vector3, b: Vector3,
		run0: float, run1: float, width: float) -> void:
	"""One quad of the ribbon, with the UVs in metres.

	The ribbons are horizontal, so their normal points up: the winding alone would leave
	the road and the river lit from below."""
	var n := Vector3.UP
	st.set_normal(n)
	st.set_uv(Vector2(run0, 0.0))
	st.add_vertex(pa)
	st.set_normal(n)
	st.set_uv(Vector2(run1, width))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(Vector2(run0, width))
	st.add_vertex(pb)
	st.set_normal(n)
	st.set_uv(Vector2(run0, 0.0))
	st.add_vertex(pa)
	st.set_normal(n)
	st.set_uv(Vector2(run1, 0.0))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(Vector2(run1, width))
	st.add_vertex(b)


func _asphalt() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex("res://assets/textures/asphalt_02/asphalt_02_diff.jpg")
	mat.normal_enabled = true
	mat.normal_texture = _tex("res://assets/textures/asphalt_02/asphalt_02_nor_gl.jpg")
	mat.roughness_texture = _tex("res://assets/textures/asphalt_02/asphalt_02_rough.jpg")
	mat.uv1_scale = Vector3(0.25, 0.25, 1.0)
	mat.roughness = 0.85
	# the street lamps of the Bund road: a faint warm glow on the asphalt, so the
	# driver's view is not a black band
	mat.emission_enabled = true
	mat.emission = Color(0.055, 0.045, 0.035)
	return mat


func _sidewalk() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex("res://assets/textures/concrete_pavement/concrete_pavement_diff.jpg")
	mat.uv1_scale = Vector3(0.3, 0.3, 1.0)
	mat.roughness = 0.9
	mat.albedo_color = Color(0.62, 0.61, 0.58)
	return mat


func _paint() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.83, 0.72)
	mat.emission_enabled = true
	mat.emission = Color(0.80, 0.76, 0.62)
	mat.roughness = 0.8
	return mat


func _water() -> Material:
	if OS.has_environment("BUND_PLAIN_WATER"):
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.05, 0.07, 0.09)
		plain.roughness = 0.1
		return plain
	var mat := load("res://shaders/materials/SH_water.tres")
	var water := mat as ShaderMaterial
	if water == null:
		return mat as Material
	# A calmer surface than the river shader's default: the waves of a 6 m ripple map
	# scatter the screen-space reflection into big soft blobs, and the row then stops
	# being reflected in the river. The preview wants the gold of the row on the water.
	var copy := water.duplicate() as ShaderMaterial
	copy.set_shader_parameter("wave_strength", 0.15)
	copy.set_shader_parameter("roughness_value", 0.05)
	return copy


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# ---------------------------------------------------------------- the lights
func _build_lights() -> void:
	var parsed := _sidecar()
	if parsed.is_empty():
		return
	var records: Array = parsed.get("lights", [])
	for rec: Dictionary in records:
		var light := _make_light(rec)
		light.visible = false
		add_child(light)
		_lights.append(light)
	# the promenade lanterns: the soft deck lights stand exactly on them
	for lamp: Dictionary in parsed.get("deck_lamps", []):
		var pos: Array = lamp["position"]
		_deck_anchors.append(Vector3(pos[0], pos[1], pos[2]))
	_select_nearest()
	print("bund preview: %d lights in the sidecar, %d deck lanterns"
		% [_lights.size(), _deck_anchors.size()])


func _build_deck_lights() -> void:
	"""Warm lamps on the promenade deck so the walkway is not a black band.

	They follow the camera like the uplights: the 8 nearest lanterns are lit. They cast
	no specular, or the water in front of the deck would carry white blobs."""
	for i in DECK_LIGHTS:
		var lamp := OmniLight3D.new()
		lamp.name = "Deck_%02d" % i
		lamp.light_color = DECK_COLOR
		lamp.light_energy = DECK_ENERGY
		lamp.omni_range = DECK_RANGE
		lamp.shadow_enabled = false
		lamp.light_specular = 0.0
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = FADE_BEGIN
		lamp.distance_fade_length = FADE_LENGTH
		add_child(lamp)
		_deck_lights.append(lamp)


func _make_light(rec: Dictionary) -> SpotLight3D:
	var pos_arr: Array = rec["position"]
	var dir_arr: Array = rec["direction"]
	var col_arr: Array = rec["color"]
	var light := SpotLight3D.new()
	light.name = String(rec.get("name", "Uplight"))
	light.position = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	light.light_color = Color(col_arr[0], col_arr[1], col_arr[2])
	light.light_energy = float(rec.get("energy", 25.0))
	light.spot_range = float(rec.get("range", 30.0))
	# Godot's spot_angle is in DEGREES (art dossier 3.4: a 40 deg cone)
	light.spot_angle = float(rec.get("angle", 40.0))
	light.spot_attenuation = SPOT_ATTENUATION
	light.shadow_enabled = false
	light.light_specular = SPOT_SPECULAR
	light.distance_fade_enabled = true
	light.distance_fade_begin = FADE_BEGIN
	light.distance_fade_length = FADE_LENGTH
	# aim the spot: it shines along its local -Z
	var dir := Vector3(dir_arr[0], dir_arr[1], dir_arr[2]).normalized()
	var z_axis := -dir
	var up := Vector3.UP
	if absf(z_axis.dot(up)) > 0.99:
		up = Vector3.FORWARD
	var x_axis := up.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	light.transform = Transform3D(Basis(x_axis, y_axis, z_axis), light.position)
	return light


func _select_nearest() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var origin := cam.global_position
	var order: Array = _lights.duplicate()
	order.sort_custom(func(a: SpotLight3D, b: SpotLight3D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	for i in order.size():
		var light: SpotLight3D = order[i]
		light.visible = i < MAX_LIGHTS
	# the deck lamps follow the camera as well
	var anchors: Array = _deck_anchors.duplicate()
	anchors.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(origin) < b.distance_squared_to(origin))
	for i in _deck_lights.size():
		var lamp: OmniLight3D = _deck_lights[i]
		if i < anchors.size():
			lamp.global_position = anchors[i]
			lamp.visible = true
		else:
			lamp.visible = false
	var active := 0
	for light in _lights:
		if light.visible:
			active += 1
	for lamp in _deck_lights:
		if lamp.visible:
			active += 1
	if active != _active:
		_active = active
		print("bund preview: %d active lights" % active)
