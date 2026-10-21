# Lead notes for car_model (mandatory) — from the lead's look at the 23:44 glb vs photos 03/09
IMPORT-CHURN (lead, 08:40, mandatory): Godot imports are now the team-wide bottleneck (934 textures, 3.8 GB import cache, 25+
  callers queued behind the import lock). For your unit: (1) write generated textures/meshes ONLY when their bytes change
  (generate to memory/tmp, compare with the existing file, skip identical) so rebuilds do not touch unchanged files; (2) small
  props and parts use 1024² (or 512²) maps and shared atlases/trim sheets — 2048² only for hero surfaces; (3) never write
  scratch images inside game/ (use tmp/<unit>/); (4) report your texture count + total MB in status.
LEAD-BODY (supersedes items 1–2 of the earlier notes; MANDATORY, do this first in the next round):
  The lead wrote the shell builder `blender/lib/roadster_body.py` (core-owned; read it, do not copy/modify it): `body, glass,
  liners = roadster_body.build(col)` returns `Body` (material slots SH_car_paint / M_BlackTrim / SH_glass_gold / M_TBar, sharp
  K-row creases, wells cut, black tail valance below z 0.59, smart-UV'd, bevel + weighted-normal modifiers), `Glass`
  (canopy + T-tops + backlight + side DLO, one clean shell) and `ArchLiners`. Lead preview: captures/blender/lead_body2_studio.jpg.
  1. DELETE your own loft/body/glass/panel-patch code paths and build on this shell (parent everything under `Roadster`).
  2. Doors: split `Door_L`/`Door_R` from `Body` along the dossier door cut lines (side_profile.door_front_cut/rear_cut) with
     bmesh bisect + face selection by side, pivot per dossier; leave a dark inner surface behind them.
  3. Keep/attach your parts: wheels/tyres/brakes, front light bar + headlamp panels, rear light bar (z 0.843–0.857), the black
     valance details (4 nozzles + fan ports + diffuser strakes), plate, markers, wing, interior (seat + COPV), markers/empties.
  4. Panel-gap normal map: bake on this Body's UVs (or draw the gap lines as 4 mm grooves); it must be visible in a close view.
  5. Re-run the overlay checks on the new body (side/top/rear) and the compare_rear capture vs photo 09.
1. **Surfaces look polygonal/triangulated** (visible shading breaks across every facet, twisted quads). The real car is big
   SMOOTH flat panels with crisp creases. Fix: resample the loft along Y every ≤ 0.12 m by linear interpolation
   between the JSON sections (ruled surfaces stay planar), keep each K-row as a marked sharp edge, use smooth
   shading + a Weighted Normal modifier (face-area mode, keep sharp) or harden normals via the 4 mm bevel, so flat
   facets render perfectly flat and only the K-row creases show. No visible triangle seams in any studio view.
2. **Glass reads as transparent orange plastic with chaotic dark triangles inside.** Target = photo 03: one continuous
   dark bronze-gold glossy canopy that reads almost opaque from outside. Blender material: base #3A2718, metallic 0.6,
   roughness 0.04, alpha 0.95 (BLENDED), coat 1.0; name stays `SH_glass_gold`. The glass must be ONE clean shell with
   consistent outward normals (no flipped/overlapping faces → the black triangles), and the cabin under it tidy and dark
   (#12141A) so only faint silhouettes show at grazing angles.
3. **Hood**: remove the black rectangular slot — the vent hood is closed in normal state (panel line at Y +1.80 only).
4. **Front**: the splitter/lower black parts must be a thin integrated lip (photo 03/06), not a separate protruding plate;
   add the thin white front light bar (Z 0.44, emissive #F2F6FF strength 8) and the two headlamp triangles with jewels —
   they must be visible in the front34 studio render.
5. **Rear (photo 09)**: the red light bar is a THICK glowing bar (14 mm lens with a bright 6 mm core, strength 10) that
   wraps slightly at the ends; the 4 nozzles must read clearly: titanium rings + gold throats (#B08458) at Z 0.50 in the
   black valance, with the small black round fan/camera ports and the vertical diffuser strakes below. Make a
   close-up render framed on the valance (camera ~1.2 m behind, Z 0.5) and put it side by side with photo 09 as
   `captures/car_model/compare_rear.jpg`.
6. Emissives must glow in previews (preview uses EEVEE: emission strength ≥ 8 and bloom-free is fine, but the bars must
   be clearly the brightest red/white lines in the frame).

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.
