extends Node
## Cycles the emission colour of the LED meshes of a landmark (the Oriental Pearl Tower).

## The colours the LEDs cycle through.
const COLORS: Array[Color] = [Color("ff3fa4"), Color("8a3cff"), Color("2e7bff")]
## The seconds of a full cycle.
const PERIOD := 40.0

var materials: Array[StandardMaterial3D] = []
var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, PERIOD)
	var phase: float = _elapsed / PERIOD * float(COLORS.size())
	for i in materials.size():
		var a: Color = COLORS[i % COLORS.size()]
		var b: Color = COLORS[(i + 1) % COLORS.size()]
		var t: float = phase - floor(phase)
		materials[i].emission = a.lerp(b, t)
