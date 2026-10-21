extends RefCounted
## The textures and the materials of the damage effects. They are built once and shared by
## every car (a car must not build a 128^2 texture on every crash).

static var _smoke_texture: Texture2D = null
static var _spark_texture: Texture2D = null
static var _fireball_texture: Texture2D = null
## The quads of the particles, shared by every car: one material means one shader to
## compile, and the compile must not happen on the frame of a crash.
static var _smoke_quad: Mesh = null
static var _spark_quad: Mesh = null


## A soft noise blob for the smoke: a simplex FBM times a radial falloff.
static func smoke_texture() -> Texture2D:
	if _smoke_texture != null:
		return _smoke_texture
	var size := 128
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_octaves = 5
	noise.frequency = 0.035
	noise.seed = 21
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(centre) / (size * 0.5)
			var radial := pow(maxf(1.0 - d * d, 0.0), 1.5)
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(radial * (0.45 + 0.55 * n), 0.0, 1.0)))
	_smoke_texture = ImageTexture.create_from_image(image)
	return _smoke_texture


## A small hot blob for the sparks.
static func spark_texture() -> Texture2D:
	if _spark_texture != null:
		return _spark_texture
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(centre) / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 0.95, 0.85, a * a))
	_spark_texture = ImageTexture.create_from_image(image)
	return _spark_texture


## The blob of the fireball of a wreck: a hot core broken by the noise, so it does not read
## as a soft ball.
static func fireball_texture() -> Texture2D:
	if _fireball_texture != null:
		return _fireball_texture
	var size := 128
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_octaves = 4
	noise.frequency = 0.06
	noise.seed = 7
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(centre) / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# The fire is broken: the edge of the ball is eaten by the noise.
			a = clampf(pow(a, 0.6) * (0.45 + 0.85 * n), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 0.82, 0.55, a))
	_fireball_texture = ImageTexture.create_from_image(image)
	return _fireball_texture


## The quad of the smoke, shared by every car.
static func smoke_quad() -> Mesh:
	if _smoke_quad == null:
		_smoke_quad = soft_quad(Color(0.541, 0.561, 0.588, 0.5), 0.7, smoke_texture(), false,
				true, 0.18)
	return _smoke_quad


## The quad of the sparks, shared by every car.
static func spark_quad() -> Mesh:
	if _spark_quad == null:
		_spark_quad = soft_quad(Color(1.0, 0.78, 0.35), 0.12, spark_texture(), true)
	return _spark_quad


## A soft particle quad: the smoke and the sparks use it.
## `particles` gives the quad the billboard of a particle (it keeps its scale, so the curve
## of the size of the smoke is not thrown away), `emission` makes it read at night.
static func soft_quad(colour: Color, size: float, texture: Texture2D,
		additive: bool = false, particles: bool = false, emission: float = 0.0) -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if particles \
			else BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.4
	material.vertex_color_use_as_albedo = true
	material.albedo_color = colour
	material.albedo_texture = texture
	material.disable_receive_shadows = true
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = colour
		material.emission_energy_multiplier = emission
	if additive:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = material
	return quad
