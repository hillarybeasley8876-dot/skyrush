class_name PoliceDebuff
extends RefCounted
## The debuffs of the player: the punctures of the spike strips and the EMP of the drone.
##
## ONE owner: the module remembers the speed cap of the player, combines the multipliers of the
## active debuffs and restores everything when they expire, when the pursuit ends and when the
## player changes. (The proper fix is an `apply_puncture` / `apply_emp` on the ArcadeCar of the
## vehicle unit; see the request in status/police.md.)

## The top speed factor of a punctured tyre (dossier §6.3).
const PUNCTURE_FACTOR := 0.65
## How long the tyres stay punctured (s).
const PUNCTURE_TIME := 8.0
## The speed factor of the EMP pulse (dossier §6.3).
const EMP_FACTOR := 0.7
## How long the EMP pulse lasts (s).
const EMP_TIME := 3.0

var _puncture: float = 0.0
var _emp: float = 0.0
var _player: VehicleBase = null
## The speed cap of the player without the debuffs.
var _base_cap: float = 0.0
## The cap this module wrote last (the boost module changes it when the player uses a boost).
var _applied_cap: float = -1.0
## The N2 of the player, stored while the EMP blocks it.
var _stored_n2: float = 0.0
var _n2_blocked: bool = false


## The tick: the debuffs run out and the cap is kept in sync.
func tick(delta: float, player: VehicleBase) -> void:
	if player == null:
		return
	if player != _player:
		on_player_changed(player)
	_puncture = maxf(_puncture - delta, 0.0)
	if _emp > 0.0:
		_emp = maxf(_emp - delta, 0.0)
		if _emp <= 0.0:
			_restore_n2(player)
	_apply(player)


## A new player: the debuffs of the old car are dropped.
func on_player_changed(player: VehicleBase) -> void:
	_player = player
	_puncture = 0.0
	_emp = 0.0
	_applied_cap = -1.0
	_base_cap = 0.0
	_stored_n2 = 0.0
	_n2_blocked = false


## The pursuit is over: every debuff ends.
func clear() -> void:
	if _player != null and _n2_blocked:
		_restore_n2(_player)
	_puncture = 0.0
	_emp = 0.0
	_applied_cap = -1.0
	_base_cap = 0.0


## A car drove over a spike strip: the tyres are punctured.
func puncture(player: VehicleBase) -> void:
	if player == null:
		return
	_puncture = PUNCTURE_TIME
	if _player != player:
		on_player_changed(player)
	_apply(player)


## The EMP of the drone: the player loses 30 % of his speed and his N2 for three seconds.
func emp(player: VehicleBase) -> void:
	if player == null:
		return
	if _player != player:
		on_player_changed(player)
	_emp = EMP_TIME
	var boost: Variant = player.get("boost")
	if boost != null and not _n2_blocked:
		# The tank is stored, not emptied: it comes back when the pulse is over.
		_stored_n2 = float(boost.get("n2"))
		boost.set("n2", 0.0)
		_n2_blocked = true
	_apply(player)


## True while the player is punctured.
func is_punctured() -> bool:
	return _puncture > 0.0


## True while the EMP pulse lasts.
## Writes the speed cap of the player: the base cap of the boost module times the debuffs.
func _apply(player: VehicleBase) -> void:
	var boost: Variant = player.get("boost")
	if boost == null:
		return
	var current := float(boost.get("speed_cap"))
	if not is_equal_approx(current, _applied_cap):
		# The boost module changed the cap (the player used a boost): that is the new base.
		_base_cap = current
	var factor := 1.0
	if _puncture > 0.0:
		factor *= PUNCTURE_FACTOR
	if _emp > 0.0:
		factor *= EMP_FACTOR
	_applied_cap = _base_cap * factor
	boost.set("speed_cap", _applied_cap)


## Gives the stored N2 back to the player.
func _restore_n2(player: VehicleBase) -> void:
	if not _n2_blocked:
		return
	var boost: Variant = player.get("boost")
	if boost != null:
		boost.set("n2", _stored_n2)
	_stored_n2 = 0.0
	_n2_blocked = false
