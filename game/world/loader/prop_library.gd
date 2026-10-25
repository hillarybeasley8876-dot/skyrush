extends RefCounted
## Resolves a prop type ("lamp", "planter", "tree", ...) to geometry. Prefers the glb produced by the
## props unit (res://assets/props/<type>.glb); falls back to procedural geometry so the world is
## never empty. A prop is a list of parts (mesh + material + local transform); each part becomes
## one MultiMesh so that batching survives.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const MeshMerger := preload("res://world/build/mesh_merger.gd")
const PROPS_DIR := "res://assets/props/"
## The props unit writes the street kit in street/ and the sites in sites/.
const PROP_DIRS: PackedStringArray = ["res://assets/props/", "res://assets/props/street/",
	"res://assets/props/sites/"]
## The furniture kinds of the roads unit mapped onto the glb of the props unit.
const GLB_FOR_KIND: Dictionary = {
	"lamp": "lamp_street",
	"lamp_magnolia": "lamp_magnolia",
	"lamp_heritage": "lamp_heritage",
	"tree": "plane_tree_1",
	"sign": "road_name_sign",
	"bus_stop": "bus_stop",
	"noise_wall": "noise_wall",
	"gantry": "guide_gantry_27",
	"vms": "vms_board",
	"traffic_light": "traffic_light_mast",
	"planter": "planter_pot_privet",
	"planter_pot_privet": "planter_pot_privet",
	"planter_pot_bougainvillea": "planter_pot_bougainvillea",
	"bin": "bin",
	"bollard": "bollard",
	"billboard": "billboard_pole",
	"bike_share": "bike_share",
	"e_scooter": "e_scooter",
	"hydrant": "hydrant",
	"metro_entrance": "metro_entrance",
	"neon_blade_frame": "neon_blade_frame",
	"shop_sign": "guide_sign",
}

## The prop types whose emissive head is a surface of their own (the street lamps).
const GLOW_MESHES: Dictionary = {
	"lamp": true, "lamp_heritage": true, "lamp_magnolia": true, "lamp_deck_double": true,
}

## The materials of the emissive head of a lamp. The head is the second surface of the mesh of
## the glb (the empties of the glb are named Light, Light_1 and Light_2, they carry no mesh).
const GLOW_MATERIALS: Array[String] = ["Prop_Opal", "Prop_Emissive", "Prop_Lamp"]

## The materials of the panel of a sign, per prop type. The panel is a surface of the mesh, so
## it is found by its material and not by the name of a node.
const SIGN_MATERIALS: Dictionary = {
	"shop_sign": ["Prop_Sign"],
}

## The materials that must not be drawn: the gantry of the props unit has a panel with a baked
## road name on it, and the world unit puts its own panels in its place.
const HIDDEN_MATERIALS: Dictionary = {
	"gantry": ["Prop_Sign", "Prop_SignLit"],
	"guide_gantry_19": ["Prop_Sign", "Prop_SignLit"],
	"guide_gantry_27": ["Prop_Sign", "Prop_SignLit"],
}

## The mesh of a prop that carries a generated sign texture.
const SIGN_MESH: Dictionary = {
	"vms": "Screen",
}

## The props whose origin is not on the ground: the panel of a shop board is at the centre of
## the board, and the post of the glb reaches down to the ground.
const LIFT: Dictionary = {
	"shop_sign": 1.59,
}

## The props that are not used at the size of the glb.
const SCALE: Dictionary = {
	"shop_sign": 0.75,
}

const SODIUM := Color("ffb46b")
const LED := Color("d9e8ff")
const HERITAGE := Color("ffa757")

var _cache: Dictionary = {}


## PropDef: {"parts": Array[Dictionary], "light": Dictionary, "kind": StringName}
## `variant` picks between the variants of a prop (the three plane trees).
func get_prop(type: String, variant: int = 0) -> Dictionary:
	var key := type if variant == 0 else "%s_%d" % [type, variant]
	if _cache.has(key):
		return _cache[key]
	var def := _from_glb(type, variant)
	if def.is_empty():
		def = _procedural(type)
	_cache[key] = def
	return def
## The light a prop carries (the lamps of the street kit). The offsets come from the empty
## nodes of the glb, so the light sits on the head of the mesh.
func _light_of(type: String, offsets: Array = []) -> Dictionary:
	if offsets.is_empty():
		match type:
			"lamp":
				return {"color": LED, "energy": 2.2, "range": 18.0, "kind": "omni",
					"offset": Vector3(1.6, 8.6, 0.0)}
			"lamp_heritage", "lamp_magnolia":
				return {"color": HERITAGE, "energy": 1.6, "range": 12.0, "kind": "omni",
					"offset": Vector3(1.0, 7.6, 0.0)}
			_:
				return {}
	var colour := LED
	var energy := 2.2
	var light_range := 18.0
	if type == "lamp_heritage" or type == "lamp_magnolia":
		colour = HERITAGE
		energy = 1.6
		light_range = 12.0
	return {"color": colour, "energy": energy, "range": light_range, "kind": "omni",
		"offset": offsets[0], "offsets": offsets}


## The glb of the props unit, split into one part per surface group (a MultiMesh has one
## surface). The head of a lamp and the panel of a sign are surfaces of the mesh, not nodes of
## their own, so the surfaces are split by their material.
func _from_glb(type: String, variant: int = 0) -> Dictionary:
	var path := _find_glb(type, variant)
	if path == "":
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	var node := packed.instantiate() as Node3D
	if node == null:
		return {}
	MaterialLibrary.apply(node)
	var instances: Array[MeshInstance3D] = []
	var screen: MeshInstance3D = null
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if String(mi.name) == String(SIGN_MESH.get(type, "Screen")):
			screen = mi  # the screen keeps its own material: the sign texture goes on it
			continue
		instances.append(mi)
	var hidden: Array = HIDDEN_MATERIALS.get(type, [])
	var body := MeshMerger.merge_where(instances, PackedStringArray(),
		func(m: Material) -> bool: return not _is_hidden(m, hidden))
	var parts: Array[Dictionary] = [{
		"key": type + "_0",
		"mesh": body,
		"transform": Transform3D.IDENTITY,
	}]
	if screen != null:
		parts.append({
			"key": type + "_screen",
			"mesh": screen.mesh,
			"material": screen.get_active_material(0),
			"transform": screen.transform,
			"sign": true,
		})
	elif SIGN_MATERIALS.has(type):
		# The panel of the sign is a surface of the mesh: it becomes a part of its own, so the
		# generated texture (or the atlas of the shop names) can go on it.
		var sign_materials: Array = SIGN_MATERIALS[type]
		var panel := MeshMerger.merge_where(instances, PackedStringArray(),
			func(m: Material) -> bool: return _matches(m, sign_materials))
		if panel.get_surface_count() > 0:
			var quad := _panel_quad(panel)
			parts.append({
				"key": type + "_panel",
				"mesh": quad["mesh"],
				"transform": quad["transform"],
				"sign": true,
				"atlas": type == "shop_sign",
			})
	if GLOW_MESHES.has(type):
		# The head of a lamp is its own part, so the street lamps can stay visible from the air
		# (the grid of the city is a net of light dots).
		var glow := MeshMerger.merge_where(instances, PackedStringArray(),
			func(m: Material) -> bool: return _is_glow(m))
		if glow.get_surface_count() > 0:
			parts.append({
				"key": type + "_glow",
				"mesh": glow,
				"transform": Transform3D.IDENTITY,
				"glow": true,
			})
	var light_offsets := _light_offsets(node, type)
	node.free()
	if body.get_surface_count() == 0 and screen == null and parts.size() == 1:
		return {}
	return {"parts": parts, "light": _light_of(type, light_offsets),
		"kind": StringName(type), "height": _height(body),
		"lift": float(LIFT.get(type, 0.0)), "scale": float(SCALE.get(type, 1.0))}


## The panel of a sign as a quad with the uvs of the whole panel, so the cell of the atlas
## fills it. The panel of the props unit is a flat surface of its mesh; the world unit puts
## its own texture on it.
static func _panel_quad(mesh: Mesh) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.size() < 3:
		return {"mesh": mesh, "transform": Transform3D.IDENTITY}
	var normal := (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0])
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for vertex in vertices:
		low = Vector2(minf(low.x, vertex.x), minf(low.y, vertex.y))
		high = Vector2(maxf(high.x, vertex.x), maxf(high.y, vertex.y))
	var size := high - low
	var centre := Vector3((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, vertices[0].z)
	# The quad of Godot faces +Z; the panel of the glb may face the other way.
	var yaw := PI if normal.z < 0.0 else 0.0
	return {"mesh": ProcMeshes.quad(size.x, size.y),
		"transform": Transform3D(Basis(Vector3.UP, yaw), centre)}


## The offsets of the light nodes of the glb (the head of a lamp is an empty of the glb, but
## it sits on the head of the mesh).
static func _light_offsets(node: Node3D, type: String) -> Array:
	var out: Array = []
	for child in node.get_children():
		if not child is Node3D:
			continue
		if not String(child.name).begins_with("Light"):
			continue
		out.append((child as Node3D).position)
	return out


## The height of a mesh (the prop is scaled to the height the roads unit states).
static func _height(mesh: Mesh) -> float:
	if mesh == null:
		return 0.0
	var box := AABB()
	var first := true
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if first:
				box = AABB(vertex, Vector3.ZERO)
				first = false
			else:
				box = box.expand(vertex)
	return box.size.y if not first else 0.0


## True when the material is one of the emissive head of a lamp.
static func _is_glow(material: Material) -> bool:
	if material == null:
		return false
	var name := material.resource_name.get_slice(".", 0)
	return GLOW_MATERIALS.has(name)


## True when the material is one of the hidden ones (the baked panel of a gantry).
static func _is_hidden(material: Material, hidden: Array) -> bool:
	return _matches(material, hidden)


## True when the material is one of the names (the duplicates of Blender are ignored).
static func _matches(material: Material, names: Array) -> bool:
	if material == null:
		return false
	var name := material.resource_name.get_slice(".", 0)
	return names.has(name)


## The glb file of a prop type, searched in the props directories.
func _find_glb(type: String, variant: int = 0) -> String:
	var names: Array[String] = [type]
	if GLB_FOR_KIND.has(type):
		names.push_front(String(GLB_FOR_KIND[type]))
	if type == "tree":
		names.push_front("plane_tree_%d" % (1 + variant % 3))
	for name in names:
		for dir in PROP_DIRS:
			var path := dir + name + ".glb"
			if ResourceLoader.exists(path):
				return path
	return ""


func _procedural(type: String) -> Dictionary:
	var parts: Array[Dictionary] = []
	var light: Dictionary = {}
	match type:
		"lamp":
			parts = _lamp_parts(LED, light)
		"lamp_heritage":
			parts = _lamp_parts(HERITAGE, light)
		"planter":
			parts = [
				ProcMeshes.part(ProcMeshes.box(Vector3(2.4, 0.9, 1.2)), ProcMeshes.material("concrete"), ProcMeshes.at(Vector3(0, 0.45, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(2.2, 0.55, 1.0)), ProcMeshes.material("foliage"), ProcMeshes.at(Vector3(0, 1.1, 0))),
			]
		"tree":
			parts = [
				ProcMeshes.part(ProcMeshes.cylinder(0.22, 3.6), ProcMeshes.material("bark"), ProcMeshes.at(Vector3(0, 1.8, 0))),
				ProcMeshes.part(ProcMeshes.sphere(1.7), ProcMeshes.material("foliage"), ProcMeshes.at(Vector3(0, 4.4, 0))),
				ProcMeshes.part(ProcMeshes.sphere(1.15), ProcMeshes.material("foliage"), ProcMeshes.at(Vector3(1.1, 3.7, 0.4))),
				ProcMeshes.part(ProcMeshes.sphere(1.0), ProcMeshes.material("foliage"), ProcMeshes.at(Vector3(-0.9, 3.9, -0.6))),
			]
		"bin":
			parts = [
				ProcMeshes.part(ProcMeshes.cylinder(0.36, 1.0), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(0, 0.5, 0))),
			]
		"bollard":
			parts = [
				ProcMeshes.part(ProcMeshes.cylinder(0.13, 0.95), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(0, 0.48, 0))),
			]
		"sign":
			parts = [
				ProcMeshes.part(ProcMeshes.cylinder(0.07, 3.0), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(0, 1.5, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(1.4, 0.9, 0.08)), ProcMeshes.material("sign_blue"), ProcMeshes.at(Vector3(0, 2.6, 0))),
			]
		"billboard":
			parts = [
				ProcMeshes.part(ProcMeshes.box(Vector3(0.5, 9.0, 0.5)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(-3.0, 4.5, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(0.5, 9.0, 0.5)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(3.0, 4.5, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(7.4, 4.2, 0.25)), ProcMeshes.material("panel"), ProcMeshes.at(Vector3(0, 8.6, 0))),
			]
		"gantry":
			parts = [
				ProcMeshes.part(ProcMeshes.box(Vector3(0.6, 7.0, 0.6)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(-5.4, 3.5, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(0.6, 7.0, 0.6)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(5.4, 3.5, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(10.2, 2.4, 0.35)), ProcMeshes.material("sign_green"), ProcMeshes.at(Vector3(0, 6.4, 0))),
			]
		"vms":
			parts = [
				ProcMeshes.part(ProcMeshes.box(Vector3(0.45, 6.0, 0.45)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(-2.4, 3.0, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(0.45, 6.0, 0.45)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(2.4, 3.0, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(5.2, 2.2, 0.22)), ProcMeshes.material("panel"), ProcMeshes.at(Vector3(0, 6.0, 0))),
			]
		"bus_stop":
			parts = [
				ProcMeshes.part(ProcMeshes.box(Vector3(8.0, 0.16, 1.8)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(0, 2.6, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(0.12, 2.6, 0.12)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(-3.6, 1.3, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(0.12, 2.6, 0.12)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(3.6, 1.3, 0))),
				ProcMeshes.part(ProcMeshes.box(Vector3(7.4, 2.0, 0.08)), ProcMeshes.glow(Color("0a1a2a"), 0.9), ProcMeshes.at(Vector3(0, 1.4, -0.8))),
			]
		"noise_wall":
			parts = [
				ProcMeshes.part(ProcMeshes.box(Vector3(30.0, 3.6, 0.35)), ProcMeshes.material("concrete"), ProcMeshes.at(Vector3(0, 1.8, 0))),
			]
		"canopy":
			parts = _canopy_parts()
		_:
			return {}
	for i in parts.size():
		parts[i]["key"] = "%s_%d" % [type, i]
	# The panel that carries the generated sign texture.
	if type == "gantry":
		parts[2]["sign"] = true
	elif type == "vms":
		parts[2]["sign"] = true
	return {"parts": parts, "light": light, "kind": StringName(type)}


func _lamp_parts(head_color: Color, light: Dictionary) -> Array[Dictionary]:
	var head := Vector3(5.2, 8.7, 0.0)
	light.merge({"color": head_color, "energy": 2.5, "range": 18.0,
		"offset": head, "kind": "omni"}, true)
	return [
		ProcMeshes.part(ProcMeshes.cylinder(0.13, 9.0), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(0, 4.5, 0))),
		ProcMeshes.part(ProcMeshes.box(Vector3(5.4, 0.16, 0.16)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(2.6, 8.95, 0))),
		ProcMeshes.part(ProcMeshes.box(Vector3(1.0, 0.24, 0.5)), ProcMeshes.glow(head_color, 6.0), ProcMeshes.at(head)),
	]


## Gas-station / toll canopy: slab, fascia band, columns, LED underside.
func _canopy_parts() -> Array[Dictionary]:
	var parts: Array[Dictionary] = [
		ProcMeshes.part(ProcMeshes.box(Vector3(20.0, 0.5, 30.0)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(0, 6.0, 0))),
		ProcMeshes.part(ProcMeshes.box(Vector3(20.4, 1.4, 30.4)), ProcMeshes.glow(Color("e60012"), 0.6), ProcMeshes.at(Vector3(0, 6.9, 0))),
	]
	for z in [-13.0, 0.0, 13.0]:
		parts.append(ProcMeshes.part(ProcMeshes.box(Vector3(0.7, 6.0, 0.7)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(-8.0, 3.0, z))))
		parts.append(ProcMeshes.part(ProcMeshes.box(Vector3(0.7, 6.0, 0.7)), ProcMeshes.material("metal"), ProcMeshes.at(Vector3(8.0, 3.0, z))))
	return parts
