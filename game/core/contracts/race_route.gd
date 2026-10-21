class_name RaceRoute
extends Resource
## A race/pursuit route through the city. Produced by the world unit, consumed by modes and AI.

@export var id: StringName = &""
@export var title: String = ""
@export var laps: int = 1
## Checkpoint gates in order; each transform's origin is the gate centre, -Z = driving direction.
@export var checkpoints: Array[Transform3D] = []
@export var gate_width: float = 24.0
## Ideal racing line for rival AI (closed for circuits).
@export var racing_line: Curve3D
## Start grid slots, index 0 = pole. -Z = driving direction.
@export var grid: Array[Transform3D] = []
