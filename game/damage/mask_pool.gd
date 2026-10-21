extends RefCounted
## The pool of the paint-scrape masks (dossier §7.7: the damage unit must not hold a
## megabyte per car). A car that is never hit owns no mask, and a car that leaves the
## world gives its mask back.
##
## The pool holds at most POOL_SIZE masks and hands out the one that was released the
## longest time ago (the least recently used one). A mask that a car still wears is never
## taken away from it: the pool only holds the masks of the cars that left the world.

const MaskAtlas := preload("res://damage/mask_atlas.gd")

## The number of masks the pool holds at most (the review asks for 16 or less).
const POOL_SIZE := 16
## The number of masks that are built when the director starts. The rest is built while
## the game is idle, so a hit never pays for a megabyte.
const WARM_MASKS := 8

## The masks that are free: the least recently used one comes first.
static var _pool: Array = []


## A mask for a car that was hit.
static func acquire():
	if not _pool.is_empty():
		# The least recently used mask comes first.
		var mask = _pool.pop_front()
		if mask != null:
			mask.clear()
			return mask
	return _new_mask()


## The number of free masks (the director tops the pool up while the game is idle).
static func free_count() -> int:
	return _pool.size()


## Fills the pool, so the first hit of the game does not pay for the megabyte of a mask.
static func warm_up() -> void:
	var masks: Array = []
	for i in WARM_MASKS:
		masks.append(_new_mask())
	for mask in masks:
		release(mask)


## The pool is topped up while the game is idle: a mask costs 1.9 ms to build, and that
## cost must not land on a hit.
static func top_up() -> void:
	while _pool.size() < WARM_MASKS:
		release(_new_mask())


## A mask goes back to the pool. The texture is cleaned with it, so the next car does not
## see the scrape of the car before it.
static func release(mask) -> void:
	if mask == null:
		return
	mask.clean()
	if _pool.size() < POOL_SIZE:
		# The most recently used mask is the last one: it is the one that is dropped last.
		_pool.append(mask)
		return
	# The pool is full: the least recently used mask goes, the new one takes its place.
	_pool.pop_front()
	_pool.append(mask)


## A new mask: the image and its texture (a megabyte each).
static func _new_mask():
	var fresh = MaskAtlas.new()
	fresh.data = Image.create(MaskAtlas.SIZE, MaskAtlas.SIZE, false, Image.FORMAT_RGBA8)
	fresh.data.fill(Color(0.0, 0.0, 0.0, 1.0))
	fresh.texture = ImageTexture.create_from_image(fresh.data)
	return fresh
