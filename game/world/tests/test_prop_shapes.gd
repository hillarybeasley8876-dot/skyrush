extends Node
## Probe: the structure of the prop glbs of the props unit (the surfaces, the materials and the
## nodes of the lamps and of the signs).
## Run: tools/godot.sh test res://world/tests/test_prop_shapes.gd

const PATHS: Array[String] = [
	"res://assets/props/street/lamp_street.glb",
	"res://assets/props/street/lamp_magnolia.glb",
	"res://assets/props/street/lamp_heritage.glb",
	"res://assets/props/street/lamp_deck_double.glb",
	"res://assets/props/street/guide_sign.glb",
	"res://assets/props/street/guide_gantry_27.glb",
	"res://assets/props/street/neon_blade_frame.glb",
	"res://assets/props/street/bus_stop.glb",
	"res://assets/props/street/traffic_light_mast.glb",
]


func _ready() -> void:
	await get_tree().process_frame
	for path in PATHS:
		_report(path)
	print("[probe] done")
	get_tree().quit(0)


func _report(path: String) -> void:
	if not ResourceLoader.exists(path):
		print("[probe] %s MISSING" % path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("[probe] %s not a PackedScene" % path)
		return
	var node := packed.instantiate() as Node3D
	print("[probe] --- %s" % path.get_file())
	for child in node.get_children():
		print("[probe]   node %s (%s)" % [child.name, child.get_class()])
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				var name := mat.resource_name if mat != null else "<null>"
				var emission := 0.0
				var base := mat as BaseMaterial3D
				if base != null:
					emission = base.emission_energy_multiplier
				print("[probe]     surface %d material '%s' emission %.2f" % [i, name, emission])
				var arrays := mi.mesh.surface_get_arrays(i)
				var aabb := AABB()
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if not verts.is_empty():
					aabb = AABB(verts[0], Vector3.ZERO)
					for v in verts:
						aabb = aabb.expand(v)
				print("[probe]       verts %d aabb %s" % [verts.size(), str(aabb)])
	node.free()
