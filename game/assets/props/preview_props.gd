extends Node3D
## Preview scene for the props unit (unit: props).
##
##   tools/godot.sh shot --scene=res://assets/props/preview_props.tscn --out=props \
##       --cams=res://assets/props/preview_cams.json --quality=ultra
##
## It instances the shared night-city environment and stands the three gameplay
## sites (toll plaza, gas station, charging hub) on a wet-asphalt apron, with a
## strip of street kit for scale. The cameras in preview_cams.json shoot each
## site from the driver's seat (15-25 m out), from a 7 m hop apex and from 100 m.
##
## The props carry Empty markers named `Light` / `Light_<n>` whose local +Y
## points where the light falls (CONTRACTS.md §2). Turning them into real lights
## here both lights the preview and proves the marker contract.

const ENV_SCENE := "res://world/env/environment.tscn"
const WET_ASPHALT := "res://shaders/materials/SH_wet_asphalt.tres"
const SITES := "res://assets/props/sites/"
const STREET := "res://assets/props/street/"

# Site placement in Godot space (metres, Y up).
const TOLL_POS := Vector3(0.0, 0.0, 0.0)
const GAS_POS := Vector3(600.0, 0.0, 0.0)
const CHARGE_POS := Vector3(1200.0, 0.0, 0.0)
const STREET_POS := Vector3(0.0, 0.0, 420.0)
const SKYLANE_POS := Vector3(1800.0, 0.0, 0.0)

# The light of the `Light` / `Light_<n>` markers.  The cone is wide (78 degrees)
# so the canopy lights also reach the vertical surfaces: a booth wall or a
# dispenser only reads white when the light spills onto it.  The world unit
# should use the same values for the markers of the sites.
const SITE_LIGHT_ENERGY := 9.0
# The charging hub is open on three sides, so its markers need a little more
# energy to lift the white posts and the dispensers.
const CHARGE_LIGHT_ENERGY := 11.0
# The toll plaza is 112 m long with ten lights (one every two lanes), so its
# markers need more energy than the two canopies to light the same ground.
const TOLL_LIGHT_ENERGY := 19.0
const SITE_LIGHT_RANGE := 42.0
const STREET_LIGHT_ENERGY := 5.0
const STREET_LIGHT_RANGE := 26.0
const LIGHT_ANGLE := 78.0
const LIGHT_ATTENUATION := 0.5
const LIGHT_COLOUR := Color(1.0, 0.94, 0.84)


func _ready() -> void:
	_build_environment()
	_build_ground()
	_add_site(SITES + "toll_plaza.glb", TOLL_POS, TOLL_LIGHT_ENERGY)
	_add_site(SITES + "gas_station.glb", GAS_POS, SITE_LIGHT_ENERGY)
	_add_site(SITES + "charge_station.glb", CHARGE_POS, CHARGE_LIGHT_ENERGY)
	_add_sky_lane()
	_add_street_kit()


func _build_environment() -> void:
	var packed := load(ENV_SCENE) as PackedScene
	if packed == null:
		push_warning("props preview: no environment scene at " + ENV_SCENE)
		return
	add_child(packed.instantiate())


func _build_ground() -> void:
	# The shared wet-asphalt surface, tiled every 4 m over a 2 km apron.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400.0, 1400.0)
	ground.mesh = plane
	var mat: Material = null
	if ResourceLoader.exists(WET_ASPHALT):
		mat = load(WET_ASPHALT) as Material
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.030, 0.031, 0.036)
		mat.roughness = 0.85
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).uv1_scale = Vector3(600.0, 350.0, 1.0)
	ground.material_override = mat
	ground.position = Vector3(600.0, -0.05, 0.0)
	add_child(ground)


func _add_site(path: String, pos: Vector3, energy: float = SITE_LIGHT_ENERGY) -> void:
	var node := _load_prop(path)
	if node == null:
		return
	node.position = pos
	add_child(node)
	_add_marker_lights(node, energy, SITE_LIGHT_RANGE)


## The props carry Empty markers named `Light` / `Light_<n>` whose local +Y points
## where the light falls (CONTRACTS.md §2). Turning them into real lights here
## both lights the preview and proves the marker contract.
func _add_marker_lights(node: Node3D, energy: float, range_m: float) -> void:
	for child in node.find_children("*", "Node3D", true, false):
		var marker := child as Node3D
		if marker == null:
			continue
		var marker_name := String(marker.name)
		if not (marker_name == "Light" or marker_name.begins_with("Light_")):
			continue
		var spot := SpotLight3D.new()
		spot.name = "%s_Spot" % marker_name
		spot.light_energy = energy
		spot.light_color = LIGHT_COLOUR
		spot.spot_range = range_m
		spot.spot_angle = LIGHT_ANGLE
		spot.spot_angle_attenuation = LIGHT_ATTENUATION
		spot.shadow_enabled = false
		marker.add_child(spot)
		spot.global_transform = marker.global_transform


func _load_prop(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("props preview: missing " + path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	MaterialLibrary.apply(node)
	return node


## The three sky-lane pieces: the launch ramp, the hologram ring and the sign.
func _add_sky_lane() -> void:
	for file in ["sky_lane_pad.glb", "sky_lane_gate.glb", "sky_lane_gantry.glb"]:
		var node := _load_prop(SITES + file)
		if node == null:
			continue
		node.position = SKYLANE_POS
		add_child(node)
		_add_marker_lights(node, SITE_LIGHT_ENERGY, SITE_LIGHT_RANGE)


func _add_street_kit() -> void:
	# A short street: lamps, a traffic light, a bus stop and a gantry, so the
	# screenshots show the props at the scale the player sees them.
	var line: Array[Dictionary] = [
		{"file": "lamp_street.glb", "pos": Vector3(0.0, 0.0, 0.0)},
		{"file": "traffic_light_mast.glb", "pos": Vector3(9.0, 0.0, 0.0)},
		{"file": "road_name_sign.glb", "pos": Vector3(17.0, 0.0, 0.0)},
		{"file": "bus_stop.glb", "pos": Vector3(26.0, 0.0, 0.0)},
		{"file": "plane_tree_1.glb", "pos": Vector3(38.0, 0.0, 0.0)},
		{"file": "planter_pot_bougainvillea.glb", "pos": Vector3(44.0, 0.0, 0.0)},
		{"file": "cone.glb", "pos": Vector3(48.0, 0.0, 0.0)},
		{"file": "bin.glb", "pos": Vector3(53.0, 0.0, 0.0)},
		{"file": "bollard.glb", "pos": Vector3(58.0, 0.0, 0.0)},
		{"file": "hydrant.glb", "pos": Vector3(63.0, 0.0, 0.0)},
		{"file": "e_scooter.glb", "pos": Vector3(68.0, 0.0, 0.0)},
		{"file": "bike_share.glb", "pos": Vector3(76.0, 0.0, 0.0)},
		{"file": "crash_barrier.glb", "pos": Vector3(88.0, 0.0, 0.0)},
		{"file": "billboard_pole.glb", "pos": Vector3(100.0, 0.0, 0.0)},
		{"file": "scaffold.glb", "pos": Vector3(116.0, 0.0, 0.0)},
		{"file": "neon_blade_frame.glb", "pos": Vector3(134.0, 0.0, 0.0)},
		{"file": "lamp_magnolia.glb", "pos": Vector3(0.0, 0.0, 18.0)},
		{"file": "lamp_heritage.glb", "pos": Vector3(9.0, 0.0, 18.0)},
		{"file": "noise_wall.glb", "pos": Vector3(19.0, 0.0, 18.0)},
		{"file": "metro_entrance.glb", "pos": Vector3(30.0, 0.0, 18.0)},
		{"file": "vms_board.glb", "pos": Vector3(50.0, 0.0, 18.0)},
		{"file": "guide_sign.glb", "pos": Vector3(64.0, 0.0, 18.0)},
		{"file": "ac_unit.glb", "pos": Vector3(76.0, 0.0, 18.0)},
		{"file": "hologram_projector.glb", "pos": Vector3(86.0, 0.0, 18.0)},
	]
	for item in line:
		var node := _load_prop(STREET + String(item["file"]))
		if node == null:
			continue
		node.position = STREET_POS + (item["pos"] as Vector3)
		add_child(node)
		_add_marker_lights(node, STREET_LIGHT_ENERGY, STREET_LIGHT_RANGE)
