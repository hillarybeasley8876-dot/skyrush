extends RefCounted
# Applies one benchmark configuration ("glow", "ssr+vfog", ...) on top of a reset baseline.
const Radial := preload("res://scripts/radial_blur_effect.gd")

var w        # bench_world.gd instance
var vp: Viewport                    # main viewport (kept for clarity)
var vps: Array[Viewport] = []       # main + amplification SubViewports: viewport-level settings go to all
var cams: Array[Camera3D] = []
var extras: Array[Node] = []
var last_bake_ms := -1

func _init(world, viewport: Viewport, extra_vps: Array[Viewport], extra_cams: Array[Camera3D]) -> void:
	w = world
	vp = viewport
	vps = [viewport]
	vps.append_array(extra_vps)
	cams = [world.camera]
	cams.append_array(extra_cams)

func _vp_set(prop: StringName, value) -> void:
	for v in vps: v.set(prop, value)

func _cam_set(prop: StringName, value) -> void:
	for c in cams: c.set(prop, value)

func reset() -> void:
	var e: Environment = w.env
	e.glow_enabled = false
	e.ssr_enabled = false
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.volumetric_fog_enabled = false
	e.fog_enabled = false
	_vp_set(&"use_taa", false)
	_vp_set(&"msaa_3d", Viewport.MSAA_DISABLED)
	_vp_set(&"screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED)
	_scale(Viewport.SCALING_3D_MODE_BILINEAR, 1.0)
	_cam_set(&"compositor", null)
	_cam_set(&"cull_mask", 0xFFFFF)
	for o in w.omnis: o.shadow_enabled = false
	for n in extras: n.queue_free()
	extras.clear()

func apply(cfg: String) -> void:
	reset()
	for f in cfg.split("+"):
		_apply_one(f)

func _add(n: Node) -> Node:
	w.root.add_child(n)
	extras.append(n)
	return n

func _apply_one(f: String) -> void:
	var e: Environment = w.env
	match f:
		"base": pass
		"glow":
			e.glow_enabled = true
			e.glow_intensity = 0.8
			e.glow_bloom = 0.05
			e.glow_hdr_threshold = 1.0
		"ssr": e.ssr_enabled = true
		"ssao": e.ssao_enabled = true
		"ssil": e.ssil_enabled = true
		"fog":
			e.fog_enabled = true
			e.fog_density = 0.004
		"vfog":
			e.volumetric_fog_enabled = true
			e.volumetric_fog_density = 0.015
			e.volumetric_fog_albedo = Color("#8090b0")
		"sdfgi": e.sdfgi_enabled = true
		"voxelgi": _voxelgi()
		"rprobe_once": _probe(ReflectionProbe.UPDATE_ONCE)
		"rprobe_always": _probe(ReflectionProbe.UPDATE_ALWAYS)
		"decals64": _decals(64)
		"particles20k": _particles(4, 5000, true)
		"particles20k_notrail": _particles(4, 5000, false)
		"particles4k": _particles(4, 1000, true)
		"glass24": _glass(24)
		"area16": _area(16, false, false)
		"area4": _area(4, false, false)
		"area16_r10": _area(16, false, false, 10.0)
		"area16_shadow": _area(16, true, false)
		"area16_tex": _area(16, false, true)
		"shadow8":
			for i in 8: w.omnis[i].shadow_enabled = true
		"taa": _vp_set(&"use_taa", true)
		"fxaa": _vp_set(&"screen_space_aa", Viewport.SCREEN_SPACE_AA_FXAA)
		"smaa": _vp_set(&"screen_space_aa", Viewport.SCREEN_SPACE_AA_SMAA)
		"msaa2": _vp_set(&"msaa_3d", Viewport.MSAA_2X)
		"msaa4": _vp_set(&"msaa_3d", Viewport.MSAA_4X)
		"ss050": _scale(Viewport.SCALING_3D_MODE_BILINEAR, 0.5)
		"ss150": _scale(Viewport.SCALING_3D_MODE_BILINEAR, 1.5)
		"ss200": _scale(Viewport.SCALING_3D_MODE_BILINEAR, 2.0)
		"nodraw": _cam_set(&"cull_mask", 0)
		"fsr1_077": _scale(Viewport.SCALING_3D_MODE_FSR, 0.77)
		"fsr2_067": _scale(Viewport.SCALING_3D_MODE_FSR2, 0.67)
		"mfxs_067": _scale(Viewport.SCALING_3D_MODE_METALFX_SPATIAL, 0.67)
		"mfxt_067": _scale(Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, 0.67)
		"radial":
			var c := Compositor.new()
			var fx = Radial.new()
			fx.strength = 0.15
			c.compositor_effects = [fx]
			_cam_set(&"compositor", c)
		_: push_error("unknown feature " + f)

func _scale(mode: int, s: float) -> void:
	_vp_set(&"scaling_3d_mode", mode)
	_vp_set(&"scaling_3d_scale", s)

func _voxelgi() -> void:
	var gi := VoxelGI.new()
	gi.size = Vector3(160, 100, 400)
	gi.position = Vector3(w.STREET_X, 40, -160)
	_add(gi)
	var t := Time.get_ticks_msec()
	gi.bake(w.root)
	last_bake_ms = Time.get_ticks_msec() - t

func _probe(mode: int) -> void:
	var p := ReflectionProbe.new()
	p.size = Vector3(60, 40, 400)
	p.position = Vector3(w.STREET_X, 10, -160)
	p.update_mode = mode
	p.box_projection = true
	_add(p)

func _decals(n: int) -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.2, 0.8, 1), Color(0.0, 0.9, 1.0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.width = 256
	tex.height = 256
	for i in n:
		var d := Decal.new()
		d.texture_albedo = tex
		d.size = Vector3(4, 2, 4)
		d.position = Vector3(w.STREET_X + (i % 3 - 1) * 3.0, 0.0, 30.0 - i * 6.0)
		_add(d)

func _particles(emitters: int, amount: int, trails: bool) -> void:
	var hf := GPUParticlesCollisionHeightField3D.new()
	hf.size = Vector3(120, 60, 300)
	hf.position = Vector3(w.STREET_X, 20, -100)
	hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_add(hf)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.3
	pm.collision_friction = 0.2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#ffb000")
	mat.use_particle_trails = true
	mat.vertex_color_use_as_albedo = true
	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = 0.04
	ribbon.sections = 4
	ribbon.material = mat
	for i in emitters:
		var p := GPUParticles3D.new()
		p.amount = amount
		p.lifetime = 1.2
		p.process_material = pm
		p.trail_enabled = trails
		p.trail_lifetime = 0.2
		if trails:
			p.draw_pass_1 = ribbon
		else:
			var q := QuadMesh.new()
			q.size = Vector2(0.08, 0.08)
			var qm := mat.duplicate() as StandardMaterial3D
			qm.use_particle_trails = false
			qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			q.material = qm
			p.draw_pass_1 = q
		p.collision_base_size = 0.05
		p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 40, 80))
		p.position = Vector3(w.STREET_X + (i % 2) * 4.0 - 2.0, 0.5, -10.0 - i * 15.0)
		_add(p)

func _glass(n: int) -> void:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.6, 0.85, 1.0, 0.25)
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.refraction_enabled = true
	m.refraction_scale = 0.05
	var q := QuadMesh.new()
	q.size = Vector2(8, 5)
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.position = Vector3(w.STREET_X + (5.5 if i % 2 == 0 else -5.5), 3.0, 10.0 - i * 9.0)
		mi.rotation_degrees = Vector3(0, 90 if i % 2 == 0 else -90, 0)
		_add(mi)

func _area(n: int, shadows: bool, textured: bool, light_range := 25.0) -> void:
	var tex: Texture2D = null
	if textured:   # stand-in for a billboard image: 256 px gradient
		var g := Gradient.new()
		g.colors = PackedColorArray([Color("#ff2bd6"), Color("#00e5ff")])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 256
		gt.height = 128
		tex = gt
	for i in n:   # 4 x 2 m billboards facing the street, alternating sides
		var a := AreaLight3D.new()
		a.area_size = Vector2(4, 2)
		a.area_range = light_range
		a.light_energy = 4.0
		a.light_color = w.NEON[i % w.NEON.size()]
		a.shadow_enabled = shadows
		a.area_texture = tex
		var side := 1.0 if i % 2 == 0 else -1.0
		a.position = Vector3(w.STREET_X + 5.5 * side, 6.0, 10.0 - i * 14.0)
		a.rotation_degrees = Vector3(0, 90.0 * side, 0)
		_add(a)
