# Lead notes for landmarks (mandatory)
IMPORT-CHURN (lead, 08:40, mandatory): Godot imports are now the team-wide bottleneck (934 textures, 3.8 GB import cache, 25+
  callers queued behind the import lock). For your unit: (1) write generated textures/meshes ONLY when their bytes change
  (generate to memory/tmp, compare with the existing file, skip identical) so rebuilds do not touch unchanged files; (2) small
  props and parts use 1024² (or 512²) maps and shared atlases/trim sheets — 2048² only for hero surfaces; (3) never write
  scratch images inside game/ (use tmp/<unit>/); (4) report your texture count + total MB in status.
L-ART1 (lead): Oriental Pearl spheres render WHITE — must be glossy pink-magenta glass `#B0306A` (metallic 0.3, roughness 0.15)
  with silver bands `#C8CCD0`, plus the separate LED dot-grid shells animating pink→violet→blue (dossier §6.1). At night the OPT is
  the most colourful object on the skyline.
L-ART2 (lead): the dragon pillar relief is a flat brown 2D silhouette printed on a white tiled cylinder. Dossier §1.2: brushed
  stainless `#B9BCBE` (metallic 1, roughness 0.30, vertical brushing), dark patinated bronze relief `#3B2F25` with raised edges
  `#8A6A3E`, 0.12 m deep normal+height, 9 angular archaic kui-dragons spiralling up between deck levels, square-spiral 雷纹 background
  filling all gaps, sun disc east / moon west. Generate the height map procedurally (numpy) with real relief (bevelled edges, scales
  as repeated chevrons), bake normals; show a 2 m close-up and compare with `ref/shanghai/sheets/c_pillar.jpg`.
L-ART3 (lead): Lujiazui towers read as black slabs with sparse orange dots. Use the facade shader office preset with ~35–40 % lit
  windows in cool/neutral whites, lit crowns (Jin Mao gold OK; SWFC white edge + aperture outline; Shanghai Tower white dotted floor
  bands and notch line), and give 2–3 backdrop towers giant LED ad facades (hologram/LED shader, energy ≤ E2.5).

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## ART-NIGHT (10-20 10:20, evidence: captures/lead_view1_{bund,lujiazui,dragon,yanan,spiral,sky,toll,charge}.jpg, captures/lead_view2_{pudong,pearl,pillar}.jpg (main.tscn --skip-menu --env-only)) — mandatory, see ART.md §11
L-NIGHT1: Lujiazui reads dark from the Bund and from the air: the Shanghai Tower, SWFC and Jin Mao are grey
  silhouettes with no lighting (lead_view1_lujiazui, lead_view1_sky). Give every landmark its real night LED
  signature (ART.md §11): Shanghai Tower twisting LED lines + crown; SWFC opening outlined blue-white + edge
  lines; Jin Mao gold-white tiered crown and banding; red aviation beacons blinking 1 Hz on every top.
  Emission energy so they are the second-brightest thing in frame after the player car (glow picks them up).
L-NIGHT2: Oriental Pearl (lead_view2_pearl) reads, but add the small spheres between the columns, LED dot
  chasing on the spheres (animated in the shader, 0.5–1 Hz), lit column edges and the base spheres.
L-NIGHT3: the dragon pillar is not readable under the decks at night (lead_view2_pillar): its relief needs
  its own uplights (warm gold from the base, like the real one) and a lit plinth.
