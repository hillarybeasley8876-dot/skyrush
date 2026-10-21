extends "res://audio/emitter_collection.gd"
## The world emitters: the collection of emitter_collection.gd plus the two sources that need
## their own logic — the police sirens and the river bed.
##
## The sirens alternate between the wail and the yelp: every patrol car has its own countdown,
## so no two cars switch in the same scan, and the switch is a crossfade (both samples keep
## playing, so it never restarts a sample and never cuts). The river bed plays while the player
## is near a "river" point of interest of the world.

## How often a police car switches between the wail and the yelp (s).
var _yelp_period := Tuning.POLICE_YELP_PERIOD_S
## The serial of the last siren (it spreads the sirens over the yelp period).
var _siren_serial := 0


## The number of sirens that play the yelp (the rest play the wail).
func yelp_count() -> int:
	var count := 0
	for e in _emitters:
		if bool(e["yelp"]):
			count += 1
	return count


## The state of every siren ("w" = the wail, "y" = the yelp) — the test counts the switches.
func siren_states() -> PackedStringArray:
	var out := PackedStringArray()
	for e in _emitters:
		var voice := _entry_voice(e)
		if voice == null or voice.id != &"siren_wail":
			continue
		out.append("y" if bool(e["yelp"]) else "w")
	return out


## The countdown of a siren to its first switch: the cars are spread over the half period, so
## they never switch together.
func _siren_timer(id: StringName) -> float:
	if id != &"siren_wail":
		return 0.0
	var half := _yelp_period * 0.5
	var count := maxi(1, Tuning.POLICE_EMITTER_MAX)
	# the spread is smaller than the half period, so no car switches in the same scan as another
	var spread := float(_siren_serial % count) * half / float(count + 1)
	_siren_serial += 1
	return half - spread


## The sirens and the river bed.
func _update_sources() -> void:
	_update_sirens()
	_update_river()


## A high heat or a close police car switches that car's siren to the yelp; at a high heat the
## wail and the yelp alternate (each car has its own countdown, so they do not switch together).
func _update_sirens() -> void:
	var player := Game.player
	var heat_yelp := heat >= Tuning.HEAT_YELP_FROM
	for e in _emitters:
		var voice := _entry_voice(e)
		if voice == null or voice.id != &"siren_wail":
			continue
		var target := _entry_target(e)
		if target == null:
			continue
		var distance := Tuning.EMITTER_FAR_DISTANCE_M
		if player != null and is_instance_valid(player):
			distance = target.global_position.distance_to(player.global_position)
		var close := distance <= Tuning.POLICE_YELP_RANGE_M
		# the timer counts down to the next switch, every car has its own
		var timer := float(e["yelp_timer"]) - Tuning.EMITTER_SCAN_INTERVAL_S
		if timer <= 0.0:
			timer += _yelp_period * 0.5
			e["alternate"] = not bool(e["alternate"])
		e["yelp_timer"] = timer
		var alternate := heat_yelp and bool(e["alternate"])
		var want_yelp := close or alternate
		if want_yelp != bool(e["yelp"]):
			e["yelp"] = want_yelp
			# the crossfade: both samples keep playing, so the switch never cuts
			voice.set_mode(1.0 if want_yelp else 0.0)


## The river bed plays when the player is near the river (the world publishes "river" points).
func _update_river() -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var world := Game.world
	if world == null:
		return
	var origin := player.global_position
	var river_pos := Vector3.ZERO
	var have_river := false
	var distance := Tuning.EMITTER_FAR_DISTANCE_M
	for poi in world.get_points_of_interest():
		if StringName(poi.get("kind", "")) != &"river":
			continue
		var pos: Vector3 = poi.get("position", Vector3.ZERO)
		have_river = true
		var d := origin.distance_to(pos)
		if d < distance:
			distance = d
			river_pos = pos
	var index := _river_index()
	if not have_river or distance > Tuning.RIVER_EMITTER_RANGE_M:
		if index >= 0:
			_drop(index)
		return
	if index < 0:
		_attach_river(river_pos)
		return
	# the bed follows the player along the river
	var voice := _entry_voice(_emitters[index])
	if voice != null:
		voice.position = river_pos


## The index of the river emitter (-1 when there is none).
func _river_index() -> int:
	for i in _emitters.size():
		var voice := _entry_voice(_emitters[i])
		if voice != null and voice.id == &"river_ambience":
			return i
	return -1


## Creates the river bed at the nearest point of the river.
func _attach_river(position: Vector3) -> void:
	var stream := SfxLibrary.stream(&"river_ambience", SfxLibrary.SFX_DIR, true)
	if stream == null:
		return
	var voice := EmitterVoice.new()
	voice.setup(self, [stream], &"river_ambience", Tuning.RIVER_EMITTER_DB,
			Tuning.RIVER_UNIT_SIZE_M, null)
	voice.position = position
	voice.set_paused(_paused)
	_emitters.append({
		"voice": voice, "target": null, "callable": Callable(), "id": &"river_ambience",
		"player": voice.player, "yelp": false, "alternate": false, "yelp_timer": 0.0,
	})
