extends RefCounted
## The billboards and the scaffolds along the roads are pursuit breakers: hitting a Support_ node
## at 60 km/h or more drops the structure and wrecks the police behind it.
##
## A breaker stands at the building line of its road (half the width of the road plus its
## sidewalk plus a metre) and faces the road, so a car that leaves the road hits it.

const Spline := preload("res://world/api/spline_util.gd")
const BreakerScript := preload("res://world/build/pursuit_breaker.gd")

const BILLBOARD_GLB := "res://assets/props/street/billboard_pole.glb"
const SCAFFOLD_GLB := "res://assets/props/street/scaffold.glb"
## The distance between two billboards on a road.
const BREAKER_SPACING := 700.0
## The distance between two scaffolds on a road.
const SCAFFOLD_SPACING := 900.0
## The distance between the kerb of the road and the breaker.
const KERB_GAP := 1.0
const MAX_BILLBOARDS := 24
const MAX_SCAFFOLDS := 10
## The space a site needs around it.
const SITE_CLEARANCE := 6.0


## Places the breakers along the roads and returns them.
func build(parent: Node3D, roads: Array, sites: Array = []) -> Array[Node]:
	var out: Array[Node] = []
	var billboards := 0
	var scaffolds := 0
	for road in roads:
		if not road is Dictionary:
			continue
		var d := road as Dictionary
		var line: PackedVector3Array = _line(d)
		if line.size() < 2:
			continue
		var length: float = Spline.total_length(line)
		var count := int(length / BREAKER_SPACING)
		for i in count:
			if billboards >= MAX_BILLBOARDS:
				break
			var distance := (float(i) + 0.5) * BREAKER_SPACING
			var spot := _spot(d, line, distance, 1.0)
			if not bool(spot["ok"]):
				continue
			if _in_site(spot["transform"].origin, sites):
				continue
			var breaker: Node = _add_breaker(parent, BILLBOARD_GLB, spot["transform"], "广告牌倒塌!")
			if breaker != null:
				out.append(breaker)
			billboards += 1
		if scaffolds < MAX_SCAFFOLDS and int(length / SCAFFOLD_SPACING) > 0:
			var distance2 := length * 0.5
			var spot2 := _spot(d, line, distance2, -1.0)
			if bool(spot2["ok"]) and not _in_site(spot2["transform"].origin, sites):
				var breaker2: Node = _add_breaker(parent, SCAFFOLD_GLB, spot2["transform"],
					"脚手架倒塌!")
				if breaker2 != null:
					out.append(breaker2)
				scaffolds += 1
	return out


## The place of a breaker: at the building line of the road, facing the road.
## {"ok": bool, "transform": Transform3D}.
func _spot(road: Dictionary, line: PackedVector3Array, distance: float,
		side: float) -> Dictionary:
	var point := Spline.point_at(line, distance)
	var tangent := Spline.tangent_at(line, distance)
	var normal := Vector3(-tangent.z, 0.0, tangent.x)
	var offset := (_half_width(road) + _sidewalk(road) + KERB_GAP) * side
	var position := point + normal * offset
	var forward := -normal * signf(side)
	return {"ok": true, "transform": Transform3D(Basis.looking_at(forward, Vector3.UP), position)}


## The half width of the pavement of a road.
func _half_width(road: Dictionary) -> float:
	var lanes := int(road.get("lanes_fwd", 2))
	var width := float(road.get("lane_width", 3.75))
	var median := float(road.get("median", 1.0))
	return median * 0.5 + float(lanes) * width


func _sidewalk(road: Dictionary) -> float:
	return float(road.get("sidewalk", 0.0))


## True when the point is inside a site (a gas station, a charge bay, a police station).
func _in_site(position: Vector3, sites: Array) -> bool:
	for site in sites:
		if not site is Dictionary:
			continue
		var d := site as Dictionary
		var size: Array = d.get("size", [0.0, 0.0])
		var half := Vector2(float(size[0]) if size.size() > 0 else 0.0,
			float(size[1]) if size.size() > 1 else 0.0) * 0.5 + Vector2(SITE_CLEARANCE, SITE_CLEARANCE)
		if absf(position.x - float(d.get("x", 0.0))) <= half.x \
				and absf(position.z - float(d.get("z", 0.0))) <= half.y:
			return true
	return false


## One breaker: the glb of the props unit and the pursuit breaker that drops it.
func _add_breaker(parent: Node3D, path: String, xform: Transform3D, label: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null
	MaterialLibrary.apply(model)
	var root := Node3D.new()
	root.name = "Breaker_" + path.get_file().get_basename()
	root.transform = xform
	parent.add_child(root)
	root.add_child(model)
	var breaker := BreakerScript.new()
	breaker.name = "PursuitBreaker"
	breaker.label = label
	root.add_child(breaker)
	breaker.setup(model)
	return breaker


## The centre line of a road of the city description.
static func _line(road: Dictionary) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var raw: Variant = road.get("points", [])
	if not raw is Array:
		return pts
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			pts.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	return Spline.resample(Spline.sample_centerline(pts, str(road.get("spline", "catmull"))), 4.0)
