extends Node
## The dent paint must stay in sync with the shared car paint (the shaders unit owns
## res://shaders/car_paint.gdshader): every uniform of the shared paint must exist in the
## damage paint, with the same type, so a car never changes its look when it is dented.

const CAR_PAINT := preload("res://shaders/car_paint.gdshader")
const DENT_PAINT := preload("res://damage/dent_paint.gdshader")

var _failures: int = 0


func _ready() -> void:
	var source := _uniforms(CAR_PAINT)
	var mine := _uniforms(DENT_PAINT)
	var missing: Array[String] = []
	var wrong: Array[String] = []
	for name: StringName in source:
		if not mine.has(name):
			missing.append(String(name))
		elif int(mine[name]) != int(source[name]):
			wrong.append("%s (%d -> %d)" % [name, int(source[name]), int(mine[name])])
	_expect("the damage paint has every uniform of the car paint", missing.is_empty())
	if not missing.is_empty():
		print("  missing: ", missing)
	_expect("the types of the shared uniforms are the same", wrong.is_empty())
	if not wrong.is_empty():
		print("  wrong type: ", wrong)
	# The instance uniforms (the paint colour of a car) must be there too.
	var source_instances := _instance_uniforms(CAR_PAINT)
	var mine_instances := _instance_uniforms(DENT_PAINT)
	for name: String in source_instances:
		_expect("the damage paint keeps the instance uniform %s" % name,
				mine_instances.has(name))
	# The damage paint is generated from the shared paint: the hash of the source is written
	# into its header, so a change of the shared paint that was not generated fails the test.
	var digest := _source_hash()
	var written := _written_hash(DENT_PAINT)
	_expect("the damage paint was generated from the current car paint (%s)" % digest,
			written == digest)
	print(("FAIL" if _failures > 0 else "PASS") + " paint sync (%d failures)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## The hash of the shared car paint (the same one the generator writes).
func _source_hash() -> String:
	var file := FileAccess.open("res://shaders/car_paint.gdshader", FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().sha256_text().substr(0, 16)


## The hash the generator wrote into the header of the damage paint.
func _written_hash(shader: Shader) -> String:
	for line in shader.code.split("\n"):
		var text := line.strip_edges()
		if not text.begins_with("// source hash:"):
			continue
		return text.trim_prefix("// source hash:").strip_edges()
	return ""


## The uniforms of a shader and their types.
func _uniforms(shader: Shader) -> Dictionary:
	var out: Dictionary = {}
	for u in shader.get_shader_uniform_list():
		out[StringName(u["name"])] = int(u["type"])
	return out


## The instance uniforms of a shader (they are not in the uniform list).
func _instance_uniforms(shader: Shader) -> Array[String]:
	var out: Array[String] = []
	for line in shader.code.split("\n"):
		var text := line.strip_edges()
		if not text.begins_with("instance uniform"):
			continue
		var parts := text.split(" ", false)
		if parts.size() >= 4:
			out.append(parts[3])
	return out


func _expect(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
