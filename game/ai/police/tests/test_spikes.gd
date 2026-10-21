extends Node
## The spike strips (ref/gameplay/DOSSIER.md §6.3).
##
##   tools/godot.sh test res://ai/police/tests/test_spikes.gd
##
## A car over a strip gets punctured tyres (the top speed drops to 65 % for eight seconds), the
## police cars drive over their own strips without a problem and the strips lie on the road.

const T := preload("res://ai/police/tests/police_test.gd")
## The top speed of the player (km/h).
const TOP_KMH := 250.0
## The top speed with punctured tyres (km/h).
const PUNCTURED_KMH := 165.0
## The seconds the player needs to reach his top speed.
const ACCEL_TIME := 12.0
## The seconds the punctured car is measured (the puncture lasts eight seconds).
const PUNCTURE_MEASURE := 6.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	# The patrols of the road would take the roles of the test.
	t.director.remove_all_units()
	await _check_puncture(t)
	await _check_top_speed(t)
	await _check_restore(t)
	await _check_two_strips(t)
	await _check_police_car(t)
	await _check_on_the_road(t)
	await _check_geometry(t)
	await _check_sweep(t)
	t.expect(20)
	t.finish()


## The speed cap of a police car (km/h).
func _cop_cap(cop: PoliceCar) -> float:
	var boost: Variant = cop.get("boost")
	if boost == null:
		return TOP_KMH
	return float(boost.get("speed_cap")) * 3.6


## The speed cap of the player (km/h).
func _cap(t: T) -> float:
	var boost: Variant = t.player.get("boost")
	if boost == null:
		return TOP_KMH
	return float(boost.get("speed_cap")) * 3.6


## A strip on the road punctures the tyres of the player.
func _check_puncture(t: T) -> void:
	t.director.debuff.clear()
	var strip := PoliceSpikeStrip.new()
	t.tree.root.add_child(strip)
	strip.global_position = t.player.global_position
	strip.setup(Vector3.RIGHT)
	await t.idle(0.5)
	t.check(t.director.debuff.is_punctured(), "the player is punctured")
	t.check(_cap(t) < PUNCTURED_KMH, "the top speed drops (%.0f km/h)" % _cap(t))
	strip.queue_free()


## The punctured car really is slower: the top speed on the straight.
func _check_top_speed(t: T) -> void:
	t.director.debuff.clear()
	t.player.reset_to(t.straight_start(-800.0))
	await t.drive(ACCEL_TIME, 0.0, 250.0)
	var clean := t.player.get_speed_kmh()
	t.check(clean > 200.0, "the player reaches his top speed (%.0f km/h)" % clean)
	t.director.debuff.puncture(t.player)
	await t.drive(PUNCTURE_MEASURE, 0.0, 250.0)
	var punctured := t.player.get_speed_kmh()
	t.check(punctured <= PUNCTURED_KMH,
			"the punctured car is slower on the straight (%.0f km/h of %.0f)"
			% [punctured, PUNCTURED_KMH])
	t.director.debuff.clear()


## The pursuit ends: the top speed comes back at once.
func _check_restore(t: T) -> void:
	t.director.debuff.puncture(t.player)
	await t.idle(0.2)
	var punctured := _cap(t)
	t.director.debuff.clear()
	await t.idle(0.1)
	t.check(punctured < TOP_KMH - 5.0, "the puncture slows the player (%.0f km/h)" % punctured)
	t.check(_cap(t) > TOP_KMH - 5.0, "the top speed comes back (%.0f km/h)" % _cap(t))


## Two strips in a row do not restore the cap twice.
func _check_two_strips(t: T) -> void:
	t.director.debuff.clear()
	t.director.debuff.puncture(t.player)
	await t.idle(2.0)
	t.director.debuff.puncture(t.player)
	await t.idle(0.2)
	var punctured := _cap(t)
	await t.idle(9.0)
	t.check(punctured < TOP_KMH - 5.0, "the second puncture holds the cap (%.0f km/h)" % punctured)
	t.check(_cap(t) > TOP_KMH - 5.0, "the cap is back when the punctures are over (%.0f km/h)"
				% _cap(t))
	t.director.debuff.clear()


## A police car over a strip is not punctured and does not raise an error.
func _check_police_car(t: T) -> void:
	var cop: PoliceCar = t.director.spawn_unit_at(t.straight_start(-505.0),
			PoliceFleet.Role.PURSUE)
	t.check(cop != null, "the police car is on the road")
	if cop == null:
		return
	var strip := PoliceSpikeStrip.new()
	t.tree.root.add_child(strip)
	strip.global_position = cop.global_position
	strip.setup(Vector3.RIGHT)
	await t.idle(0.3)
	var before := _cop_cap(cop)
	await t.idle(1.0)
	t.check(_cop_cap(cop) > before - 5.0,
			"the police car is not punctured (%.0f -> %.0f km/h)" % [before, _cop_cap(cop)])
	strip.queue_free()
	t.despawn_unit(cop)


## The strips of the units lie on the road.
func _check_on_the_road(t: T) -> void:
	t.director.force_heat(4)
	t.director.spawn_enabled = true
	t.director.blockade.clear_strips()
	t.director.blockade.stripper.timer = 0.5
	# The speed test drove the player off the end of the straight, so he goes back on the road.
	t.player.reset_to(t.straight_start(-500.0))
	# The heat fades when nothing happens, so the test holds it up while the strips are dropped.
	for i in 14:
		t.director.force_heat(4)
		await t.idle(1.0)
	var on_road := 0
	for strip in t.director.strips:
		var space := t.tree.root.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(strip.global_position + Vector3.UP * 5.0,
				strip.global_position - Vector3.UP * 1.0, 1)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			on_road += 1
	t.check(t.director.strips.size() > 0, "the units drop a strip (%d)" % t.director.strips.size())
	t.check(on_road == t.director.strips.size(), "every strip lies on the road (%d of %d)"
			% [on_road, t.director.strips.size()])


## The strip is centred on its node: the cases run from -3.5 m to +3.5 m and the lamp is at
## the right end.
func _check_geometry(t: T) -> void:
	var strip := PoliceSpikeStrip.new()
	t.tree.root.add_child(strip)
	strip.setup(Vector3.BACK)
	strip.global_position = t.player.global_position
	# The strip of the test is not in the list of the dispatcher, so it is ticked here.
	strip.tick(0.6)
	var extent := strip.case_extent()
	t.check(absf(extent.x + 3.5) <= 0.05 and absf(extent.y - 3.5) <= 0.05,
			"the cases run from -3.5 m to +3.5 m (%.2f to %.2f)" % [extent.x, extent.y])
	t.check(strip.lamp_position().x > 3.5, "the lamp is at the right end (%.2f m)"
			% strip.lamp_position().x)
	strip.queue_free()


## The sweep of the review: a car over the spikes is punctured, a car beside them is not.
func _check_sweep(t: T) -> void:
	var strip := PoliceSpikeStrip.new()
	t.tree.root.add_child(strip)
	strip.setup(Vector3.BACK)
	for local_x: float in [-4.5, -3.0, -1.5, 1.5, 3.0, 4.5]:
		t.director.debuff.clear()
		t.player.reset_to(t.straight_start(-500.0))
		strip.global_position = t.player.global_position + Vector3(0.0, 0.0, local_x)
		strip.reset_strip()
		strip.tick(0.5)
		await t.idle(0.2)
		await t.drive(2.0, 0.0, 60.0)
		var punctured := t.director.debuff.is_punctured()
		var inside := absf(local_x) <= 3.0
		t.check(punctured == inside,
				"the car at %.1f m of the strip is %s" % [local_x,
				"punctured" if punctured else "not punctured"])
	strip.queue_free()
	t.director.debuff.clear()
