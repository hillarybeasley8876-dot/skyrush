extends RefCounted
## The buildings of the city that are not fuel sites: the 派出所 and the covered carports where
## the police lose the player faster.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")
const Heading := preload("res://world/api/heading.gd")

## The size of the police station.
const STATION_SIZE := Vector3(18.0, 9.0, 12.0)
## The height of the blue band with the name.
const STATION_BAND_H := 1.9
## The height of the blue band.
const BAND_Y := 7.0
## The grid of the windows of the police station.
const WINDOW_COLUMNS := 5
const WINDOW_ROWS := 2
const WINDOW_SIZE := Vector3(2.2, 1.6, 0.12)
## The position of the first window of the front.
const WINDOW_X0 := 7.2
const WINDOW_STEP := 3.6
const WINDOW_Y0 := 2.0
const WINDOW_ROW_STEP := 2.4
## The size of the name of the station.
const SIGN_SIZE := Vector2(9.0, 1.9)
## The size of the emblem of the police.
const BADGE_SIZE := 1.2
## The height of the emblem.
const BADGE_Y := 4.8
## The entrance canopy.
const CANOPY_Y := 3.4
const CANOPY_Z := 7.0
## The height of the light bar on the roof.
const BAR_Y := 9.7
## The size of the covered carport.
const CARPORT_SIZE := Vector3(26.0, 4.2, 18.0)
const CARPORT_POSTS := 6
const CARPORT_BAYS := 4

## The signs of the sites that need a generated texture.
var sign_texts: Array[Dictionary] = []


## A covered carport: a roof on columns, lights under it, a sign and the bays of the cars.
func build_hiding(parent: Node3D, poi: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "HidingSpot_" + str(poi.get("id", "poi"))
	root.position = position(poi)
	root.rotation.y = Heading.yaw_from_heading(float(poi.get("heading_deg", 0.0)))
	parent.add_child(root)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	roof.mesh = ProcMeshes.box(Vector3(CARPORT_SIZE.x, 0.5, CARPORT_SIZE.z))
	roof.material_override = ProcMeshes.material("concrete")
	roof.position = Vector3(0, CARPORT_SIZE.y, 0)
	root.add_child(roof)
	var soffit := MeshInstance3D.new()
	soffit.name = "Soffit"
	soffit.mesh = ProcMeshes.box(Vector3(CARPORT_SIZE.x - 1.0, 0.1, CARPORT_SIZE.z - 1.0))
	soffit.material_override = ProcMeshes.glow(Color("d9e8ff"), 1.4)
	soffit.position = Vector3(0, CARPORT_SIZE.y - 0.3, 0)
	root.add_child(soffit)
	for i in CARPORT_POSTS:
		var post := MeshInstance3D.new()
		post.name = "Post_%d" % i
		post.mesh = ProcMeshes.box(Vector3(0.5, CARPORT_SIZE.y, 0.5))
		post.material_override = ProcMeshes.material("concrete")
		post.position = Vector3((float(i % 3) * 2.0 - 1.0) * 10.0, CARPORT_SIZE.y * 0.5,
			(float(i / 3) * 2.0 - 1.0) * 7.0)
		root.add_child(post)
	for i in CARPORT_BAYS:
		var bay := MeshInstance3D.new()
		bay.name = "Bay_%d" % i
		bay.mesh = ProcMeshes.box(Vector3(0.12, 0.02, 5.0))
		bay.material_override = ProcMeshes.material("bay")
		bay.position = Vector3(-9.0 + float(i) * 6.0, 0.03, 0)
		root.add_child(bay)
	var sign := MeshInstance3D.new()
	sign.name = "Sign"
	sign.mesh = ProcMeshes.box(Vector3(4.0, 0.9, 0.14))
	sign.material_override = ProcMeshes.material("sign_green")
	sign.position = Vector3(0, 3.4, 8.9)
	root.add_child(sign)
	sign_texts.append({"sign": sign, "text": "开放车库 OPEN GARAGE", "type": "station",
		"style": "green"})


## A 派出所: white tiled walls, a blue band with the name, a grid of windows with a few lit,
## an entrance canopy, a red and blue light bar and the bays of the parked cars.
## The front of the station faces the road (the heading of the point of interest).
func build_police_station(parent: Node3D, poi: Dictionary, at: Vector3 = Vector3.INF) -> void:
	var root := Node3D.new()
	root.name = "PoliceStation_" + str(poi.get("id", "poi"))
	root.position = position(poi) if at == Vector3.INF else at
	root.rotation.y = Heading.yaw_from_heading(float(poi.get("heading_deg", 0.0)))
	parent.add_child(root)
	var building := MeshInstance3D.new()
	building.name = "Building"
	building.mesh = ProcMeshes.box(STATION_SIZE)
	building.material_override = ProcMeshes.material("police_tile")
	building.position = Vector3(0, STATION_SIZE.y * 0.5, 0)
	root.add_child(building)
	# The blue band with the name of the station.
	var band := MeshInstance3D.new()
	band.name = "Band"
	band.mesh = ProcMeshes.box(Vector3(STATION_SIZE.x + 0.3, STATION_BAND_H, STATION_SIZE.z + 0.3))
	band.material_override = ProcMeshes.material("police_blue")
	band.position = Vector3(0, BAND_Y, 0)
	root.add_child(band)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	roof.mesh = ProcMeshes.box(Vector3(STATION_SIZE.x + 0.7, 0.4, STATION_SIZE.z + 0.7))
	roof.material_override = ProcMeshes.material("concrete")
	roof.position = Vector3(0, STATION_SIZE.y + 0.2, 0)
	root.add_child(roof)
	# The window grid of the front: a fifth of them is lit.
	var lit_count := 0
	for column in WINDOW_COLUMNS:
		for row in WINDOW_ROWS:
			var lit := (column * 3 + row * 5) % 5 == 0
			if lit:
				lit_count += 1
			var window := MeshInstance3D.new()
			window.name = "Window_%d_%d" % [column, row]
			window.mesh = ProcMeshes.box(WINDOW_SIZE)
			window.material_override = ProcMeshes.glow(Color("ffd7a0"), 1.6) if lit \
				else ProcMeshes.material("glass_dark")
			window.position = Vector3(-WINDOW_X0 + float(column) * WINDOW_STEP,
				WINDOW_Y0 + float(row) * WINDOW_ROW_STEP, STATION_SIZE.z * 0.5 + 0.05)
			root.add_child(window)
	# The name of the station on the band, and the emblem of the police.
	var sign := MeshInstance3D.new()
	sign.name = "Sign"
	sign.mesh = ProcMeshes.quad(SIGN_SIZE.x, SIGN_SIZE.y)
	sign.position = Vector3(0, BAND_Y, STATION_SIZE.z * 0.5 + 0.2)
	root.add_child(sign)
	var label := str(poi.get("label", "派出所"))
	sign_texts.append({"sign": sign, "text": "%s POLICE" % label, "type": "station",
		"style": "station"})
	var badge := MeshInstance3D.new()
	badge.name = "Badge"
	badge.mesh = ProcMeshes.quad(BADGE_SIZE, BADGE_SIZE)
	badge.position = Vector3(0, BADGE_Y, STATION_SIZE.z * 0.5 + 0.2)
	root.add_child(badge)
	sign_texts.append({"sign": badge, "text": "警", "type": "station", "style": "badge"})
	# The entrance canopy.
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = ProcMeshes.box(Vector3(6.0, 0.25, 2.6))
	canopy.material_override = ProcMeshes.material("metal")
	canopy.position = Vector3(0, CANOPY_Y, CANOPY_Z)
	root.add_child(canopy)
	for i in 2:
		var post := MeshInstance3D.new()
		post.name = "CanopyPost_%d" % i
		post.mesh = ProcMeshes.cylinder(0.12, CANOPY_Y)
		post.material_override = ProcMeshes.material("metal")
		post.position = Vector3(-2.6 + float(i) * 5.2, CANOPY_Y * 0.5, CANOPY_Z + 1.0)
		root.add_child(post)
	# The light bar on the roof.
	var bar := MeshInstance3D.new()
	bar.name = "LightBar_Red"
	bar.mesh = ProcMeshes.box(Vector3(2.4, 0.3, 0.4))
	bar.material_override = ProcMeshes.glow(Color("ff2030"), 4.0)
	bar.position = Vector3(0, BAR_Y, 0)
	root.add_child(bar)
	var bar_blue := MeshInstance3D.new()
	bar_blue.name = "LightBar_Blue"
	bar_blue.mesh = ProcMeshes.box(Vector3(2.4, 0.3, 0.4))
	bar_blue.material_override = ProcMeshes.glow(Color("2a5cff"), 4.0)
	bar_blue.position = Vector3(0, BAR_Y, -0.5)
	root.add_child(bar_blue)
	# The bays of the parked cars.
	for i in 3:
		var bay := MeshInstance3D.new()
		bay.name = "Bay_%d" % i
		bay.mesh = ProcMeshes.box(Vector3(0.12, 0.02, 5.0))
		bay.material_override = ProcMeshes.material("bay")
		bay.position = Vector3(-7.0 + float(i) * 7.0, 0.03, 10.0)
		root.add_child(bay)


static func position(poi: Dictionary) -> Vector3:
	return Vector3(float(poi.get("x", 0.0)), float(poi.get("y", 0.0)), float(poi.get("z", 0.0)))
