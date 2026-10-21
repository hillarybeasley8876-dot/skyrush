extends RefCounted
## The heading convention of city.json (data/city/SCHEMA.md): `heading_deg` 0 = north (−Z),
## 90 = east (+X), 180 = south (+Z), 270 = west (−X).
##
## A Godot node with `rotation.y = yaw` looks along (−sin yaw, 0, −cos yaw), so the yaw of a
## heading is its negative. Every conversion in the world unit goes through this file.

## The yaw (rotation.y) of a heading in degrees.
static func yaw_from_heading(heading_deg: float) -> float:
	return -deg_to_rad(heading_deg)


## The direction a heading points to (0 = north = −Z, 90 = east = +X).
static func forward_from_heading(heading_deg: float) -> Vector3:
	var yaw := yaw_from_heading(heading_deg)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## The basis whose −Z points along the heading.
static func basis_from_heading(heading_deg: float) -> Basis:
	return Basis(Vector3.UP, yaw_from_heading(heading_deg))