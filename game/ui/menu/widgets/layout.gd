extends RefCounted
## Layout helpers for the menu.
##
## `Control.set_anchors_preset()` keeps the *current* rect, so a control that is already in the
## tree and still has its default zero size stays zero-sized after the call. `fill()` sets the
## full-rect anchors and zeroes the offsets, which is what every menu screen wants.

## Makes the control fill its parent.
static func fill(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
