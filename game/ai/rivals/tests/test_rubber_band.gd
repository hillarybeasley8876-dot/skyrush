extends Node
## The rubber band of the rivals (dossier 6.2): a rival that leads the player is slowed down,
## a rival that trails is sped up, and the band is off in the last 10 % of the race.


func _ready() -> void:
	var fails := 0
	var normal := RivalBrain.new()
	normal.setup(RivalFleet.preset(&"normal"), 0.0, 1.0, null, 1234)
	var easy := RivalBrain.new()
	easy.setup(RivalFleet.preset(&"easy"), 0.0, 1.0, null, 4321)
	var hard := RivalBrain.new()
	hard.setup(RivalFleet.preset(&"hard"), 0.0, 1.0, null, 99)

	fails += _expect(absf(normal.rubber_factor(0.0, 0.0) - 1.0) < 0.001,
		"no gap -> no band")
	fails += _expect(absf(normal.rubber_factor(100.0, 0.0) - 0.955) < 0.001,
		"100 m ahead -> 0.955")
	fails += _expect(absf(normal.rubber_factor(-100.0, 0.0) - 1.04) < 0.001,
		"100 m behind -> 1.04")
	fails += _expect(absf(normal.rubber_factor(5000.0, 0.0) - 0.93) < 0.001,
		"the band is clamped to the range of the difficulty")
	fails += _expect(absf(normal.rubber_factor(-5000.0, 0.0) - 1.06) < 0.001,
		"the band is clamped to 1.06")
	fails += _expect(absf(normal.rubber_factor(200.0, 0.95) - 1.0) < 0.001,
		"the band is off in the last 10 % of the race")
	fails += _expect(absf(normal.rubber_factor(200.0, 0.9) - 1.0) < 0.001,
		"the band is off at 90 %")

	fails += _expect(easy.rubber_factor(300.0, 0.0) < normal.rubber_factor(300.0, 0.0),
		"easy is slowed down more when it leads")
	fails += _expect(easy.rubber_factor(-300.0, 0.0) < normal.rubber_factor(-300.0, 0.0),
		"easy gains less speed when it trails")
	fails += _expect(hard.rubber_factor(300.0, 0.0) > normal.rubber_factor(300.0, 0.0),
		"hard keeps more speed when it leads")
	fails += _expect(hard.rubber_factor(-300.0, 0.0) > normal.rubber_factor(-300.0, 0.0),
		"hard gains more speed when it trails")

	print("RUBBER BAND TESTS OK (%d failures)" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> int:
	print(("PASS " if condition else "FAIL ") + label)
	return 0 if condition else 1
