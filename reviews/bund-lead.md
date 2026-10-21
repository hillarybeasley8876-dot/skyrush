# Lead notes for bund (mandatory)
IMPORT-CHURN (lead, 08:40, mandatory): Godot imports are now the team-wide bottleneck (934 textures, 3.8 GB import cache, 25+
  callers queued behind the import lock). For your unit: (1) write generated textures/meshes ONLY when their bytes change
  (generate to memory/tmp, compare with the existing file, skip identical) so rebuilds do not touch unchanged files; (2) small
  props and parts use 1024² (or 512²) maps and shared atlases/trim sheets — 2048² only for hero surfaces; (3) never write
  scratch images inside game/ (use tmp/<unit>/); (4) report your texture count + total MB in status.
B-ART1 (lead, vs `hsbc_customs_night_2026.jpg`): the facades are flat tan boxes with punched black windows. The gold look comes
  from LIGHT on neutral granite (textured, albedo ≈ #ABAAA3), not from a tan albedo: in every preview/Godot capture use the uplights
  from bund_lights.json (+ crown floods) so each facade is brightest at the base and the crown with a strong vertical gradient and
  dark shadow lines under every cornice, exactly like the reference photo.
B-ART2: real relief depth: rusticated base (0.15 m grooves), giant-order columns/pilasters (HSBC 6 Ionic columns, single-double-
  double-single), cornices projecting 0.6–1.2 m, window surrounds/pediments 0.15–0.3 m proud, recessed windows 0.3 m. No flat
  painted facades; the reviewer measures relief in a 5 m capture.
B-ART3: the flood wall's river face must show the blue light curtains of the reference (vertical cascades `#1E8BFF`→`#29D3FF`,
  repeating every ~6 m) reflected in the river; Customs House clock faces backlit warm white; Peace Hotel pyramid lit green-teal.
B-ART4: windows are dark reflective glass with only sparse warm amber interiors (≈ 25 %), never black holes.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.
