extends Node
## npc_cars material contract test.
##
## The fleet is made of plain colours (no texture, no UV), and the game finds its surfaces by the name of the material: the traffic
## paints the surface that wears SH_car_paint_npc (the colour of a car is an instance uniform; the taxi wears its own SH_car_paint_taxi,
## the white of a police car is SH_car_paint_police: all three are materials of the shader library), the lamps of a traffic car are the
## surfaces NPC_lamp_front (Lamp_F) and NPC_lamp_rear (Lamp_R), the brake lamps of a car with physics are NPC_lamp_brake, the light
## bar of a police car is two meshes with one material each (the police unit duplicates surface 0 to drive the strobe).
##
##     python tools/gd.py test res://assets/cars/npc/tests/test_npc_materials.gd

const TRAFFIC := ["sedan_ev", "suv_ev", "hatch_ev", "taxi", "robotaxi", "van", "truck", "bus"]
const POLICE := ["police_patrol", "police_interceptor", "police_suv"]
const DRONE := "police_drone"
const PAINT := "SH_car_paint_npc"
const TAXI_PAINT := "SH_car_paint_taxi"
const POLICE_PAINT := "SH_car_paint_police"
const GLASS := "NPC_glass_dark"
## The cars of the pack have no texture: nothing may sample an image.
const FLAT := true


func _ready() -> void:
	var ok := true
	for model_name in TRAFFIC:
		ok = _check_car(model_name, false) and ok
	for model_name in POLICE:
		ok = _check_car(model_name, true) and ok
	ok = _check_drone() and ok
	ok = _check_preview() and ok
	get_tree().quit(0 if ok else 1)


func _load(model_name: String) -> Node:
	var packed := load("res://assets/cars/npc/%s.glb" % model_name) as PackedScene
	if packed == null:
		print("FAIL %s does not load" % model_name)
		return null
	var root := packed.instantiate()
	add_child(root)
	return root


func _check_car(model_name: String, police: bool) -> bool:
	var root := _load(model_name)
	if root == null:
		return false
	var ok := true
	var body_materials := _materials(root, "Body")
	if police:
		if body_materials.has(PAINT):
			print("FAIL %s wears the traffic paint (the police cars are black and white)" % model_name)
			ok = false
		if not body_materials.has("NPC_police_black") or not body_materials.has(POLICE_PAINT):
			print("FAIL %s Body lacks the police black and white (%s): %s" % [model_name, POLICE_PAINT, body_materials])
			ok = false
	else:
		var paint := TAXI_PAINT if model_name == "taxi" else PAINT
		if not body_materials.has(paint):
			print("FAIL %s Body has no %s surface: %s" % [model_name, paint, body_materials])
			ok = false
	for pair in [["Lamp_F", "NPC_lamp_front"], ["Lamp_R", "NPC_lamp_brake" if police else "NPC_lamp_rear"], ["Glass", GLASS],
			["Wheel_FL", "NPC_tyre"], ["Wheel_RR", "NPC_rim"]]:
		var wanted := String(pair[1])
		if not _materials(root, String(pair[0])).has(wanted):
			print("FAIL %s %s has no %s surface: %s" % [model_name, pair[0], wanted, _materials(root, String(pair[0]))])
			ok = false
	if police:
		for pair in [["LightBar_Red", "NPC_lightbar_red"], ["LightBar_Blue", "NPC_lightbar_blue"]]:
			var materials := _materials(root, String(pair[0]))
			if materials != [String(pair[1])]:
				print("FAIL %s %s has to be one surface of %s: %s" % [model_name, pair[0], pair[1], materials])
				ok = false
	if FLAT:
		var textured := _textured(root)
		if not textured.is_empty():
			print("FAIL %s surfaces with a texture: %s" % [model_name, ", ".join(textured)])
			ok = false
	if ok:
		print("PASS %s has the materials of the contract" % model_name)
	root.queue_free()
	return ok


## The drone is the procedural model of the old generator: it keeps its textures and its UVs.
func _check_drone() -> bool:
	var root := _load(DRONE)
	if root == null:
		return false
	var ok := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				var uvs: PackedVector2Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_TEX_UV]
				if uvs.is_empty():
					print("FAIL %s surface %s#%d is textured and has no UVs" % [DRONE, mi.name, i])
					ok = false
	if ok:
		print("PASS %s textured surfaces have UVs" % DRONE)
	root.queue_free()
	return ok


## The preview scene must load and hold the whole fleet.
func _check_preview() -> bool:
	var preview := load("res://assets/cars/npc/preview_npc.tscn") as PackedScene
	if preview == null:
		print("FAIL preview_npc.tscn does not load")
		return false
	var scene := preview.instantiate()
	add_child(scene)
	var ok := true
	var cars := 0
	for child in scene.get_children():
		if not (child is Node3D) or child is Light3D:
			continue
		if String((child as Node3D).name) in TRAFFIC + POLICE + [DRONE]:
			cars += 1
			if absf((child as Node3D).position.y) > 0.01:
				print("FAIL preview %s is not on the ground (y=%.2f)" % [child.name, (child as Node3D).position.y])
				ok = false
	if cars < 12:
		print("FAIL preview_npc.tscn only has %d vehicles" % cars)
		ok = false
	if ok:
		print("PASS preview_npc.tscn has the whole fleet")
	scene.queue_free()
	return ok


## The names of the materials of the surfaces of a named mesh.
func _materials(root: Node, node_name: String) -> Array:
	var out: Array = []
	for child in root.find_children(node_name, "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat != null and not out.has(mat.resource_name):
				out.append(mat.resource_name)
	return out


## The surfaces that sample an image.
func _textured(root: Node) -> Array:
	var out: Array = []
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				var base := mat as BaseMaterial3D
				if base.albedo_texture != null or base.normal_texture != null or base.roughness_texture != null \
						or base.emission_texture != null:
					out.append("%s#%d" % [mi.name, i])
	return out
