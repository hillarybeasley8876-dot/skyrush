extends Resource
## The cached city of the world unit: the lane graph with its links, the routes and the
## placements of the street furniture. The cache is written to a binary .res whose name is the
## hash of the three data files, so it is rebuilt when one of them changes.

@export var lanes: Array[LanePath] = []
@export var routes: Dictionary = {}
@export var furniture: Array[Dictionary] = []
@export var traffic_lights: Array[Dictionary] = []
