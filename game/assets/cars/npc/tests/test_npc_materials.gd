extends Node
## npc_cars material and UV contract test (unit: npc_cars).
##
## Every textured surface must carry UVs, the lamps must sample the right LED
## strips of the shared trim sheet, the route sign must use its whole image
## and the preview scene must stand on the ground.
##
##     tools/godot.sh test res://assets/cars/npc/tests/test_npc_materials.gd

const MODELS := ["sedan_ev", "suv_ev", "hatch_ev", "taxi", "robotaxi",
	"police_patrol", "police_interceptor", "police_suv", "van", "truck", "bus",
	"police_drone"]

# the LED strips of the shared trim sheet: the front bar samples the white
# strip, the tail bar the red one (ref/art §4.8)
const LED_WHITE := Rect2(0.5, 0.5, 0.25, 0.125)
const LED_RED := Rect2(0.75, 0.5, 0.25, 0.125)
# the route sign covers its image (the UV of the whole 1024x256 sheet)
const SIGN_COVER := 0.9


func _ready() -> void:
	var ok := true
	for model_name in MODELS:
		ok = _check_model(model_name) and ok
	ok = _check_preview() and ok
	get_tree().quit(0 if ok else 1)


func _check_model(model_name: String) -> bool:
	var ok := true
	var path := "res://assets/cars/npc/%s.glb" % model_name
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL %s does not load" % model_name)
		return false
	var root := packed.instantiate()
	add_child(root)
	var no_uv := _surfaces_without_uv(root)
	if not no_uv.is_empty():
		print("FAIL %s surfaces without UVs: %s" % [model_name, ", ".join(no_uv)])
		ok = false
	if model_name != "police_drone":
		ok = _check_lamp_uvs(root, model_name) and ok
	if model_name == "bus":
		ok = _check_sign_uv(root) and ok
	root.queue_free()
	return ok


func _check_lamp_uvs(root: Node, model_name: String) -> bool:
	"""The tail lamp must sample the red LED strip, the head lamp the white one.

	Every surface of the lamp node is checked on its own: the head lamp also
	carries the dark reflector of the lamp housing.
	"""
	var ok := true
	for pair in [["Lamp_F", LED_WHITE], ["Lamp_R", LED_RED]]:
		var node_name := String(pair[0])
		var rect: Rect2 = pair[1]
		var found := false
		var lit := false
		for child in root.find_children(node_name, "MeshInstance3D", true, false):
			found = true
			var mi := child as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var uvs := _uv_range(mi, i)
				if uvs.size == Vector2.ZERO:
					continue
				if rect.grow(0.002).encloses(uvs):
					lit = true
		if not found:
			print("FAIL %s is missing %s" % [model_name, node_name])
			ok = false
		elif not lit:
			print("FAIL %s %s does not sample the LED strip %s"
					% [model_name, node_name, rect])
			ok = false
	if ok:
		print("PASS %s lamps sample the right LED strips" % model_name)
	return ok


func _check_sign_uv(root: Node) -> bool:
	"""The LED route sign must cover its image (r3 item 5b)."""
	var ok := true
	for node_name in ["SignRoute", "SignRouteSide"]:
		for child in root.find_children(node_name, "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			var lo := Vector2(2.0, 2.0)
			var hi := Vector2(-2.0, -2.0)
			for i in mi.mesh.get_surface_count():
				var uvs := _uv_range(mi, i)
				if uvs.size == Vector2.ZERO:
					continue
				lo = lo.min(uvs.position)
				hi = hi.max(uvs.end)
			if hi.x < lo.x:
				continue
			var cover: float = minf(hi.x - lo.x, hi.y - lo.y)
			if cover < SIGN_COVER:
				print("FAIL %s %s covers only %.0f %% of its image"
						% [node_name, node_name, cover * 100.0])
				ok = false
	if ok:
		print("PASS bus the route signs use their whole image")
	return ok


func _check_preview() -> bool:
	"""The preview scene must load and look at the fleet."""
	var ok := true
	var preview := load("res://assets/cars/npc/preview_npc.tscn") as PackedScene
	if preview == null:
		print("FAIL preview_npc.tscn does not load")
		return false
	var scene := preview.instantiate()
	add_child(scene)
	var cars := 0
	for child in scene.get_children():
		if not (child is Node3D):
			continue
		var car_name := String((child as Node3D).name)
		if not car_name.ends_with("_ev") and not car_name in ["taxi", "robotaxi",
				"van", "truck", "bus", "police_drone", "police_patrol",
				"police_interceptor", "police_suv"]:
			continue
		cars += 1
		if absf((child as Node3D).position.y) > 0.01:
			print("FAIL preview %s is not on the ground (y=%.2f)"
					% [child.name, (child as Node3D).position.y])
			ok = false
	if cars < 12:
		print("FAIL preview_npc.tscn only has %d vehicles" % cars)
		ok = false
	var cam := scene.find_child("Camera3D", true, false) as Camera3D
	if cam == null:
		print("FAIL preview_npc.tscn has no Camera3D")
		ok = false
	else:
		var fwd := -cam.global_transform.basis.z
		print("PASS preview camera at %v forward %v" % [cam.global_position, fwd])
		if fwd.y >= 0.0 or fwd.y < -0.4:
			print("FAIL preview camera does not look slightly down")
			ok = false
	if ok:
		print("PASS preview_npc.tscn has the whole fleet")
	scene.queue_free()
	return ok


func _uv_range(mi: MeshInstance3D, surface: int) -> Rect2:
	"""The bounding rectangle of the UVs of one surface of a mesh."""
	var lo := Vector2(2.0, 2.0)
	var hi := Vector2(-2.0, -2.0)
	var arrays := mi.mesh.surface_get_arrays(surface)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	if hi.x < lo.x:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	return Rect2(lo, hi - lo)


func _surfaces_without_uv(node: Node) -> Array:
	var out: Array = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat == null:
				continue
			var textured := false
			if mat is BaseMaterial3D:
				var base := mat as BaseMaterial3D
				textured = base.albedo_texture != null or base.normal_enabled \
						or base.roughness_texture != null \
						or base.metallic_texture != null \
						or base.emission_enabled and base.emission_texture != null \
						or base.ao_enabled and base.ao_texture != null
			if not textured:
				continue
			var arrays := mi.mesh.surface_get_arrays(i)
			if arrays[Mesh.ARRAY_TEX_UV] == null \
					or (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty():
				out.append("%s#%d" % [mi.name, i])
	return out
