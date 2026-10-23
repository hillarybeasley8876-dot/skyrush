extends Node
## The health of the car and the HOP prompt of the HUD (tools/gd.py test
## res://ui/hud/tests/test_health_hop.gd).
##
## The HUD draws two things the design promises: the health bar (the health of the car) and the
## "跳！HOP ▲" prompt in front of a roadblock / toll plaza.
##
## The widgets are found by name and every read is guarded, so a missing widget prints a FAIL
## line instead of breaking the test.

const HudScene := preload("res://ui/hud/hud.tscn")
const Palette := preload("res://ui/theme/skyrush_palette.gd")

## A world with a toll plaza and a roadblock site (the HUD reads the sites of the world).
class FakeWorld extends WorldBase:
	var loading_fraction: float = 1.0
	var pois: Array[Dictionary] = []
	var sites: Array[Transform3D] = []

	func is_ready() -> bool:
		return true

	func get_points_of_interest() -> Array[Dictionary]:
		return pois

	func get_roadblock_sites() -> Array[Transform3D]:
		return sites


var _failures: int = 0
var _hud: CanvasLayer = null
var _player: VehicleBase = null
var _world: FakeWorld = null


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
	await _test_health()
	await _test_health_writes()
	await _test_hop()
	await _test_hop_toll()
	await _test_hop_nearest()
	print("HUD HEALTH HOP TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The health bar: the number, the colour of the fill and the wrecked car.
func _test_health() -> void:
	var hud := await _make_hud()
	var bar: Object = hud.get("health_bar")
	_check(bar != null, "the HUD has a health bar")
	if bar == null:
		await _free_hud()
		return
	var tele: CarTelemetry = hud.get("telemetry_override")
	tele.health_norm = 1.0
	await _frames(2)
	_check(_text(bar, "_value") == "100", "full health shows 100 (%s)" % _text(bar, "_value"))
	_check(is_equal_approx(float(bar.get("_ratio")), 1.0),
		"the bar is full at 100 %% (%.2f)" % float(bar.get("_ratio")))
	_check(bar.get("_fill_color") == Palette.GREEN, "the bar is green above 60 %")
	tele.health_norm = 0.5
	await _frames(2)
	_check(_text(bar, "_value") == "50", "half health shows 50 (%s)" % _text(bar, "_value"))
	_check(bar.get("_fill_color") == Palette.AMBER, "the bar is amber between 25 and 60 %")
	tele.health_norm = 0.2
	await _frames(2)
	_check(_text(bar, "_value") == "20", "a low health shows 20 (%s)" % _text(bar, "_value"))
	_check(bar.get("_fill_color") == Palette.RED, "the bar is red below 25 %")
	tele.health_norm = 0.0
	await _frames(2)
	_check(not bool(bar.get("visible")), "a wrecked car hides the health bar")
	await _free_hud()


## The number of the health is written only when the whole percent changes.
func _test_health_writes() -> void:
	var hud := await _make_hud()
	var bar: Object = hud.get("health_bar")
	if bar == null:
		_check(false, "the HUD has a health bar (the write counter)")
		await _free_hud()
		return
	var tele: CarTelemetry = hud.get("telemetry_override")
	await _frames(2)
	# The counter is zeroed, so only the writes of this value are counted.
	bar.set("text_writes", 0)
	tele.health_norm = 0.5
	await _frames(100)
	_check(int(bar.get("text_writes")) == 1,
		"the number is written once for 100 identical updates (%d)" %
		int(bar.get("text_writes")))
	await _free_hud()


## The HOP prompt: the gates (the N2, the ground) and the site ahead of the car.
func _test_hop() -> void:
	var hud := await _make_hud()
	var hint: Object = hud.get("hop_hint")
	_check(hint != null, "the HUD has a HOP hint")
	if hint == null:
		await _free_hud()
		return
	var tele: CarTelemetry = hud.get("telemetry_override")
	tele.n2 = 80.0
	tele.airborne = false
	tele.flying = false
	_place_player(Vector3(0.0, 0.6, 0.0))
	_set_sites(hint, _sites([Vector3(0.0, 0.0, -120.0)]))
	await _frames(30)
	_check(bool(hint.get("visible")), "the hint shows for a roadblock 120 m ahead")
	_check(_text(hint, "_distance").contains("120"),
		"the hint shows the distance (%s)" % _text(hint, "_distance"))
	_set_sites(hint, _sites([Vector3(0.0, 0.0, 120.0)]))
	await _frames(30)
	_check(not bool(hint.get("visible")), "a roadblock behind the car hides the hint")
	_set_sites(hint, _sites([Vector3(0.0, 10.0, -120.0)]))
	await _frames(30)
	_check(not bool(hint.get("visible")), "a roadblock on another level hides the hint")
	_set_sites(hint, _sites([Vector3(0.0, 0.0, -200.0)]))
	await _frames(30)
	_check(not bool(hint.get("visible")), "a roadblock 200 m ahead hides the hint")
	_set_sites(hint, _sites([Vector3(0.0, 0.0, -120.0)]))
	tele.n2 = 30.0
	await _frames(30)
	_check(not bool(hint.get("visible")), "without 50 N2 the hint hides")
	tele.n2 = 80.0
	await _frames(30)
	_check(bool(hint.get("visible")), "with 50 N2 the hint comes back")
	tele.airborne = true
	await _frames(30)
	_check(not bool(hint.get("visible")), "an airborne car hides the hint")
	tele.airborne = false
	tele.flying = true
	await _frames(30)
	_check(not bool(hint.get("visible")), "a flying car hides the hint")
	await _free_hud()


## A toll plaza of the world qualifies like a roadblock site.
func _test_hop_toll() -> void:
	var hud := await _make_hud()
	var hint: Object = hud.get("hop_hint")
	if hint == null:
		_check(false, "the HUD has a HOP hint (the toll plaza)")
		await _free_hud()
		return
	var tele: CarTelemetry = hud.get("telemetry_override")
	tele.n2 = 80.0
	_place_player(Vector3(0.0, 0.6, 0.0))
	_world = FakeWorld.new()
	_world.pois = [{"kind": &"toll", "position": Vector3(0.0, 0.0, -100.0), "label": "plaza"}]
	add_child(_world)
	Game.world = _world
	await _frames(30)
	_check(bool(hint.get("visible")), "a toll plaza ahead shows the hint")
	_check(_text(hint, "_distance").contains("100"),
		"the hint shows the distance of the plaza (%s)" % _text(hint, "_distance"))
	await _free_hud()


## Of two qualifying sites the nearest one decides the distance.
func _test_hop_nearest() -> void:
	var hud := await _make_hud()
	var hint: Object = hud.get("hop_hint")
	if hint == null:
		_check(false, "the HUD has a HOP hint (the nearest site)")
		await _free_hud()
		return
	var tele: CarTelemetry = hud.get("telemetry_override")
	tele.n2 = 80.0
	_place_player(Vector3(0.0, 0.6, 0.0))
	_set_sites(hint, _sites([Vector3(0.0, 0.0, -140.0), Vector3(0.0, 0.0, -60.0)]))
	await _frames(30)
	_check(_text(hint, "_distance").contains("60"),
		"the nearest site decides the distance (%s)" % _text(hint, "_distance"))
	await _free_hud()


## The text of a label of a widget ("" when the widget or the label is missing).
func _text(node: Object, key: String) -> String:
	if node == null:
		return ""
	var value: Variant = node.get(key)
	if value == null:
		return ""
	return str(value.get("text"))


## The sites of the hint (the test hands them in, the HUD reads them from the world).
func _set_sites(hint: Object, positions: Array[Vector3]) -> void:
	hint.call("set_sites", positions)


## The positions as a typed array (the widget takes an Array[Vector3]).
func _sites(positions: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in positions:
		out.append(p)
	return out


## The player of the test: on the ground, facing -Z.
func _place_player(pos: Vector3) -> void:
	if _player == null:
		return
	_player.global_transform = Transform3D(Basis.IDENTITY, pos)


## Build a HUD instance with a faked telemetry and a player.
func _make_hud() -> CanvasLayer:
	var hud := HudScene.instantiate() as CanvasLayer
	add_child(hud)
	await _frames(2)
	hud.set("telemetry_override", CarTelemetry.new())
	_hud = hud
	_player = VehicleBase.new()
	_player.freeze = true
	add_child(_player)
	Game.player = _player
	return hud


## Free the HUD, the player and the world.
func _free_hud() -> void:
	if _hud != null:
		_hud.queue_free()
		_hud = null
	if _player != null:
		_player.queue_free()
		_player = null
	if _world != null:
		_world.queue_free()
		_world = null
	Game.player = null
	Game.world = null
	await _frames(2)
