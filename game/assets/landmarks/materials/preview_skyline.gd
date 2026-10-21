extends Node3D
## Preview scene setup: the shared night environment (world/env/env_recipe.gd),
## the landmark light rig (materials/landmark_lights.gd) and the reflection
## probes that keep the metals from rendering black.

const EnvRecipe := preload("res://world/env/env_recipe.gd")


func _ready() -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null:
		world_env.environment = EnvRecipe.make_environment({})
	for probe in get_children():
		if probe is ReflectionProbe:
			# UPDATE_ONCE: the r3 review measured the preview at 50-64 fps with
			# UPDATE_ALWAYS (the r2 preview ran at 121-191)
			(probe as ReflectionProbe).update_mode = ReflectionProbe.UPDATE_ONCE
	# the SH_* materials must look in the preview the way they look in game
	MaterialLibrary.apply(self)
