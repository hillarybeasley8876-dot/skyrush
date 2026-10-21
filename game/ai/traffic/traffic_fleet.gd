class_name TrafficFleet
extends RefCounted
## The traffic fleet: which models, colours and liveries the AI traffic uses.
##
## Variety (dossier 6.1): 6 models x 8 colours, 5 % taxis, 8 % vans, 4 % buses/trucks.
## Colours follow the art dossier 4.7 traffic mix (China's fleet is mostly white, black, silver):
## white 35 %, black 20 %, silver 25 %, blue 8 %, grey 12 %; taxis are the fictional teal 申城出租.

const TAXI_COLOR := Color("1e8c8a")

## id -> {name, type, length, width, height, mass, health, glb}
## type: &"car", &"taxi", &"van", &"bus_truck"
const MODELS: Dictionary = {
	&"sedan_ev": {"name": "轿车", "type": &"car", "length": 4.85, "width": 1.90, "height": 1.47,
		"mass": 1500.0, "health": 40.0, "glb": "sedan_ev"},
	&"hatch_ev": {"name": "两厢", "type": &"car", "length": 3.95, "width": 1.77, "height": 1.55,
		"mass": 1350.0, "health": 40.0, "glb": "hatch_ev"},
	&"suv_ev": {"name": "SUV", "type": &"car", "length": 4.75, "width": 1.93, "height": 1.68,
		"mass": 1900.0, "health": 45.0, "glb": "suv_ev"},
	&"taxi_ev": {"name": "申城出租", "type": &"taxi", "length": 4.60, "width": 1.90, "height": 1.50,
		"mass": 1500.0, "health": 40.0, "glb": "taxi"},
	&"robotaxi": {"name": "无人出租车", "type": &"taxi", "length": 4.60, "width": 1.90, "height": 1.50,
		"mass": 1500.0, "health": 40.0, "glb": "robotaxi"},
	&"van_ev": {"name": "厢式货车", "type": &"van", "length": 5.30, "width": 2.00, "height": 2.10,
		"mass": 2400.0, "health": 60.0, "glb": "van"},
	&"bus_city": {"name": "公交车", "type": &"bus_truck", "length": 12.00, "width": 2.55, "height": 3.20,
		"mass": 12000.0, "health": 300.0, "glb": "bus"},
	&"truck_box": {"name": "货车", "type": &"bus_truck", "length": 7.50, "width": 2.35, "height": 3.30,
		"mass": 9000.0, "health": 200.0, "glb": "truck"},
}

## Colour mix of the ordinary fleet (art dossier 4.7).
const COLOURS: Array = [
	{"color": Color("e8e8e6"), "weight": 0.35},
	{"color": Color("9da3a8"), "weight": 0.25},
	{"color": Color("0e0f11"), "weight": 0.20},
	{"color": Color("5a5f63"), "weight": 0.12},
	{"color": Color("1f3a5f"), "weight": 0.08},
]


## The share of the fleet of every type: 83 % cars, 5 % taxis, 8 % vans, 4 % buses and trucks.
const TYPE_SHARE: Dictionary = {
	&"car": 0.83,
	&"taxi": 0.05,
	&"van": 0.08,
	&"bus_truck": 0.04,
}


## The number of cars of every model in a fleet of `total` cars.
##
## The pool is built with this mix, so a spawn never has to build a car in the middle of the
## game (the first car of a model takes 28 ms, the rest 0.4 ms).
static func fleet_counts(total: int) -> Dictionary:
	var counts: Dictionary = {}
	for id: StringName in MODELS:
		counts[id] = 0
	var per_type: Dictionary = {}
	for id: StringName in MODELS:
		var type: StringName = MODELS[id]["type"]
		per_type[type] = int(per_type.get(type, 0)) + 1
	for id: StringName in MODELS:
		var type: StringName = MODELS[id]["type"]
		var share := float(TYPE_SHARE.get(type, 0.0)) / float(maxi(int(per_type[type]), 1))
		counts[id] = int(round(share * float(total)))
	return counts


## Picks a model for a new car, honouring the type mix (5 % taxi, 8 % van, 4 % bus/truck).
static func pick_model(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf()
	var type: StringName = &"car"
	if roll < 0.05:
		type = &"taxi"
	elif roll < 0.13:
		type = &"van"
	elif roll < 0.17:
		type = &"bus_truck"
	var pool: Array[StringName] = []
	for id: StringName in MODELS:
		if MODELS[id]["type"] == type:
			pool.append(id)
	if pool.is_empty():
		pool = [&"sedan_ev"]
	var chosen: StringName = pool[rng.randi() % pool.size()]
	return {"id": chosen, "data": MODELS[chosen]}


## Picks the body colour of a car. Taxis always wear the 申城出租 teal.
static func pick_colour(rng: RandomNumberGenerator, type: StringName) -> Color:
	if type == &"taxi":
		return TAXI_COLOR
	var roll := rng.randf()
	var acc := 0.0
	for entry in COLOURS:
		acc += float((entry as Dictionary)["weight"])
		if roll <= acc:
			return (entry as Dictionary)["color"] as Color
	return Color("9da3a8")


## The mass (kg) of a model.
static func mass_of(model_id: StringName) -> float:
	return float(MODELS.get(model_id, MODELS[&"sedan_ev"])["mass"])


## The health (HP) of a model (dossier 7.3: traffic sedan 40, van 60, bus 300).
static func health_of(model_id: StringName) -> float:
	return float(MODELS.get(model_id, MODELS[&"sedan_ev"])["health"])
