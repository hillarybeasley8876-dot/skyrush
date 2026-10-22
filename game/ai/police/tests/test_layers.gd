extends Node
## The police rules must not cross the levels of the map.
##
##   python tools/gd.py test res://ai/police/tests/test_layers.gd
##
## The map is not flat: a street at y = 0 runs under the elevated deck at y = 10. A cop that
## drives on the street cannot bust a player on the deck, a hiding spot under the deck does not
## hide a player on the deck, and the HUD does not warn about a bust for a cop under the deck.
##
## Every rule has two halves: on the same level everything happens as before, on the other level
## nothing happens at all.

const STUB := preload("res://core/stubs/stub_car.tscn")
const HudPursuit := preload("res://ui/hud/hud_pursuit.gd")

const STREET := 0.6        ## m: the height of a car on the street
const DECK := 10.6         ## m: the height of a car on the deck
const SPOT := Vector3(200.0, 0.0, 1660.0)     ## the hiding spot under the deck
const HIDE_POS := Vector3(200.0, 0.0, 1665.0)  ## the player next to the spot
const HIDE_DECK_POS := Vector3(200.0, 0.0, 1663.0)  ## the player on the deck over the spot
const PLAYER_POS := Vector3(200.0, 0.0, 1660.0)  ## the player on the street
const COP_POS := Vector3(205.0, 0.0, 1660.0)  ## the cop, five metres away
const DT := 1.0 / 120.0     ## s: the physics step
const BUST_TIME := 2.0     ## s: how long the busted meter has to fill


## A cop that is only a place for the rules: no car, no light bar, no physics.
class TestCop extends PoliceCar:
	func _ready() -> void:
		pass


var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _run() -> void:
	_test_hiding_same_level()
	_test_hiding_on_a_deck()
	_test_busted_same_level()
	_test_busted_under_a_deck()
	_test_hud_same_level()
	_test_hud_under_a_deck()
	if _failures == 0:
		print("POLICE LAYER TESTS OK (0 failures)")
		get_tree().quit(0)
	else:
		print("POLICE LAYER TESTS FAILED")
		get_tree().quit(1)


## The player next to a hiding spot, on the same level: the spot hides it.
func _test_hiding_same_level() -> void:
	var pursuit := PolicePursuit.new()
	var spots: Array[Vector3] = [SPOT]
	pursuit.hiding_spots = spots
	var player := _make_player(STREET, HIDE_POS)
	pursuit._update_hiding_spot(player)
	_check(pursuit.in_hiding_spot, "a player next to a spot on the same level is hidden")


## The same spot, but the player is on the deck 10.6 m above the street: the spot is not hers.
func _test_hiding_on_a_deck() -> void:
	var pursuit := PolicePursuit.new()
	var spots: Array[Vector3] = [SPOT]
	pursuit.hiding_spots = spots
	var player := _make_player(DECK, HIDE_DECK_POS)
	pursuit._update_hiding_spot(player)
	_check(not pursuit.in_hiding_spot,
			"a spot under the deck does not hide a player on the deck")


## A cop next to a standing player, on the same level: the busted meter fills.
func _test_busted_same_level() -> void:
	var pursuit := PolicePursuit.new()
	pursuit.set_state(&"chase")
	var player := _make_player(STREET, PLAYER_POS)
	var units: Array[PoliceCar] = [_make_cop(Vector3(COP_POS.x, STREET, COP_POS.z))]
	for i in int(BUST_TIME * 120.0):
		pursuit.update_busted(DT, player, units)
	_check(pursuit.busted > 0.0, "the meter fills for a cop on the same level (%.2f)"
			% pursuit.busted)


## The same cop under the deck, the player on the deck: the meter stays empty.
func _test_busted_under_a_deck() -> void:
	var pursuit := PolicePursuit.new()
	pursuit.set_state(&"chase")
	var player := _make_player(DECK, PLAYER_POS)
	var units: Array[PoliceCar] = [_make_cop(Vector3(COP_POS.x, STREET, COP_POS.z))]
	for i in int(BUST_TIME * 120.0):
		pursuit.update_busted(DT, player, units)
	_check(pursuit.busted <= 0.0, "the meter stays empty for a cop under the deck (%.2f)"
			% pursuit.busted)


## The HUD of the pursuit: a cop on the same level fills the busted bar.
func _test_hud_same_level() -> void:
	var hud := HudPursuit.new()
	var t := CarTelemetry.new()
	t.speed_kmh = 0.0
	var police := PackedVector3Array([Vector3(COP_POS.x, STREET, COP_POS.z)])
	for i in 120:
		hud.update(t, 1, &"chase", police, Vector3(PLAYER_POS.x, STREET, PLAYER_POS.z), DT)
	_check(hud.busted > 0.0, "the HUD warns about a cop on the same level (%.2f)" % hud.busted)


## The same cop under the deck: the HUD does not warn about a bust.
func _test_hud_under_a_deck() -> void:
	var hud := HudPursuit.new()
	var t := CarTelemetry.new()
	t.speed_kmh = 0.0
	var police := PackedVector3Array([Vector3(COP_POS.x, STREET, COP_POS.z)])
	for i in 120:
		hud.update(t, 1, &"chase", police, Vector3(PLAYER_POS.x, DECK, PLAYER_POS.z), DT)
	_check(hud.busted <= 0.0, "the HUD does not warn about a cop under the deck (%.2f)"
			% hud.busted)


## The player: the stub car of the core, frozen at a height.
func _make_player(height: float, xz: Vector3) -> VehicleBase:
	var player := STUB.instantiate() as VehicleBase
	add_child(player)
	player.gravity_scale = 0.0
	player.freeze = true
	player.global_position = Vector3(xz.x, height, xz.z)
	return player


## The cop: a place for the rules, five metres from the player.
func _make_cop(pos: Vector3) -> PoliceCar:
	var cop := TestCop.new()
	add_child(cop)
	cop.gravity_scale = 0.0
	cop.freeze = true
	cop.global_position = pos
	return cop
