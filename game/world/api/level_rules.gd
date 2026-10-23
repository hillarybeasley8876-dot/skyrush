extends RefCounted
## The levels of the map: the rule that tells a street from the deck above it.
##
## A street at y = 0 runs under the elevated roads (y = 10 to 31), under the Nanpu bridge
## (y = 42.5) and under the ramps. Two heights are on the SAME level when they differ by at most
## LEVEL metres. The tolerance is never more than 4 m: a deck is 10 m above the street, so a
## bigger tolerance would mix the levels again.

## Two heights are on the same level when they differ by at most this many metres.
const LEVEL := 3.0
## A link joins two lanes whose ends are on the same level (a ramp changes the level slowly, so
## the tolerance of a link is tighter than the tolerance of a level).
const LINK_LEVEL := 1.0
