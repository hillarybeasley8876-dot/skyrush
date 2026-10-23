extends Node
## HUD demo: fakes telemetry and fires every HUD event in a loop, without needing a world.
## Run it with:  tools/godot.sh shot --scene=res://ui/hud/demo/hud_demo.tscn --out=hud --times=...
## Options: --bg=white|magenta (a flat background to judge the readability), --widescreen (21:9),
## --sixteen10 (16:10).

const HudScene := preload("res://ui/hud/hud.tscn")
const Backdrop := preload("res://ui/hud/demo/demo_backdrop.gd")
const DemoSteps := preload("res://ui/hud/demo/demo_steps.gd")

var hud: CanvasLayer
var car: VehicleBase
var tele: CarTelemetry
var _t: float = 0.0
var _step: int = 0
var _steps: Array = []


func _ready() -> void:
	Game.mode = &"race"
	_apply_window_size()
	_apply_background()

	var back_layer := CanvasLayer.new()
	back_layer.layer = 0
	add_child(back_layer)
	var back := Backdrop.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back_layer.add_child(back)

	hud = HudScene.instantiate() as CanvasLayer
	add_child(hud)

	_make_cars()
	_build_map()
	_steps = DemoSteps.build(self)


## --widescreen (21:9) and --sixteen10 let the capture tool check the anchors at other aspects.
func _apply_window_size() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--widescreen":
			DisplayServer.window_set_size(Vector2i(2560, 1080))
		elif arg == "--sixteen10":
			DisplayServer.window_set_size(Vector2i(1920, 1200))


## --bg=white|magenta puts a flat, deliberately hostile background behind the HUD.
func _apply_background() -> void:
	var bg := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bg="):
			bg = arg.trim_prefix("--bg=")
	if bg.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color.WHITE if bg == "white" else Color("ff2bd6")
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)


func _make_cars() -> void:
	car = VehicleBase.new()
	car.name = "DemoCar"
	car.display_name = "Roadster"
	car.freeze = true
	add_child(car)
	car.add_to_group("player")
	Game.player = car
	tele = car.telemetry

	for i in 2:
		var cop := VehicleBase.new()
		cop.name = "Cop%d" % i
		cop.display_name = "警车"
		cop.freeze = true
		cop.position = Vector3(90.0 * float(i + 1), 0.0, -70.0 * float(i))
		add_child(cop)
		cop.add_to_group("police")

	var rival := VehicleBase.new()
	rival.name = "Rival"
	rival.display_name = "疾风"
	rival.freeze = true
	rival.position = Vector3(-25.0, 0.0, 30.0)
	add_child(rival)
	rival.add_to_group("rivals")


func _build_map() -> void:
	var lines: Array[PackedVector2Array] = []
	for i in 5:
		var o := float(i - 2) * 220.0
		lines.append(PackedVector2Array([Vector2(-700, o), Vector2(700, o)]))
		lines.append(PackedVector2Array([Vector2(o, -700), Vector2(o, 700)]))
	lines.append(PackedVector2Array([Vector2(-700, 120), Vector2(0, -40), Vector2(700, 60)]))
	hud.demo_polylines = lines
	var pois: Array[Dictionary] = [
		{"kind": &"charge", "position": Vector3(220, 0, -220), "label": "申城闪充"},
		{"kind": &"gas", "position": Vector3(-220, 0, 220), "label": "中石华"},
		{"kind": &"toll", "position": Vector3(440, 0, -220), "label": "申城收费站"},
		{"kind": &"sky_lane", "position": Vector3(0, 0, -440), "label": "飞行航道"},
		{"kind": &"landmark", "position": Vector3(-120, 0, 330), "label": "龙柱"},
	]
	hud.demo_pois = pois


func _reset_state() -> void:
	Events.heat_changed.emit(0)
	Events.pursuit_state_changed.emit(&"none")
	Events.mode_status.emit(&"none", {})
	Events.checkpoint_passed.emit(car, 0, 8)
	Events.checkpoint_passed.emit(car, 1, 8)
	Events.lap_completed.emit(car, 1, 48.32)


func _process(delta: float) -> void:
	_t += delta
	if _t >= DemoSteps.LOOP_TIME:
		_t -= DemoSteps.LOOP_TIME
		_step = 0
	while _step < _steps.size() and float(_steps[_step][0]) <= _t:
		var action: Callable = _steps[_step][1]
		action.call()
		_step += 1
	_drive_telemetry()


## The faked telemetry: the states that the events alone cannot show.
func _drive_telemetry() -> void:
	var airborne := _t >= 23.2 and _t < 25.2
	var flying := _t >= 25.2 and _t < 26.6
	tele.speed_kmh = 176.0 + 40.0 * sin(_t * 0.8)
	tele.motor_load = 0.45 + 0.25 * sin(_t * 1.7)
	tele.battery = 0.87 - 0.02 * sin(_t * 0.2)
	tele.n2 = 120.0 + 30.0 * sin(_t * 0.5)
	tele.n2_pending = 18.0 if _t > 5.0 and _t < 6.0 else 0.0
	tele.boost_kind = &"nitro" if _t > 8.0 and _t < 9.4 else &""
	tele.mini_window = _t >= 5.4 and _t < 5.9
	# The Big Hop ring: charging, then armed (charge 1.0) at the end of the hold.
	tele.hop_charge = 0.0
	if _t >= 22.2 and _t < 22.7:
		tele.hop_charge = clampf((_t - 22.2) * 3.0, 0.0, 1.0)
	elif _t >= 22.7 and _t < 23.1:
		tele.hop_charge = 1.0
	tele.airborne = airborne
	tele.flying = flying
	tele.airtime = (_t - 23.2) if airborne else 0.0
	tele.altitude_m = (_t - 23.2) * 7.5 if airborne else 0.0
	tele.pitch_deg = (_t - 23.2) * 26.0 if airborne else 0.0
	tele.downforce_kg = 1200.0 + 1800.0 * sin((_t - 23.2) * 0.9) if airborne else 0.0
	tele.thrusters = {
		"Nozzle_P1": 0.8 if airborne else 0.0,
		"Nozzle_P2": 0.8 if airborne else 0.0,
		"Nozzle_P3": 0.5 if airborne else 0.0,
		"Nozzle_P4": 0.5 if airborne else 0.0,
	}
