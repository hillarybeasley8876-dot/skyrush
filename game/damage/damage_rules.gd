extends RefCounted
## The damage numbers of ref/gameplay/DOSSIER.md §7.2 - §7.3 and the takedown rules of §3.5.
## Pure functions only: no scene, no autoloads, so the unit test drives every rule directly.

## Impact ratio limits (dossier 7.2): below 0.35 a scrape, below 0.70 a hit, above a head-on.
const SCRAPE_LIMIT := 0.35
const HIT_LIMIT := 0.70
## A head-on hit at 30 m/s (108 km/h) wrecks the car whatever its HP is.
const WRECK_HEAD_ON := 30.0
## The street furniture that stands (trees, masts, shelters, planters, billboards; the lamps break away) costs this share of the
## damage of a wall, and it never wrecks a car in one hit: a tree is not a wall of concrete. A tree at 150 km/h costs 40 HP, at
## 250 km/h it still wrecks the car.
const PROP_DAMAGE_SCALE := 0.4
## The physics layer of the street furniture (CONTRACTS: layer 3).
const PROP_LAYER := 1 << 2
## damage_HP = HP_COEFF * max(0, v_n - HP_FLOOR)^2 * k_mass
const HP_COEFF := 0.15
const HP_FLOOR := 5.0
## A traffic glance costs the player 1 HP, grinding against a wall 2 HP per second.
const GRAZE_HP := 1.0
const GRIND_HP_PER_S := 2.0
## The impact ratio of a traffic glance (dossier 7.2).
const GRAZE_IMPACT := 0.3
## The longest grind between two reports of the same contact.
const IMPACT_WINDOW := 0.15
## The front-ram bonus: the car that hits with its front takes half the damage.
const RAM_FACTOR := 0.5
const RAM_DOT := 0.7
## A vertical takedown (landing on a roof) is fatal for the car below.
const VERTICAL_HP := 999.0
const VERTICAL_SPEED := 5.0
const VERTICAL_NORMAL := 0.7
## Takedown credit (dossier 3.5): a wreck within 2 s of the player's last contact.
const TAKEDOWN_WINDOW := 2.0
const TAKEDOWN_MIN_SPEED := 3.0
## The streak window and the rewards.
const STREAK_WINDOW := 10.0
const TAKEDOWN_POINTS := 50
const STREAK_BONUS := 25
## The psyche-out: the player is close but never touched the car.
const PSYCHE_OUT_RANGE := 8.0


## The closing speed along the contact normal (dossier 7.2). The normal points out of the
## other body, so the closing direction is -normal.
static func closing_speed(v_rel: Vector3, normal: Vector3) -> float:
	return maxf(0.0, -v_rel.dot(normal))


## 0 = a scrape along the surface, 1 = a head-on hit.
static func impact_ratio(v_rel: Vector3, normal: Vector3) -> float:
	return clampf(closing_speed(v_rel, normal) / maxf(v_rel.length(), 0.1), 0.0, 1.0)


## k_mass (dossier 7.3): 1.0 against the static world, 2*m_other/(m_self+m_other) car to car.
static func k_mass(m_self: float, m_other: float, other_dynamic: bool) -> float:
	if not other_dynamic or m_other <= 0.0:
		return 1.0
	return 2.0 * m_other / maxf(m_self + m_other, 1.0)


## The HP of one hit.
static func damage_hp(v_n: float, k: float) -> float:
	return HP_COEFF * pow(maxf(0.0, v_n - HP_FLOOR), 2.0) * k


## 0.5 when the hit landed with the front of the car, 1.0 otherwise.
static func ram_factor(forward: Vector3, normal: Vector3) -> float:
	return RAM_FACTOR if forward.dot(-normal) > RAM_DOT else 1.0


## True when one car landed on the roof of the other one. The rule is symmetric: it does not
## matter which of the two cars reports the contact, the car below is the one that is hit.
static func is_vertical(n: Vector3, v_rel: Vector3) -> bool:
	return absf(n.y) > VERTICAL_NORMAL and absf(v_rel.y) >= VERTICAL_SPEED


## The points of a takedown with the given streak length (1 = the first of the streak).
static func takedown_points(streak: int) -> int:
	return TAKEDOWN_POINTS + STREAK_BONUS * maxi(streak - 1, 0)
