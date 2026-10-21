class_name TrafficVisual
extends RefCounted
## Builds the visual of an AI traffic car: the npc glb when the npc_cars unit has shipped one,
## a procedural body otherwise. Either way the car gets painted bodywork, the real lamp meshes of
## the model and the amber indicator cards.
##
## The body paint is the shared `SH_car_paint_npc` shader material. Its colour is an INSTANCE
## uniform (`base_color_override`), so every car wears its own colour from ONE material.

const NPC_DIR := "res://assets/cars/npc/"
const PAINT_SHADER := "car_paint.gdshader"
const PAINT_MATERIAL := "SH_car_paint_npc"
const INDICATOR_SIZE := Vector2(0.17, 0.13)
const INDICATOR_PROUD := 0.03  ## m: how far the indicator card stands off the lens
const INDICATOR_INSET := 0.26  ## m: how far inboard of the end of the lamp bar the card sits

static var _glbs: Dictionary = {}
static var _bodies: Dictionary = {}


## The AABB of the body of a model, measured from the `Body` mesh of the glb, so the box
## collider of the car matches the mesh. The fallback is the size the fleet declares.
static func body_aabb(model_id: StringName) -> AABB:
	if _bodies.has(model_id):
		return _bodies[model_id] as AABB
	var data := TrafficFleet.MODELS.get(model_id, TrafficFleet.MODELS[&"sedan_ev"]) as Dictionary
	var fallback := AABB(Vector3(-float(data["width"]) * 0.5, 0.0, -float(data["length"]) * 0.5),
			Vector3(float(data["width"]), float(data["height"]), float(data["length"])))
	var result := fallback
	var glb := find_glb(String(data["glb"]))
	if glb != null:
		var instance := glb.instantiate()
		for node in instance.find_children("Body", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var aabb := mesh.get_aabb()
			if aabb.size.length() > 0.01:
				result = aabb
			break
		instance.free()
	_bodies[model_id] = result
	return result


## Asks the engine for the npc models, so the first traffic car does not have to wait for the
## glb to load (that took half a second and stalled the frame).
static func preload_models() -> void:
	var dir := DirAccess.open(NPC_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".glb"):
			continue
		var path := NPC_DIR + file
		if ResourceLoader.has_cached(path):
			continue
		ResourceLoader.load_threaded_request(path)


## The npc glb for `keyword` (null when the npc_cars unit has not shipped it).
##
## The exact name wins; a name that only contains the keyword is the fallback. The police models
## are never used for the traffic.
static func find_glb(keyword: String) -> PackedScene:
	if _glbs.has(keyword):
		return _glbs[keyword] as PackedScene
	var found: PackedScene = null
	var partial: PackedScene = null
	var dir := DirAccess.open(NPC_DIR)
	if dir != null:
		for file in dir.get_files():
			if not file.ends_with(".glb"):
				continue
			var model := file.get_basename().to_lower()
			if model.contains("police"):
				continue
			if model == keyword:
				found = load(NPC_DIR + file) as PackedScene
				break
			if partial == null and model.contains(keyword):
				partial = load(NPC_DIR + file) as PackedScene
	if found == null:
		found = partial
	_glbs[keyword] = found
	return found


## Builds the "Visual" node of a traffic car (meshes only, no physics).
static func build(model_id: StringName, colour: Color) -> Node3D:
	var data := TrafficFleet.MODELS.get(model_id, TrafficFleet.MODELS[&"sedan_ev"]) as Dictionary
	var root := Node3D.new()
	root.name = "Visual"
	var glb := find_glb(String(data["glb"]))
	if glb != null:
		var instance := glb.instantiate()
		root.add_child(instance)
		apply_colour(instance, colour)
		MaterialLibrary.apply(instance)
		_add_indicator_cards(root)
	else:
		_build_body(root, data, colour)
		_add_lamps(root, data)
	return root


## Paints the body of the car.
##
## The colour is the instance uniform `base_color_override` of the car paint shader (a plain
## `base_color` in the material would be ignored by the renderer). Only the surfaces that use the
## traffic paint are painted; the taxi keeps its own teal livery.
static func apply_colour(node: Node, colour: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if not _has_paint_surface(mesh):
			continue
		mesh.set_instance_shader_parameter(&"base_color_override",
				Color(colour.r, colour.g, colour.b, 1.0))


## True when one of the surfaces of the mesh uses the traffic paint.
static func _has_paint_surface(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null:
		return false
	for i in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(i)
		if material != null and material.resource_name == PAINT_MATERIAL:
			return true
	return false


## Adds the amber indicator cards to a car that uses a glb model. The lamps themselves are the
## model's own lenses (see TrafficLamps); only the indicators are added.
static func _add_indicator_cards(root: Node3D) -> void:
	for node in root.find_children("Body", "MeshInstance3D", true, false):
		var body := node as MeshInstance3D
		if body != null:
			_add_indicators(root, body)
			return


## The amber indicator cards: small quads on the lamp bars of the car, a few centimetres proud of
## the lens, so they read as a lens of their own and not as a sticker on the paint.
static func _add_indicators(root: Node3D, body: MeshInstance3D) -> void:
	var front := _lamp_anchor(root, "Lamp_F", body, -1.0)
	var rear := _lamp_anchor(root, "Lamp_R", body, 1.0)
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		_indicator(root, "Indicator_F%s" % tag,
				Vector3(front.x * side, front.y, front.z), 0.0)
		_indicator(root, "Indicator_R%s" % tag,
				Vector3(rear.x * side, rear.y, rear.z), PI)


## Where an indicator card sits: the inner end of the lamp bar, `sign` in front of the lens.
static func _lamp_anchor(root: Node3D, lamp_name: String, body: MeshInstance3D,
		sign: float) -> Vector3:
	var mesh := root.find_child(lamp_name, true, false) as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		var aabb := mesh.get_aabb()
		if aabb.size.x > 0.05:
			return Vector3(aabb.size.x * 0.5 - INDICATOR_INSET,
					aabb.position.y + aabb.size.y * 0.5,
					aabb.position.z + sign * INDICATOR_PROUD)
	var fallback := body.get_aabb()
	return Vector3(fallback.size.x * 0.5 - INDICATOR_INSET,
			clampf(fallback.position.y + fallback.size.y * 0.35, 0.4, 1.0),
			fallback.position.z + (fallback.size.z if sign > 0.0 else 0.0)
					+ sign * INDICATOR_PROUD)


## One indicator card.
static func _indicator(root: Node3D, card_name: String, pos: Vector3, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = card_name
	mi.mesh = TrafficMesh.quad(INDICATOR_SIZE)
	mi.material_override = TrafficMaterials.indicator()
	mi.position = pos
	mi.rotation.y = yaw
	root.add_child(mi)


## The procedural body: a few tapered boxes for the shell, the glass house and the roof. It is
## only the fallback for a model the npc_cars unit has not shipped.
static func _build_body(root: Node3D, data: Dictionary, colour: Color) -> void:
	for part in _shape(data) as Array:
		var p := part as Dictionary
		var mat: Material = TrafficMaterials.paint()
		if String(p["kind"]) == "glass":
			mat = TrafficMaterials.glass()
		elif String(p["kind"]) == "trim":
			mat = TrafficMaterials.trim()
		var mi := MeshInstance3D.new()
		mi.mesh = TrafficMesh.tapered_box(p["bottom"], p["top"], float(p["h"]), float(p["y"]),
				p["shift"])
		mi.material_override = mat
		root.add_child(mi)
		if mat == TrafficMaterials.paint():
			mi.set_instance_shader_parameter(&"base_color_override",
					Color(colour.r, colour.g, colour.b, 1.0))
	_add_wheels(root, data)
	_add_bumpers(root, data)


## The wheels of the car: rubber tyres with a hub, at the four corners.
static func _add_wheels(root: Node3D, data: Dictionary) -> void:
	var length := float(data["length"])
	var width := float(data["width"])
	var type := StringName(data["type"])
	var radius := 0.34
	var track := 0.5 * width - 0.12
	if type == &"bus_truck":
		radius = 0.50
		track = 0.5 * width - 0.16
	elif type == &"van":
		radius = 0.38
	var tyre_width := 0.22 if type != &"bus_truck" else 0.30
	var axles: Array = [-0.30 * length, 0.30 * length]
	if type == &"bus_truck":
		axles = [-0.34 * length, 0.26 * length, 0.38 * length]
	for z in axles:
		for side: float in [-1.0, 1.0]:
			var wheel := TrafficMesh.wheel(radius, tyre_width)
			wheel.position = Vector3(track * side, radius, float(z))
			for child in wheel.get_children():
				(child as MeshInstance3D).material_override = TrafficMaterials.rubber()
			root.add_child(wheel)
			var hub := MeshInstance3D.new()
			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = radius * 0.55
			hub_mesh.bottom_radius = radius * 0.55
			hub_mesh.height = tyre_width + 0.01
			hub_mesh.radial_segments = 10
			hub.mesh = hub_mesh
			hub.rotation.z = PI * 0.5
			hub.position = wheel.position
			hub.material_override = TrafficMaterials.trim()
			root.add_child(hub)


## The bumpers and the grille: dark trim so the car does not end in a bare box.
static func _add_bumpers(root: Node3D, data: Dictionary) -> void:
	var length := float(data["length"])
	var width := float(data["width"])
	var height := float(data["height"])
	for side: float in [-1.0, 1.0]:
		var bumper := MeshInstance3D.new()
		bumper.mesh = TrafficMesh.tapered_box(Vector2(0.5 * width - 0.10, 0.09),
				Vector2(0.5 * width - 0.13, 0.07), 0.20 * height, 0.16 * height)
		bumper.position = Vector3(0.0, 0.0, side * (0.5 * length - 0.06))
		bumper.material_override = TrafficMaterials.trim()
		root.add_child(bumper)
	var grille := MeshInstance3D.new()
	grille.mesh = TrafficMesh.tapered_box(Vector2(0.5 * width - 0.28, 0.05),
			Vector2(0.5 * width - 0.30, 0.04), 0.12 * height, 0.30 * height)
	grille.position = Vector3(0.0, 0.0, -(0.5 * length - 0.04))
	grille.material_override = TrafficMaterials.trim()
	root.add_child(grille)


## The lamps of the procedural body: the same soft additive patches the models use.
static func _add_lamps(root: Node3D, data: Dictionary) -> void:
	var length := float(data["length"])
	var width := float(data["width"])
	var height := float(data["height"])
	var type := StringName(data["type"])
	var half := 0.5 * length
	var half_w := 0.5 * width
	var lamp_y := 0.44 * height
	if type == &"bus_truck":
		lamp_y = 0.30 * height
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		_lamp(root, "Lamp_Head_%s" % tag, TrafficMaterials.head(),
				Vector3(side * (half_w - 0.26), lamp_y, -half + 0.02), 0.0)
		_lamp(root, "Lamp_Tail_%s" % tag, TrafficMaterials.tail(),
				Vector3(side * (half_w - 0.24), lamp_y + 0.04, half - 0.02), PI)
		_lamp(root, "Indicator_F%s" % tag, TrafficMaterials.indicator(),
				Vector3(side * (half_w - 0.09), lamp_y, -half + 0.03), 0.0)
		_lamp(root, "Indicator_R%s" % tag, TrafficMaterials.indicator(),
				Vector3(side * (half_w - 0.09), lamp_y, half - 0.03), PI)


## One lamp patch of the procedural body.
static func _lamp(root: Node3D, lamp_name: String, mat: Material, pos: Vector3, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = lamp_name
	mi.mesh = TrafficMesh.quad(Vector2(0.36, 0.17))
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	root.add_child(mi)


## The body layout of a model: a list of parts (kind, bottom, top, y, height, shift).
## kind: "paint", "glass" or "trim".
static func _shape(data: Dictionary) -> Array:
	var type := StringName(data["type"])
	var length := float(data["length"])
	var width := float(data["width"])
	var height := float(data["height"])
	if type == &"bus_truck":
		return [
			{"kind": "paint", "bottom": Vector2(0.5 * width - 0.06, 0.5 * length - 0.10),
				"top": Vector2(0.5 * width - 0.08, 0.5 * length - 0.14), "y": 0.12 * height,
				"h": 0.55 * height, "shift": Vector2.ZERO},
			{"kind": "glass", "bottom": Vector2(0.5 * width - 0.07, 0.5 * length - 0.12),
				"top": Vector2(0.5 * width - 0.09, 0.5 * length - 0.16), "y": 0.67 * height,
				"h": 0.20 * height, "shift": Vector2.ZERO},
			{"kind": "paint", "bottom": Vector2(0.5 * width - 0.09, 0.5 * length - 0.16),
				"top": Vector2(0.5 * width - 0.13, 0.5 * length - 0.22), "y": 0.87 * height,
				"h": 0.13 * height, "shift": Vector2.ZERO},
		]
	if type == &"van":
		return [
			{"kind": "paint", "bottom": Vector2(0.5 * width - 0.08, 0.5 * length - 0.05),
				"top": Vector2(0.5 * width - 0.10, 0.5 * length - 0.09), "y": 0.10 * height,
				"h": 0.78 * height, "shift": Vector2(0.0, 0.10 * length)},
			{"kind": "glass", "bottom": Vector2(0.5 * width - 0.11, 0.16 * length),
				"top": Vector2(0.5 * width - 0.13, 0.13 * length), "y": 0.44 * height,
				"h": 0.30 * height, "shift": Vector2(0.0, -0.30 * length)},
			{"kind": "paint", "bottom": Vector2(0.5 * width - 0.10, 0.5 * length - 0.09),
				"top": Vector2(0.5 * width - 0.15, 0.5 * length - 0.15), "y": 0.88 * height,
				"h": 0.12 * height, "shift": Vector2(0.0, 0.10 * length)},
		]
	return [
		{"kind": "paint", "bottom": Vector2(0.5 * width - 0.12, 0.5 * length - 0.05),
			"top": Vector2(0.5 * width - 0.18, 0.5 * length - 0.14), "y": 0.20 * height,
			"h": 0.46 * height, "shift": Vector2.ZERO},
		{"kind": "paint", "bottom": Vector2(0.5 * width - 0.18, 0.5 * length - 0.14),
			"top": Vector2(0.5 * width - 0.21, 0.5 * length - 0.19), "y": 0.66 * height,
			"h": 0.05 * height, "shift": Vector2.ZERO},
		{"kind": "glass", "bottom": Vector2(0.5 * width - 0.23, 0.30 * length),
			"top": Vector2(0.5 * width - 0.27, 0.24 * length), "y": 0.71 * height,
			"h": 0.23 * height, "shift": Vector2(0.0, 0.05 * length)},
		{"kind": "paint", "bottom": Vector2(0.5 * width - 0.27, 0.24 * length),
			"top": Vector2(0.5 * width - 0.31, 0.21 * length), "y": 0.94 * height,
			"h": 0.06 * height, "shift": Vector2(0.0, 0.05 * length)},
	]
