class_name PoliceRadio
extends RefCounted
## The radio chatter of the police (dossier §6.3 and the voice manifest of the audio unit).
##
## Every line is shown as a toast with the style "police" and, when the audio unit is running, it
## is also spoken with the radio voice of the manifest. The lines are the ones of the dossier:
## "嫌疑车辆，立即靠边停车！" / "请求支援！" / "部署路障！" / "目标飞走了！".

## id -> {text: the Chinese line, voice: the id of the audio unit's voice manifest}.
const LINES: Dictionary = {
	&"stop": {"text": "嫌疑车辆，立即靠边停车！", "voice": &"radio_suspect"},
	&"backup": {"text": "请求支援！", "voice": &"radio_reinforce"},
	&"roadblock": {"text": "部署路障！", "voice": &"radio_roadblock"},
	&"checkpoint": {"text": "前方路口设卡", "voice": &"radio_checkpoint"},
	&"drone": {"text": "无人机已升空", "voice": &"radio_drone"},
	&"heavy": {"text": "重型车辆准备拦截", "voice": &"radio_heavy"},
	&"flee": {"text": "目标飞走了！", "voice": &"radio_escape"},
	&"lost": {"text": "目标失去视线", "voice": &"radio_lost"},
	&"found": {"text": "重新发现目标", "voice": &"radio_found"},
	&"all_units": {"text": "全体单位注意", "voice": &"radio_all_units"},
	&"airspace": {"text": "全体单位，注意管制", "voice": &"radio_airspace"},
	&"emp": {"text": "EMP锁定！", "voice": &"radio_emp"},
	&"emp_pulse": {"text": "EMP脉冲！", "voice": &"radio_emp_pulse"},
	&"spikes": {"text": "前方投放钉刺带", "voice": &"radio_spikes"},
	&"hold": {"text": "保持追踪，不要开火", "voice": &"radio_hold"},
}

## The gap between two lines of the same kind (s).
const MIN_GAP := 7.0

## The tick clock of the radio (s): the chatter runs on the game clock, not on the wall clock.
static var clock: float = 0.0
static var _last_time: Dictionary = {}


## Advances the clock of the radio (the dispatcher calls it every tick).
static func tick(dt: float) -> void:
	clock += dt


## Says a line: the toast for the HUD and, when the audio unit is there, the radio voice.
static func say(id: StringName, min_gap: float = MIN_GAP) -> void:
	var line: Dictionary = LINES.get(id, {}) as Dictionary
	if line.is_empty():
		return
	var last := float(_last_time.get(id, -99.0))
	if clock - last < min_gap:
		return
	_last_time[id] = clock
	Events.toast.emit(String(line["text"]), &"police")
	_voice(StringName(line["voice"]))


## The radio voice of the audio unit (the group "audio"), with the radio squelch in front.
static func _voice(id: StringName) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio := tree.get_first_node_in_group(&"audio")
	if audio == null:
		return
	if audio.has_method("play_voice"):
		audio.call("play_voice", id)


## The line of a radio id, for the tests and the HUD.
static func text_of(id: StringName) -> String:
	var line: Dictionary = LINES.get(id, {}) as Dictionary
	return String(line.get("text", ""))
