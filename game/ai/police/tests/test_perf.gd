extends Node
## The cost of the police AI with the full heat-5 unit count (dossier §6.3).
##
##   tools/godot.sh test res://ai/police/tests/test_perf.gd
##
## The budget of the brief: the dispatcher costs at most 1.5 ms per frame on average and 3.0 ms
## at its peak, and the police add at most 2 ms of wall time to a physics step. The test reports
## the raw (not smoothed) tick of the dispatcher, the wall time the units cost and the time
## every part of the dispatcher needed (the five most expensive ones).

const T := preload("res://ai/police/tests/police_test.gd")
const BUDGET_MS := 1.5
const PEAK_MS := 3.0
const WALL_MS := 2.0
const UNITS := 12
const FRAMES := 1200
## The frames the measurement skips (the units settle on their lanes).
const WARMUP := 120
## The load of the machine above which the numbers are read with care.
const HIGH_LOAD := 12.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-400.0))
	t.director.spawn_enabled = false
	# The wall time of a frame without the police.
	var quiet := await _wall_time(t)
	t.director.force_heat(5)
	for i in UNITS:
		var unit: PoliceCar = t.director.spawn_unit_at(
				t.straight_start(-400.0 - 14.0 * float(i)), PoliceFleet.Role.PURSUE)
		if unit != null:
			# The units are at the speed of the player, so they stay in the ring.
			unit.linear_velocity = Vector3(25.0, 0.0, 0.0)
	await t.idle(1.0)
	var busy := await _wall_time(t)
	var samples: Array[float] = []
	var modules: Dictionary = {}
	for i in FRAMES:
		await t.drive_frame(0.0, 90.0)
		# The first second is the warm-up (the units settle on their lanes).
		if i < WARMUP:
			continue
		samples.append(t.director.tick_ms)
		for name: String in t.director.module_ms:
			var value := float(t.director.module_ms[name])
			modules[name] = float(modules.get(name, 0.0)) + value
		if t.director.tick_ms > 3.0:
			print("  SLOW frame ", i, " tick=", t.director.tick_ms)
	var total := 0.0
	for value: float in samples:
		total += value
	var mean := total / float(samples.size())
	# The peak is the slowest tick of the whole run: a spawn or a build must not decide the
	# budget, but the absolute maximum has to stay inside it.
	var sorted := samples.duplicate()
	sorted.sort()
	var absolute: float = sorted[sorted.size() - 1]
	var p995: float = sorted[mini(int(float(sorted.size()) * 0.995), sorted.size() - 1)]
	print("units: %d, dispatcher mean %.3f ms, p99.5 %.3f ms, max %.3f ms, wall %.3f -> %.3f ms (+%.3f)"
			% [t.director.units.size(), mean, p995, absolute, quiet, busy, busy - quiet])
	_print_modules(modules, samples.size())
	print("load: ", _load())
	t.check(t.director.units.size() >= UNITS, "the heat-5 budget of 12 units is on the road (%d)"
			% t.director.units.size())
	t.check(mean <= BUDGET_MS, "the dispatcher stays inside the budget (%.3f ms of %.1f ms)"
			% [mean, BUDGET_MS])
	t.check(absolute <= PEAK_MS, "the slowest dispatcher tick stays inside the peak (%.3f ms of %.1f ms)"
			% [absolute, PEAK_MS])
	t.check(busy - quiet <= WALL_MS, "the police cost at most %.1f ms of wall time (+%.3f ms)"
			% [WALL_MS, busy - quiet])
	t.expect(4)
	t.finish()


## Prints the five most expensive parts of the dispatcher.
func _print_modules(modules: Dictionary, frames: int) -> void:
	var names: Array = modules.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return float(modules.get(a, 0.0)) > float(modules.get(b, 0.0)))
	for i in mini(5, names.size()):
		print("  module %s: %.3f ms per tick" % [names[i],
				float(modules[names[i]]) / float(frames)])


## The load of the machine (the numbers of a busy machine are read with care).
func _load() -> float:
	if OS.get_name() != "macOS":
		return 0.0   # sysctl only exists on macOS: no process is started elsewhere
	var out: Array = []
	OS.execute("/bin/sh", ["-c", "sysctl -n vm.loadavg"], out)
	if out.is_empty():
		return 0.0
	var text := ""
	for line: String in out:
		text += line
	var parts := text.replace("{", "").replace("}", "").split(" ", false)
	if parts.is_empty():
		return 0.0
	return float(parts[0])


## The mean wall time of a physics frame in milliseconds.
func _wall_time(t: T) -> float:
	var started := Time.get_ticks_usec()
	for i in Engine.physics_ticks_per_second * 5 / 2:
		await t.tree.physics_frame
	return float(Time.get_ticks_usec() - started) / 300.0 / 1000.0
