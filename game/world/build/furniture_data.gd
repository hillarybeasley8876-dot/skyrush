extends RefCounted
## Normalises the entries of the roads unit's road_furniture.json into the internal format of
## the furniture builder, and derives the furniture from the city description when that file is
## missing.
##
## The lamp of a road follows the style of the road: a magnolia lamp on a magnolia street, a
## heritage lamp on the Bund and a double lamp in the median of a viaduct.

const PropLibrary := preload("res://world/loader/prop_library.gd")
const RoadFurniture := preload("res://world/build/road_furniture.gd")
const Heading := preload("res://world/api/heading.gd")

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
## The lamp types.
const LAMP_TYPES: Array[String] = ["lamp", "lamp_heritage", "lamp_magnolia", "lamp_deck_double"]

var _props: PropLibrary
## The style of every road of the city: {road id: {"kind", "lamps", "trees"}}.
var _road_styles: Dictionary = {}


func _init() -> void:
	_props = PropLibrary.new()


## The style of the roads of the city.
func set_road_styles(styles: Dictionary) -> void:
	_road_styles = styles


## The entries of the road_furniture.json in the internal format.
func normalise(raw: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in raw:
		var kind := String(entry.get("type", entry.get("kind", "")))
		if kind == "":
			continue
		var type := str(KIND_ALIASES.get(kind, kind))
		if type in LAMP_TYPES:
			type = _lamp_type(type, entry)
		var xform := _transform(entry)
		if xform == Transform3D.IDENTITY and not entry.has("transform") and not entry.has("x"):
			continue
		out.append({
			"type": type,
			"kind": kind,
			"transform": xform,
			"scale": float(entry.get("scale", 1.0)),
			"scale_vector": _scale_vector(entry, type),
			"light": bool(entry.get("light", type in LIGHT_TYPES)),
			"color": _color(entry.get("color", "")),
			"text": String(entry.get("text", entry.get("name", ""))),
			"text_en": str(entry.get("text_en", entry.get("name_en", ""))),
			"junction": str(entry.get("junction", "")),
			"road": str(entry.get("road", "")),
			"height_m": float(entry.get("height_m", 0.0)),
			"arms": int(entry.get("arms", 1)),
			"mount": str(entry.get("mount", "")),
			"clearance_m": float(entry.get("clearance_m", 0.0)),
			"width_m": float(entry.get("width_m", 0.0)),
			"span_m": float(entry.get("span_m", 0.0)),
		})
	return out


## The lamp of a road: the style of the road decides, and a lamp in the median of a road with
## two arms is the double lamp of the viaduct.
func _lamp_type(type: String, entry: Dictionary) -> String:
	if str(entry.get("mount", "")) == "median" and int(entry.get("arms", 1)) > 1:
		return "lamp_deck_double"
	var road := str(entry.get("road", ""))
	var style: Dictionary = _road_styles.get(road, {})
	match str(style.get("lamps", "")):
		"magnolia":
			return "lamp_magnolia"
		"heritage":
			return "lamp_heritage"
		"median_double":
			return "lamp_deck_double"
	return type


## Non-uniform scale for the props whose size the roads unit states explicitly.
func _scale_vector(entry: Dictionary, type: String) -> Vector3:
	var scale := float(entry.get("scale", 1.0))
	match type:
		"lamp", "lamp_heritage", "lamp_magnolia", "lamp_deck_double":
			var height := float(entry.get("height_m", 9.0))
			return Vector3(1.0, height / _lamp_height(type), 1.0) * scale
		"noise_wall":
			var length := float(entry.get("length_m", 30.0))
			return Vector3(length / 30.0, 1.0, 1.0) * scale
		"bus_stop":
			var bus_length := float(entry.get("length_m", 8.0))
			return Vector3(bus_length / 8.0, 1.0, 1.0) * scale
		_:
			return Vector3.ONE * scale


## The height of the lamp of the props unit (the scale of the lamp follows it).
func _lamp_height(type: String) -> float:
	var height := float(_props.get_prop(type, 0).get("height", 9.0))
	return maxf(height, 0.1)


static func _transform(entry: Dictionary) -> Transform3D:
	var raw: Variant = entry.get("transform", entry.get("position", null))
	var position := Vector3.ZERO
	var yaw := 0.0
	if raw is Array and (raw as Array).size() >= 3:
		var arr := raw as Array
		position = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		if arr.size() >= 4:
			yaw = Heading.yaw_from_heading(float(arr[3]))
	elif raw is Dictionary:
		var d := raw as Dictionary
		position = Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
		yaw = Heading.yaw_from_heading(float(d.get("heading_deg", d.get("yaw_deg", 0.0))))
	elif entry.has("x"):
		position = Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0)))
		yaw = Heading.yaw_from_heading(float(entry.get("heading_deg", 0.0)))
	return Transform3D(Basis(Vector3.UP, yaw), position)


static func _color(raw: Variant) -> Color:
	if raw is String and (raw as String).begins_with("#"):
		return Color(raw)
	return Color.WHITE


## Derives furniture from the city.json road styles when the roads unit has no furniture file.
func derive_from_roads(roads: Array) -> Array[Dictionary]:
	return RoadFurniture.new().derive_from_roads(roads)
