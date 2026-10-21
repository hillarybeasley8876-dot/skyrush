extends RefCounted
## The detachable parts of dossier §7.6 and the rules that make them come off.
##
## Only the exact names of CONTRACTS §6 are parts (and the names of the npc cars): the child
## meshes of a part ("Wing_EndPlate_L") and the interior meshes ("DoorCard_L") are not.

enum Zone { FRONT, REAR, SIDE, TOP, ANY }

const BOX := &"box"
const CYLINDER := &"cylinder"

## How a part comes off.
const MODE_DETACH := &"detach"    ## it comes off and flies away
const MODE_WRECK := &"wreck"      ## it only comes off with a violent wreck
const MODE_SPRING := &"spring"    ## it springs open on its hinge, it does not come off

## The zone limits of a car (the share of the body box).
const ZONE_TOP := 0.90
const ZONE_FRONT := 0.55
const ZONE_SIDE := 0.45

## A wheel only comes off with an impact of 0.7 or more (dossier §7.6).
const WHEEL_IMPACT := 0.7
## The Roadster's door springs open at a side hit of 18 m/s or more.
const DOOR_SPRING_SPEED := 18.0
## The angle the door springs open.
const DOOR_SPRING_ANGLE := 15.0

## The families of parts and the exact names of each family.
const FAMILIES: Dictionary = {
	"Bumper_F": ["Bumper_F"],
	"Bumper_R": ["Bumper_R"],
	"Hood": ["Hood"],
	"Diffuser": ["Diffuser"],
	"Wing": ["Wing"],
	"Door": ["Door_L", "Door_R", "Door_FL", "Door_FR", "Door_RL", "Door_RR"],
	"Mirror": ["Mirror_L", "Mirror_R"],
	"Skirt": ["Skirt_L", "Skirt_R"],
	"Wheel": ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"],
}

## The part of every family: the debris body and the rule that tears it off.
const TEMPLATES: Dictionary = {
	"Bumper_F": {"zone": Zone.FRONT, "vn": 22.0, "cumulative": 45.0, "mode": MODE_DETACH,
		"size": Vector3(1.9, 0.25, 0.3), "mass": 14.0, "shape": BOX},
	"Bumper_R": {"zone": Zone.REAR, "vn": 20.0, "mode": MODE_DETACH,
		"size": Vector3(1.8, 0.25, 0.3), "mass": 14.0, "shape": BOX},
	"Hood": {"zone": Zone.FRONT, "vn": 26.0, "mode": MODE_DETACH,
		"size": Vector3(1.2, 0.05, 0.9), "mass": 10.0, "shape": BOX},
	"Diffuser": {"zone": Zone.REAR, "vn": 20.0, "mode": MODE_DETACH,
		"size": Vector3(1.4, 0.1, 0.4), "mass": 9.0, "shape": BOX},
	"Wing": {"zone": Zone.REAR, "vn": 18.0, "mode": MODE_DETACH,
		"size": Vector3(1.4, 0.08, 0.35), "mass": 8.0, "shape": BOX},
	"Door": {"zone": Zone.SIDE, "vn": 12.0, "mode": MODE_WRECK,
		"size": Vector3(0.9, 0.6, 0.08), "mass": 11.0, "shape": BOX},
	"Mirror": {"zone": Zone.SIDE, "vn": 12.0, "mode": MODE_DETACH,
		"size": Vector3(0.25, 0.1, 0.15), "mass": 2.0, "shape": BOX},
	"Skirt": {"zone": Zone.SIDE, "vn": 16.0, "mode": MODE_DETACH,
		"size": Vector3(1.6, 0.12, 0.2), "mass": 5.0, "shape": BOX},
	"Wheel": {"zone": Zone.ANY, "vn": 999.0, "mode": MODE_WRECK, "impact": WHEEL_IMPACT,
		"size": Vector3(0.72, 0.28, 0.72), "mass": 22.0, "shape": CYLINDER},
}

## The Roadster's doors spring open instead of coming off.
const SPRING_DOORS: PackedStringArray = ["Door_L", "Door_R"]
## The instance uniforms the debris copies from the car it came from (the paint colour).
const INSTANCE_UNIFORMS: Array[StringName] = [&"base_color_override", &"panel_offset_y"]


## The exact name -> the family, built once (a hit must not walk the table).
static var _name_family: Dictionary = {}


## The definition of a glb node, or an empty dictionary when the node is not a part.
static func part_for(node_name: StringName) -> Dictionary:
	var name := String(node_name)
	if _name_family.is_empty():
		for family: String in FAMILIES:
			for member: String in FAMILIES[family]:
				_name_family[member] = family
	var family: String = _name_family.get(name, "")
	if family == "":
		return {}
	var part: Dictionary = TEMPLATES[family]
	if family == "Door" and SPRING_DOORS.has(name):
		return {
			"zone": part["zone"], "vn": DOOR_SPRING_SPEED, "mode": MODE_SPRING,
			"size": part["size"], "mass": part["mass"], "shape": part["shape"],
			"family": family,
		}
	return part


## The zone of the car that was hit, from the direction of the other body (the normal of
## the contact points out of the other body, towards the car).
static func zone_from_direction(direction: Vector3) -> int:
	if direction.y < -0.5:
		return Zone.TOP
	if absf(direction.x) > ZONE_SIDE:
		return Zone.SIDE
	if direction.z < -ZONE_FRONT:
		return Zone.FRONT
	if direction.z > ZONE_FRONT:
		return Zone.REAR
	return Zone.ANY


## True when the part must come off after this hit.
## zone: the zone of the hit. v_n: the closing speed. cumulative: the damage the zone took.
## wrecked: the car is wrecked. impact: the impact ratio of the hit.
static func should_detach(part: Dictionary, zone: int, v_n: float, cumulative: float,
		wrecked: bool, impact: float) -> bool:
	if part.is_empty():
		return false
	var part_zone := int(part.get("zone", Zone.ANY))
	if part_zone != Zone.ANY and part_zone != zone:
		return false
	var mode := StringName(part.get("mode", MODE_DETACH))
	if mode == MODE_WRECK:
		return wrecked and impact >= float(part.get("impact", WHEEL_IMPACT))
	if mode == MODE_SPRING:
		return v_n >= float(part.get("vn", 999.0))
	if cumulative >= float(part.get("cumulative", 9999.0)):
		return true
	return v_n >= float(part.get("vn", 9999.0))
