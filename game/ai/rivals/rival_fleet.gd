class_name RivalFleet
extends RefCounted
## The six racers of the fictional 申城联赛 and the three difficulty presets.
##
## The names are invented Chinese handles (no real people, no trademarks). The colours are
## muted car paints rather than neon tubes: a grid of six cars must read as paint under the
## city neon, not as six more light sources (ART.md 2: at most ~15 % of a frame may be
## saturated neon).
##
## A race fields five of the six (SPEC 3: the player against five rivals); the one that sits
## out is picked from the route and the difficulty, so every route has its own field.

## One racer: name, colour, skill offset, pace, sponsor, racing number and stripe colour.
const RACERS: Array[Dictionary] = [
	{"name": "浦江闪电", "colour": Color("1e9bd8"), "skill": 0.05, "pace": 1.01,
		"sponsor": "东方霓虹", "number": 7, "stripe": Color("12496b")},
	{"name": "外滩幽灵", "colour": Color("1a1b22"), "skill": 0.02, "pace": 1.00,
		"sponsor": "浦江电讯", "number": 12, "stripe": Color("6a4bc8")},
	{"name": "龙柱猎手", "colour": Color("c8862a"), "skill": -0.03, "pace": 0.99,
		"sponsor": "申城快递", "number": 23, "stripe": Color("5e3d12")},
	{"name": "霓虹小燕", "colour": Color("c2337e"), "skill": 0.06, "pace": 1.02,
		"sponsor": "中石华", "number": 5, "stripe": Color("6b1a4c")},
	{"name": "陆家嘴之刃", "colour": Color("b3242b"), "skill": -0.01, "pace": 1.00,
		"sponsor": "申城闪充", "number": 31, "stripe": Color("5e1116")},
	{"name": "夜行电鳗", "colour": Color("4fa83a"), "skill": 0.00, "pace": 0.99,
		"sponsor": "东方霓虹", "number": 44, "stripe": Color("25491a")},
]

## The difficulty presets (dossier 6.2).
## grip: the clone's "grip skill" A. The Roadster's own tyre limit is applied on top of it
## (see rival_speed.gd), because 32-57 m/s^2 is 3-6 g and no road car has that.
## grip_min/grip_max: the bounds of the grip ratio (a share of the tyre limit of the car).
## rubber_min/max: the rubber band range. rubber_lead/rubber_trail: the share of the gap a
## rival gives back (it leads) or takes (it trails).
## nitro_speed/nitro_fuel: the speed the nitro needs and the fuel it costs.
## mistake_min/max: the seconds between the mistakes.
## drift: whether the rivals may drift at all.
const PRESETS: Dictionary = {
	&"easy": {"grip": 32.0, "grip_min": 0.6, "grip_max": 1.10,
		"rubber_min": 0.88, "rubber_max": 1.03, "rubber_lead": 0.00045, "rubber_trail": 0.0004,
		"nitro_speed": 30.0, "nitro_fuel": 100.0,
		"mistake_min": 25.0, "mistake_max": 40.0, "drift": false},
	&"normal": {"grip": 45.0, "grip_min": 0.6, "grip_max": 1.15,
		"rubber_min": 0.93, "rubber_max": 1.06, "rubber_lead": 0.00045, "rubber_trail": 0.0004,
		"nitro_speed": 30.0, "nitro_fuel": 100.0,
		"mistake_min": 45.0, "mistake_max": 70.0, "drift": true},
	&"hard": {"grip": 57.0, "grip_min": 0.6, "grip_max": 1.15,
		"rubber_min": 0.97, "rubber_max": 1.10, "rubber_lead": 0.00045, "rubber_trail": 0.0004,
		"nitro_speed": 30.0, "nitro_fuel": 100.0,
		"mistake_min": 90.0, "mistake_max": 120.0, "drift": true},
}

## The number of racers in the league.
const COUNT := 6
## The number of rivals that race against the player (SPEC 3: five).
const FIELD_SIZE := 5


## The preset of a difficulty ("easy", "normal", "hard"); unknown names fall back to normal.
static func preset(difficulty: StringName) -> Dictionary:
	return PRESETS.get(difficulty, PRESETS[&"normal"]) as Dictionary


## The data of a racer.
static func racer(index: int) -> Dictionary:
	return RACERS[index % RACERS.size()]


## The display name of the racer at `index` (the index wraps).
static func name_of(index: int) -> String:
	return String(racer(index)["name"])


## The paint colour of the racer at `index` (the index wraps).
static func colour_of(index: int) -> Color:
	return racer(index)["colour"] as Color


## The skill offset of the racer at `index`: a fraction of the grip budget.
static func skill_of(index: int) -> float:
	return float(racer(index)["skill"])


## The pace of the racer at `index`: its own top speed factor (0.99 .. 1.02).
static func pace_of(index: int) -> float:
	return float(racer(index)["pace"])


## The parody sponsor of the racer at `index`.
static func sponsor_of(index: int) -> String:
	return String(racer(index)["sponsor"])


## The racing number of the racer at `index`.
static func number_of(index: int) -> int:
	return int(racer(index)["number"])


## The stripe colour of the racer at `index`: a darker shade of its paint.
static func stripe_of(index: int) -> Color:
	return racer(index)["stripe"] as Color


## The lateral offset of the racer from the racing line (m). The rivals drive their own line
## inside the racing line, the way a real pack does, so they do not fight for the same
## metres of tarmac. The sign alternates with the index (the start grid has two columns).
static func lane_offset_of(index: int) -> float:
	return LANE_OFFSETS[index % LANE_OFFSETS.size()]


## The personal lines of the six racers (m from the racing line). The cars are 1.95 m wide,
## so the lines are at least 2.6 m apart: the field can race side by side without touching.
const LANE_OFFSETS: Array[float] = [-5.25, 5.25, -2.6, 2.6, 0.0, 3.9]


## The field of a race: the indices of the racers that take part.
##
## The one that sits out is picked from the route and the difficulty, so every route has its
## own field and the same route always has the same one.
static func field_of(route_id: String, difficulty: StringName, size: int = FIELD_SIZE) -> Array[int]:
	var out: Array[int] = []
	var start := absi(hash("%s|%s" % [route_id, String(difficulty)])) % COUNT
	for i in size:
		out.append((start + i) % COUNT)
	return out
