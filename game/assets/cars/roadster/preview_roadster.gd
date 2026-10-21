extends Node3D
## Preview scene for the hero Roadster.
##
## The glb is imported with its own StandardMaterial3D surfaces; the shared
## shader library (CONTRACTS.md §2) replaces the SH_* materials so the shots
## show the game look: the Ano White clear-coat paint, the gold canopy and the
## red emissive light bars.

const CAR := "Roadster"


func _ready() -> void:
	var car := get_node_or_null(CAR)
	if car == null:
		push_warning("preview_roadster: no %s node" % CAR)
		return
	var swapped := MaterialLibrary.apply(car)
	print("preview_roadster: %d surfaces swapped to the shader library" % swapped)
