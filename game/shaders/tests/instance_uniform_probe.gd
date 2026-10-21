extends Node3D
## Visual probe (shaders unit): how do shader uniforms reach a mesh at runtime?
##
##   tools/godot.sh run res://shaders/tests/instance_uniform_probe.tscn 6
##
## Spheres, left to right:
##   1 green  - PLAIN uniform set on the material        -> must render green
##   2 green  - INSTANCE uniform set on the material      -> must NOT render green
##   3 blue   - INSTANCE uniform overridden per instance -> must render blue
##   4 red    - INSTANCE uniform untouched               -> renders the shader's compile-time default
##
## Counts the green / blue / red pixels in the frame instead of trusting screen coordinates.
## Prints PASS/FAIL per probe and quits with a non-zero code on failure.

const PLAIN_CODE := "shader_type spatial;\nrender_mode unshaded;\nuniform vec3 tint : source_color = vec3(1,0,0);\nvoid fragment() { ALBEDO = tint; }"
const INSTANCE_CODE := "shader_type spatial;\nrender_mode unshaded;\ninstance uniform vec3 tint : source_color = vec3(1,0,0);\nvoid fragment() { ALBEDO = tint; }"

var _cam: Camera3D


func _ready() -> void:
	var plain := ShaderMaterial.new()
	plain.shader = _shader(PLAIN_CODE)
	plain.set_shader_parameter("tint", Color(0, 1, 0))
	_sphere(plain, Vector3(-2.1, 0, 0))

	var inst := ShaderMaterial.new()
	inst.shader = _shader(INSTANCE_CODE)
	inst.set_shader_parameter("tint", Color(0, 1, 0))   # material-level instance default
	_sphere(inst, Vector3(-0.7, 0, 0))

	var override := _sphere(inst, Vector3(0.7, 0, 0))
	override.set_instance_shader_parameter("tint", Color(0, 0, 1))

	_sphere(inst, Vector3(2.1, 0, 0))                    # untouched -> compile-time default (red)

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0, 6)
	_cam.fov = 60.0
	add_child(_cam)
	_cam.look_at(Vector3.ZERO)
	_cam.current = true
	_check.call_deferred()


func _shader(code: String) -> Shader:
	var sh := Shader.new()
	sh.code = code
	return sh


func _sphere(mat: Material, pos: Vector3) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 0.45
	s.height = 0.9
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _check() -> void:
	for i in 20:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var green := 0
	var blue := 0
	var red := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var px := img.get_pixel(x, y)
			if px.g > 0.6 and px.r < 0.4 and px.b < 0.4:
				green += 1
			elif px.b > 0.6 and px.r < 0.4 and px.g < 0.4:
				blue += 1
			elif px.r > 0.6 and px.g < 0.4 and px.b < 0.4:
				red += 1
	print("PROBE counts green=%d blue=%d red=%d" % [green, blue, red])
	var failed := 0
	# One sphere of each colour is expected (sphere 1 green, sphere 3 blue, sphere 4 red).
	if green < 200:
		print("FAIL plain_uniform_material_default green=%d" % green)
		failed += 1
	else:
		print("PASS plain_uniform_material_default")
	if blue < 200:
		print("FAIL instance_uniform_override blue=%d" % blue)
		failed += 1
	else:
		print("PASS instance_uniform_override")
	if red < 200:
		print("FAIL instance_uniform_compile_default red=%d" % red)
		failed += 1
	else:
		print("PASS instance_uniform_compile_default")
	# A material-level INSTANCE default must NOT paint a second green sphere: green should match
	# the one-sphere count of blue, not double it.
	if float(green) > float(blue) * 1.4:
		print("FAIL instance_uniform_material_default_ignored green=%d blue=%d" % [green, blue])
		failed += 1
	else:
		print("PASS instance_uniform_material_default_ignored")
	print("INSTANCE_UNIFORM_PROBE %d failed" % failed)
	get_tree().quit(1 if failed > 0 else 0)
