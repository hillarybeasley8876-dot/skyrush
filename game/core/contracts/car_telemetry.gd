class_name CarTelemetry
extends RefCounted
## Per-vehicle state snapshot written by the vehicle unit every physics tick and read by HUD, audio,
## FX and camera. Contract owned by core: units read these fields, only the vehicle unit writes them.
## Resource model (ref/gameplay/DOSSIER.md §5.2): ONE resource, N₂ (氮气), 2 COPV slots of 100 units.

var speed_kmh: float = 0.0
## Signed speed along the car's forward axis (negative when reversing), km/h.
var forward_speed_kmh: float = 0.0
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
## 0..1 motor load for the EV whine / inverter sound.
var motor_load: float = 0.0
var grounded_wheels: int = 4
var airborne: bool = false
var airtime: float = 0.0
## Rear-axle slip 0..1 (tyre squeal, smoke, skid marks) and signed slip angle β in degrees.
var rear_slip: float = 0.0
var slip_angle_deg: float = 0.0
## &"grip", &"drift", &"recover".
var drift_state: StringName = &"grip"
var drift_time: float = 0.0
## N₂ units 0..200 (slot 1 = 0..100, slot 2 = 100..200) and the uncommitted gain of the current
## drift (shown striped in the filling slot until the drift ends cleanly).
var n2: float = 100.0
var n2_pending: float = 0.0
## Active boost: &"" (none), &"nitro", &"mini", &"air_mini", &"landing", &"launch", &"charge".
var boost_kind: StringName = &""
var boost_time_left: float = 0.0
## True while a 小喷 / 落地喷 input window is open (HUD shows the prompt).
var mini_window: bool = false
## Hop charge 0..1 while the hop key is held (Big Hop ring on the HUD).
var hop_charge: float = 0.0
var hovering: bool = false
var rolling: bool = false
## Battery 0..1: drains with motor use, refilled by charge stations; < 0.15 limits top speed.
var battery: float = 1.0
## Sky lane flight.
var flying: bool = false
var sky_lane_progress: float = 0.0
## Reveal-stream HUD gauges: height above ground (m), attitude (deg), downforce (kg), g-load.
var altitude_m: float = 0.0
var pitch_deg: float = 0.0
var roll_deg: float = 0.0
var downforce_kg: float = 0.0
var g_load: float = 1.0
## Thruster outputs 0..1 per nozzle marker name (&"Nozzle_R1".. &"Nozzle_P6") for FX and audio.
var thrusters: Dictionary = {}
var health_norm: float = 1.0
