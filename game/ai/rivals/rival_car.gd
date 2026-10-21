class_name RivalCar
extends ArcadeCar
## A rival racer: an ArcadeCar (the same physics as the player) driven by a RivalBrain along
## the racing line of the route.
##
## The car carries the brain, the racing name and the paint colour. The brain writes the
## driving inputs every physics tick, before the car pushes them into the drive module.

## The brain that drives this car.
var brain: RivalBrain = null
## The racing name (an invented Chinese handle).
var rival_name: String = ""
## The paint colour of the body.
var paint: Color = Color.WHITE
## The index of the racer in the fleet (0..5).
var index: int = 0
## The time the brain needed for the last tick (microseconds).
var brain_usec: int = 0
## The per-tick context, filled by the rival director.
var _context: RivalContext = RivalContext.new()


func _ready() -> void:
	super._ready()
	team = VehicleBase.Team.RIVAL
	display_name = rival_name
	add_to_group("rivals")
	add_to_group("vehicles")
	var visual := get_visual_root()
	if visual != null:
		RivalVisual.apply_paint(visual, paint)
		await RivalLivery.apply(visual, index)


## The distance along the racing line (m), unwrapped over the start line.
func progress() -> float:
	return brain.travelled if brain != null else 0.0


## The offset of the car on the racing line (m).
func line_offset() -> float:
	return brain.offset if brain != null else 0.0


## Sets the context the brain reads this tick.
func set_context(context: RivalContext) -> void:
	_context = context


## The brain drives the car for one tick. The director calls it: the far rivals are ticked
## at half the rate and hold their last controls in between.
func tick_brain(delta: float) -> void:
	if brain == null:
		return
	var started := Time.get_ticks_usec()
	brain.tick(delta, self, _context)
	brain_usec = Time.get_ticks_usec() - started


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
