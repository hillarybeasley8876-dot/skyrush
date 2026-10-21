extends RefCounted
## The dev switches of the fx unit: `--fx-no-<family>` switches one family of effects off.
##
## They exist for the bisect of a renderer error: with `--fx-no-thrusters` (and the other
## families) the run tells which effect draws the offending geometry. They are off in a normal
## run, so the game is never affected by them.

var no_thrusters: bool = false
var no_ignition: bool = false
var no_ribbons: bool = false
var no_charge_flash: bool = false
var no_skid: bool = false
var no_splash: bool = false
var no_debris: bool = false
var no_smoke: bool = false
var no_spray: bool = false


func _init() -> void:
	no_thrusters = _flag("fx-no-thrusters")
	no_ignition = _flag("fx-no-ignition")
	no_ribbons = _flag("fx-no-ribbons")
	no_charge_flash = _flag("fx-no-charge-flash")
	no_skid = _flag("fx-no-skid")
	no_splash = _flag("fx-no-splash")
	no_debris = _flag("fx-no-debris")
	no_smoke = _flag("fx-no-smoke")
	no_spray = _flag("fx-no-spray")


## True when the given switch was asked for on the command line.
static func _flag(name: String) -> bool:
	return Game.option(name) == "true"
