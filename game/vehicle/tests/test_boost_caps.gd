extends Node
## The QQ boost speed caps: 小喷 272, N2 300, CW 306.6, WCW 308.8, CWW 317.6, WCWW 319.8 km/h
## and the 330 km/h hard cap (dossier 1.4).
## Run: tools/godot.sh test res://vehicle/tests/test_boost_caps.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")


## The cap of a boost pattern in km/h.
func _cap(pat: String) -> float:
	return BoostMod.cap_for_pattern(DriveTuning.V_TOP, pat) * 3.6


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	t.check_close("小喷 only", _cap("W"), 272.0, 0.5)
	t.check_close("N2 only", _cap("C"), 300.0, 0.5)
	t.check_close("CW", _cap("CW"), 306.6, 0.5)
	t.check_close("WCW", _cap("WCW"), 308.8, 0.5)
	t.check_close("CWW", _cap("CWW"), 317.6, 0.5)
	t.check_close("WCWW", _cap("WCWW"), 319.8, 0.5)
	t.check("the hard cap", _cap("CWW") <= 330.0 and _cap("WCWW") <= 330.0,
			"= %.1f / %.1f km/h" % [_cap("CWW"), _cap("WCWW")])
	# Without nitro the mini boosts overwrite each other.
	t.check_close("WW without nitro", _cap("WW"), 272.0, 0.5)
	# The runtime: the nitro and the mini stack when they are fired in time.
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	car.boost.setup(DriveTuning.V_TOP, 200.0)
	car.boost.use_nitro()
	t.check_close("the running cap with the nitro", car.boost.speed_cap * 3.6, 300.0, 0.5)
	# A 小喷 0.2 s into the nitro stacks (CW).
	car.boost.tick(0.2)
	car.boost.open_mini_window()
	car.boost.use_mini()
	t.check_close("the CW cap", car.boost.speed_cap * 3.6, 306.6, 0.5)
	t.check("the pattern", car.boost.pattern() == "CW", "= %s" % car.boost.pattern())
	# A 小喷 too late does not stack.
	car.boost.setup(DriveTuning.V_TOP, 200.0)
	car.boost.use_nitro()
	car.boost.tick(0.6)
	car.boost.open_mini_window()
	car.boost.use_mini()
	t.check_close("a late 小喷 does not stack", car.boost.speed_cap * 3.6, 272.0, 0.5)
	t.finish()
