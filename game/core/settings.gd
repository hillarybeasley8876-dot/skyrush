extends Node
## Player settings (autoload "Settings"): quality preset, audio volumes, persisted to user://.
## Units read `quality` / `feature()` to scale their effects; the menu unit writes through set_*().

signal changed()

const PATH := "user://settings.cfg"
## Feature switches per quality preset. Units must respect these instead of inventing their own.
const PRESETS: Dictionary = {
	&"low": {"volumetric_fog": false, "ssr": false, "ssao": false, "rain": false, "shadows": 1, "traffic": 0.5, "particles": 0.4},
	&"medium": {"volumetric_fog": false, "ssr": true, "ssao": true, "rain": true, "shadows": 2, "traffic": 0.75, "particles": 0.7},
	&"high": {"volumetric_fog": true, "ssr": true, "ssao": true, "rain": true, "shadows": 3, "traffic": 1.0, "particles": 1.0},
	&"ultra": {"volumetric_fog": true, "ssr": true, "ssao": true, "rain": true, "shadows": 4, "traffic": 1.25, "particles": 1.3},
}
const BUSES: Array[StringName] = [&"Music", &"SFX", &"Voice"]

var quality: StringName = &"high"
var volumes: Dictionary = {&"Master": 0.9, &"Music": 0.7, &"SFX": 0.9, &"Voice": 1.0}
## A run with --quality=... (every tools/godot.sh run) neither reads nor writes the player's file, so
## tests that change settings cannot leak a preset into later captures or into the player's game.
var _persist := true


func _ready() -> void:
	_ensure_buses()
	_persist = not Game.has_option("quality")
	if _persist:
		_load()
	else:
		quality = StringName(Game.option("quality"))
	_apply_volumes()


func feature(key: String) -> Variant:
	return (PRESETS.get(quality, PRESETS[&"high"]) as Dictionary).get(key)


func set_quality(preset: StringName) -> void:
	if PRESETS.has(preset):
		quality = preset
		_save()
		changed.emit()


func set_volume(bus: StringName, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save()
	changed.emit()


func _ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, &"Master")


func _apply_volumes() -> void:
	for bus: StringName in volumes:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(volumes[bus]), 0.0001)))


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	quality = StringName(cfg.get_value("video", "quality", String(quality)))
	for bus: StringName in volumes:
		volumes[bus] = float(cfg.get_value("audio", String(bus), volumes[bus]))


func _save() -> void:
	if not _persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality", String(quality))
	for bus: StringName in volumes:
		cfg.set_value("audio", String(bus), volumes[bus])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])
