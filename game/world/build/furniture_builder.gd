extends RefCounted
## Places the road furniture: static repeated props (planters, lamps, trees, bins, bollards) as
## MultiMesh chunks of 512 m, and interactive props (guide gantries, VMS) as real scenes.
##
## The props that stand on the carriageway are pushed onto the sidewalk by the filter
## (build/furniture_filter.gd) and moved along the road when another prop stands in the way
## (build/prop_occupancy.gd). Every prop gets a collision shape (build/prop_collision.gd).

const PropLibrary := preload("res://world/loader/prop_library.gd")
const SignProps := preload("res://world/build/sign_props.gd")
const PropCollision := preload("res://world/build/prop_collision.gd")
const PropOccupancy := preload("res://world/build/prop_occupancy.gd")
const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const Heading := preload("res://world/api/heading.gd")

const TILE := 512.0
## The props whose long axis (X of the model: 8 m of shelter, 30 m of wall) runs along the road. The roads unit gives the
## heading of the road, and a heading makes the -Z of a model point along the road, so the shelters and the walls stood across it
## (176 of 541 shelters and 20 of 32 walls at a right angle to their road, the rest at every angle in between).
const ALONG_ROAD: Array[String] = ["bus_stop", "noise_wall"]
## The least distance between the footprint of a box prop and the centre line of a lane (m): half a car (0.95) and a margin.
const FOOTPRINT_CLEARANCE := 1.3
## How far a box that reaches into a lane is moved away from the road to clear it (m).
const FOOTPRINT_NUDGES: Array[float] = [0.4, 0.8, 1.2, 1.6, 2.0, 2.5, 3.0]
## The kinds of the roads unit's road_furniture.json mapped onto the prop types.
const KIND_ALIASES: Dictionary = {
	"street_lamp": "lamp",
	"deck_lamp": "lamp",
	"barrier_lamp": "lamp",
	"magnolia_lamp": "lamp_magnolia",
	"plane_tree": "tree",
	"road_name_sign": "sign",
	"guide_gantry": "gantry",
	"vms_board": "vms",
	"bus_stop": "bus_stop",
	"noise_wall": "noise_wall",
	"tunnel_light": "lamp",
}
## The prop types that carry a real light.
const LIGHT_TYPES: Array[String] = ["lamp", "lamp_heritage", "lamp_magnolia", "lamp_deck_double"]
## The prop types that are built as individual nodes (they carry their own textures).
const INDIVIDUAL_TYPES: Array[String] = ["gantry", "vms"]
## The distance at which each kind of furniture disappears (the light pools take over).
const VISIBILITY_END: Dictionary = {
	"lamp": 600.0, "lamp_heritage": 600.0, "lamp_magnolia": 600.0,
	"lamp_deck_double": 600.0, "tree": 350.0, "bus_stop": 250.0,
	"sign": 200.0, "bin": 120.0, "bollard": 120.0, "planter": 200.0,
	"noise_wall": 400.0, "billboard": 400.0, "gantry": 800.0, "vms": 800.0,
	"shop_sign": 150.0, "neon_blade_frame": 200.0, "metro_entrance": 200.0,
	"bike_share": 120.0, "e_scooter": 120.0, "hydrant": 120.0,
}
const DEFAULT_VISIBILITY_END := 400.0
## The head of a lamp is visible from far away: the street grid of the city reads as a net of
## light dots from the air (ART.md §11).
const GLOW_VISIBILITY_END := 1800.0
## The far dot of a lamp takes over when the head of the lamp is too small to be seen.
const DOT_VISIBILITY_BEGIN := 600.0
const DOT_VISIBILITY_END := 2500.0
## The size of the far dot of a lamp.
const DOT_SIZE := 3.0

var _props: PropLibrary
var _signs: SignProps
var _light_pool: Node
var _filter: Object
## The style of every road of the city: the lamps of a road follow its style (magnolia,
## heritage, median double) and its sign panels follow its kind (green above, blue on the
## ground).
var _road_styles: Dictionary = {}
## The atlas of the shop name boards (the name of a board is a cell of the atlas).
var _atlas: Node = null
## The occupancy grid of the props (two props may not stand inside each other).
var _occupancy: PropOccupancy
## The groups of the world: "type|part|tile" -> {"mesh", "material", "transforms", "custom"}.
var _groups: Dictionary = {}
## The positions of the props that were placed (the multi mesh cannot be read back in a
## headless run, the renderer owns its buffer).
var placed: Array[Vector3] = []
## The number of props placed per prop type.
var counts: Dictionary = {}
## The kind of every prop that was placed (the same order as `placed`).
var placed_kinds: Array[String] = []
## The entries of the props that were placed (the cache writes them).
var placed_entries: Array[Dictionary] = []
## The entries of the props that were placed (the collision is built from them).
var _collision: Array[Dictionary] = []
## The props that break away (PropCollision.BREAKAWAY, the lamps, and PropCollision.SOFT, the small furniture): {"type", "variant",
## "transform", "scale_vector", "height", "refs" (the [group key, instance] of every part and far dot), "lights" (the indices of
## the light pool)}. world/build/prop_breaker.gd.
var breakables: Array[Dictionary] = []
## The MultiMesh of every group key (a broken lamp hides its instances).
var multimeshes: Dictionary = {}


func setup(light_pool: Node, filter: Object = null, atlas: Node = null) -> void:
	_props = PropLibrary.new()
	_signs = SignProps.new()
	_signs.setup(filter)
	_light_pool = light_pool
	_filter = filter
	_atlas = atlas
	_occupancy = PropOccupancy.new()


## The style of the roads of the city: {road id: {"kind", "lamps"}}.
func set_road_styles(styles: Dictionary) -> void:
	_road_styles = styles
	_signs.set_road_styles(styles)


## Builds the furniture: repeated props as MultiMesh chunks, the gantries and VMS as real
## nodes. Returns the individual sign props that still need their generated texture.
func build(parent: Node3D, entries: Array[Dictionary]) -> Array[Dictionary]:
	var clock := Time.get_ticks_msec()
	_groups.clear()
	counts.clear()
	placed.clear()
	placed_kinds.clear()
	placed_entries.clear()
	_collision.clear()
	breakables.clear()
	multimeshes.clear()
	var signs: Array[Dictionary] = []
	var variant := 0
	var gantries: Dictionary = {}
	# The big props are placed first: they get the good places on the kerb.
	var ordered := _by_size(entries)
	for entry in ordered:
		if String(entry["type"]) == "tree" and not entry.has("variant"):
			entry["variant"] = variant % 3
			variant += 1
		var type := String(entry["type"])
		if type == "gantry":
			gantries = _signs.collect(gantries, entry)
			continue
		if type == "vms":
			signs.append(_signs.build_vms(parent, entry))
			continue
		var spot: Variant = _spot(entry)
		if spot == null:
			continue
		entry["transform"] = spot
		placed.append((spot as Transform3D).origin)
		placed_kinds.append(type)
		placed_entries.append(_cache_entry(entry))
		_count(type)
		var refs := _add_entry(entry)
		var lights := _register_light(entry)
		if PropCollision.BREAKAWAY.has(type) or PropCollision.SOFT.has(type):
			var def := _props.get_prop(type, int(entry.get("variant", 0)))
			var scale_vector: Vector3 = entry.get("scale_vector", Vector3.ONE * float(entry.get("scale", 1.0))) \
					* float(def.get("scale", 1.0))
			breakables.append({"type": type, "variant": int(entry.get("variant", 0)), "transform": spot,
				"scale_vector": scale_vector, "refs": refs, "lights": lights,
				"height": PropCollision.break_height(type, float(entry.get("height_m", 0.0)))})
		_collision.append({"type": type, "transform": spot,
			"height_m": float(entry.get("height_m", 0.0)),
			"scale_vector": entry.get("scale_vector", Vector3.ONE)})
	for key in gantries.keys():
		signs.append(_signs.build_gantry(parent, gantries[key]))
	print("[world] furniture: the props are sorted in %.2f s" % (float(Time.get_ticks_msec() - clock) / 1000.0))
	clock = Time.get_ticks_msec()
	_flush(parent)
	print("[world] furniture: the batches are built in %.2f s" % (float(Time.get_ticks_msec() - clock) / 1000.0))
	clock = Time.get_ticks_msec()
	_build_collision(parent)
	print("[world] furniture: %d collision shapes in %.2f s" % [
		_collision_count, float(Time.get_ticks_msec() - clock) / 1000.0])
	return signs


## The number of collision shapes that were built.
var _collision_count := 0


## The prop library of the furniture (the broken lamps fall as debris with its meshes).
func library() -> PropLibrary:
	return _props


## The entry of a prop that is written to the cache: everything the next build needs to put
## the prop back in the same place.
func _cache_entry(entry: Dictionary) -> Dictionary:
	return {
		"type": String(entry["type"]),
		"transform": entry["transform"],
		"scale": float(entry.get("scale", 1.0)),
		"scale_vector": entry.get("scale_vector", Vector3.ONE),
		"light": bool(entry.get("light", false)),
		"color": entry.get("color", Color.WHITE),
		"text": String(entry.get("text", "")),
		"text_en": String(entry.get("text_en", "")),
		"road": String(entry.get("road", "")),
		"height_m": float(entry.get("height_m", 0.0)),
		"variant": int(entry.get("variant", 0)),
		"arms": int(entry.get("arms", 1)),
		"placed": true,
	}


## The collision of the furniture: one body per 512 m tile.
func _build_collision(parent: Node3D) -> void:
	var builder := PropCollision.new()
	_collision_count = builder.build(parent, _collision)


## The entries in the order of the placement: the big props first. The entries are put in
## buckets instead of being sorted: the city has 48,000 of them, and a sort with a callback
## costs four seconds.
func _by_size(entries: Array[Dictionary]) -> Array[Dictionary]:
	var buckets: Array[Array] = []
	for entry in entries:
		var rank := _occupancy.rank(String(entry.get("type", "")))
		while buckets.size() <= rank:
			buckets.append([])
		(buckets[rank] as Array).append(entry)
	var out: Array[Dictionary] = []
	for bucket in buckets:
		for entry in bucket as Array:
			out.append(entry)
	return out


## The place where a prop stands: the filter moves it out of the carriageway, the occupancy
## grid moves it along the road when another prop stands in the way.
func _spot(entry: Dictionary) -> Variant:
	if bool(entry.get("placed", false)):
		return entry["transform"]  # the place comes from the cache
	var xform: Transform3D = entry["transform"]
	var type := String(entry["type"])
	var dressed := bool(entry.get("dressed", false))
	var out: Transform3D = xform
	if _filter != null:
		var moved: Variant = _filter.place(xform.origin, float(entry.get("height_m", 0.0)),
			type, str(entry.get("mount", "")), str(entry.get("road", "")), dressed)
		if moved == null:
			return null
		out.origin = moved
	# The props whose origin is not on the ground (the panel of a shop board is at its centre).
	var def := _props.get_prop(type, int(entry.get("variant", 0)))
	out.origin.y += float(def.get("lift", 0.0))
	var before: Vector3 = out.origin
	var free: Variant = _occupancy.place(out.origin, type,
		_tangent_at(out.origin, str(entry.get("road", ""))))
	if free == null:
		return null
	var after: Vector3 = free
	if after != before and _filter != null and _filter.on_carriageway(after):
		# The slide along the road pushed the prop into a carriageway: it keeps the place the
		# filter gave it, when that place is free.
		if not _occupancy.is_free(before, type):
			return null
		after = before
	out.origin = after
	if _filter != null and not _filter.clear_of_lanes(out.origin):
		# The prop would stand on a carriageway: it is dropped instead of driving there.
		return null
	if _filter != null and not dressed and _filter.in_junction_box(out.origin):
		# The filter judged the place it gave, and the slide along the road moved the prop out of it: into the box of a junction.
		return null
	if _filter != null and ALONG_ROAD.has(type):
		out.basis = _along_road(out.basis, out.origin, type == "bus_stop", str(entry.get("road", "")))
	var box: Variant = PropCollision.SHAPES.get(type, {}).get("size", null)
	if _filter != null and box != null:
		var size: Vector3 = (box as Vector3) * (entry.get("scale_vector", Vector3.ONE) as Vector3)
		if not _filter.footprint_clear(out, size, FOOTPRINT_CLEARANCE):
			# A box that reaches into a lane is solid for the traffic that drives there: it moves away from the road until
			# it is clear, or it is dropped.
			var away: Vector3 = -(_filter.road_side(out.origin, str(entry.get("road", ""))) as Vector3)
			var moved := false
			if away != Vector3.ZERO:
				for step in FOOTPRINT_NUDGES:
					var candidate := Transform3D(out.basis, out.origin + away * step)
					var clear: bool = _filter.footprint_clear(candidate, size, FOOTPRINT_CLEARANCE) \
							and _filter.clear_of_lanes(candidate.origin) \
							and (dressed or not _filter.in_junction_box(candidate.origin))
					if clear and _occupancy.is_free(candidate.origin, type):
						out = candidate
						moved = true
						break
			if not moved:
				return null
	_occupancy.reserve(out.origin, type, out.basis.get_euler().y)
	return out


## The basis of a prop whose X axis runs along the road. The direction is the one of the lanes next to the prop, not the heading of
## the data: the heading of the roads unit is 180 degrees minus the real one (a mirror in furniture.py: atan2 of the east and of
## MINUS the north), right on the roads that run east-west and wrong on every diagonal one. A shelter opens (+Z) towards the road.
func _along_road(basis: Basis, origin: Vector3, opens_to_road: bool, road: String) -> Basis:
	var toward: Vector3 = _filter.road_side(origin, road)
	if toward == Vector3.ZERO:
		return basis  # no lane near: the prop stays as the data has it
	var along: Vector3 = _filter.tangent_at(origin, road)
	if opens_to_road and Vector3(-along.z, 0.0, along.x).dot(toward) < 0.0:
		along = -along
	return Basis(along, Vector3.UP, Vector3(-along.z, 0.0, along.x))


## The direction of the road at a point (the props slide along it).
func _tangent_at(position: Vector3, type: String) -> Vector3:
	if _filter == null:
		return Vector3.FORWARD
	return _filter.tangent_at(position)


func _count(type: String) -> void:
	counts[type] = int(counts.get(type, 0)) + 1


# --- the lights ---------------------------------------------------------------------------------------

## Registers a real (pooled) light for every lamp prop. Returns the indices of the sources (a broken lamp switches them off).
func _register_light(entry: Dictionary) -> Array[int]:
	var indices: Array[int] = []
	if not bool(entry.get("light", false)) or _light_pool == null:
		return indices
	var type := String(entry["type"])
	var def := _props.get_prop(type, int(entry.get("variant", 0)))
	var spec: Dictionary = def.get("light", {})
	if spec.is_empty():
		return indices
	var xform: Transform3D = entry["transform"]
	var offsets: Array = spec.get("offsets", [spec.get("offset", Vector3.ZERO)])
	var scale_vector: Vector3 = entry.get("scale_vector", Vector3.ONE)
	var color: Color = entry.get("color", spec.get("color", Color.WHITE))
	if color == Color.WHITE and spec.has("color"):
		color = spec["color"]
	var energy := float(entry.get("energy", spec.get("energy", 2.0)))
	var light_range := float(entry.get("range", spec.get("range", 18.0)))
	var ground := xform.origin
	for offset in offsets:
		var local: Vector3 = offset * scale_vector
		var index: Variant = _light_pool.add_source(xform * local, color, energy, light_range, "omni", 0.0, 0.0,
			Vector3.ZERO, ground)
		if index is int:
			indices.append(index)
	return indices


# --- MultiMesh assembly ------------------------------------------------------------------------------

## Adds the parts of a prop to the groups of its tile. Returns the [group key, instance] of every part and far dot.
func _add_entry(entry: Dictionary) -> Array:
	var refs: Array = []
	var type := String(entry["type"])
	var def := _props.get_prop(type, int(entry.get("variant", 0)))
	var parts: Array = def.get("parts", [])
	if parts.is_empty():
		return refs
	var xform: Transform3D = entry["transform"]
	var scale := float(entry.get("scale", 1.0))
	var def_scale := float(def.get("scale", 1.0))
	for part in parts:
		var key := "%s|%s|%d_%d" % [type, String(part["key"]),
			int(floor(xform.origin.x / TILE)), int(floor(xform.origin.z / TILE))]
		if not _groups.has(key):
			_groups[key] = {"mesh": part["mesh"], "material": _material_of(part),
				"transforms": [], "custom": [], "type": type,
				"glow": bool(part.get("glow", false)), "atlas": bool(part.get("atlas", false))}
		var group: Dictionary = _groups[key]
		var list: Array = group["transforms"]
		var custom: Array = group["custom"]
		var part_xform: Transform3D = part["transform"]
		var scale_vector: Vector3 = entry.get("scale_vector", Vector3.ONE * scale) * def_scale
		var scaled := Transform3D(part_xform.basis.scaled(scale_vector), part_xform.origin * scale_vector)
		refs.append([key, list.size()])
		list.append(xform * scaled)
		custom.append(_custom_data(part, group, entry))
		if bool(part.get("glow", false)):
			refs.append_array(_add_dot(group, xform, part, scale_vector, entry))
	return refs


## The material of a part: the board of a shop name carries the atlas of the names.
func _material_of(part: Dictionary) -> Variant:
	if bool(part.get("atlas", false)) and _atlas != null:
		return _atlas.material()
	return part.get("material")


## The custom data of an instance (the cell of the atlas of a shop name board). The custom
## data of a MultiMesh is a colour: the four components carry the uv offset and the uv scale.
func _custom_data(part: Dictionary, group: Dictionary, entry: Dictionary) -> Vector4:
	if not bool(group.get("atlas", false)) or _atlas == null:
		return Vector4.ZERO
	return _atlas.cell(str(entry.get("text", "")))


## The custom data as the colour of a MultiMesh instance.
static func _as_color(value: Vector4) -> Color:
	return Color(value.x, value.y, value.z, value.w)


## The far dot of a lamp: a 2 m cross of quads at the head, so the dot never shrinks below a
## pixel when the city is seen from the air.
func _add_dot(group: Dictionary, xform: Transform3D, part: Dictionary, scale_vector: Vector3,
		entry: Dictionary) -> Array:
	var refs: Array = []
	var def := _props.get_prop(String(entry["type"]), int(entry.get("variant", 0)))
	var spec: Dictionary = def.get("light", {})
	if spec.is_empty():
		return refs
	var offsets: Array = spec.get("offsets", [spec.get("offset", Vector3.ZERO)])
	for i in offsets.size():
		var offset: Vector3 = offsets[i] * scale_vector
		var key := "%s|dot%d|%d_%d" % [String(entry["type"]), i,
			int(floor(xform.origin.x / TILE)), int(floor(xform.origin.z / TILE))]
		if not _groups.has(key):
			_groups[key] = {"mesh": ProcMeshes.cross_quad(DOT_SIZE),
				"material": ProcMeshes.dot_material(spec.get("color", Color.WHITE)),
				"transforms": [], "custom": [], "type": String(entry["type"]),
				"glow": false, "atlas": false, "dot": true}
		var dot: Dictionary = _groups[key]
		refs.append([key, (dot["transforms"] as Array).size()])
		(dot["transforms"] as Array).append(xform * Transform3D(Basis.IDENTITY, offset))
		(dot["custom"] as Array).append(Vector4.ZERO)
	return refs


func _flush(parent: Node3D) -> void:
	for key in _groups.keys():
		var group: Dictionary = _groups[key]
		var list: Array = group["transforms"]
		if list.is_empty():
			continue
		var mesh := group["mesh"] as Mesh
		if mesh == null:
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		multimesh.instance_count = list.size()
		var mmi := MultiMeshInstance3D.new()
		# its instances are set outside the physics step (or never move): no physics interpolation
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mmi.name = "Furniture_" + String(key).replace("|", "_")
		mmi.multimesh = multimesh
		multimeshes[key] = multimesh
		var material: Variant = group.get("material")
		if material != null:
			mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if bool(group.get("dot", false)):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_begin = DOT_VISIBILITY_BEGIN
			mmi.visibility_range_end = DOT_VISIBILITY_END
		elif bool(group.get("glow", false)):
			mmi.visibility_range_end = GLOW_VISIBILITY_END
		else:
			mmi.visibility_range_end = _visibility_end(String(group.get("type", "")))
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)
		# The transforms can only be written once the batch is in the tree (the buffer of the
		# multi mesh is allocated then).
		var custom: Array = group.get("custom", [])
		for i in list.size():
			multimesh.set_instance_transform(i, list[i])
			if i < custom.size():
				multimesh.set_instance_custom_data(i, _as_color(custom[i]))
	_groups.clear()


## The distance at which a kind of furniture disappears.
func _visibility_end(type: String) -> float:
	return float(VISIBILITY_END.get(type, DEFAULT_VISIBILITY_END))
