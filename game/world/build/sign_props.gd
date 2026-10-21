extends RefCounted
## The props that carry a sign: the guide gantries (a truss with a panel per direction), the VMS
## boards (a screen that cycles through the messages) and the shop name boards.
##
## They are built as individual nodes (not as a MultiMesh), because every panel has its own
## texture.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const PropLibrary := preload("res://world/loader/prop_library.gd")

## The height of the sign panel of a gantry; the width follows the 8:1 aspect of the texture.
const PANEL_HEIGHT := 1.7
const PANEL_ASPECT := 8.0
const PANEL_THICKNESS := 0.15
## The distance between the front face of the panel and the box behind it.
const PANEL_OFFSET := 0.03
## How far a gantry may slide along the road to get its posts off the carriageway.
const GANTRY_SLIDE := 20.0
## The span of a gantry when the prop does not state one.
const DEFAULT_SPAN := 27.0
## The height of the panel of the gantry of the props unit (its own panel is at 5.5 m).
const PANEL_BOTTOM := 5.5
## The distance of the panel of the gantry from the plane of its truss.
const PANEL_PLANE := 0.5
## The distance at which a gantry disappears.
const GANTRY_VISIBILITY_END := 800.0
## The distance at which a VMS board disappears.
const VMS_VISIBILITY_END := 800.0

var _props: PropLibrary
var _filter: Object


func setup(filter: Object = null) -> void:
	_props = PropLibrary.new()
	_filter = filter


## The gantries of one spot are collected together, so two entries at the same point get one
## truss and one panel per direction instead of two coplanar panels.
func collect(gantries: Dictionary, entry: Dictionary) -> Dictionary:
	var xform: Transform3D = entry["transform"]
	var key := "%d_%d" % [int(round(xform.origin.x)), int(round(xform.origin.z))]
	if not gantries.has(key):
		gantries[key] = []
	(gantries[key] as Array).append(entry)
	return gantries


## One gantry: the truss of the props unit and a panel per direction under it. The gantry
## spans the road, so only its two posts are checked: a post that stands on a lane slides the
## gantry along the road until it stands on the kerb.
func build_gantry(parent: Node3D, entries: Array) -> Dictionary:
	var first: Dictionary = entries[0]
	var xform: Transform3D = first["transform"]
	var def := _props.get_prop("gantry", 0)
	var span := float(first.get("span_m", DEFAULT_SPAN))
	xform = _slide_gantry(xform, span)
	var root := Node3D.new()
	root.name = "Gantry"
	root.transform = xform
	parent.add_child(root)
	for part in def.get("parts", []):
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		var material: Variant = part.get("material")
		if material != null:
			mi.material_override = (material as Material).duplicate()
		mi.transform = part["transform"]
		mi.visibility_range_end = GANTRY_VISIBILITY_END
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
	var panel_width := minf(PANEL_HEIGHT * PANEL_ASPECT, (span - 1.0) / float(entries.size()) - 0.4)
	var panels: Array[Dictionary] = []
	for i in entries.size():
		var entry: Dictionary = entries[i]
		# One panel per direction: the traffic that comes from either side of the gantry reads
		# the name of the road.
		for side in [1, -1]:
			var panel := _panel(root, panel_width, i, entries.size(), side)
			panels.append({
				"node": panel,
				"text": str(entry.get("text", "")),
				"text_en": str(entry.get("text_en", "")),
				"type": "gantry",
				"style": _panel_style(str(entry.get("road", ""))),
			})
	return {"node": root, "panels": panels, "type": "gantry"}


## The sign panel: a frame with a quad in front of it, so the texture covers the whole face.
## The panel sits in the plane of the panel of the gantry of the props unit.
func _panel(root: Node3D, width: float, index: int, count: int, side: int) -> MeshInstance3D:
	var height := width / PANEL_ASPECT
	var box := MeshInstance3D.new()
	box.name = "PanelBox_%d_%d" % [index, side]
	box.mesh = ProcMeshes.box(Vector3(width + 0.3, height + 0.3, PANEL_THICKNESS))
	box.material_override = ProcMeshes.material("metal")
	var step := width + 0.4
	var offset := (float(index) - float(count - 1) * 0.5) * step
	box.position = Vector3(offset, PANEL_BOTTOM + height * 0.5, float(side) * PANEL_PLANE)
	box.visibility_range_end = GANTRY_VISIBILITY_END
	root.add_child(box)
	var quad := MeshInstance3D.new()
	quad.name = "SignPanel_%d_%d" % [index, side]
	quad.mesh = ProcMeshes.quad(width, height)
	quad.material_override = ProcMeshes.material("sign_green")
	quad.position = box.position + Vector3(0.0, 0.0, float(side) * PANEL_OFFSET)
	if side < 0:
		quad.rotation.y = PI
	quad.visibility_range_end = GANTRY_VISIBILITY_END
	quad.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(quad)
	return quad


## Slides a gantry along the road until its two posts stand clear of the lanes.
func _slide_gantry(xform: Transform3D, span: float) -> Transform3D:
	if _filter == null:
		return xform
	var along := xform.basis.z.normalized()
	for step in 11:
		var distance := float(step) * GANTRY_SLIDE / 10.0
		var candidate := xform
		candidate.origin = xform.origin + along * distance
		if _posts_clear(candidate.origin, xform.basis, span):
			return candidate
	return xform


## True when the two posts of a gantry stand clear of the lanes.
func _posts_clear(origin: Vector3, basis: Basis, span: float) -> bool:
	var side := basis.x.normalized() * (span * 0.5)
	for post in [origin + side, origin - side]:
		if bool(_filter.on_lane(post)):
			return false
	return true


## The colour of a gantry panel: green on an elevated road, blue on a surface road (GB 5768.2).
func _panel_style(road: String) -> String:
	var style: Dictionary = _road_styles.get(road, {})
	return "blue" if str(style.get("kind", "surface")) == "surface" else "green"


## The style of the roads of the city: the panels follow the kind of the road.
var _road_styles: Dictionary = {}


func set_road_styles(styles: Dictionary) -> void:
	_road_styles = styles


## A VMS board: the board of the props unit with its own screen, so the message can change.
func build_vms(parent: Node3D, entry: Dictionary) -> Dictionary:
	var def := _props.get_prop("vms", 0)
	var xform: Transform3D = entry["transform"]
	var root := Node3D.new()
	root.name = "VMS"
	root.transform = xform
	parent.add_child(root)
	var screen: MeshInstance3D = null
	for part in def.get("parts", []):
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		var material: Variant = part.get("material")
		if material != null:
			mi.material_override = (material as Material).duplicate()
		mi.transform = part["transform"]
		mi.visibility_range_end = VMS_VISIBILITY_END
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
		if bool(part.get("sign", false)):
			screen = mi
	return {"node": root, "sign": screen, "panels": [], "text": "",
		"type": "vms", "style": str(entry.get("style", "amber"))}
