extends RefCounted
## The physics layers of the world (the numbers the core uses for its own bodies).
##
## The cars drive on layer 2 with the mask 0b111, so they hit the world (1), the other cars (2)
## and the props (4). The triggers (8) and the debris (16) are not in that mask.

## The world: the ground, the roads, the buildings.
const WORLD := 1 << 0
## The cars.
const VEHICLE := 1 << 1
## The street furniture: the lamps, the trees, the masts, the bollards.
const PROP := 1 << 2
## The trigger areas: the charge bays, the stunt gates, the sky lane pads.
const TRIGGER := 1 << 3
## The debris of a broken barrier arm.
const DEBRIS := 1 << 4
