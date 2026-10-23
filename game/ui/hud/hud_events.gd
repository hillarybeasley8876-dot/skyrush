extends RefCounted
## Every reaction of the HUD to the `Events` signal bus, plus the race / pursuit state the HUD
## draws. Kept apart from `hud.gd` so both stay small.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const ToastStack := preload("res://ui/hud/toast_stack.gd")
const TakedownBanner := preload("res://ui/hud/takedown_banner.gd")
const CountdownLabel := preload("res://ui/hud/countdown_label.gd")
const RacePanel := preload("res://ui/hud/race_panel.gd")
const ModeStatusReadout := preload("res://ui/hud/mode_status_readout.gd")
const MinimapPanel := preload("res://ui/hud/minimap_panel.gd")

## Widgets the handlers write into (set by the HUD when it builds its tree).
var toasts: ToastStack = null
var banner: TakedownBanner = null
var countdown: CountdownLabel = null
var hud_root: Control = null
## The race panel: the takedown banner docks below it and the place comes from the mode status.
var race_panel: RacePanel = null
## The readout of the mode status (the score, the takedown goal, the countdown).
var mode_readout: ModeStatusReadout = null
## The minimap: it draws the route of the race and the next gate of the player.
var minimap: MinimapPanel = null
## The route of the demo (the demo has no world, so it hands its own route in).
var demo_route: RaceRoute = null

## The route of the race that runs (its racing line and its checkpoints).
var _route: RaceRoute = null
## The id of the route on the map (the line is only rebuilt when the id changes).
var _route_id: String = ""
## The next gate on the map (-1 = none, -2 = not set yet).
var _next_gate: int = -2
## The distance between two points of the line of the route (m).
const ROUTE_STEP := 10.0

## The state of the running mode, from the bus (`Events.mode_status`).
var status_kind: StringName = &"none"
var status: Dictionary = {}

## Race / pursuit state.
var heat: int = 0
var pursuit_state: StringName = &"none"
var race_running: bool = false
var race_time: float = 0.0
var best_lap: float = -1.0
var lap: int = 1
var laps: int = 2
## Progress per vehicle: laps done x checkpoints per lap + the checkpoints of the current lap.
var progress: Dictionary[int, int] = {}
## Laps finished per vehicle (instance id -> laps).
var laps_done: Dictionary[int, int] = {}
## The last checkpoint index passed in the current lap (instance id -> index, -1 = none yet).
var checkpoints: Dictionary[int, int] = {}
## The number of checkpoints per lap (from the checkpoint event).
var race_total: int = 0
var takedown_streak: int = 0
var last_takedown_ms: int = 0

## A clean drift has to last at least this long to be worth a pop-up (dossier §8.4).
const DRIFT_MIN_TIME := 1.5
## Takedowns inside this window chain (dossier §3.5).
const TAKEDOWN_WINDOW := 10.0
## The near miss is a small pop-up (dossier §8.4).
const NEAR_MISS_SIZE := 40


func connect_all() -> void:
	Events.stunt.connect(_on_stunt)
	Events.toast.connect(_on_toast)
	Events.near_miss.connect(_on_near_miss)
	Events.drift_ended.connect(_on_drift_ended)
	Events.boost_started.connect(_on_boost_started)
	Events.n2_ring.connect(_on_n2_ring)
	Events.charge_finished.connect(_on_charge_finished)
	Events.takedown.connect(_on_takedown)
	Events.vehicle_wrecked.connect(_on_vehicle_wrecked)
	Events.race_countdown.connect(_on_race_countdown)
	Events.race_started.connect(_on_race_started)
	Events.race_finished.connect(_on_race_finished)
	Events.lap_completed.connect(_on_lap_completed)
	Events.checkpoint_passed.connect(_on_checkpoint_passed)
	Events.heat_changed.connect(_on_heat_changed)
	Events.pursuit_state_changed.connect(_on_pursuit_state_changed)
	Events.game_paused.connect(_on_game_paused)
	Events.mode_status.connect(_on_mode_status)


func is_player(vehicle: VehicleBase) -> bool:
	if vehicle == null:
		return false
	if Game.player != null:
		return vehicle == Game.player
	return true


## Split a mixed string at the first Latin LETTER: [chinese, english]. Digits stay with the
## Chinese part ("第2名 FINISH" -> "第2名" | "FINISH").
static func split_text(text: String) -> Array[String]:
	for i in text.length():
		var code := text.unicode_at(i)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			return [text.substr(0, i).strip_edges(), text.substr(i).strip_edges()]
	return [text.strip_edges(), ""]


func _on_stunt(_kind: StringName, points: int, label: String) -> void:
	var parts := split_text(label)
	var pts := "" if points <= 0 else "+%d" % points
	toasts.push(parts[0], parts[1], Palette.CYAN, pts)


func _on_toast(text: String, style: StringName) -> void:
	var parts := split_text(text)
	toasts.push(parts[0], parts[1], Palette.for_style(style))


func _on_near_miss(vehicle: VehicleBase, _other: VehicleBase) -> void:
	if is_player(vehicle):
		# The bar is cyan: a white bar would vanish on the light glass plate.
		toasts.push("擦身而过", "NEAR MISS", Palette.TEXT, "+5", NEAR_MISS_SIZE, Palette.CYAN)


func _on_drift_ended(vehicle: VehicleBase, duration: float, clean: bool, n2_gained: float) -> void:
	if clean and duration >= DRIFT_MIN_TIME and is_player(vehicle):
		toasts.push("漂移", "DRIFT", Palette.TEXT, "+%d" % int(round(n2_gained)), 60, Palette.CYAN)


func _on_boost_started(vehicle: VehicleBase, kind: StringName) -> void:
	if not is_player(vehicle):
		return
	match kind:
		&"nitro":
			toasts.push("氮气加速", "NITRO BOOST", Palette.CYAN)
		&"mini":
			toasts.push("小喷！", "MINI BOOST", Palette.CYAN)
		&"perfect_mini":
			toasts.push("完美小喷！", "PERFECT BOOST", Palette.CYAN)
		&"air_mini":
			toasts.push("空喷！", "AIR BOOST", Palette.CYAN)
		&"landing":
			toasts.push("落地喷！", "LANDING BOOST", Palette.CYAN)
		&"launch":
			toasts.push("完美起步！", "PERFECT START", Palette.CYAN)
		&"charge":
			toasts.push("闪充！", "FLASH CHARGE", Palette.CYAN)


func _on_n2_ring(vehicle: VehicleBase, _lane: SkyLane) -> void:
	if is_player(vehicle):
		# "N2" and not "N₂": the subscript glyph falls back to a tiny low 2 in the display face.
		toasts.push("氮气", "N2 RING", Palette.CYAN, "+40")


func _on_charge_finished(vehicle: VehicleBase, _station: Area3D, _amount: float) -> void:
	if is_player(vehicle):
		toasts.push("闪充完成 +N₂", "FLASH CHARGE", Palette.CYAN)


func _on_takedown(_victim: VehicleBase, kind: StringName) -> void:
	var now := Time.get_ticks_msec()
	if now - last_takedown_ms < TAKEDOWN_WINDOW * 1000.0:
		takedown_streak += 1
	else:
		takedown_streak = 1
	last_takedown_ms = now
	if kind == &"traffic":
		toasts.push("撞车", "TAKEDOWN", Palette.AMBER)
		return
	var sub := ""
	if takedown_streak >= 5:
		sub = "狂暴 RAMPAGE ×%d" % takedown_streak
	elif takedown_streak >= 2:
		sub = "连击 ×%d  %d-IN-A-ROW" % [takedown_streak, takedown_streak]
	banner.show_banner("撞毁！", "TAKEDOWN!", sub, _banner_dock_y())


## The y the banner docks to: below the race panel, or the dossier's 340 px.
func _banner_dock_y() -> float:
	if race_panel == null:
		return TakedownBanner.DOCK_Y
	return maxf(TakedownBanner.DOCK_Y, race_panel.position.y + race_panel.size.y + 16.0)


## The player wrecked their own car.
func _on_vehicle_wrecked(vehicle: VehicleBase, _source: Node3D) -> void:
	if is_player(vehicle):
		toasts.push("撞车", "WRECKED", Palette.RED)


func _on_race_countdown(seconds_left: int) -> void:
	countdown.set_count(seconds_left)


func _on_race_started() -> void:
	race_running = true
	race_time = 0.0
	best_lap = -1.0
	lap = 1
	progress.clear()
	laps_done.clear()
	checkpoints.clear()
	race_total = 0
	takedown_streak = 0


func _on_race_finished(results: Array) -> void:
	race_running = false
	for r in results:
		if bool(r.get("is_player", false)):
			toasts.push("第%d名" % int(r.get("position", 1)), "FINISH", Palette.CYAN)


func _on_lap_completed(vehicle: VehicleBase, completed: int, lap_time: float) -> void:
	var id := vehicle.get_instance_id()
	laps_done[id] = completed
	checkpoints[id] = -1
	_update_progress(id)
	if not is_player(vehicle):
		return
	lap = completed + 1
	# Every lap is announced; a new best lap gets an extra amber line.
	toasts.push("完成第%d圈" % completed, "LAP %d" % completed, Palette.CYAN)
	if best_lap < 0.0 or lap_time < best_lap:
		best_lap = lap_time
		toasts.push("最佳圈", "BEST LAP", Palette.AMBER)


func _on_checkpoint_passed(vehicle: VehicleBase, index: int, total: int) -> void:
	if total > 0:
		race_total = total
	var id := vehicle.get_instance_id()
	var current := int(checkpoints.get(id, -1))
	if index > current:
		checkpoints[id] = index
	_update_progress(id)


## Progress = laps finished x checkpoints per lap + the checkpoints of the running lap.
func _update_progress(id: int) -> void:
	var laps := int(laps_done.get(id, 0))
	var index := int(checkpoints.get(id, -1))
	progress[id] = laps * race_total + maxi(index + 1, 0)


func _on_heat_changed(level: int) -> void:
	var new_level := clampi(level, 0, 5)
	var rising := new_level > heat
	heat = new_level
	if new_level > 0:
		var arrow := "↑" if rising else "↓"
		toasts.push("通缉等级 %s" % arrow, "HEAT %d" % new_level, Palette.RED)


func _on_pursuit_state_changed(state: StringName) -> void:
	pursuit_state = state
	match state:
		&"chase":
			toasts.push("警方追捕！", "PURSUIT", Palette.RED)
		&"search", &"cooldown":
			toasts.push("甩开警察", "EVADING…", Palette.POLICE_BLUE)
		&"escaped":
			toasts.push("成功逃脱！", "ESCAPED", Palette.GREEN)
		&"busted":
			toasts.push("被捕", "BUSTED", Palette.RED)


## The state of the running mode, from the bus. The HUD draws it and nothing else: the laps of
## the race that runs, the place of the player and the readout (the score, the goal, the clock).
func _on_mode_status(kind: StringName, data: Dictionary) -> void:
	status_kind = kind
	status = data.duplicate()
	if kind == &"race":
		var total := int(data.get("laps", 0))
		if total > 0:
			laps = total
		var current := int(data.get("lap", 0))
		if current > 0:
			lap = current
		if race_panel != null:
			race_panel.set_place(int(data.get("position", 0)), int(data.get("racers", 0)))
		_update_route(data)
	else:
		# Without a race the standings decide the place again.
		if race_panel != null:
			race_panel.clear_place()
		_clear_route()
	if mode_readout != null:
		mode_readout.set_status(kind, data)


## The route of the race and the next gate of the player go on the minimap. The status comes
## twice a second, so the line is only rebuilt when the route changes and the marker is only
## moved when the gate changes.
func _update_route(data: Dictionary) -> void:
	if minimap == null:
		return
	var route_id := String(data.get("route", ""))
	if route_id != _route_id:
		_route_id = route_id
		_route = _find_route(route_id)
		minimap.clear_route()
		minimap.set_route(_route_line(_route))
		_next_gate = -2
	var gate := int(data.get("next_gate", -1))
	if gate == _next_gate:
		return
	_next_gate = gate
	_set_gate(gate)


## The route of the world (null when the world does not have it). The demo has no world, so it
## hands its own route in.
func _find_route(route_id: String) -> RaceRoute:
	if Game.world != null:
		var route := Game.world.get_route(StringName(route_id))
		if route != null:
			return route
	if demo_route != null and String(demo_route.id) == route_id:
		return demo_route
	return null


## The racing line of the route in world XZ, thinned to one point every ROUTE_STEP metres.
func _route_line(route: RaceRoute) -> PackedVector2Array:
	var out := PackedVector2Array()
	if route == null or route.racing_line == null:
		return out
	var last := Vector2.ZERO
	for p in route.racing_line.get_baked_points():
		var flat := Vector2(p.x, p.z)
		if out.size() > 0 and flat.distance_to(last) < ROUTE_STEP:
			continue
		out.append(flat)
		last = flat
	return out


## The gate the player has to pass next (-1 = the player is home).
func _set_gate(gate: int) -> void:
	if minimap == null:
		return
	if gate < 0 or _route == null or gate >= _route.checkpoints.size():
		minimap.clear_next_gate()
		return
	var origin := _route.checkpoints[gate].origin
	minimap.set_next_gate(Vector2(origin.x, origin.z))


## Without a race there is no route on the map.
func _clear_route() -> void:
	if minimap == null:
		return
	_route = null
	_route_id = ""
	_next_gate = -2
	minimap.clear_route()


func _on_game_paused(paused: bool) -> void:
	if hud_root != null:
		hud_root.visible = not paused
