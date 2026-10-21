extends RefCounted
## The paint-scrape mask of one car (dossier §7.5 A): a 1024x1024 atlas in the space of the
## car, split into 5 regions (left, right, front, rear, roof).
##
## The atlas is packed so that every region gets at least 150 px/m on both of its axes
## (the sides are 4.8 m long and the roof 1.9 m wide, so a 1024^2 sheet is the smallest
## that fits them all). R = the damage, G = the direction of the slide (0..PI), so the
## scratches of the shader follow the direction the car slid in.
##
## The brushes are cached: a hit never builds one, it only blends the one it needs. The
## masks themselves come from a small pool, so a city full of cars does not hold a texture
## per car.

const SIZE := 1024
## The gutter between two regions, in pixels.
const GUTTER := 4
## The pixels per metre every region gets (dossier §7.5 A wants a sharp scrape).
const TARGET_PPM := 150.0
## The scrape streak: a streak along the slide, not a disc.
const STREAK_BASE := 0.15
const STREAK_PER_VN := 0.03
const STREAK_MAX := 1.2
const STREAK_WIDTH_FACTOR := 0.5
## The buckets of the brush (the length and the width of the streak, in pixels) and the
## levels of the intensity. The brushes are cached, so the buckets must be few.
const LENGTH_BUCKETS := [32, 64, 96]
const WIDTH_BUCKETS := [12, 24]
const PEAKS := [0.35, 0.6, 0.8, 1.0]
## The number of directions the slide is quantised to (the G channel of the mask).
const ANGLE_BUCKETS := 8
## The intensity of a scrape: it follows the closing speed and how square the hit was.
const INTENSITY_BASE := 0.35
const INTENSITY_PER_VN := 0.04
const INTENSITY_MAX := 1.0
## The share of the intensity that a glancing hit keeps.
const INTENSITY_GRAZE := 0.5
var data: Image = null
var texture: ImageTexture = null
var dirty: bool = false
## The number of uploads of this mask (the test proves that the scrape reaches the GPU).
var upload_count: int = 0
var car_min: Vector3 = Vector3(-0.95, 0.0, -2.3)
var car_size: Vector3 = Vector3(1.9, 1.45, 4.6)
## The pixel rect of every region: left, right, front, rear, roof.
var rects: Array[Vector4] = []
## The pixels per metre of the atlas.
var ppm: float = TARGET_PPM
## The rects that were painted (they are cleared when the mask goes back to the pool).
var _used: Array[Rect2i] = []
## The cached brushes, by their size, direction, angle and level.
static var _brushes: Dictionary = {}

## The region of the atlas a car-space normal points at (the same rule as the shader).
static func region_of(normal: Vector3) -> int:
	if absf(normal.y) > 0.7:
		return 4
	if absf(normal.x) > absf(normal.z):
		return 0 if normal.x < 0.0 else 1
	return 2 if normal.z < 0.0 else 3


## The pixel rect of every region of a car of this size.
##
## The roof is tall and narrow, the sides are short and wide: the roof takes the left
## column, the sides and the front and the rear stack up in the column next to it.
static func rects_for(minimum: Vector3, size: Vector3) -> Array[Vector4]:
	var ppm := _ppm_of(size)
	var roof_w := maxi(int(round(size.x * ppm)), 4)
	var roof_h := maxi(int(round(size.z * ppm)), 4)
	var side_w := maxi(int(round(size.z * ppm)), 4)
	var side_h := maxi(int(round(size.y * ppm)), 4)
	var front_w := maxi(int(round(size.x * ppm)), 4)
	var right_x := float(roof_w + GUTTER)
	return [
		Vector4(right_x, 0.0, float(side_w), float(side_h)),   # the left side
		Vector4(right_x, float(side_h + GUTTER), float(side_w), float(side_h)),  # the right side
		Vector4(right_x, float(2 * (side_h + GUTTER)), float(front_w), float(side_h)),
		Vector4(right_x, float(3 * (side_h + GUTTER)), float(front_w), float(side_h)),
		Vector4(0.0, 0.0, float(roof_w), float(roof_h)),        # the roof
	]


## The pixels per metre: 150 when the car fits, less when it is a long bus.
static func _ppm_of(size: Vector3) -> float:
	var by_width := (SIZE - GUTTER) / maxf(size.x + size.z, 0.01)
	var by_height := (SIZE - 3 * GUTTER) / maxf(3.0 * size.y, 0.01)
	return minf(TARGET_PPM, minf(by_width, by_height))


## Sets the mask up for a car of this box. The mask must be clean (the pool gives a clean
## one), so the painted rects are not cleared here.
func setup(minimum: Vector3, size: Vector3) -> void:
	car_min = minimum
	car_size = size
	ppm = _ppm_of(size)
	rects = rects_for(minimum, size)
	if data == null:
		data = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		data.fill(Color(0.0, 0.0, 0.0, 1.0))
		texture = ImageTexture.create_from_image(data)


## Uploads the mask to the GPU (the caller decides when).
func upload() -> void:
	if texture == null or data == null:
		return
	texture.update(data)
	dirty = false
	upload_count += 1


## The share of the mask that is damaged, 0..1 (an estimate, the test only needs a number).
func coverage() -> float:
	if data == null:
		return 0.0
	var total := 0
	for rect in _used:
		total += rect.size.x * rect.size.y
	return clampf(float(total) / float(SIZE * SIZE), 0.0, 1.0)


## The mask goes back to the pool: the painted rects are cleared, the rest is left alone.
func clear() -> void:
	if data == null:
		return
	for rect in _used:
		data.fill_rect(rect, Color(0.0, 0.0, 0.0, 1.0))
	_used.clear()
	dirty = true


## The mask is clean and the GPU knows it: the next car that takes this mask must not see
## the scrape of the car before it.
func clean() -> void:
	clear()
	if texture == null or data == null:
		return
	texture.update(data)
	dirty = false


# --- the scrape -------------------------------------------------------------------------------
## Paints the scrape into the mask: a streak along the slide, in the region of the panel that
## was hit. The brush is clipped to its own region, so a scrape on the left never bleeds into
## the region of the right.
func splat(car_point: Vector3, car_normal: Vector3, slide: Vector3, v_n: float,
		radius: float, impact: float = 1.0) -> void:
	if data == null or rects.is_empty():
		return
	var region := region_of(car_normal)
	var rect: Vector4 = rects[region]
	var local := _region_local(region, car_point)
	var centre := Vector2(rect.x, rect.y) + Vector2(local.x * rect.z, local.y * rect.w)
	# The centre of the scrape stays in its region: a hit that lands outside the box of the
	# car (a flat panel, a hit at the edge) is painted at the edge of the region.
	centre.x = clampf(centre.x, rect.x, rect.x + rect.z)
	centre.y = clampf(centre.y, rect.y, rect.y + rect.w)
	# The slide, in the plane of the region: the scratch lines run along it.
	var plane := _region_plane(region)
	var along := Vector2(slide.dot(plane[0]), slide.dot(plane[1]))
	if along.length() < 0.01:
		along = Vector2(1.0, 0.0)
	var angle := fposmod(atan2(along.y, along.x), PI)
	var angle_frac := angle / PI
	var vertical: bool = absf(along.y) > absf(along.x)
	# The streak: its length follows the sliding speed, its width half the dent radius.
	var length_m := clampf(STREAK_BASE + v_n * STREAK_PER_VN, STREAK_BASE, STREAK_MAX)
	var width_m := maxf(radius * STREAK_WIDTH_FACTOR, 0.02)
	var length_px := _bucket(length_m * ppm, LENGTH_BUCKETS)
	var width_px := _bucket(width_m * ppm, WIDTH_BUCKETS)
	# A scrape only dulls the clear coat, a hard hit tears the paint off.
	var raw := clampf(INTENSITY_BASE + v_n * INTENSITY_PER_VN, INTENSITY_BASE,
			INTENSITY_MAX) * (INTENSITY_GRAZE + (1.0 - INTENSITY_GRAZE) * impact)
	var peak: float = PEAKS[0]
	for level: float in PEAKS:
		if absf(level - raw) < absf(peak - raw):
			peak = level
	var brush := _brush(length_px, width_px, vertical, angle_frac, peak)
	if brush == null:
		return
	var size := brush.get_size()
	var at := Vector2i(int(centre.x) - size.x / 2, int(centre.y) - size.y / 2)
	# The brush is clipped to its region, never shifted.
	var region_rect := Rect2i(int(rect.x), int(rect.y), int(rect.z), int(rect.w))
	var clipped := Rect2i(at, size).intersection(region_rect)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	var src := Rect2i(clipped.position - at, clipped.size)
	data.blend_rect(brush, src, clipped.position)
	_used.append(clipped)
	dirty = true


## The 0..1 coordinates of a car-space point in its region.
func _region_local(region: int, point: Vector3) -> Vector2:
	match region:
		0, 1:
			return Vector2((point.z - car_min.z) / maxf(car_size.z, 0.01),
					(point.y - car_min.y) / maxf(car_size.y, 0.01))
		4:
			return Vector2((point.x - car_min.x) / maxf(car_size.x, 0.01),
					(point.z - car_min.z) / maxf(car_size.z, 0.01))
	return Vector2((point.x - car_min.x) / maxf(car_size.x, 0.01),
			(point.y - car_min.y) / maxf(car_size.y, 0.01))


## The two axes of the plane of a region, in car space (the sides are z/y, the front and the
## rear x/y, the roof x/z).
static func _region_plane(region: int) -> Array:
	match region:
		0, 1:
			return [Vector3.BACK, Vector3.UP]
		4:
			return [Vector3.RIGHT, Vector3.BACK]
	return [Vector3.RIGHT, Vector3.UP]


## The bucket of the brush that fits a size.
static func _bucket(value: float, buckets: Array) -> int:
	var best: int = int(buckets[0])
	var distance := INF
	for size: int in buckets:
		var d := absf(float(size) - value)
		if d < distance:
			distance = d
			best = size
	return best


## The cached brush of a streak: a smooth ellipse. The alpha is the profile, the red channel
## the damage and the green channel the direction of the slide.
##
## The profile is built at a quarter of the size and scaled up: a brush of 80x20 pixels
## would cost 1.7 ms to build pixel by pixel, and a hit has a budget of 1 ms. The quarter
## is the smallest that keeps the plateau of the middle (the bare core of the scrape).
static func _brush(length_px: int, width_px: int, vertical: bool, angle_frac: float,
		peak: float) -> Image:
	var key := "%d:%d:%s:%.3f:%.2f" % [length_px, width_px, vertical, angle_frac, peak]
	if _brushes.has(key):
		return _brushes[key] as Image
	var w: int = width_px if vertical else length_px
	var h: int = length_px if vertical else width_px
	var tw: int = maxi(int(w / 4), 4)
	var th: int = maxi(int(h / 4), 4)
	var bytes := PackedByteArray()
	bytes.resize(tw * th * 4)
	var angle_byte := int(clampf(angle_frac, 0.0, 1.0) * 255.0)
	for y in th:
		for x in tw:
			var dx := (float(x) + 0.5) / float(tw) * 2.0 - 1.0
			var dy := (float(y) + 0.5) / float(th) * 2.0 - 1.0
			var d := sqrt(dx * dx + dy * dy)
			var profile := 0.0
			if d < 1.0:
				# The profile has a plateau in the middle, so the scrape has a bare core, a
				# ring of chipped paint and a scuffed edge instead of one flat patch.
				profile = smoothstep(1.0, 0.45, d) * peak
			var i := (y * tw + x) * 4
			bytes[i] = 255
			bytes[i + 1] = angle_byte
			bytes[i + 2] = 0
			bytes[i + 3] = int(clampf(profile, 0.0, 1.0) * 255.0)
	var template := Image.create_from_data(tw, th, false, Image.FORMAT_RGBA8, bytes)
	template.resize(w, h, Image.INTERPOLATE_BILINEAR)
	_brushes[key] = template
	return template

