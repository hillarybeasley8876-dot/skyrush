extends RefCounted
# Builds the benchmark night-city: wet ground, 400 buildings, neon strips, 50 omni lights.
# All numbers are fixed (seeded RNG) so every run renders the same frame.

const GRID := 20            # 20 x 20 = 400 buildings
const PITCH := 32.0         # metres between building centres (street ~12 m wide)
const STREET_X := 336.0     # street between building columns 9 and 10
const NEON := [Color("#ff2bd6"), Color("#00e5ff"), Color("#ffb000"), Color("#7a5cff")]

var root: Node3D
var env: Environment
var camera: Camera3D
var sun: DirectionalLight3D
var omnis: Array[OmniLight3D] = []
var rng := RandomNumberGenerator.new()
var minimal := false   # true: env + ground + sun only (instancing tests add their own content)

func build(parent: Node) -> Node3D:
	rng.seed = 1337
	root = Node3D.new()
	root.name = "BenchWorld"
	parent.add_child(root)
	_env()
	_ground()
	if not minimal:
		_buildings()
	_lights()
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 1500.0
	camera.position = Vector3(STREET_X, 1.4, 40.0)   # mid-city street, driver-ish height
	camera.basis = Basis.looking_at(Vector3(STREET_X, 4.0, -300.0) - camera.position)  # look_at() fails before add_child
	root.add_child(camera)
	camera.make_current()
	return root

func _env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#05060a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#1b2030")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

func _ground() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.02
	var rough := NoiseTexture2D.new()
	rough.width = 512
	rough.height = 512
	rough.seamless = true
	rough.noise = noise
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#15171c")
	m.roughness = 1.0
	m.roughness_texture = rough          # dark cells = puddles (low roughness)
	m.metallic_specular = 0.6
	m.uv1_scale = Vector3(40, 40, 1)
	var pm := PlaneMesh.new()
	pm.size = Vector2(GRID * PITCH + 200, GRID * PITCH + 200)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(GRID * PITCH * 0.5 - PITCH * 0.5, 0, -GRID * PITCH * 0.5)
	root.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var ws := WorldBoundaryShape3D.new()
	cs.shape = ws
	body.add_child(cs)
	root.add_child(body)

func _buildings() -> void:
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("#2a2f3a")
	bm.roughness = 0.55
	bm.metallic = 0.3
	var neon_mats: Array[StandardMaterial3D] = []
	for c in NEON:
		var nm := StandardMaterial3D.new()
		nm.albedo_color = Color.BLACK
		nm.emission_enabled = true
		nm.emission = c
		nm.emission_energy_multiplier = 6.0
		neon_mats.append(nm)
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	var strip := BoxMesh.new()
	strip.size = Vector3(1, 0.35, 1)
	for ix in GRID:
		for iz in GRID:
			if ix == 0 and iz < 3: continue
			var h := rng.randf_range(12.0, 90.0)
			var w := rng.randf_range(16.0, 22.0)
			var b := MeshInstance3D.new()
			b.mesh = box
			b.material_override = bm
			b.scale = Vector3(w, h, w)
			b.position = Vector3(ix * PITCH + PITCH, h * 0.5, -iz * PITCH)
			root.add_child(b)
			var s := MeshInstance3D.new()   # neon band on the street face
			s.mesh = strip
			s.material_override = neon_mats[(ix + iz) % neon_mats.size()]
			s.scale = Vector3(w + 0.4, 1.0, w + 0.4)
			s.position = b.position + Vector3(0, rng.randf_range(-0.3, 0.3) * h, 0)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(s)

func _lights() -> void:
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#8fa6ff")
	sun.light_energy = 0.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	for i in (0 if minimal else 50):   # street lights along the camera's street, then scattered
		var o := OmniLight3D.new()
		o.light_color = NEON[i % NEON.size()]
		o.light_energy = 3.0
		o.omni_range = 14.0
		o.position = Vector3(STREET_X + (4.0 if i % 2 == 0 else -4.0), 5.0, 20.0 - i * 12.0)
		root.add_child(o)
		omnis.append(o)
