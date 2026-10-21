extends RefCounted
## The single N2 resource (2 COPV slots of 100), the nitro (C), the mini boost (W) and the QQ
## speed-cap stacking (dossier 1.4, 5.2, 8.1). Pure logic, no engine calls, so it can be unit
## tested on its own.
##
## The nitro and the mini boost burn on their own timers: a 小喷 fired 0.2 s into a burning
## nitro stacks on top of it (that is what the QQ cap table describes).

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")

## N2 units, 0..200 (slot 1 = 0..100, slot 2 = 100..200).
var n2: float = 100.0
## &"", &"nitro", &"mini", &"air_mini", &"landing", &"launch", &"charge".
var kind: StringName = &""
## Seconds left of the running boost.
var time_left: float = 0.0
## Speed cap in m/s for the current boost combination.
var speed_cap: float = DriveTuning.V_TOP
## Seconds left of the open mini-boost window (小喷).
var mini_window: float = 0.0
## Uncommitted drift gauge in slots (filled while drifting, committed on a clean exit).
var pending_gauge: float = 0.0
## True on the tick a boost ended: the car raises Events.boost_ended once and clears the flag.
var ended: bool = false

var _nitro_time: float = 0.0
var _mini_time: float = 0.0
var _mini_kind: StringName = &"mini"
var _launch_time: float = 0.0
var _charge_time: float = 0.0
## Boost history: {"k": "C"/"W", "t": seconds}. Used to rebuild the stacking pattern.
var _stack: Array[Dictionary] = []
var _clock: float = 0.0
var _base_top: float = DriveTuning.V_TOP


## Clears every boost timer (a respawn or a reset).
func reset() -> void:
	if kind != &"":
		ended = true
	_nitro_time = 0.0
	_mini_time = 0.0
	_launch_time = 0.0
	_charge_time = 0.0
	mini_window = 0.0
	kind = &""
	time_left = 0.0
	speed_cap = _base_top
	_stack.clear()


func setup(base_top: float, start_n2: float) -> void:
	_base_top = base_top
	n2 = start_n2
	_stack.clear()
	_clock = 0.0
	_nitro_time = 0.0
	_mini_time = 0.0
	_launch_time = 0.0
	_charge_time = 0.0


func tick(dt: float) -> void:
	_clock += dt
	var was: StringName = kind
	_nitro_time = maxf(_nitro_time - dt, 0.0)
	_mini_time = maxf(_mini_time - dt, 0.0)
	_launch_time = maxf(_launch_time - dt, 0.0)
	_charge_time = maxf(_charge_time - dt, 0.0)
	if mini_window > 0.0:
		mini_window = maxf(mini_window - dt, 0.0)
	_prune_stack()
	_update_kind()
	speed_cap = _current_cap()
	if was != &"" and kind == &"":
		ended = true


func _update_kind() -> void:
	if _launch_time > 0.0:
		kind = &"launch"
		time_left = _launch_time
	elif _charge_time > 0.0:
		kind = &"charge"
		time_left = _charge_time
	elif _nitro_time > 0.0:
		kind = &"nitro"
		time_left = _nitro_time
	elif _mini_time > 0.0:
		kind = _mini_kind
		time_left = _mini_time
	else:
		kind = &""
		time_left = 0.0


## The connected boost pattern, e.g. "CWW". Boosts fired too late (or a W-W pair that was too
## close or too far apart) break the chain, exactly like the QQ timing rules.
func pattern() -> String:
	var s: String = ""
	var newer_t: float = 0.0
	for i in range(_stack.size() - 1, -1, -1):
		var cur: Dictionary = _stack[i]
		if s.is_empty():
			s = String(cur["k"])
			newer_t = float(cur["t"])
			continue
		# The gap between this boost and the next newer one in the chain.
		var gap: float = newer_t - float(cur["t"])
		var ok: bool = true
		if String(cur["k"]) == "C":
			ok = gap <= BoostTuning.CW_GAP_MAX
		else:
			ok = gap >= BoostTuning.WW_GAP_MIN and gap <= BoostTuning.WW_GAP_MAX
		if not ok:
			break
		s = String(cur["k"]) + s
		newer_t = float(cur["t"])
	return s


## Speed cap in m/s for a boost pattern (dossier 1.4). Pure function, unit tested.
static func cap_for_pattern(base: float, pat: String) -> float:
	var cap: float = base
	var has_c: bool = pat.contains("C")
	var w_total: int = pat.count("W")
	if has_c:
		cap += BoostTuning.N2_EXTRA_V
	if w_total == 0:
		return minf(cap, DriveTuning.V_CAP)
	if not has_c:
		# Without nitro the mini boosts overwrite each other.
		return minf(cap + BoostTuning.MINI_EXTRA_V, DriveTuning.V_CAP)
	var c_index: int = pat.rfind("C")
	var w_after: int = pat.length() - c_index - 1
	var w_before: int = c_index
	# The QQ table: CW 0.3, WCW 0.4, CWW 0.8, WCWW 0.9. A third W adds nothing.
	var coeff: float = BoostTuning.STACK["CWW"]
	if w_after == 1:
		coeff = BoostTuning.STACK["WCW"] if w_before > 0 else BoostTuning.STACK["CW"]
	elif w_after == 2:
		coeff = BoostTuning.STACK["WCWW"] if w_before > 0 else BoostTuning.STACK["CWW"]
	else:
		coeff = BoostTuning.STACK["WCWW"] if w_before > 0 else BoostTuning.STACK["CWW"]
	return minf(cap + coeff * BoostTuning.MINI_EXTRA_V, DriveTuning.V_CAP)


func _current_cap() -> float:
	if _nitro_time > 0.0 and _mini_time > 0.0:
		return cap_for_pattern(_base_top, pattern())
	if _nitro_time > 0.0:
		return cap_for_pattern(_base_top, "C")
	if _mini_time > 0.0:
		return cap_for_pattern(_base_top, "W")
	return _base_top


## Fires the nitro: needs one full slot (100 units), burns for N2_TIME seconds.
func use_nitro() -> bool:
	if n2 < BoostTuning.N2_SLOT:
		return false
	n2 -= BoostTuning.N2_SLOT
	_nitro_time = BoostTuning.N2_TIME
	_push("C")
	_update_kind()
	speed_cap = _current_cap()
	return true


## Fires the mini boost (小喷). Only allowed while the window is open.
func use_mini() -> bool:
	if mini_window <= 0.0:
		return false
	mini_window = 0.0
	_mini_time = BoostTuning.MINI_TIME
	_mini_kind = &"mini"
	_push("W")
	_update_kind()
	speed_cap = _current_cap()
	return true


## Air mini boost (空喷): free, once per jump, 0.5 s.
func use_air_mini() -> bool:
	if _mini_time > 0.0:
		return false
	_mini_time = AirTuning.AIR_MINI_TIME
	_mini_kind = &"air_mini"
	_push("W")
	_update_kind()
	speed_cap = _current_cap()
	return true


## Landing mini boost (落地喷).
func use_landing_mini() -> bool:
	if _mini_time > 0.0:
		return false
	_mini_time = BoostTuning.MINI_TIME
	_mini_kind = &"landing"
	_push("W")
	_update_kind()
	speed_cap = _current_cap()
	return true


## Thruster launch (完美起步).
func start_launch() -> void:
	_launch_time = BoostTuning.LAUNCH_TIME
	_update_kind()
	speed_cap = _base_top


## Charge bay boost (闪充).
func start_charge() -> void:
	_charge_time = BoostTuning.CHARGE_TIME
	_update_kind()
	speed_cap = _base_top


## Extra acceleration in m/s^2 from the running boost.
func boost_accel() -> float:
	if _launch_time > 0.0:
		return BoostTuning.LAUNCH_ACCEL
	if _charge_time > 0.0:
		return BoostTuning.CHARGE_ACCEL
	if _nitro_time > 0.0:
		return BoostTuning.N2_ACCEL
	if _mini_time > 0.0:
		return BoostTuning.MINI_ACCEL
	return 0.0


## Opens the mini-boost window (called on a clean drift exit).
func open_mini_window() -> void:
	mini_window = BoostTuning.MINI_WINDOW


## Commits the pending drift gauge (in slots) into the N2 tank. Returns the units granted.
func commit_gauge(slots: float) -> float:
	var units: float = minf(slots * BoostTuning.N2_SLOT, BoostTuning.N2_MAX - n2)
	n2 = minf(n2 + units, BoostTuning.N2_MAX)
	pending_gauge = 0.0
	return units


## Spends N2 units; returns false when the tank is too empty.
func spend_n2(amount: float) -> bool:
	if n2 < amount:
		return false
	n2 -= amount
	return true


## Self-refilling compressor: +3 /s while grounded and idle, up to the first slot.
func self_refill(dt: float, grounded: bool, thrusting: bool) -> void:
	if not grounded or thrusting or n2 >= BoostTuning.N2_SLOT:
		return
	n2 = minf(n2 + BoostTuning.SELF_REFILL_PER_S * dt, BoostTuning.N2_SLOT)


## True when the window is open and the player was fast enough for a perfect mini boost.
func mini_is_perfect() -> bool:
	return mini_window > 0.0 and mini_window > BoostTuning.MINI_WINDOW - BoostTuning.MINI_PERFECT


func _push(k: String) -> void:
	_stack.append({"k": k, "t": _clock})
	if _stack.size() > BoostTuning.STACK_MAX:
		_stack.remove_at(0)


func _prune_stack() -> void:
	while _stack.size() > 0:
		var first: Dictionary = _stack[0]
		if _clock - float(first["t"]) > BoostTuning.STACK_PRUNE:
			_stack.remove_at(0)
		else:
			break
