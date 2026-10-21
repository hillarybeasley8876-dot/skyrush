extends Node
## car_model test: the hero Roadster glb keeps the node names, materials, pivots,
## dimensions, textures and left/right layout the contracts ask for
## (CONTRACTS.md §6, brief "Acceptance", car_model reviews round 1 #15,
## round 2 #13 and round 3 #12).
##
## The checks live in roadster_checks.gd and roadster_checks2.gd, so this file
## stays short enough to read.

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
	c.check_materials(by_name, car)
	c.check_dimensions(by_name)
	c.check_inside(by_name)
	c.check_panels(by_name)
	c.check_wheels(by_name)
	c.check_layout(by_name)
	c.check_uvs(by_name)
	c.check_textures(by_name)
	c2.check_surfaces(by_name)
	c2.check_lamps(by_name)
	c2.check_clearances(by_name)
	c2.check_wing(by_name)
	c2.check_tyre_winding(by_name)
	_fail = c.failures + c2.failures
	print(("FAIL %d checks failed" % _fail) if _fail > 0 else "PASS all checks")
	get_tree().quit(0 if _fail == 0 else 1)
