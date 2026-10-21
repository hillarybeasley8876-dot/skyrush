extends RefCounted
## The takedown credit of dossier 3.5: the player gets the credit for the wreck of a car it
## touched in the last 2 s (or that wrecked itself within 8 m - the psyche-out). The
## takedowns of 10 s in a row make a streak and every takedown is worth points.

const Rules := preload("res://damage/damage_rules.gd")
const CarDamage := preload("res://damage/car_damage.gd")

## The takedowns in a row.
var streak: int = 0

## The labels of dossier §3.5.
const LABEL_TAKEDOWN := "撞毁！"
const LABEL_VERTICAL := "碾压！VERTICAL TAKEDOWN!"
const LABEL_PSYCHE := "心理战！PSYCHE OUT!"

var _streak_until: float = 0.0


## Gives the player the credit for a wreck, when it is owed. `now` is the game clock.
func credit(victim: VehicleBase, state: CarDamage, now: float) -> bool:
	var kind := kind_of(victim)
	if kind == &"":
		return false
	var earned := now - state.last_player_contact <= Rules.TAKEDOWN_WINDOW
	var psyche := false
	if not earned:
		# The psyche-out: the player is close but never touched the car (dossier 3.5).
		var player := Game.player
		psyche = player != null and is_instance_valid(player) \
				and state.last_player_contact < 0.0 \
				and player.global_position.distance_to(victim.global_position) <= Rules.PSYCHE_OUT_RANGE
		earned = psyche
	if not earned:
		return false
	if now <= _streak_until:
		streak += 1
	else:
		streak = 1
	_streak_until = now + Rules.STREAK_WINDOW
	Events.takedown.emit(victim, kind)
	Events.stunt.emit(&"takedown", Rules.takedown_points(streak), _label(state, psyche))
	return true


## The banner label of the takedown (dossier §3.5).
func _label(state: CarDamage, psyche: bool) -> String:
	var label := LABEL_TAKEDOWN
	if state.vertical_credit:
		label = LABEL_VERTICAL
	elif psyche:
		label = LABEL_PSYCHE
	if streak >= 5:
		return "%s 狂暴 RAMPAGE ×%d" % [label, streak]
	if streak >= 2:
		return "%s 连击 ×%d" % [label, streak]
	return label


## The kind of takedown from the team of the victim.
static func kind_of(victim: VehicleBase) -> StringName:
	match victim.team:
		VehicleBase.Team.POLICE:
			return &"police"
		VehicleBase.Team.RIVAL:
			return &"rival"
		VehicleBase.Team.TRAFFIC:
			return &"traffic"
	return &""
