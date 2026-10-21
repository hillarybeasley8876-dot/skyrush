extends Control
## The crisp source of the logo's glow: the canvas the glyphs are drawn into before the blur.
##
## The logo hands over a painter (its own draw function), so the glow and the crisp glyphs share
## one layout and one advance loop.

## Draws the glyphs (the logo's own painter; the canvas item is the argument).
var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
