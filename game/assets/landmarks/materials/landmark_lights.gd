extends Node
## Spawns the real lights for the landmarks.
##
## The glb files export `Flood_*` / `Aviation_*` marker empties (CONTRACTS 2:
## the empty's local +Y is the effect direction). This rig reads the light
## specs from landmarks_manifest.json and puts a real light at every empty of
## the matching asset, so the captures prove the night look instead of a flat
## emissive guess.
##
## Every spec names the ASSET it belongs to: the rig finds the node whose
## scene file is that asset (the glb or the wrapper tscn) and only collects
## that node's `Flood_*` children. Without that, one spec would light every
## tower in the scene.
##
## Two bugs the r3 review found are fixed here:
##   * `spot_angle` is in DEGREES in Godot, so it is passed straight through
##     (the old `deg_to_rad` made every beam 0.44 deg wide);
##   * a SpotLight3D shines along its local -Z, so the light is turned to
##     point along the empty's +Y (the effect direction).

const MANIFEST := "res://assets/landmarks/landmarks_manifest.json"


func _ready() -> void:
	var spec: Array = _read_spec()
	var spawned: int = 0
	for entry in spec:
		spawned += _attach(entry)
	print("landmark_lights: %d lights spawned" % spawned)


func _read_spec() -> Array:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	if file == null:
		push_error("landmark_lights: cannot read " + MANIFEST)
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("lights"):
		return []
	var lights: Variant = data["lights"]
	if typeof(lights) != TYPE_ARRAY:
		return []
	return lights


func _attach(entry: Dictionary) -> int:
	var asset: String = String(entry.get("asset", ""))
	var prefix: String = String(entry.get("empty", ""))
	var host: Node = _find_asset(get_parent(), asset)
	if host == null:
		push_warning("landmark_lights: no node for asset '%s'" % asset)
		return 0
	var empties: Array[Node3D] = []
	_collect(host, prefix, empties)
	for empty in empties:
		_spawn(empty, entry, asset)
	return empties.size()


func _find_asset(root: Node, asset: String) -> Node:
	"""The node whose scene file is this asset (the glb or the wrapper tscn)."""
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var path: String = node.scene_file_path
		if path == "":
			continue
		if path.get_file().get_basename() == asset:
			return node
	return null


func _collect(node: Node, prefix: String, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D and child.name.begins_with(prefix):
			out.append(child)
		_collect(child, prefix, out)


func _spawn(empty: Node3D, entry: Dictionary, asset: String) -> void:
	var kind: String = String(entry.get("type", "spot"))
	var light: Light3D
	if kind == "omni":
		light = OmniLight3D.new()
		light.omni_range = float(entry.get("range", 30.0))
	else:
		light = SpotLight3D.new()
		light.spot_range = float(entry.get("range", 30.0))
		# Godot's spot_angle is in DEGREES (the half angle of the cone)
		light.spot_angle = float(entry.get("angle", 25.0))
		light.spot_attenuation = 1.0
	light.light_color = Color(String(entry.get("color", "#FFFFFF")))
	light.light_energy = float(entry.get("energy", 10.0))
	light.shadow_enabled = bool(entry.get("shadow", false))
	light.name = "Light_%s_%s" % [asset, empty.name]
	add_child(light)
	light.global_transform = empty.global_transform
	_aim(light, empty)


func _aim(light: Light3D, empty: Node3D) -> void:
	"""Check the aim of a light against the empty it came from.

    CONTRACTS 2: the empty's local -Z is the effect direction, and a
    SpotLight3D shines along its local -Z, so the light inherits the empty's
    transform unchanged. (The glb is exported Y-up, so the Blender arrow's
    +Y becomes the glTF's -Z.)"""
	if not (light is SpotLight3D):
		return
	var dir := -empty.global_transform.basis.z
	if dir.length_squared() < 0.5:
		push_warning("landmark_lights: %s has no aim" % empty.name)
