extends Node
## Mutes the music bed of the game, so a capture shows the car and the world alone.
##
## The scene wraps main.tscn:
##   tools/godot.sh movie --movie=out.avi --timeline=res://audio/capture/gameplay_timeline.json
##     --skip-menu --stub=world --scene=res://audio/capture/nomusic.tscn

func _ready() -> void:
	# the director builds itself in its own first frame
	await get_tree().process_frame
	await get_tree().process_frame
	var audio := get_tree().get_first_node_in_group("audio")
	if audio == null:
		push_warning("[audio] the capture scene found no audio director")
		return
	audio.call("set_music_enabled", false)
