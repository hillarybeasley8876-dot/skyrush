## SKYRUSH look-dev scene: an elevated-road crossing at night with every material from the DOSSIER.
## Run (from repo root):
##   Godot --path ref/art/lookdev --resolution 1280x720 -- out=res://renders/lookdev.png frames=150
extends Node3D

const M := preload("res://materials.gd")
const E := preload("res://env_recipe.gd")
const B := preload("res://builder.gd")

var _frames := 150
var _out := "res://renders/lookdev.png"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
	add_child(E.make_world_environment())
	B.build_road(self)
	B.build_city(self)
	B.build_lights(self)
	_build_hero_samples()
	add_child(_make_probe())
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.position = Vector3(0.6, 1.45, 4.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 3.2, -60.0))
	_capture.call_deferred()

func _build_hero_samples() -> void:
	var s := SphereMesh.new()
	s.radius = 0.55
	s.height = 1.1
	B.mesh(self, s, M.car_paint(), Vector3(-1.6, 0.55, -3.5))
	var c := SphereMesh.new()
	c.radius = 0.35
	c.height = 0.7
	B.mesh(self, c, M.chrome(), Vector3(1.9, 0.35, -3.0))
	var tyre := TorusMesh.new()
	tyre.inner_radius = 0.22
	tyre.outer_radius = 0.36
	var ty := B.mesh(self, tyre, M.tyre_rubber(), Vector3(0.9, 0.36, -2.4))
	ty.rotation_degrees = Vector3(0, 0, 90)
	B.mesh(self, B.box(Vector3(0.8, 0.4, 0.05)), M.tinted_glass(), Vector3(-0.4, 0.5, -1.8))

func _make_probe() -> ReflectionProbe:
	# One static probe per ~120-170 m of road: captures OUR street so puddles reflect our lights, not the HDRI.
	var rp := ReflectionProbe.new()
	rp.size = Vector3(60, 40, 170)
	rp.position = Vector3(0, 12, -70)
	rp.origin_offset = Vector3(0, -10, 60)   # capture point ~2 m above the road, near the player
	rp.box_projection = true
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	rp.intensity = 1.0
	rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	rp.blend_distance = 4.0
	return rp

func _capture() -> void:
	for i in _frames:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	var err := img.save_png(_out)
	print("LOOKDEV_SAVED ", _out, " err=", err)
	get_tree().quit()
