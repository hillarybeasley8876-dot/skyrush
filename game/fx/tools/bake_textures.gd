extends Node
## Texture bake for the fx unit (run once, then the PNGs live in game/fx/textures/).
##   tools/godot.sh test res://fx/tools/bake_textures.gd -- --timeout=280
## Bakes: spark streak, arc streak, air streak, rain streak, tyre track, splash ripple, energy
## ribbon and the flame atlas. Seeded, so the output is deterministic.

const OUT_DIR := "res://fx/textures/"
const TUNE := preload("res://fx/fx_tuning.gd")
const SPARK_W := 32
const SPARK_H := 256
const AIR_W := 16
const AIR_H := 256
const TRACK_W := 256
const TRACK_H := 1024
## The number of tread grooves of the tyre track.
const TRACK_GROOVES := 7
## The contrast of a groove: the rubber between the grooves is much lighter.
const TRACK_GROOVE_MIN := 0.35
## The scuff breaks of the track are at this scale (metres).
const TRACK_SCUFF_METRES := 0.3
const RAIN_W := 32
const RAIN_H := 128
const RIPPLE := 512
const RIBBON_W := 512
const RIBBON_H := 64
## The number of chevron dashes along one energy ribbon.
const RIBBON_DASHES := 4
const FLAME_CELLS := 4
const FLAME_CELL := 256
## The soft edge of a flame lick (pixels).
const FLAME_EDGE := 25.0
## The soft edge of a flame lick in the u units of a cell (u runs from -1 to 1).
const FLAME_EDGE_U := 0.195
## The tongues of a lick split in the top third of the cell.
const FLAME_SPLIT := 0.36
## The empty border of every cell (pixels).
const FLAME_GUTTER := 12.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_bake_spark()
	_bake_arc()
	_bake_air()
	_bake_track()
	_bake_rain()
	_bake_ripple()
	_bake_ribbon()
	_bake_flame()
	print("BAKE done")
	get_tree().quit(0)


func _save(image: Image, name: String) -> void:
	var path := OUT_DIR + name
	var err := image.save_png(path)
	print("BAKE ", name, " ", image.get_width(), "x", image.get_height(), " err=", err)


## 2D fbm, used by the small textures.
func _fbm(noise: FastNoiseLite, x: float, y: float, octaves: int) -> float:
	var total := 0.0
	var amplitude := 1.0
	var frequency := 1.0
	var norm := 0.0
	for i in octaves:
		total += noise.get_noise_2d(x * frequency, y * frequency) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	return total / maxf(norm, 0.001)


## 3D fbm. The z stays unscaled, so the octaves of a cell still line up with the z of the
## sequence: the 16 cells of the atlas are one cloud that evolves.
func _fbm3(noise: FastNoiseLite, x: float, y: float, z: float, octaves: int) -> float:
	var total := 0.0
	var amplitude := 1.0
	var frequency := 1.0
	var norm := 0.0
	for i in octaves:
		total += noise.get_noise_3d(x * frequency, y * frequency, z) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	return total / maxf(norm, 0.001)


## Spark streak: a white-hot head that fades into an orange tail.
func _bake_spark() -> void:
	var img := Image.create(SPARK_W, SPARK_H, false, Image.FORMAT_RGBA8)
	for y in SPARK_H:
		var t := float(y) / float(SPARK_H - 1)  ## 0 = tail, 1 = head
		var head := pow(t, 3.0)
		for x in SPARK_W:
			var fx := absf(float(x) / float(SPARK_W - 1) - 0.5) * 2.0
			var core := 1.0 - smoothstep(0.0, 0.55, fx)
			var a := core * (0.25 + 0.75 * head)
			var col := Color(1.0, 1.0, 1.0, 0.0).lerp(Color(1.0, 0.42, 0.06, 0.0), 1.0 - head)
			col.a = a
			img.set_pixel(x, y, col)
	_save(img, "spark_streak.png")


## Arc streak: a white-hot core with a cyan halo, so the charge arcs read as electricity and not
## as green lines (the core colour times a cyan tint would cancel out).
func _bake_arc() -> void:
	var img := Image.create(SPARK_W, SPARK_H, false, Image.FORMAT_RGBA8)
	for y in SPARK_H:
		var t := float(y) / float(SPARK_H - 1)
		var head := pow(t, 2.0)
		for x in SPARK_W:
			var fx := absf(float(x) / float(SPARK_W - 1) - 0.5) * 2.0
			var core := 1.0 - smoothstep(0.0, 0.45, fx)
			var halo := (1.0 - smoothstep(0.2, 1.0, fx)) * 0.45
			var a := clampf(core + halo, 0.0, 1.0) * (0.2 + 0.8 * head)
			var col := Color(1.0, 1.0, 1.0).lerp(Color(0.098, 0.902, 1.0), 1.0 - core)
			col.a = a
			img.set_pixel(x, y, col)
	_save(img, "arc_streak.png")


## Air streak: a soft white line (16 x 256). It is the ribbon of displaced air of a near miss
## and the cold vapour of a nitro ignition: no orange, no heat.
func _bake_air() -> void:
	var img := Image.create(AIR_W, AIR_H, false, Image.FORMAT_RGBA8)
	for y in AIR_H:
		var t := float(y) / float(AIR_H - 1)
		var fade := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.6, 1.0, t))
		for x in AIR_W:
			var fx := absf(float(x) / float(AIR_W - 1) - 0.5) * 2.0
			var core := 1.0 - smoothstep(0.0, 0.9, fx)
			var a := core * fade
			img.set_pixel(x, y, Color(0.851, 0.910, 1.0, a))
	_save(img, "air_streak.png")


## Rain streak: a thin bright line with a soft head.
func _bake_rain() -> void:
	var img := Image.create(RAIN_W, RAIN_H, false, Image.FORMAT_RGBA8)
	for y in RAIN_H:
		var t := float(y) / float(RAIN_H - 1)
		var fade := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.75, 1.0, t))
		for x in RAIN_W:
			var fx := absf(float(x) / float(RAIN_W - 1) - 0.5) * 2.0
			var a := (1.0 - smoothstep(0.0, 0.8, fx)) * fade
			img.set_pixel(x, y, Color(0.85, 0.92, 1.0, a))
	_save(img, "rain_streak.png")


## Tyre track: 7 longitudinal tread grooves across the 24 cm track, two shoulder lines, the
## rubber broken up by scuffs along the length. The alpha of a groove is 1.0, the tread blocks
## between them 0.35, so the mark reads as stripes and not as a black hairline.
func _bake_track() -> void:
	var img := Image.create(TRACK_W, TRACK_H, false, Image.FORMAT_RGBA8)
	var grain := FastNoiseLite.new()
	grain.seed = 4242
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.02
	# The scuffs are at a 0.3 m scale: the texture repeats every 1.2 m along the track.
	var scuff_scale: float = float(TRACK_H) / (TUNE.SKID_UV_METRES / TRACK_SCUFF_METRES)
	for y in TRACK_H:
		for x in TRACK_W:
			var u := float(x) / float(TRACK_W - 1)
			var v := float(y) / float(TRACK_H - 1)
			var grooves := absf(fposmod(u * float(TRACK_GROOVES), 1.0) - 0.5) * 2.0
			var groove := 1.0 - smoothstep(0.22, 0.62, grooves)
			var a := lerpf(TRACK_GROOVE_MIN, 1.0, groove)
			# The two shoulder lines of the tyre.
			var shoulder := 1.0 - smoothstep(0.0, 0.035, absf(u - 0.12))
			shoulder = maxf(shoulder, 1.0 - smoothstep(0.0, 0.035, absf(u - 0.88)))
			a = maxf(a, shoulder * 0.95)
			# The scuffs: the rubber is broken up along the length of the track.
			var scuff := _fbm(grain, float(x) * 0.02, float(y) / scuff_scale, 3) * 0.5 + 0.5
			a *= 0.3 + 0.7 * smoothstep(0.32, 0.72, scuff)
			# Only the very edge of the track is feathered, so the mark keeps its width.
			var edge := minf(u, 1.0 - u)
			a *= smoothstep(0.0, 0.03, edge)
			img.set_pixel(x, y, Color(0.08, 0.08, 0.08, clampf(a, 0.0, 1.0)))
	_save(img, "tyre_track.png")


## Splash ripple: the main ring and three thinner rings around it, with a slight wobble on the
## radius (a perfect ring reads as a decal, not as water).
func _bake_ripple() -> void:
	var img := Image.create(RIPPLE, RIPPLE, false, Image.FORMAT_RGBA8)
	var c := (RIPPLE - 1) * 0.5
	var noise := FastNoiseLite.new()
	noise.seed = 5150
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	# The rings: the radius, the amplitude and the width of every one of them.
	var radii := [0.52, 0.66, 0.76, 0.85]
	var amps := [1.0, 0.55, 0.32, 0.18]
	var widths := [0.10, 0.055, 0.04, 0.03]
	for y in RIPPLE:
		for x in RIPPLE:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var d := sqrt(dx * dx + dy * dy)
			# A slight wobble on the radius: the ring is water, not a printed circle.
			var wob := noise.get_noise_2d(dx * 3.0, dy * 3.0) * 0.025
			var a := 0.0
			for i in radii.size():
				var r: float = float(radii[i]) + wob * (1.0 + float(i) * 0.5)
				var w: float = float(widths[i])
				a += float(amps[i]) * (1.0 - smoothstep(0.0, w, absf(d - r)))
			a *= clampf(1.0 - smoothstep(0.9, 1.0, d), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.85, 0.92, 1.0, clampf(a, 0.0, 1.0)))
	_save(img, "ripple.png")


## Energy ribbon: a bright leading edge (#E6FDFF), a cyan tail (#19E6FF) in chevron dashes and
## a filament noise, so the ribbon reads as energy and not as a printed stripe.
func _bake_ribbon() -> void:
	var img := Image.create(RIBBON_W, RIBBON_H, false, Image.FORMAT_RGBA8)
	var dash := float(RIBBON_W) / float(RIBBON_DASHES)
	var noise := FastNoiseLite.new()
	noise.seed = 8123
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.08
	for y in RIBBON_H:
		for x in RIBBON_W:
			var v := float(y) / float(RIBBON_H - 1)
			var across := absf(v - 0.5) * 2.0
			var phase := fposmod(float(x), dash) / dash
			# The chevron: the leading edge is a V that points along the ribbon.
			var lead := fposmod(phase + across * 0.3, 1.0)
			var a := smoothstep(0.0, 0.1, lead) * (1.0 - smoothstep(0.1, 1.0, lead) * 0.85)
			a *= 1.0 - smoothstep(0.5, 1.0, across)
			# The filaments: a fine noise along the ribbon that breaks the flat chevron.
			var filament := _fbm(noise, float(x) * 0.6, float(y) * 0.12, 2) * 0.5 + 0.5
			a *= 0.55 + 0.75 * filament
			# The hot leading edge of every dash.
			var hot := 1.0 - smoothstep(0.0, 0.16, lead)
			var col := Color(0.902, 0.992, 1.0).lerp(Color(0.098, 0.902, 1.0),
					smoothstep(0.0, 0.45, lead))
			col = col.lerp(Color(0.902, 0.992, 1.0), hot * 0.8)
			col.a = clampf(a, 0.0, 1.0)
			img.set_pixel(x, y, col)
	_save(img, "energy_ribbon.png")


## Flame atlas: 4 x 4 cells of 256 px. Every cell is a DIFFERENT lick: a teardrop whose base is
## 45% of the cell wide and whose top third splits into two or three tongues, with a soft edge
## of 25 px and a noise that is stretched upwards (4-6 lumps per cell, no grain).
##
## The tip of the lick is at the TOP of the cell (row 0 of the image), so the flame stands up.
func _bake_flame() -> void:
	var size := FLAME_CELLS * FLAME_CELL
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 909
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.09
	for cy in FLAME_CELLS:
		for cx in FLAME_CELLS:
			var cell := cy * FLAME_CELLS + cx
			for y in FLAME_CELL:
				for x in FLAME_CELL:
					var a := _flame_alpha(x, y, cell, noise)
					# The white-hot core of the lick lives in the texture, not in the HDR.
					var core := _flame_core(x, y, cell)
					var col := Color(1.0, 0.97, 0.88).lerp(Color(1.0, 1.0, 1.0), core)
					col.a = a
					img.set_pixel(cx * FLAME_CELL + x, cy * FLAME_CELL + y, col)
	_save(img, "flame_atlas.png")


## The alpha of one pixel of a flame cell.
##
## v runs from 0 (the tip, the top row of the image) to 1 (the base). The shape is a teardrop
## that splits into two or three tongues in its top third; the noise stretches the boundary up
## and down, so the lick has lumps and no grain.
##
## u runs from -1 to 1 across the cell: the base of the lick is 45% of the cell wide.
func _flame_alpha(x: int, y: int, cell: int, noise: FastNoiseLite) -> float:
	var v := (float(y) + 0.5) / float(FLAME_CELL)
	var u := ((float(x) + 0.5) / float(FLAME_CELL)) * 2.0 - 1.0
	# The number of tongues, how far they spread at the tip and the width of the base.
	var tongues := _flame_tongues(cell)
	var spread := _flame_spread(cell)
	var base := _flame_base(cell)
	# The noise: it varies fast across the flame and slow along it (stretched upwards).
	var lump := _fbm(noise, float(x) * 0.22 + float(cell) * 13.0, float(y) * 0.05, 2) * 0.5 + 0.5
	var best := 0.0
	for j in tongues:
		# The tongues are one mass in the lower two thirds and split in the top third.
		var centre := (float(j) - float(tongues - 1) * 0.5) * spread \
				* pow(clampf((FLAME_SPLIT - v) / FLAME_SPLIT, 0.0, 1.0), 1.4)
		var half := base * pow(v, 0.5) * (0.78 + 0.44 * lump)
		var dist := absf(u - centre)
		# The soft edge of 25 px.
		var shape := 1.0 - smoothstep(maxf(half - FLAME_EDGE_U, 0.0), half, dist)
		best = maxf(best, shape)
	# The tip fades out and the base is cut off by the road.
	best *= smoothstep(0.0, 0.10, v) * (1.0 - smoothstep(0.90, 1.0, v))
	# The gutter around every cell: nothing at the border.
	var edge := minf(minf(float(x), float(FLAME_CELL - 1 - x)),
			minf(float(y), float(FLAME_CELL - 1 - y)))
	best *= clampf((edge - FLAME_GUTTER) / 4.0, 0.0, 1.0)
	return clampf(best, 0.0, 1.0)


## The white-hot core of a lick: it is the middle of the tongue, not the whole shape.
func _flame_core(x: int, y: int, cell: int) -> float:
	var v := (float(y) + 0.5) / float(FLAME_CELL)
	var u := ((float(x) + 0.5) / float(FLAME_CELL)) * 2.0 - 1.0
	var tongues := _flame_tongues(cell)
	var spread := _flame_spread(cell)
	var base := _flame_base(cell)
	var best := 0.0
	for j in tongues:
		var centre := (float(j) - float(tongues - 1) * 0.5) * spread \
				* pow(clampf((FLAME_SPLIT - v) / FLAME_SPLIT, 0.0, 1.0), 1.4)
		var half := base * pow(v, 0.5)
		var dist := absf(u - centre) / maxf(half, 0.001)
		best = maxf(best, clampf(1.0 - dist * 2.2, 0.0, 1.0))
	return best * smoothstep(0.0, 0.12, v)


## The number of tongues of a cell (two or three).
static func _flame_tongues(cell: int) -> int:
	return 2 + (cell % 2)


## How far the tongues spread at the tip of a cell.
static func _flame_spread(cell: int) -> float:
	return 0.20 + 0.07 * float((cell / 2) % 4)


## The width of the base of a cell, as a fraction of the cell (the brief: 45%).
static func _flame_base(cell: int) -> float:
	return 0.38 + 0.05 * float(cell % 3)
