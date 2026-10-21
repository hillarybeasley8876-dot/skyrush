extends RefCounted
# Instancing / culling benchmark content for bench.gd (--minimal --features=res://scripts/inst_features.gd).
# Config tokens joined by "+": content (mm20k, mm20k_chunk, mi2k, mi2k_mats, mi10k, city2k), city options
# (hlod, occ), camera (street default, air). Example: city2k+occ+street
const N_SIDE := 45            # 45 x 45 = 2025 buildings (~2k)
const PITCH := 30.0
const HALF := N_SIDE * PITCH * 0.5

var w
var vps: Array[Viewport] = []
var cams: Array[Camera3D] = []
var holder: Node3D
var last_bake_ms := -1
var bmesh: BoxMesh
var bmat: StandardMaterial3D

func _init(world, viewport: Viewport, extra_vps: Array[Viewport], extra_cams: Array[Camera3D]) -> void:
	w = world
	vps = [viewport]
	vps.append_array(extra_vps)
	cams = [world.camera]
	cams.append_array(extra_cams)
	bmesh = BoxMesh.new()          # ~1k-triangle "detailed building"
	bmesh.size = Vector3(1, 1, 1)
	bmesh.subdivide_width = 8
	bmesh.subdivide_height = 8
	bmesh.subdivide_depth = 8
	bmat = StandardMaterial3D.new()
	bmat.albedo_color = Color("#2a2f3a")

func reset() -> void:
	if holder:
		holder.free()
	holder = Node3D.new()
	w.root.add_child(holder)
	for v in vps:
		v.use_occlusion_culling = false

func apply(cfg: String) -> void:
	reset()
	var toks := cfg.split("+")
	var cam_air := toks.has("air")
	for t in toks:
		match t:
			"mm20k": _multimesh(20000, 1)
			"mm20k_chunk": _multimesh(20000, 10)
			"mi2k": _separate(2000, false)
			"mi2k_mats": _separate(2000, true)
			"mi2k_iu": _separate_instance_uniform(2000)
			"mi10k": _separate(10000, false)
			"city2k": _city(toks.has("hlod"), toks.has("occ"))
			"occ":
				for v in vps: v.use_occlusion_culling = true
			"hlod", "air", "street", "empty": pass
			_: push_error("unknown token " + t)
	var eye := Vector3(0, 150, HALF + 60) if cam_air else Vector3(PITCH * 0.5, 1.6, HALF - 10)
	var target := Vector3(0, 0, -HALF * 0.3) if cam_air else Vector3(PITCH * 0.5, 4, -HALF)
	for c in cams:
		c.far = 3000.0
		c.transform = Transform3D(Basis.looking_at(target - eye), eye)

func _rand_xform(i: int, n: int) -> Transform3D:
	var side := int(ceil(sqrt(float(n))))
	var span := N_SIDE * PITCH
	var x := (i % side) * span / side - span * 0.5
	var z := (i / side) * span / side - span * 0.5
	return Transform3D(Basis().scaled(Vector3(0.4, 4.0, 0.4)), Vector3(x + 2.0, 2.0, z + 2.0))

func _multimesh(n: int, chunks_per_side: int) -> void:
	var cyl := CylinderMesh.new()     # street prop: 16 sides, ~64 tris
	cyl.radial_segments = 16
	cyl.rings = 1
	cyl.material = bmat
	var per := chunks_per_side * chunks_per_side
	var buckets: Array = []
	buckets.resize(per)
	for k in per: buckets[k] = []
	var span := N_SIDE * PITCH
	for i in n:
		var xf := _rand_xform(i, n)
		var cx := clampi(int((xf.origin.x + span * 0.5) / span * chunks_per_side), 0, chunks_per_side - 1)
		var cz := clampi(int((xf.origin.z + span * 0.5) / span * chunks_per_side), 0, chunks_per_side - 1)
		buckets[cz * chunks_per_side + cx].append(xf)
	for b in buckets:
		if b.is_empty(): continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cyl
		mm.instance_count = b.size()
		for j in b.size(): mm.set_instance_transform(j, b[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if chunks_per_side > 1:
			mmi.visibility_range_end = 400.0
		holder.add_child(mmi)

func _separate(n: int, unique_mats: bool) -> void:
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = bmesh
		if unique_mats:
			var m := bmat.duplicate() as StandardMaterial3D
			m.albedo_color = Color.from_hsv(float(i % 97) / 97.0, 0.4, 0.3)
			mi.material_override = m
		else:
			mi.material_override = bmat
		mi.transform = _rand_xform(i, n).scaled_local(Vector3(10, 2, 10))
		holder.add_child(mi)

func _city(hlod: bool, occ: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var block := 9                                  # 9 x 9 buildings per HLOD block -> 25 blocks
	var items: Array[Dictionary] = []
	for ix in N_SIDE:
		for iz in N_SIDE:
			var h := rng.randf_range(12.0, 90.0)
			var s := rng.randf_range(18.0, 22.0)
			items.append({"key": Vector2i(ix / block, iz / block), "size": Vector3(s, h, s),
				"pos": Vector3(ix * PITCH - HALF + PITCH, h * 0.5, iz * PITCH - HALF)})
	var proxies := {}
	if hlod:   # pass 1: build every proxy WITH its mesh before any child points at it
		var tools := {}
		for it in items:
			if not tools.has(it.key):
				tools[it.key] = SurfaceTool.new()
				tools[it.key].begin(Mesh.PRIMITIVE_TRIANGLES)
			var bx := BoxMesh.new()                 # 12-tri proxy box merged into the block mesh
			bx.size = it.size
			tools[it.key].append_from(bx, 0, Transform3D(Basis(), it.pos))
		for key in tools:
			var node := MeshInstance3D.new()
			node.mesh = tools[key].commit()
			node.material_override = bmat
			node.visibility_range_begin = 350.0     # proxy only beyond 350 m; children shown inside
			node.visibility_range_begin_margin = 20.0
			holder.add_child(node)
			proxies[key] = node
	for it in items:   # pass 2: detailed buildings (+ occluders)
		var mi := MeshInstance3D.new()
		mi.mesh = bmesh
		mi.material_override = bmat
		mi.transform = Transform3D(Basis().scaled(it.size), it.pos)
		holder.add_child(mi)
		if hlod:
			mi.visibility_parent = mi.get_path_to(proxies[it.key])
		if occ:
			var oc := OccluderInstance3D.new()
			var bo := BoxOccluder3D.new()
			bo.size = it.size * 0.95
			oc.occluder = bo
			oc.position = it.pos
			holder.add_child(oc)

func _separate_instance_uniform(n: int) -> void:
	var sh := Shader.new()   # per-object colour WITHOUT a per-object material
	sh.code = "shader_type spatial;\ninstance uniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() { ALBEDO = tint.rgb; EMISSION = tint.rgb * 2.0; }\n"
	var m := ShaderMaterial.new()
	m.shader = sh
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = bmesh
		mi.material_override = m
		mi.set_instance_shader_parameter(&"tint", Color.from_hsv(float(i % 97) / 97.0, 0.8, 0.8))
		mi.transform = _rand_xform(i, n).scaled_local(Vector3(10, 2, 10))
		holder.add_child(mi)
