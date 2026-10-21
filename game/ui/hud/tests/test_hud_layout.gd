extends Node
## HUD layout tests (tools/godot.sh test res://ui/hud/tests/test_hud_layout.gd).
##
## The layout of the HUD: the clusters must clear the flight gauges in flight, the speedometer
## labels must stay between the tick ladder and the motor ring, the countdown must be visible
## again in the second race and the flight gauges must appear after 0.3 s of airtime.
##
## The rects are read from the LIVE controls, not from a copy of the layout numbers.

const HudScene := preload("res://ui/hud/hud.tscn")
const FlightCluster := preload("res://ui/hud/flight_cluster.gd")
const SpeedDialScript := preload("res://ui/hud/speed_dial.gd")
const CountdownLabel := preload("res://ui/hud/countdown_label.gd")
const GaugeDial := preload("res://ui/hud/gauge_dial.gd")

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _test_flight_clearance()
	await _test_dial_labels()
	await _test_countdown_again()
	await _test_flight()
	print("HUD LAYOUT TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## In flight the speed cluster must clear the PITCH and ALTITUDE gauges and the N2 cluster must
## clear the DOWNFORCE ring and the attitude icon. The rects are read from the LIVE controls, not
## from a copy of the layout numbers.
func _test_flight_clearance() -> void:
	for viewport in [Vector2(1920, 1080), Vector2(1920, 1200), Vector2(2560, 1080)]:
		var hud := await _make_hud()
		var root: Control = hud.get("root")
		# The HUD root is pinned to the top left, so the test can size it.
		root.anchor_left = 0.0
		root.anchor_top = 0.0
		root.anchor_right = 0.0
		root.anchor_bottom = 0.0
		root.offset_left = 0.0
		root.offset_top = 0.0
		root.offset_right = viewport.x
		root.offset_bottom = viewport.y
		var tele: CarTelemetry = hud.get("telemetry_override")
		await _frames(4)
		tele.airborne = true
		tele.airtime = 0.5
		tele.downforce_kg = 2400.0
		tele.pitch_deg = 30.0
		tele.altitude_m = 12.0
		await _frames(30)
		var speed: Control = hud.get("speed_cluster")
		var nitro: Control = hud.get("nitro_cluster")
		var flight: FlightCluster = hud.get("flight")
		var down := _aabb(flight.get("_downforce"))
		var att := _aabb(flight.get("_attitude"))
		var pitch := _aabb(flight.get("_pitch"))
		var alt := _aabb(flight.get("_altitude"))
		var speed_rect := _aabb(speed)
		var nitro_rect := _aabb(nitro)
		_check(not speed_rect.intersects(pitch.grow(16.0)) and not speed_rect.intersects(alt.grow(16.0)),
			"the speed cluster clears the flight gauges at %dx%d" % [int(viewport.x), int(viewport.y)])
		_check(not nitro_rect.intersects(down.grow(16.0)) and not nitro_rect.intersects(att.grow(16.0)),
			"the N2 cluster clears the DOWNFORCE ring at %dx%d" % [int(viewport.x), int(viewport.y)])
		_check(nitro.modulate.a >= 0.85,
			"the N2 stays visible in flight (alpha %.2f)" % nitro.modulate.a)
		_free_hud(hud)


## The bounding box of a control in the screen space (the scale included).
func _aabb(c: Control) -> Rect2:
	var t := c.get_global_transform()
	var corners: Array[Vector2] = [t * Vector2.ZERO, t * Vector2(c.size.x, 0.0), t * c.size,
		t * Vector2(0.0, c.size.y)]
	var r := Rect2(corners[0], Vector2.ZERO)
	for p in corners:
		r = r.expand(p)
	return r


## The dial labels must stay between the tick ladder (r 106) and the motor ring (r 136).
func _test_dial_labels() -> void:
	var dial := SpeedDialScript.new()
	dial.size = Vector2(300, 300)
	add_child(dial)
	await _frames(2)
	var centre := Vector2(150, 150)
	var nearest := 999.0
	var furthest := 0.0
	for rect in dial.label_rects():
		var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)]
		for corner in corners:
			var r := corner.distance_to(centre)
			nearest = minf(nearest, r)
			furthest = maxf(furthest, r)
	_check(nearest > 106.0 and furthest < 136.0,
		"the dial labels stay between the ticks and the motor ring (r %.1f .. %.1f)" %
		[nearest, furthest])
	dial.queue_free()
	await _frames(1)


## The countdown of the second race must be visible: the alpha is reset on every count.
func _test_countdown_again() -> void:
	var hud := await _make_hud()
	var countdown: CountdownLabel = hud.get("countdown")
	countdown.set_count(0)
	await _frames(150)
	countdown.set_count(3)
	await _frames(2)
	_check(countdown.get("_label").modulate.a > 0.95,
		"the countdown of the second race is visible (alpha %.2f)" %
		countdown.get("_label").modulate.a)
	_free_hud(hud)



## The flight gauges appear after 0.3 s of airtime and the N2 cluster steps aside.
func _test_flight() -> void:
	var hud := await _make_hud()
	var tele := CarTelemetry.new()
	hud.set("telemetry_override", tele)
	tele.airborne = true
	tele.airtime = 0.5
	tele.downforce_kg = 2400.0
	tele.pitch_deg = 34.0
	tele.altitude_m = 12.5
	tele.thrusters = {"Nozzle_P1": 0.9, "Nozzle_P2": 0.9}
	hud.call("_process", 0.016)
	await _frames(30)
	_check(bool(hud.get("flight").get("visible")), "the flight gauges appear while airborne")
	_check(float(hud.get("nitro_cluster").get("modulate").a) >= 0.85,
		"the N2 cluster stays visible in flight (alpha %.2f)" %
		float(hud.get("nitro_cluster").get("modulate").a))
	# The pitch gauge fills by |pitch| / 180 (dossier §6.4).
	var flight: FlightCluster = hud.get("flight")
	var pitch: GaugeDial = flight.get("_pitch")
	_check(is_equal_approx(float(pitch.get("fill")), 34.0 / 180.0),
		"the pitch gauge fills by |pitch| / 180 (%.3f)" % float(pitch.get("fill")))
	tele.airborne = false
	tele.airtime = 0.0
	hud.call("_process", 0.016)
	await _frames(30)
	_check(not bool(hud.get("flight").get("visible")), "the flight gauges hide again on landing")
	_free_hud(hud)



## Build a HUD instance with a faked telemetry.
func _make_hud() -> CanvasLayer:
	var hud := HudScene.instantiate() as CanvasLayer
	add_child(hud)
	await _frames(2)
	hud.set("telemetry_override", CarTelemetry.new())
	return hud


func _free_hud(hud: CanvasLayer) -> void:
	hud.queue_free()
	await _frames(2)
