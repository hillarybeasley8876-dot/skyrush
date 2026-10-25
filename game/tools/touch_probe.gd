extends Node
## What does a car touch at a place? The player car is put at the place and the shapes that overlap its box (with a margin) are listed:
## the body, the kind of the shape, its size and its place. For the places where a car stops dead (a follow trial, a fuzz drive).
##
##   python tools/gd.py test res://tools/touch_probe.gd -- --timeout=300 --stub=audio,menu,hud,traffic,police,rivals --at=-1491.2,8.9,750.1 --yaw=270
##
## Options: at=x,y,z (the origin of the car), yaw=degrees (the yaw of the car: 0 looks along -Z, 270 looks along -X), margin=m (0.2),
## grow=m (the box is made this much bigger in length, to look AHEAD of the car: 0), mask=n (the collision layers that are asked: 23; 4 is the props alone)

const MAIN := "res://main.tscn"


func _ready() -> void:
	_run.call_deferred()


func _describe(body: CollisionObject3D, index: int) -> String:
	var rid: RID = PhysicsServer3D.body_get_shape(body.get_rid(), index)
	var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(body.get_rid(), index)
	var data: Variant = PhysicsServer3D.shape_get_data(rid)
	var at := body.global_transform * xf
	var yaw := rad_to_deg(atan2(-at.basis.x.z, at.basis.x.x))
	var kind := ""
	if data is Vector3:
		kind = "box %s" % str((data as Vector3) * 2.0)
	elif data is Dictionary and (data as Dictionary).has("faces"):
		kind = "mesh (%d triangles)" % (((data as Dictionary)["faces"] as PackedVector3Array).size() / 3)
	elif data is Dictionary:
		kind = "cylinder r %.2f h %.2f" % [float((data as Dictionary).get("radius", 0.0)), float((data as Dictionary).get("height", 0.0))]
	else:
		kind = str(data).left(40)
	return "%s shape %d %s at (%.1f %.1f %.1f) yaw %.0f" % [body.name, index, kind, at.origin.x, at.origin.y, at.origin.z, yaw]


func _run() -> void:
	var at := String(Game.option("at", "0,1,0")).split(",")
	var yaw := deg_to_rad(float(Game.option("yaw", "0")))
	var margin := float(Game.option("margin", "0.2"))
	var grow := float(Game.option("grow", "0"))
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().create_timer(2.0).timeout
	var car := Game.player as ArcadeCar
	car.reset_to(Transform3D(Basis(Vector3.UP, yaw), Vector3(float(at[0]), float(at[1]), float(at[2]))))
	car.freeze = true
	for i in Engine.physics_ticks_per_second / 4:
		await get_tree().physics_frame
	var shape_node := car.get_node("Collision") as CollisionShape3D if car.has_node("Collision") else car.get_node("Body") as CollisionShape3D
	var box := (shape_node.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size.z += grow
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	var xf := shape_node.global_transform
	xf.origin += -car.global_transform.basis.z * (grow * 0.5)
	query.transform = xf
	query.collision_mask = int(Game.option("mask", "23"))
	query.exclude = [car.get_rid()]
	query.margin = margin
	var hits := get_viewport().world_3d.direct_space_state.intersect_shape(query, 16)
	print("TOUCH the car at (%s %s %s) yaw %.0f: %d shapes within %.2f m" % [at[0], at[1], at[2], rad_to_deg(yaw), hits.size(), margin])
	for hit in hits:
		print("TOUCH   ", _describe(hit["collider"] as CollisionObject3D, int(hit["shape"])))
	get_tree().quit(0)
