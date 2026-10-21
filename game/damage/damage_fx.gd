extends Node3D
## The damage tiers of dossier §7.4, seen on the car itself:
##   light  (60-31 % HP): grey smoke from the engine bay, one head lamp flickers
##   heavy  (30-1 % HP):  dark smoke, sparks under the car, the bumper hangs at 25 degrees
##   wrecked:            a fireball at the engine bay
## The Roadster is an EV, so its heavy state is white smoke and blue electrical arcs
## instead of black oil smoke (dossier §7.4).
##
## Nothing is built before the car is hurt: a car that joins the world owns no light, no
## particle and no mesh.

const DamageLamp := preload("res://damage/damage_lamp.gd")
const BumperHang := preload("res://damage/bumper_hang.gd")
const TierEmitters := preload("res://damage/tier_emitters.gd")
const EvArcs := preload("res://damage/ev_arcs.gd")
const FxAssets := preload("res://damage/fx_assets.gd")

const FLASH_COLOR := Color(1.0, 0.69, 0.29)             ## #FFB04A
const FLASH_TIME := 0.4
const FLASH_ENERGY := 8.0
const FLASH_RANGE := 6.0
const FIREBALL_TIME := 0.4
## The fireball is 1.5 to 2.5 m wide while it burns.
const FIREBALL_WIDTH := 2.0
const FIREBALL_HDR := 6.0

var vehicle: VehicleBase = null
## True for the electric cars (the player Roadster): white smoke and arcs.
var electric: bool = false

var _lamp: DamageLamp = null
var _bumper: BumperHang = null
var _emitters: TierEmitters = null
var _arcs: EvArcs = null
var _flash: OmniLight3D = null
var _fireball: Sprite3D = null
var _flash_timer: float = 0.0
var _fireball_timer: float = 0.0


## Builds the rig for a car. `electric` = the white smoke + arcs of the Roadster.
func setup(car: VehicleBase, is_electric: bool) -> void:
	vehicle = car
	electric = is_electric
	_lamp = DamageLamp.new()
	_bumper = BumperHang.new()
	_emitters = TierEmitters.new()
	_emitters.setup(car, is_electric)


## The tier of the car: 0 clean, 1 light, 2 heavy, 3 wrecked.
func apply_tier(tier: int) -> void:
	if tier <= 0:
		_stop()
		return
	if tier < 3:
		# The lamp flickers when the car is light or heavy, not before.
		_lamp.setup(vehicle)
		_emitters.apply_tier(tier)
	if tier >= 2:
		_ensure_arcs()
	if _arcs != null:
		_arcs.visible = electric and tier >= 2
		if _arcs.visible:
			_arcs.start()
		else:
			_arcs.stop()


## True while the tier smoke is running (for the test).
func smoke_running() -> bool:
	return _emitters != null and _emitters.smoke_running()


## The respawn: the car is whole again (the bumper goes back on its hinge, the lamp stops
## flickering, the smoke stops).
func reset() -> void:
	_stop()
	_bumper.reset()
	_lamp.reset()


## The bumper of the car hangs (dossier §7.4). `side` is the side of the last hit.
func hang_bumper(side: float = 0.0) -> void:
	_bumper.hang(vehicle, side)


## The wreck: the fireball and the flash at the engine bay.
func play_wreck() -> void:
	_ensure_flash()
	_flash.light_energy = FLASH_ENERGY
	_flash_timer = FLASH_TIME
	_ensure_fireball()
	_fireball_timer = FIREBALL_TIME
	_emitters.apply_tier(2)


func _process(delta: float) -> void:
	_tick_flash(delta)
	_tick_lamp(delta)
	if _emitters != null:
		_emitters.tick(delta)


func _tick_lamp(delta: float) -> void:
	if _lamp != null:
		_lamp.tick(delta)


## The flash of the wreck and the fireball.
func _tick_flash(delta: float) -> void:
	if _flash != null and _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - delta)
		_flash.light_energy = FLASH_ENERGY * (_flash_timer / FLASH_TIME)
		if _flash_timer <= 0.0:
			_flash.light_energy = 0.0
	if _fireball == null or _fireball_timer <= 0.0:
		return
	_fireball_timer = maxf(0.0, _fireball_timer - delta)
	var k := _fireball_timer / FIREBALL_TIME
	_fireball.visible = true
	_fireball.modulate.a = k
	# The fireball grows while it burns.
	_fireball.scale = Vector3.ONE * lerpf(0.75, 1.25, 1.0 - k)
	if _fireball_timer <= 0.0:
		_fireball.visible = false


## Stops everything: the car is whole again.
func _stop() -> void:
	_emitters.stop()
	if _arcs != null:
		_arcs.stop()
		_arcs.visible = false


## The arcs of the electric car (dossier §7.4): they only exist on a heavy EV.
func _ensure_arcs() -> void:
	if _arcs != null or not electric:
		return
	_arcs = EvArcs.new()
	_arcs.name = "Arcs"
	add_child(_arcs)
	_arcs.setup(vehicle)


## The light of the wreck, at the engine bay.
func _ensure_flash() -> void:
	if _flash != null:
		return
	_flash = OmniLight3D.new()
	_flash.light_color = FLASH_COLOR
	_flash.light_energy = 0.0
	_flash.omni_range = FLASH_RANGE
	_flash.shadow_enabled = false
	_flash.position = _emitters.engine_bay()
	add_child(_flash)


## The fireball of the wreck.
func _ensure_fireball() -> void:
	if _fireball != null:
		return
	_fireball = Sprite3D.new()
	_fireball.texture = FxAssets.fireball_texture()
	_fireball.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_fireball.shaded = false
	_fireball.pixel_size = FIREBALL_WIDTH / float(maxi(FxAssets.fireball_texture().get_width(), 1))
	# The fireball is HDR, so it glows in the night.
	_fireball.modulate = Color(1.0, 0.75, 0.45, 0.0) * FIREBALL_HDR
	_fireball.visible = false
	_fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireball.position = _emitters.engine_bay()
	add_child(_fireball)
