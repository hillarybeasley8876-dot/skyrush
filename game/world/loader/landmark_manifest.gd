extends RefCounted
## The landmarks of the landmarks unit, placed with the contract in
## res://assets/landmarks/landmarks_manifest.json (anchor [x, y, z], rotation_y, an optional
## wrapper scene and the list of the floodlights). The landmarks are visible from far away (no
## visibility range), so the skyline of Lujiazui stands over the Bund.

const MANIFEST_PATH := "res://assets/landmarks/landmarks_manifest.json"
const LedCycle := preload("res://world/loader/led_cycle.gd")

## The floodlights found in the landmarks: {position, direction, color, energy, range, angle}.
var floods: Array[Dictionary] = []


## Instantiates every landmark of the manifest under `parent` and returns the number of them.
func build(parent: Node3D) -> int:
	floods.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("[world] %s is missing" % MANIFEST_PATH)
		return 0
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return 0
	var root := data as Dictionary
	var assets: Array = root.get("assets", [])
	var light_specs: Array = root.get("lights", [])
	var count := 0
	for entry in assets:
		if not entry is Dictionary:
			continue
		var asset := entry as Dictionary
		var node := _instantiate(asset)
		if node == null:
			continue
		node.position = _anchor(asset)
		node.rotation.y = float(asset.get("rotation_y", 0.0))
		parent.add_child(node)
		_collect_floods(node, str(asset.get("name", "")), light_specs)
		if str(asset.get("name", "")) == "oriental_pearl":
			_animate_led(node)
		count += 1
	return count


## The landmark of the manifest: the wrapper scene when there is one (it applies the facade
## shader with the seed of the tower), the glb otherwise.
func _instantiate(asset: Dictionary) -> Node3D:
	var wrapper := str(asset.get("wrapper", ""))
	if wrapper != "" and ResourceLoader.exists(wrapper):
		var packed := load(wrapper) as PackedScene
		if packed != null:
			var wrapped := packed.instantiate() as Node3D
			if wrapped != null:
				return wrapped
	var path := str(asset.get("glb", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	MaterialLibrary.apply(node)
	return node


## The world position of a landmark: [x, y, z]; [x, z] is the fallback of the old format.
static func _anchor(asset: Dictionary) -> Vector3:
	var anchor: Array = asset.get("anchor", [0.0, 0.0])
	if anchor.size() >= 3:
		return Vector3(float(anchor[0]), float(anchor[1]), float(anchor[2]))
	return Vector3(float(anchor[0]), 0.0, float(anchor[1]))


## The floodlights of the manifest: the empties whose name starts with the prefix carry the
## position and the aim of a light; the manifest carries its colour, energy, angle and range.
func _collect_floods(node: Node3D, asset_name: String, light_specs: Array) -> void:
	for spec in light_specs:
		if not spec is Dictionary:
			continue
		var entry := spec as Dictionary
		if str(entry.get("asset", "")) != asset_name:
			continue
		var prefix := str(entry.get("empty", ""))
		if prefix == "":
			continue
		for child in node.find_children(prefix + "*", "Node3D", true, false):
			var light := child as Node3D
			if light == null:
				continue
			floods.append({
				"position": light.global_position,
				"direction": -light.global_basis.z.normalized(),
				"color": Color(str(entry.get("color", "#FFC98A"))),
				"energy": float(entry.get("energy", 10.0)),
				"angle": float(entry.get("angle", 25.0)),
				"range": float(entry.get("range", 40.0)),
			})


## The LED spheres of the Oriental Pearl Tower cycle through pink, violet and blue.
func _animate_led(node: Node3D) -> void:
	var materials: Array[StandardMaterial3D] = []
	for child in node.find_children("LED_Sphere*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.get_active_material(0) as StandardMaterial3D
		if mat != null and not materials.has(mat):
			materials.append(mat)
	if materials.is_empty():
		return
	var animator := LedCycle.new()
	animator.materials = materials
	node.add_child(animator)
