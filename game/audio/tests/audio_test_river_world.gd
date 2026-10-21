extends WorldBase
## A world double for the audio tests: it publishes the points of interest it is given, so the
## river bed of the world emitters can be tested without the city.

## The points of interest the double publishes (the same shape as the world contract).
var pois: Array[Dictionary] = []


func get_points_of_interest() -> Array[Dictionary]:
	return pois


## Publishes a list of points of interest (the test hands over a plain array).
func set_pois(list: Array) -> void:
	pois.clear()
	for entry in list:
		pois.append(entry)
