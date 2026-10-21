extends RefCounted
## The street furniture derived from the city.json road styles: the lamps of the road, the
## planters of the elevated decks, the plane trees of the avenues and the bins. Used when the
## roads unit has no road_furniture.json.

const Spline := preload("res://world/api/spline_util.gd")
const Heading := preload("res://world/api/heading.gd")

## The colours of the lamps.
const LED := Color("d9e8ff")
const SODIUM := Color("ffb46b")
const HERITAGE := Color("ffa757")
## The spacing of the lamps per road type (metres).
const DECK_SPACING := 30.0
const STREET_SPACING := 35.0
const MAGNOLIA_SPACING := 12.0
const HERITAGE_SPACING := 25.0
## The spacing of the planters, the trees and the bins.
const PLANTER_SPACING := 12.0
const TREE_SPACING := 20.0
const BIN_SPACING := 60.0
## The energy and the range of the lamps.
const DECK_ENERGY := 2.5
const STREET_ENERGY := 2.0
const MAGNOLIA_ENERGY := 0.8
const HERITAGE_ENERGY := 2.0
const LAMP_RANGE := 18.0
const MAGNOLIA_RANGE := 7.0
const HERITAGE_RANGE := 15.0


## Derives furniture from the city.json road styles when the roads unit has no furniture file.
func derive_from_roads(roads: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for road in roads:
		if not road is Dictionary:
			continue
		out.append_array(_road_props(road as Dictionary))
	return out


func _road_props(road: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var style: Dictionary = road.get("style", {})
	var line := Spline.road_line(road)
	if line.size() < 2:
		return out
	var kind := str(road.get("kind", "surface"))
	var elevated := kind == "elevated" or kind == "bridge"
	var w := float(road.get("lane_width", 3.75))
	var median := float(road.get("median", 1.0))
	var fwd := int(road.get("lanes_fwd", 2))
	var shoulder := float(road.get("shoulder", 0.5))
	var lamps := str(style.get("lamps", "none"))
	var parapet := str(style.get("parapet", "none"))
	var trees := str(style.get("trees", "none"))
	var edge := median * 0.5 + float(fwd) * w + shoulder
	var total := Spline.total_length(line)
	if lamps != "none":
		out.append_array(_lamps(line, edge, median, lamps, elevated, style))
	if parapet == "planter" and elevated:
		out.append_array(_planters(line, edge, total))
	if trees == "plane" and not elevated:
		out.append_array(_trees(line, edge, total))
	out.append_array(_bins(line, edge, total))
	return out


func _lamps(line: PackedVector3Array, edge: float, median: float, style: String, elevated: bool,
		road_style: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spacing := 30.0 if elevated else 35.0
	var prop_type := "lamp"
	var color := LED
	var energy := 2.5
	var light_range := 18.0
	match style:
		"magnolia":
			spacing = 12.0
			prop_type = "lamp_heritage"
			color = HERITAGE
			energy = 0.8
			light_range = 7.0
		"heritage":
			spacing = 25.0
			prop_type = "lamp_heritage"
			color = HERITAGE
			energy = 2.0
			light_range = 15.0
		"median_double":
			spacing = 30.0
		"side", "barrier":
			spacing = 35.0 if not elevated else 30.0
			color = SODIUM if bool(road_style.get("sodium", false)) else LED
			energy = 2.0
	var tans := Spline.tangents(line)
	var length := Spline.total_length(line)
	var count := maxi(int(length / spacing), 1)
	for i in count:
		var d := (float(i) + 0.5) * spacing
		var point := Spline.point_at(line, d)
		var index := Spline.index_at(line, d)
		var tangent := tans[index]
		var normal := Vector3(-tangent.z, 0.0, tangent.x)
		if style == "median_double":
			for sign_side in [1.0, -1.0]:
				out.append(_lamp_entry(point, normal * (median * 0.5 * sign_side), 0.0,
					prop_type, color, energy, light_range))
		else:
			for sign_side in [1.0, -1.0]:
				out.append(_lamp_entry(point, normal * (edge * sign_side),
					atan2(tangent.x, tangent.z) + (0.0 if sign_side > 0.0 else PI),
					prop_type, color, energy, light_range))
	return out


func _lamp_entry(point: Vector3, offset: Vector3, yaw: float, prop_type: String,
		color: Color, energy: float, light_range: float) -> Dictionary:
	var position := point + offset
	return {
		"type": prop_type,
		"transform": Transform3D(Basis(Vector3.UP, yaw), position),
		"scale": 1.0,
		"light": true,
		"color": color,
		"energy": energy,
		"range": light_range,
	}


func _planters(line: PackedVector3Array, edge: float, length: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spacing := 12.0
	var count := maxi(int(length / spacing), 1)
	var tans := Spline.tangents(line)
	for i in count:
		var d := float(i) * spacing
		var point := Spline.point_at(line, d)
		var tangent := tans[Spline.index_at(line, d)]
		var normal := Vector3(-tangent.z, 0.0, tangent.x)
		for sign_side in [1.0, -1.0]:
			out.append({
				"type": "planter",
				"transform": Transform3D(Basis(Vector3.UP, atan2(tangent.x, tangent.z)),
					point + normal * (edge * sign_side)),
				"scale": 1.0, "light": false, "color": Color.WHITE,
			})
	return out


func _trees(line: PackedVector3Array, edge: float, length: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spacing := 20.0
	var count := maxi(int(length / spacing), 1)
	var tans := Spline.tangents(line)
	for i in count:
		var d := float(i) * spacing
		var point := Spline.point_at(line, d)
		var tangent := tans[Spline.index_at(line, d)]
		var normal := Vector3(-tangent.z, 0.0, tangent.x)
		out.append({
			"type": "tree",
			"transform": Transform3D(Basis(Vector3.UP, atan2(tangent.x, tangent.z)),
				point + normal * (edge + 2.0)),
			"scale": 1.0, "light": false, "color": Color.WHITE,
		})
	return out


func _bins(line: PackedVector3Array, edge: float, length: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spacing := 60.0
	var count := maxi(int(length / spacing), 1)
	var tans := Spline.tangents(line)
	for i in count:
		var d := float(i) * spacing + 30.0
		if d > length:
			break
		var point := Spline.point_at(line, d)
		var tangent := tans[Spline.index_at(line, d)]
		var normal := Vector3(-tangent.z, 0.0, tangent.x)
		out.append({
			"type": "bin",
			"transform": Transform3D(Basis(Vector3.UP, atan2(tangent.x, tangent.z)),
				point + normal * (edge + 1.2)),
			"scale": 1.0, "light": false, "color": Color.WHITE,
		})
	return out

