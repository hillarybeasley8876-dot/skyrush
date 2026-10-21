extends RefCounted
## Camera-unit settings (own config file, `user://skyrush_camera.cfg`).
## Core `Settings` has no `motion_blur` key yet (see status/camera.md "Requests"), so the
## camera unit owns the toggle until core adds it. Command line override:
## `--motion_blur=off` / `--motion_blur=on`.

const PATH := "user://skyrush_camera.cfg"

var motion_blur: bool = true
var speed_lines: bool = true
var camera_shake: bool = true

signal changed


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		motion_blur = bool(cfg.get_value("camera", "motion_blur", motion_blur))
		speed_lines = bool(cfg.get_value("camera", "speed_lines", speed_lines))
		camera_shake = bool(cfg.get_value("camera", "camera_shake", camera_shake))
	_apply_cli()


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("camera", "motion_blur", motion_blur)
	cfg.set_value("camera", "speed_lines", speed_lines)
	cfg.set_value("camera", "camera_shake", camera_shake)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("camera config: could not save %s (error %d)" % [PATH, err])


func set_motion_blur(enabled: bool) -> void:
	if motion_blur == enabled:
		return
	motion_blur = enabled
	save_to_disk()
	changed.emit()


func set_speed_lines(enabled: bool) -> void:
	if speed_lines == enabled:
		return
	speed_lines = enabled
	save_to_disk()
	changed.emit()


func set_camera_shake(enabled: bool) -> void:
	if camera_shake == enabled:
		return
	camera_shake = enabled
	save_to_disk()
	changed.emit()


## `--motion_blur=off` wins over the saved file (debug / capture runs).
func _apply_cli() -> void:
	var opt := Game.option("motion_blur")
	if opt == "off" or opt == "false" or opt == "0":
		motion_blur = false
	elif opt == "on" or opt == "true" or opt == "1":
		motion_blur = true
	if Game.option("speed_lines") == "off":
		speed_lines = false
	if Game.option("camera_shake") == "off":
		camera_shake = false
