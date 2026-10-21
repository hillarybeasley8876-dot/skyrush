extends SceneTree
# Drops a sphere on a box; final resting y + process info differ between Jolt and GodotPhysics3D.
var ball: RigidBody3D
var n := 0
func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(20, 1, 20); gs.shape = bs
	ground.add_child(gs); root3d.add_child(ground)
	ball = RigidBody3D.new()
	var cs := CollisionShape3D.new(); var sp := SphereShape3D.new(); sp.radius = 0.5; cs.shape = sp
	ball.add_child(cs); ball.position = Vector3(0, 3, 0); root3d.add_child(ball)
	print("ENGINE_SETTING ", ProjectSettings.get_setting("physics/3d/physics_engine"))
func _physics_process(_d: float) -> bool:
	n += 1
	if n == 120:
		print("BALL_Y %.7f" % ball.position.y)
		print("INFO active=", PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS), " pairs=", PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS), " islands=", PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ISLAND_COUNT))
		return true
	return false
