extends Node
## car_model test: the hero Roadster glb keeps the node names, materials, pivots, dimensions,
## layout and palette the contracts ask for (CONTRACTS.md 6): white pearl and gloss black, no
## texture, the parts the damage unit moves, the markers the thrusters and the camera read.
##
## The checks live in roadster_checks.gd and roadster_checks2.gd, so this file stays short.
## Run: python tools/gd.py test res://assets/cars/roadster/tests/test_roadster.gd

const GLB := "res://assets/cars/roadster/roadster.glb"
const Checks := preload("res://assets/cars/roadster/tests/roadster_checks.gd")
const Checks2 := preload("res://assets/cars/roadster/tests/roadster_checks2.gd")

var _fail := 0


func _ready() -> void:
	var packed := load(GLB) as PackedScene
	if packed == null:
		print("FAIL cannot load " + GLB)
		get_tree().quit(1)
		return
	var car := packed.instantiate()
	add_child(car)
	# the global transforms are only composed after the tree has processed the
	# new node, so the checks have to wait for one frame
	await get_tree().process_frame
	var c := Checks.new()
	var c2 := Checks2.new()
	var by_name := {}
	c.collect(car, by_name)
	c.check_names(by_name)
	c.check_materials(car)
	c.check_palette(car)
	c.check_dimensions(by_name, car)
	c.check_wheels(by_name)
	c.check_layout(by_name)
	c2.check_surfaces(by_name)
	c2.check_hinges(by_name)
	c2.check_lights(by_name)
	c2.check_wing(by_name)
	c2.check_markers(by_name)
	c2.check_ends(by_name)
	_fail = c.failures + c2.failures
	_fail += _self_test()
	print(("FAIL %d checks failed" % _fail) if _fail > 0 else "PASS all checks")
	get_tree().quit(0 if _fail == 0 else 1)


## The checks have to be able to fail: a gold wheel, a red body, a textured material and a rotated
## wheel must each be caught. Returns the number of checks that did not catch their fault.
func _self_test() -> int:
	var missed := 0
	var root := Node3D.new()
	add_child(root)
	for spec in [["M_GoldWheel", Color(0.43, 0.23, 0.10)], ["SH_car_paint", Color(0.7, 0.0, 0.0)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.resource_name = spec[0]
		mat.albedo_color = spec[1]
		mi.mesh.surface_set_material(0, mat)
		root.add_child(mi)
	var textured := MeshInstance3D.new()
	textured.mesh = BoxMesh.new()
	var tex_mat := StandardMaterial3D.new()
	tex_mat.resource_name = "M_Textured"
	tex_mat.albedo_texture = PlaceholderTexture2D.new()
	textured.mesh.surface_set_material(0, tex_mat)
	root.add_child(textured)
	var probe := Checks.new()
	probe.quiet = true
	probe.check_palette(root)
	if probe.failures != 2:
		print("FAIL the palette check did not catch the gold wheel, the red paint and the texture (%d of 2 checks failed)" % probe.failures)
		missed += 1
	var wheels := {}
	for n in Checks.WHEELS:
		var w := MeshInstance3D.new()
		w.name = n
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.384
		cyl.bottom_radius = 0.384
		cyl.height = 0.28
		w.mesh = cyl
		w.position = Vector3(0.98, 0.5, 0.0)
		w.rotation = Vector3(0.0, 0.0, 0.5)
		root.add_child(w)
		wheels[n] = w
	probe = Checks.new()
	probe.quiet = true
	probe.check_wheels(wheels)
	if probe.failures == 0:
		print("FAIL the wheel check did not catch rotated, raised, misplaced wheels")
		missed += 1
	root.queue_free()
	return missed
