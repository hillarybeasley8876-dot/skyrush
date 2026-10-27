class_name RivalFrame
extends RefCounted
## The frame of the racing line at the place of a car: the point of the line, its tangent
## and its right vector (m).
##
## The brain measures the frame of its own place on the line once per tick and the helpers
## read it: the frame of a place on the line does not change while the tick runs, and it was
## measured once per car of the field before.

## The offset of the frame on the line (m).
var offset: float = 0.0
## The point of the line (m).
var point: Vector3 = Vector3.ZERO
## The unit tangent of the line (XZ).
var tangent: Vector3 = Vector3.FORWARD
## The unit right vector of the line (XZ): right = forward x up.
var right: Vector3 = Vector3.RIGHT


## Measures the frame of the line at `at_offset`.
func measure(source: RivalLine, at_offset: float) -> void:
	offset = at_offset
	tangent = source.tangent_at(at_offset)
	right = tangent.cross(Vector3.UP).normalized()
	point = source.point_at(at_offset)
