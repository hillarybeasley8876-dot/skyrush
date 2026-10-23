extends CanvasLayer
## SKYRUSH in-game HUD (QQ飞车-style, cyberpunk).
##
## Owns: `res://ui/hud/hud.tscn` (this scene) and everything under `res://ui/hud/**`.
## Reads the car state from `CarTelemetry` (via `Game.player`), world data from `Game.world`
## (`WorldBase`) and reacts to the `Events` signal bus. The pause overlay belongs to the menu
## unit; the HUD only hides itself on `game_paused`.
##
## The widget tree is built in code so every cluster stays a small, testable script:
##   speed_cluster / nitro_cluster  — bottom corners
##   race_panel / pursuit_panel     — top left (position or heat)
##   timer_panel / minimap          — top right
##   toasts / banner / countdown    — centre
##   flight                         — the reveal-stream gauges, shown while airborne

const UI := preload("res://ui/theme/skyrush_theme.gd")
const HudEvents := preload("res://ui/hud/hud_events.gd")
const HudPursuit := preload("res://ui/hud/hud_pursuit.gd")
const SpeedCluster := preload("res://ui/hud/speed_cluster.gd")
const NitroCluster := preload("res://ui/hud/nitro_cluster.gd")
const RacePanel := preload("res://ui/hud/race_panel.gd")
const PursuitPanel := preload("res://ui/hud/pursuit_panel.gd")
const TimerPanel := preload("res://ui/hud/timer_panel.gd")
const MinimapPanel := preload("res://ui/hud/minimap_panel.gd")
const ToastStack := preload("res://ui/hud/toast_stack.gd")
const TakedownBanner := preload("res://ui/hud/takedown_banner.gd")
const CountdownLabel := preload("res://ui/hud/countdown_label.gd")
const FlightCluster := preload("res://ui/hud/flight_cluster.gd")
const ModeStatusReadout := preload("res://ui/hud/mode_status_readout.gd")
const HealthBar := preload("res://ui/hud/health_bar.gd")
const HopHint := preload("res://ui/hud/hop_hint.gd")

## The flight gauges only appear after this much airtime (brief: airborne > 0.3 s).
const FLIGHT_AIRTIME := 0.3
## How much the speed cluster shrinks (about its bottom-right corner) so it clears the flight
## gauges, and how far it moves up (a function of the viewport height, see flight_speed_shift).
const FLIGHT_SPEED_SCALE := 0.72
const FLIGHT_SPEED_ALPHA := 0.75
## The N2 cluster keeps its N2 visible in flight (the player spends it there): it shrinks a little
## and moves up over the DOWNFORCE ring.
const FLIGHT_NITRO_SCALE := 0.8
const FLIGHT_NITRO_ALPHA := 0.9
## The duration of the layout tween.
const LAYOUT_TIME := 0.2
const STANDINGS_PERIOD := 0.25
## The lap count used when the world has no route (a request for the real value is in the status).
const DEFAULT_LAPS := 2
## How often the police / rival blips are refreshed (seconds).
const BLIP_PERIOD := 0.1

var root: Control
var speed_cluster: SpeedCluster
var nitro_cluster: NitroCluster
var race_panel: RacePanel
var pursuit_panel: PursuitPanel
var timer_panel: TimerPanel
var minimap: MinimapPanel
var toasts: ToastStack
var banner: TakedownBanner
var countdown: CountdownLabel
var flight: FlightCluster
## The readout of the mode status (the score, the takedown goal, the countdown).
var mode_status: ModeStatusReadout
## The health of the car (the bar under the clusters).
var health_bar: HealthBar
## The prompt to hop over a roadblock / toll plaza.
var hop_hint: HopHint
## The full-screen dim of the BUSTED screen (dossier §8.4).
var busted_dim: ColorRect

## Set by the demo / tests to drive the HUD without a world or a car.
var telemetry_override: CarTelemetry = null
var demo_polylines: Array[PackedVector2Array] = []
var demo_pois: Array[Dictionary] = []

var events: HudEvents

var _flight_active: bool = false
var _map_loaded: bool = false
var _world: WorldBase = null
var _world_polylines: Array[PackedVector2Array] = []
var _world_pois: Array[Dictionary] = []
var _sky_lanes: Array[PackedVector2Array] = []
var _plumes: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _minimap_timer: float = 0.0
## The pursuit state and the standings (hud_pursuit.gd).
var pursuit: HudPursuit
var _standings_timer: float = 0.0
var _layout_tween: Tween
## The settled position of the clusters (the layout position, without the flight shift).
var _speed_base: Vector2 = Vector2.ZERO
var _nitro_base: Vector2 = Vector2.ZERO
var _layout_ready: bool = false
var _timer_shown: bool = true


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.build()
	add_child(root)
	pursuit = HudPursuit.new()
	_build()
	events = HudEvents.new()
	events.toasts = toasts
	events.banner = banner
	events.countdown = countdown
	events.hud_root = root
	events.race_panel = race_panel
	events.mode_readout = mode_status
	events.minimap = minimap
	events.connect_all()


func _build() -> void:
	speed_cluster = SpeedCluster.new()
	UI.place(speed_cluster, 1, 1, 1, 1, -336, -366, -36, -26)
	root.add_child(speed_cluster)

	nitro_cluster = NitroCluster.new()
	UI.place(nitro_cluster, 0, 1, 0, 1, 40, -292, 250, -52)
	root.add_child(nitro_cluster)

	race_panel = RacePanel.new()
	UI.place(race_panel, 0, 0, 0, 0, 40, 36, 316, 36)
	race_panel.visible = Game.mode == &"race"
	root.add_child(race_panel)

	pursuit_panel = PursuitPanel.new()
	UI.place(pursuit_panel, 0, 0, 0, 0, 40, 36, 316, 212)
	pursuit_panel.visible = false
	root.add_child(pursuit_panel)

	timer_panel = TimerPanel.new()
	UI.place(timer_panel, 1, 0, 1, 0, -280, 36, -36, 196)
	root.add_child(timer_panel)

	minimap = MinimapPanel.new()
	UI.place(minimap, 1, 0, 1, 0, -288, 212, -36, 464)
	root.add_child(minimap)

	# The readout of the mode status (the score of the free roam, the goal and the countdown of a
	# pursuit). It is under the BUSTED dim, like the panels.
	mode_status = ModeStatusReadout.new()
	UI.place(mode_status, 0, 0, 1, 1)
	root.add_child(mode_status)

	flight = FlightCluster.new()
	UI.place(flight, 0, 0, 1, 1)
	root.add_child(flight)

	# The health of the car: a thin bar in the bottom centre, between the two clusters (the N2
	# cluster is on the left, the speed cluster on the right).
	health_bar = HealthBar.new()
	UI.place(health_bar, 0.5, 1.0, 0.5, 1.0, -110.0, -76.0, 110.0, -48.0)
	root.add_child(health_bar)

	# The prompt to hop over a roadblock / toll plaza: centred in the upper third, under the
	# score readout and over the toasts.
	hop_hint = HopHint.new()
	UI.place(hop_hint, 0.5, 0.09, 0.5, 0.09, -180.0, 0.0, 180.0, 96.0)
	root.add_child(hop_hint)

	# The BUSTED dim covers the panels and the clusters, but NOT the toasts, the banner and the
	# countdown: a red 被捕 BUSTED has to stay readable (dossier §8.4).
	busted_dim = ColorRect.new()
	busted_dim.color = Color(0, 0, 0, 0.6)
	busted_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	busted_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busted_dim.visible = false
	root.add_child(busted_dim)

	toasts = ToastStack.new()
	UI.place(toasts, 0, 0, 1, 1)
	root.add_child(toasts)

	banner = TakedownBanner.new()
	UI.place(banner, 0, 0, 1, 1)
	root.add_child(banner)

	countdown = CountdownLabel.new()
	UI.place(countdown, 0, 0, 1, 1)
	root.add_child(countdown)


func _process(delta: float) -> void:
	var t := _telemetry()
	if t == null:
		return
	if not _layout_ready:
		_layout_ready = true
		# The speed cluster shrinks about its bottom-right corner in flight, the N2 cluster about
		# its bottom-left corner.
		speed_cluster.pivot_offset = speed_cluster.size
		nitro_cluster.pivot_offset = Vector2(0.0, nitro_cluster.size.y)
	elif not _flight_active and (_layout_tween == null or not _layout_tween.is_valid()):
		# The settled (not in flight) position of the clusters.
		_speed_base = speed_cluster.position
		_nitro_base = nitro_cluster.position
	if events.race_running:
		events.race_time += delta
	speed_cluster.update_values(t.speed_kmh, t.motor_load, t.boost_kind != &"", t.battery)
	nitro_cluster.update_values(t.n2, t.n2_pending, t.mini_window, t.hop_charge)
	health_bar.set_health(t.health_norm)
	_update_hop(t, delta)
	timer_panel.update_values(events.race_time, events.best_lap, events.lap, events.laps,
		events.race_running)
	_update_timer_layout()
	_update_flight(t)
	_update_minimap(t)
	_update_pursuit(t, delta)
	_update_standings(delta)
	busted_dim.visible = events.pursuit_state == &"busted"


## The car's telemetry: the override of the demo and the tests, or the player's car.
func _telemetry() -> CarTelemetry:
	if telemetry_override != null:
		return telemetry_override
	if Game.player != null:
		return Game.player.telemetry
	return null


## The prompt to hop over a roadblock / toll plaza. The sites of the world are read once (the
## world builds them asynchronously) and the prompt scans the cached list five times a second.
func _update_hop(t: CarTelemetry, delta: float) -> void:
	hop_hint.sync_world()
	var player := Game.player
	if player == null:
		hop_hint.hide_hint()
		return
	hop_hint.update_state(t, player.global_position, player.get_forward(), delta)


## Outside a race there is no clock, so the time panel is hidden and the map moves up.
func _update_timer_layout() -> void:
	if events.race_running == _timer_shown:
		return
	_timer_shown = events.race_running
	if events.race_running:
		# The mode status knows the laps of the race that runs; the first route of the world is
		# only the fallback for a race without a status.
		if events.status_kind != &"race":
			events.laps = _route_laps()
	timer_panel.visible = _timer_shown
	if _timer_shown:
		UI.place(timer_panel, 1, 0, 1, 0, -280, 36, -36, 196)
		UI.place(minimap, 1, 0, 1, 0, -288, 212, -36, 464)
	else:
		UI.place(minimap, 1, 0, 1, 0, -288, 36, -36, 288)


## The number of laps of the active race route (RaceRoute.laps). The world does not say which
## route is running, so the first one is used; a request for an explicit signal is in the status.
func _route_laps() -> int:
	if Game.world == null:
		return DEFAULT_LAPS
	var ids := Game.world.get_route_ids()
	if ids.is_empty():
		return DEFAULT_LAPS
	var route := Game.world.get_route(ids[0])
	if route == null:
		return DEFAULT_LAPS
	return maxi(route.laps, 1)


func _update_flight(t: CarTelemetry) -> void:
	var flying := t.flying or (t.airborne and t.airtime > FLIGHT_AIRTIME)
	if flying != _flight_active:
		_flight_active = flying
		flight.set_active(flying)
		_set_flight_layout(flying)
	if not flying:
		return
	_plumes[0] = float(t.thrusters.get("Nozzle_P1", 0.0))
	_plumes[1] = float(t.thrusters.get("Nozzle_P2", 0.0))
	_plumes[2] = float(t.thrusters.get("Nozzle_P3", 0.0))
	_plumes[3] = float(t.thrusters.get("Nozzle_P4", 0.0))
	flight.set_values(t.downforce_kg, t.pitch_deg, t.altitude_m, _plumes)


## In flight the reveal-stream gauges take the bottom corners, so the speed cluster moves up and
## dims a little. The N2 cluster stays visible (the player spends it in flight): it shrinks a
## little and moves up over the DOWNFORCE ring. The targets are ABSOLUTE, so a quick hop in / hop
## out can never leave the clusters half way.
func _set_flight_layout(active: bool) -> void:
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
	_layout_tween = create_tween()
	_layout_tween.set_ignore_time_scale(true)
	_layout_tween.set_parallel(true)
	# The targets are ABSOLUTE (the settled position plus the shift), so a tween that is killed
	# half way can never make the clusters drift.
	var shift := FlightCluster.flight_speed_shift(root.size) if active else 0.0
	var speed_target := _speed_base + Vector2(0.0, -shift)
	var nitro_target := _nitro_base
	if active:
		nitro_target.y = FlightCluster.flight_nitro_target(root.size, nitro_cluster.size.y)
	_layout_tween.tween_property(speed_cluster, "position", speed_target, LAYOUT_TIME)
	_layout_tween.tween_property(speed_cluster, "scale",
		Vector2.ONE * (FLIGHT_SPEED_SCALE if active else 1.0), LAYOUT_TIME)
	_layout_tween.tween_property(speed_cluster, "modulate:a",
		FLIGHT_SPEED_ALPHA if active else 1.0, LAYOUT_TIME)
	_layout_tween.tween_property(nitro_cluster, "position", nitro_target, LAYOUT_TIME)
	_layout_tween.tween_property(nitro_cluster, "scale",
		Vector2.ONE * (FLIGHT_NITRO_SCALE if active else 1.0), LAYOUT_TIME)
	_layout_tween.tween_property(nitro_cluster, "modulate:a",
		FLIGHT_NITRO_ALPHA if active else 1.0, LAYOUT_TIME)
	speed_cluster.set_battery_visible(not active)
	# Only the 小喷 prompt is hidden: the N2 itself is what the player spends in flight.
	nitro_cluster.set_prompt_visible(not active)


## The world builds its road network asynchronously, so the HUD may ask for the map before the
## world is ready. Reload it when the world changed or when it finished building after we started.
func _needs_map() -> bool:
	if not _map_loaded or _world != Game.world:
		return true
	if _world_polylines.is_empty() and Game.world != null:
		return float(Game.world.get("loading_fraction")) >= 1.0
	return false


func _update_minimap(t: CarTelemetry) -> void:
	var player := Game.player
	if player == null:
		return
	_minimap_timer -= get_process_delta_time()
	if _minimap_timer <= 0.0:
		_minimap_timer = BLIP_PERIOD
		minimap.refresh_blips(player.global_position)
		if _needs_map():
			_world = Game.world
			_map_loaded = true
			_world_polylines = []
			_world_pois = []
			_sky_lanes = []
			if _world != null:
				_world_polylines = _world.get_minimap_polylines()
				_world_pois = _world.get_points_of_interest()
				_sky_lanes = minimap.collect_sky_lanes(_world)
			elif not demo_polylines.is_empty():
				_world_polylines = demo_polylines
				_world_pois = demo_pois
			minimap.set_world(_world_polylines, _world_pois, _sky_lanes)
	minimap.update_map(player.global_position, MinimapPanel.heading_for(player), t.speed_kmh)


func _update_pursuit(t: CarTelemetry, delta: float) -> void:
	if events.heat <= 0 and events.pursuit_state == &"none":
		# The pursuit is over (the state came from the bus): the panel goes away with it.
		# While the state is "busted" / "escaped" the panel stays, and the dim with it.
		pursuit_panel.visible = false
		return
	var player := Game.player
	var player_pos := player.global_position if player != null else Vector3.ZERO
	pursuit.update(t, events.heat, events.pursuit_state, minimap.police_positions(), player_pos,
		delta)
	pursuit_panel.update_values(events.heat, pursuit.units, pursuit.units_max,
		events.pursuit_state, pursuit.evade, pursuit.busted)


func _update_standings(delta: float) -> void:
	_standings_timer -= delta
	if _standings_timer <= 0.0:
		_standings_timer = STANDINGS_PERIOD
		pursuit.rebuild_standings(events.progress, Game.player, _rivals())
		# The standings are only written when they were rebuilt, not every frame.
		race_panel.set_standings(pursuit.standings)
	if events.heat > 0:
		pursuit_panel.visible = true
		race_panel.visible = false
	elif Game.mode == &"race" or events.status_kind == &"race":
		race_panel.visible = true
		pursuit_panel.visible = false
	else:
		race_panel.visible = false


## The rival vehicles of the race.
func _rivals() -> Array[VehicleBase]:
	var out: Array[VehicleBase] = []
	for n in get_tree().get_nodes_in_group("rivals"):
		var v := n as VehicleBase
		if v != null:
			out.append(v)
	return out
