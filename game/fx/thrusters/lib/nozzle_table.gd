extends RefCounted
## Roadster nozzle layout in Godot coordinates (Y up, -Z forward, +X right).
##
## Source: ref/roadster/DOSSIER.md §5 (nozzle table). The dossier stores positions in Blender
## coordinates (x, y_forward, z_up); the conversion used here is
##     blender (bx, by, bz)  ->  godot (bx, bz, -by)
## and the same conversion applies to the jet directions.
##
## When the car glTF is present the real `Nozzle_*` markers win; this table is the fallback for
## stub cars and for validating a marker's orientation (see thruster_rig.gd).

## Group ids: "rear" (main thrust), "lift" (corner lift), "yaw" (front yaw).
const REAR := "rear"
const LIFT := "lift"
const YAW := "yaw"

## name -> {pos, dir, group, length, radius, speed, spread}
##   length  : jet core length at full thrust, metres
##   radius  : core radius scale (throat 0.03 m -> tip 0.09 m at radius = 0.9)
##   speed   : vapour initial velocity, m/s
##   spread  : vapour cone spread, degrees
##   damping : vapour linear damping, m/s^2 (dossier §6.3: 100, so the lift jet travels
##             v^2/2d = 6.1 m and reaches the road from a 6 m hover, and the yaw jet 1.1 m)
const NOZZLES: Dictionary = {
	"Nozzle_R1": {"pos": Vector3(-0.36, 0.50, 2.085), "dir": Vector3(0, 0, 1),
		"group": REAR, "length": 0.9, "radius": 0.9, "speed": 30.0, "spread": 7.0,
			"rear": true, "damping": 100.0},
	"Nozzle_R2": {"pos": Vector3(-0.12, 0.50, 2.085), "dir": Vector3(0, 0, 1),
		"group": REAR, "length": 0.9, "radius": 0.9, "speed": 30.0, "spread": 7.0,
			"rear": true, "damping": 100.0},
	"Nozzle_R3": {"pos": Vector3(0.12, 0.50, 2.085), "dir": Vector3(0, 0, 1),
		"group": REAR, "length": 0.9, "radius": 0.9, "speed": 30.0, "spread": 7.0,
			"rear": true, "damping": 100.0},
	"Nozzle_R4": {"pos": Vector3(0.36, 0.50, 2.085), "dir": Vector3(0, 0, 1),
		"group": REAR, "length": 0.9, "radius": 0.9, "speed": 30.0, "spread": 7.0,
			"rear": true, "damping": 100.0},
	"Nozzle_P1": {"pos": Vector3(-0.57, 0.15, -1.95), "dir": Vector3(0, -1, 0),
		"group": LIFT, "length": 0.6, "radius": 0.75, "speed": 35.0, "spread": 7.0,
			"damping": 100.0},
	"Nozzle_P2": {"pos": Vector3(0.57, 0.15, -1.95), "dir": Vector3(0, -1, 0),
		"group": LIFT, "length": 0.6, "radius": 0.75, "speed": 35.0, "spread": 7.0,
			"damping": 100.0},
	"Nozzle_P3": {"pos": Vector3(-0.73, 0.15, 1.95), "dir": Vector3(0, -1, 0),
		"group": LIFT, "length": 0.6, "radius": 0.75, "speed": 35.0, "spread": 7.0,
			"damping": 100.0},
	"Nozzle_P4": {"pos": Vector3(0.73, 0.15, 1.95), "dir": Vector3(0, -1, 0),
		"group": LIFT, "length": 0.6, "radius": 0.75, "speed": 35.0, "spread": 7.0,
			"damping": 100.0},
	"Nozzle_P5": {"pos": Vector3(-0.68, 0.30, -2.02), "dir": Vector3(-1, 0, 0),
		"group": YAW, "length": 0.35, "radius": 0.45, "speed": 15.0, "spread": 7.0,
			"damping": 100.0},
	"Nozzle_P6": {"pos": Vector3(0.68, 0.30, -2.02), "dir": Vector3(1, 0, 0),
		"group": YAW, "length": 0.35, "radius": 0.45, "speed": 15.0, "spread": 7.0,
			"damping": 100.0},
}

## Canonical order: rear first, then the perimeter set.
const NAMES: PackedStringArray = [
	"Nozzle_R1", "Nozzle_R2", "Nozzle_R3", "Nozzle_R4",
	"Nozzle_P1", "Nozzle_P2", "Nozzle_P3", "Nozzle_P4",
	"Nozzle_P5", "Nozzle_P6",
]


static func get_nozzle(nozzle_name: StringName) -> Dictionary:
	return NOZZLES.get(String(nozzle_name), {})


## Names belonging to a group, in canonical order.
static func names_in_group(group: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n in NAMES:
		if String(NOZZLES[n]["group"]) == group:
			out.append(n)
	return out


## True when the jet points downwards in the car's local frame (perimeter lift nozzles).
static func is_down_firing(nozzle_name: StringName) -> bool:
	var cfg: Dictionary = get_nozzle(nozzle_name)
	return not cfg.is_empty() and (cfg["dir"] as Vector3).y < -0.5
