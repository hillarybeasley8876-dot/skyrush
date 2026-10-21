extends Node
## HUD unit tests (tools/godot.sh test res://ui/hud/tests/test_hud.gd).
##
## CONTRACTS §3: tests are Nodes run by the core test host, so the autoloads exist and the
## scripts can be preloaded.
##
## Covers: the fonts (the Noto weight axis), the COPV slot filling from the bottom, the speed
## cluster, the N2 cluster, the race clock format, the race position across laps, the pursuit
## panel and the blinking heat pips, the minimap (heading-up, clipped, cheap), the toast stack
## (max 3, merging), the takedown banner (real-time docking), the hop ring threshold and the
## pause hide. The LAYOUT tests live in test_hud_layout.gd.

const HudScene := preload("res://ui/hud/hud.tscn")
const HudScript := preload("res://ui/hud/hud.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const Gauge := preload("res://ui/hud/gauge_dial.gd")
const TimerPanelScript := preload("res://ui/hud/timer_panel.gd")
const HopRingScript := preload("res://ui/hud/hop_ring.gd")
const EventsScript := preload("res://ui/hud/hud_events.gd")
const SpeedCluster := preload("res://ui/hud/speed_cluster.gd")
const NitroCluster := preload("res://ui/hud/nitro_cluster.gd")
const N2Slot := preload("res://ui/hud/n2_slot.gd")
const TimerPanel := preload("res://ui/hud/timer_panel.gd")
const RacePanel := preload("res://ui/hud/race_panel.gd")
const PursuitPanel := preload("res://ui/hud/pursuit_panel.gd")
const MinimapPanel := preload("res://ui/hud/minimap_panel.gd")
const ToastStack := preload("res://ui/hud/toast_stack.gd")
const TakedownBanner := preload("res://ui/hud/takedown_banner.gd")
const GaugeDial := preload("res://ui/hud/gauge_dial.gd")


class CountedPips extends "res://ui/hud/heat_pips.gd":
	var draws: int = 0
	func _draw() -> void:
		super._draw()
		draws += 1


var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _test_fonts()
	await _test_zero_feature()
	await _test_map_texels()
	await _test_slots_and_cluster()
	await _test_timer()
	await _test_standings()
	await _test_pursuit()
	await _test_minimap()
	await _test_toasts()
	await _test_banner()
	await _test_hop_ring()
	await _test_pause()
	print("HUD TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The Noto Sans SC weight axis only applies with the integer OpenType tag (Godot 4.7 ignores the
## "wght" string key and leaves the font at Thin / wght 100).
func _test_fonts() -> void:
	var sample := "TAKEDOWN PURSUIT Roadster 0123456789"
	var text_w := Fonts.text().get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var bold_w := Fonts.text_bold().get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var black_w := Fonts.text_black().get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	_check(text_w > 800.0 and text_w < 830.0, "the UI face is weight 500 (%.0f px)" % text_w)
	_check(bold_w > 840.0 and bold_w < 870.0, "the bold face is weight 800 (%.0f px)" % bold_w)
	_check(black_w >= bold_w, "the black face is heavier than the bold one (%.0f px)" % black_w)
	_check(Fonts.techno() != null, "the techno face (Oxanium) loads")


## Oxanium ships the OpenType "zero" feature, so the livestream's slashed zero is a real glyph.
func _test_zero_feature() -> void:
	var tag := TextServerManager.get_primary_interface().name_to_tag("zero")
	var font := Fonts.techno()
	_check(font.get_supported_variation_list().size() >= 0, "the techno face reports its variations")
	_check(font.opentype_features.has(tag), "the techno face enables the zero feature")


## The texel of a road point must map back to the point through the overlay's transform.
func _test_map_texels() -> void:
	var hud := await _make_hud()
	var minimap: MinimapPanel = hud.get("minimap")
	var lines: Array[PackedVector2Array] = []
	for i in 4:
		var pts := PackedVector2Array()
		for j in 40:
			pts.append(Vector2(float(j) * 37.0 - 700.0, float(i) * 220.0 + sin(float(j)) * 60.0))
		lines.append(pts)
	var no_pois: Array[Dictionary] = []
	minimap.set_world(lines, no_pois)
	await _frames(2)
	minimap.update_map(Vector3(120.0, 0.0, -80.0), Vector3(0.6, 0.0, -0.8), 100.0)
	await _frames(2)
	var world_min: Vector2 = minimap.get("_world_min")
	var tex_zoom: float = minimap.get("_tex_zoom")
	var zoom: float = minimap.get("_zoom")
	var rot: float = minimap.get("_rot")
	var player: Vector2 = minimap.get("_player_pos")
	var k := zoom / maxf(tex_zoom, 0.0001)
	var centre: Vector2 = minimap.get("_clip").get("size") * 0.5
	var rel := (world_min - player) * zoom
	var translation := centre + Vector2(rel.x * cos(rot) - rel.y * sin(rot),
		rel.x * sin(rot) + rel.y * cos(rot))
	var worst := 0.0
	for i in 20:
		var p := Vector2(randf_range(-600.0, 600.0), randf_range(-400.0, 400.0))
		var texel := (p - world_min) * tex_zoom
		var screen := translation + Vector2(
			(texel.x * k) * cos(rot) - (texel.y * k) * sin(rot),
			(texel.x * k) * sin(rot) + (texel.y * k) * cos(rot))
		worst = maxf(worst, screen.distance_to(minimap.project_point(p)))
	_check(worst < 1.0, "the map texel maps back to the road point (worst %.2f px)" % worst)
	_free_hud(hud)


## The COPV slot fills from the bottom, the pending gain rides above the liquid.
func _test_slots_and_cluster() -> void:
	var hud := await _make_hud()
	var tele: CarTelemetry = hud.get("telemetry_override")
	var cluster: NitroCluster = hud.get("nitro_cluster")
	tele.n2 = 141.0
	await _frames(2)
	var slot0: N2Slot = cluster.get("_slots")[0]
	var slot1: N2Slot = cluster.get("_slots")[1]
	_check(is_equal_approx(slot0.get("value"), 100.0), "slot 1 holds 100 units")
	_check(is_equal_approx(slot1.get("value"), 41.0),
		"slot 2 holds the rest, filled from the bottom (%.0f)" % float(slot1.get("value")))
	tele.n2 = 60.0
	tele.n2_pending = 25.0
	tele.mini_window = true
	await _frames(2)
	_check(is_equal_approx(slot0.get("pending"), 25.0),
		"the pending drift gain rides on the filling slot")
	_check(bool(cluster.get("_prompt").visible), "the 小喷 prompt shows while the window is open")
	# The slot stores the floats on every call: a slot that falls back to zero is empty again.
	slot0.set_values(1.4, 0.0)
	slot0.set_values(0.4, 0.0)
	slot0.set_values(0.0, 0.0)
	_check(is_zero_approx(float(slot0.get("value"))),
		"an empty slot keeps no stale value (%.2f)" % float(slot0.get("value")))

	var speed: SpeedCluster = hud.get("speed_cluster")
	tele.speed_kmh = 213.4
	tele.motor_load = 0.5
	await _frames(2)
	_check(str(speed.get("_value").text) == "213", "the speed cluster shows the rounded speed")
	tele.boost_kind = &"nitro"
	await _frames(2)
	_check(speed.get("_value").get_theme_color("font_color").r > 0.9,
		"the speed number turns magenta on boost")
	_free_hud(hud)


func _test_timer() -> void:
	_check(TimerPanelScript.format_time(27.74) == "00'27\"74", "the race clock uses the QQ format")
	_check(TimerPanelScript.format_time(59.996) == "00'59\"99",
		"the centiseconds are floored, never rounded up")
	var hud := await _make_hud()
	var panel: TimerPanel = hud.get("timer_panel")
	panel.update_values(27.74, 48.32, 1, 2, true)
	_check(str(panel.get("_time").text).contains("00'27\"74"), "the clock shows the race time")
	_check(str(panel.get("_lap").text) == "1/2", "the lap counter shows 1/2")
	panel.update_values(27.74, 48.32, 1, 2, false)
	_check(not bool(panel.get("_box").visible), "the clock rows hide outside a race")
	_free_hud(hud)


## The position must be right from lap 2 on: progress = laps done x checkpoints + the checkpoints
## of the running lap, and ties keep the previous order.
func _test_standings() -> void:
	var hud := await _make_hud()
	var player := VehicleBase.new()
	player.display_name = "Roadster"
	player.freeze = true
	add_child(player)
	Game.player = player
	var rival := VehicleBase.new()
	rival.display_name = "疾风"
	rival.freeze = true
	add_child(rival)
	rival.add_to_group("rivals")
	hud.set("telemetry_override", CarTelemetry.new())
	await _frames(2)

	Events.race_started.emit()
	for v in [player, rival]:
		for i in 8:
			Events.checkpoint_passed.emit(v, i, 8)
		Events.lap_completed.emit(v, 1, 60.0)
	await _frames(2)
	# The rival runs six checkpoints into lap 2.
	for i in 6:
		Events.checkpoint_passed.emit(rival, i, 8)
	await _frames(60)
	var panel: RacePanel = hud.get("race_panel")
	_check(str(panel.get("_rank_text")) == "2ND",
		"the rival leading in lap 2 puts the player 2ND (%s)" % str(panel.get("_rank_text")))
	# The player catches up: a full lap of checkpoints in lap 2.
	for i in 8:
		Events.checkpoint_passed.emit(player, i, 8)
	await _frames(60)
	_check(str(panel.get("_rank_text")) == "1ST",
		"the player overtaking in lap 2 puts them 1ST (%s)" % str(panel.get("_rank_text")))
	rival.queue_free()
	player.queue_free()
	Game.player = null
	_free_hud(hud)


## The pursuit panel, the heat pips and their 2 Hz blink.
func _test_pursuit() -> void:
	var pips := CountedPips.new()
	pips.size = Vector2(120, 20)
	add_child(pips)
	pips.set_level(3)
	await _frames(120)
	_check(pips.draws >= 3 and pips.draws <= 5,
		"the heat pips blink 4 times a second (%d redraws in 120 frames)" % pips.draws)
	pips.queue_free()

	var hud := await _make_hud()
	var panel: PursuitPanel = hud.get("pursuit_panel")
	panel.update_values(3, 4, 7, &"chase", 0.0, 0.0)
	await _frames(1)
	_check(int(panel.get("_pips").get("level")) == 3, "the heat pips show level 3")
	_check(str(panel.get("_status").text).contains("PURSUIT"), "the pursuit state is written out")
	panel.update_values(3, 4, 7, &"cooldown", 0.5, 0.0)
	await _frames(1)
	_check(str(panel.get("_status").text).contains("EVADING"), "the cooldown reads as evading")
	_free_hud(hud)


## The minimap: heading-up, clipped to its panel and cheap.
func _test_minimap() -> void:
	var hud := await _make_hud()
	var minimap: MinimapPanel = hud.get("minimap")
	var lines: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)])]
	var no_pois: Array[Dictionary] = []
	minimap.set_world(lines, no_pois)
	await _frames(1)
	# The player faces +X (east): east must be up on the map, north must be to the left.
	minimap.update_map(Vector3.ZERO, Vector3.RIGHT, 100.0)
	await _frames(1)
	var centre: Vector2 = minimap.get("_clip").get("size") * 0.5
	var east: Vector2 = minimap.project_point(Vector2(100, 0))
	var north: Vector2 = minimap.project_point(Vector2(0, -100))
	_check(east.y < centre.y - 1.0, "the minimap is heading-up (the way ahead is up)")
	_check(north.x < centre.x - 1.0, "the minimap keeps the right hand side on the right")
	# Nothing may be drawn outside the clipped area.
	var clip: Control = minimap.get("_clip")
	_check(bool(clip.get("clip_contents")), "the map area is clipped")
	_free_hud(hud)


## The toast stack: at most three visible, repeats merge.
func _test_toasts() -> void:
	var hud := await _make_hud()
	var toasts: ToastStack = hud.get("toasts")
	for i in 6:
		toasts.push("测试 %d" % i, "TEST %d" % i, Color.WHITE)
	await _frames(1)
	var box: VBoxContainer = toasts.get("_box")
	_check(box.get_child_count() == 3, "at most three toasts are visible (%d)" % box.get_child_count())
	toasts.push("擦身而过", "NEAR MISS", Color.WHITE, "+5")
	toasts.push("擦身而过", "NEAR MISS", Color.WHITE, "+5")
	await _frames(1)
	_check(box.get_child_count() == 3, "a repeated toast does not add a row")
	# The two lines follow the skewed plate edge, so they keep their margin over the accent bar.
	var row: Control = box.get_child(0)
	var skew := tan(deg_to_rad(12.0)) * row.size.y
	var zh: Label = row.get("_zh")
	var sub: Control = row.get("_sub")
	var zh_edge := skew - skew * (zh.position.y + zh.size.y * 0.5) / row.size.y
	var sub_edge := skew - skew * (sub.position.y + sub.size.y * 0.5) / row.size.y
	_check(is_equal_approx(zh.position.x, zh_edge) and is_equal_approx(sub.position.x, sub_edge),
		"the toast lines follow the skewed plate edge")
	_free_hud(hud)


## The takedown banner pops in the centre and docks top-left — in REAL time, even in slow motion.
func _test_banner() -> void:
	var hud := await _make_hud()
	var banner: TakedownBanner = hud.get("banner")
	Engine.time_scale = 0.3
	banner.show_banner("撞毁！", "TAKEDOWN!", "连击 ×2")
	await _frames(3)
	_check(float(banner.get("_dock")) < 0.5, "the banner starts in the centre")
	await _frames(20)
	_check(float(banner.get("_dock")) > 0.9,
		"the banner docks in real time under slow motion (%.2f)" % float(banner.get("_dock")))
	Engine.time_scale = 1.0
	_check(str(banner.get("_main")) == "撞毁！", "the banner keeps the Chinese line")
	_free_hud(hud)


## The Big Hop ring is only armed at charge 1.0 (the telemetry is already normalised against the
## 0.25 s hold time).
func _test_hop_ring() -> void:
	var ring := HopRingScript.new()
	add_child(ring)
	ring.set_charge(0.5)
	await _frames(1)
	_check(not ring.armed, "a half charged hop is not the Big Hop")
	ring.set_charge(1.0)
	await _frames(1)
	_check(ring.armed, "a fully charged hop is armed")
	ring.queue_free()


func _test_pause() -> void:
	var hud := await _make_hud()
	Events.game_paused.emit(true)
	await _frames(1)
	_check(not bool(hud.get("root").get("visible")), "the HUD hides while the game is paused")
	Events.game_paused.emit(false)
	await _frames(1)
	_check(bool(hud.get("root").get("visible")), "the HUD comes back after the pause")
	_free_hud(hud)


## Build a HUD instance with a faked telemetry.
func _make_hud() -> CanvasLayer:
	var hud := HudScene.instantiate() as CanvasLayer
	add_child(hud)
	await _frames(2)
	hud.set("telemetry_override", CarTelemetry.new())
	return hud


func _free_hud(hud: CanvasLayer) -> void:
	hud.queue_free()
	await _frames(2)
