extends Node
## The damage numbers of dossier §7.2 - §7.3 and the tier table of §7.4.

const Rules := preload("res://damage/damage_rules.gd")
const CarDamage := preload("res://damage/car_damage.gd")
const Parts := preload("res://damage/part_catalog.gd")

var _failures: int = 0


func _ready() -> void:
	_check_hp_examples()
	_check_k_mass()
	_check_classification()
	_check_ram_bonus()
	_check_tiers()
	_check_parts()
	_check_points()
	print(("FAIL" if _failures > 0 else "PASS") + " damage formula (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## The examples of dossier 7.3: v_n 10 -> 4 HP, 20 -> 34, 25 -> 60, 28 -> 79.
func _check_hp_examples() -> void:
	_approx("hp at 10 m/s", Rules.damage_hp(10.0, 1.0), 3.75)
	_approx("hp at 20 m/s", Rules.damage_hp(20.0, 1.0), 33.75)
	_approx("hp at 25 m/s", Rules.damage_hp(25.0, 1.0), 60.0)
	_approx("hp at 28 m/s", Rules.damage_hp(28.0, 1.0), 79.35)
	_approx("hp below the 5 m/s floor", Rules.damage_hp(4.0, 1.0), 0.0)
	_approx("hp at 30 m/s", Rules.damage_hp(30.0, 1.0), 93.75)


func _check_k_mass() -> void:
	_approx("k_mass against the world", Rules.k_mass(1900.0, 0.0, false), 1.0)
	_approx("k_mass of equal cars", Rules.k_mass(1900.0, 1900.0, true), 1.0)
	_approx("k_mass of a 2.6 t SUV", Rules.k_mass(1900.0, 2600.0, true), 1.1556, 0.001)


func _check_classification() -> void:
	var head_on := Vector3(0.0, 0.0, -20.0)
	var normal := Vector3(0.0, 0.0, 1.0)
	_approx("closing speed of a head-on hit", Rules.closing_speed(head_on, normal), 20.0)
	_approx("impact ratio of a head-on hit", Rules.impact_ratio(head_on, normal), 1.0)
	var scrape := Vector3(18.0, 0.0, -4.0)
	_approx("impact ratio of a scrape", Rules.impact_ratio(scrape, normal), 0.22, 0.01)
	var hit := Vector3(12.0, 0.0, -10.0)
	_approx("impact ratio of a 50 degree hit", Rules.impact_ratio(hit, normal), 0.64, 0.02)
	_expect("a vertical landing is vertical",
			Rules.is_vertical(Vector3.UP, Vector3(0.0, -6.0, 0.0)))
	_expect("a slow landing is not vertical",
			not Rules.is_vertical(Vector3.UP, Vector3(0.0, -3.0, 0.0)))


func _check_ram_bonus() -> void:
	var forward := Vector3(0.0, 0.0, -1.0)
	_approx("a front hit takes half", Rules.ram_factor(forward, Vector3(0.0, 0.0, 1.0)), 0.5)
	_approx("a rear hit takes all", Rules.ram_factor(forward, Vector3(0.0, 0.0, -1.0)), 1.0)


func _check_tiers() -> void:
	_expect("a full car is clean", CarDamage.tier_of(100.0, 100.0) == CarDamage.Tier.CLEAN)
	_expect("60 % is light", CarDamage.tier_of(60.0, 100.0) == CarDamage.Tier.LIGHT)
	_expect("61 % is clean", CarDamage.tier_of(61.0, 100.0) == CarDamage.Tier.CLEAN)
	_expect("30 % is heavy", CarDamage.tier_of(30.0, 100.0) == CarDamage.Tier.HEAVY)
	_expect("31 % is light", CarDamage.tier_of(31.0, 100.0) == CarDamage.Tier.LIGHT)
	_expect("0 % is wrecked", CarDamage.tier_of(0.0, 100.0) == CarDamage.Tier.WRECKED)


func _check_parts() -> void:
	var bumper := Parts.part_for(&"Bumper_F")
	_expect("the front bumper is detachable", not bumper.is_empty())
	_expect("a 23 m/s front hit takes the bumper",
			Parts.should_detach(bumper, Parts.Zone.FRONT, 23.0, 0.0, false, 1.0))
	_expect("a 10 m/s front hit keeps the bumper",
			not Parts.should_detach(bumper, Parts.Zone.FRONT, 10.0, 0.0, false, 1.0))
	_expect("45 HP of front damage takes the bumper",
			Parts.should_detach(bumper, Parts.Zone.FRONT, 5.0, 45.0, false, 0.5))
	_expect("a rear hit does not take the front bumper",
			not Parts.should_detach(bumper, Parts.Zone.REAR, 30.0, 0.0, false, 1.0))
	var wing := Parts.part_for(&"Wing")
	_expect("an 18 m/s rear hit takes the wing",
			Parts.should_detach(wing, Parts.Zone.REAR, 18.0, 0.0, false, 1.0))
	var wheel := Parts.part_for(&"Wheel_FL")
	_expect("a wheel only comes off on a violent wreck",
			Parts.should_detach(wheel, Parts.Zone.ANY, 40.0, 0.0, true, 0.8))
	_expect("a gentle wreck keeps the wheels",
			not Parts.should_detach(wheel, Parts.Zone.ANY, 40.0, 0.0, true, 0.4))
	_expect("the npc door names are found", not Parts.part_for(&"Door_FL").is_empty())
	_expect("the npc mirror names are found", not Parts.part_for(&"Mirror_L").is_empty())


func _check_points() -> void:
	_expect("the first takedown is 50 points", Rules.takedown_points(1) == 50)
	_expect("the second takedown is 75 points", Rules.takedown_points(2) == 75)
	_expect("the fifth takedown is 150 points", Rules.takedown_points(5) == 150)


func _approx(label: String, got: float, want: float, tolerance: float = 0.02) -> void:
	if absf(got - want) > tolerance:
		_failures += 1
		print("FAIL %s: got %.4f, want %.4f" % [label, got, want])
	else:
		print("PASS %s (%.4f)" % [label, got])


func _expect(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
