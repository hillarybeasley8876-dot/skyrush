# 飞驰申城 SKYRUSH: NEON SHANGHAI — game bible (SPEC.md)

Core-owned by the lead (Opus). Workers (MiniMax M3.1) read it; only the lead edits it.
Companion docs: `ART.md` (art bible — binding), `CONTRACTS.md` (code contracts + file ownership),
`ref/*/DOSSIER.md` (research), `briefs/<unit>.md` (one per unit), `status/<unit>.md` (checkpoints).

## 1. Pitch
Night, rain-slick, neon Shanghai, a few years from now. You drive the new **Tesla Roadster
("Rocket" trim)** revealed 2026-10-15: 0–100 km/h in under a second, cold-gas thrusters that make it
hop, hover, barrel-roll and fly on marked sky lanes. QQ飞车 drift-and-boost handling, Burnout-style
takedowns with slow-motion crash cams, NFS-style police pursuits, and a recognizable compressed
Shanghai: 延安高架 with the 龙柱 interchange, 南北高架, the 南浦大桥 spiral ramp, the Bund (外滩), the
river, 陆家嘴 towers, a toll plaza (收费站), gas stations (加油站) and flash-charging stations (闪充站).

## 2. Pillars (every unit is judged against these)
1. **The car is the star.** The Roadster must be instantly recognizable from the reveal (wedge
   body, black arrowhead canopy, flying buttresses, full-width red rear light bar, four round rear
   nozzles). The thruster plumes are the signature effect — layered, physical, gorgeous.
2. **Speed you can feel.** 60 fps at 1080p, FOV ramp, camera lag, speed lines, wind, motion blur,
   boost punch. Drifting is easy to start, rewarding to chain (QQ飞车 小喷/双喷/落地喷).
3. **Shanghai, then cyberpunk.** Real landmarks and road furniture first (piers, parapet flower
   boxes, overhead gantries, Bund floodlights), then the 2049 layer (holograms, neon, flying lanes).
4. **Everything is detailed.** No flat untextured surfaces anywhere the camera can see. Every
   material has a texture or a procedural detail layer (normal, roughness breakup, dirt, wear).
5. **Crashes have weight.** Rigid bodies, deformation, flying parts, sparks, smoke, slow-mo.

## 3. Game structure
- **Title / menu** → **Free roam** (default), **Race** (竞速赛: checkpoints vs 5 rivals),
  **Pursuit** (警匪追逐: escape the police, or take them down).
- Free roam has police that react to offences (speeding past a patrol, ramming, running a toll
  gate without paying = flying over it). Heat 1–5. Escape by breaking line of sight for the
  cooldown time, or by flying where they cannot follow.
- Stunts give score + boost: 飞跃加油站, 飞跃收费站, 飞跃车阵, 飞跃路障, near miss (擦肩而过), drift
  chains, barrel roll, long airtime, takedowns (撞废警车).
- Charging stations (申城闪充): drive through the lane at any speed → 0.45 s flash → battery and
  air tank refilled, short "charge" boost.

## 4. Controls (registered in core/input_setup.gd — do not redefine)
| Action | Keyboard | Gamepad |
|---|---|---|
| accelerate / brake-reverse | W/↑, S/↓ | RT, LT |
| steer | A/D, ←/→ | left stick |
| drift (hold) | Shift | RB |
| N₂ boost (氮气) | Ctrl / J | A |
| 小喷 mini boost | re-press accelerate in the window, or K | B |
| hop (tap) / Big Hop (hold, release) / hover (hold in air) | Space | X |
| leave sky lane early | F | L3 |
| barrel roll left / right (airborne) | Q / E | D-pad ← / → |
| look back / camera | C / V | LB / Y |
| horn / reset car / pause | H / R / Esc | R3 / Back / Start |

## 5. Feel targets — `ref/gameplay/DOSSIER.md` is the tuning authority (§0 TL;DR, §4–§5, §8)
- Base top speed 250 km/h, N₂ boost 300 km/h for 3.0 s, hard cap 330 km/h; 0–100 km/h 2.3 s
  (0.9 s with the 完美起步 thruster launch). Mass 1,900 kg, Jolt, 120 Hz, CCD, ShapeCast wheels.
- QQ飞车 drift: assisted GRIP→DRIFT→RECOVER, β 26°–52°, a 3 s drift ≈ one N₂ slot; 小喷 window
  0.50 s on clean exits, 空喷/落地喷, CW/WCW/CWW speed-cap stacking.
- ONE resource N₂ (2 COPV slots × 100): boost 100, hop 25, Big Hop 50 (apex 7.8 m — clears a gas
  station canopy with a short hover), hover 12/s, barrel roll 20 (360° in 0.70 s), sky lane 10/s.
- Sky lanes (飞行航道): launch pad ≥ 120 km/h + ≥ 25 N₂ → on-rails flight in a 14 × 8 m tube, rings
  refill N₂, exit with a cold-gas puff. Charge bays (闪充): ≥ 60 km/h → N₂ 200, battery full, +20 HP.
- Camera: vFOV 62° → 84° max, position lag λ 14/s, yaw λ 7/s (4.5/s drifting); takedown cam 2.7 s
  with 0.30× slow-mo (§3.5 of the dossier).

## 6. Map (stylized, compressed ≈ 0.45× real distances; details in ref/shanghai/DOSSIER.md)
Origin at the Bund end of 延安东路; X east, Z south, Y up, metres. Districts:
1. **外滩 The Bund** (west bank of the 黄浦江): 中山东一路 6 lanes + promenade + floodwall, the
   classic façades with gold floodlighting, 外白渡桥 at the north end.
2. **延安高架** E–W from the Bund westward, double-deck interchange with **南北高架** at the
   **龙柱** (dragon pillar) junction; ramps down to ground streets.
3. **陆家嘴** (east bank): 东方明珠, 金茂, 环球金融中心, 上海中心, circular skybridge, 世纪大道.
4. **南浦大桥** south: H-towers, cable fans, the Puxi **spiral approach ramp**.
5. **延安东路隧道** under the river (Bund ↔ Lujiazui).
6. **Expressway + toll plaza** at the west/south edge (申城收费站), gas station and charging stations
   along main roads, flight lanes (飞行通道) over selected elevated sections and across the river.

## 7. Production
- Engine Godot 4.7.2 (Forward+, Metal, Jolt). Project `game/`. Assets built in Blender 5.2 by
  Python scripts in `blender/`, exported to `game/assets/**.glb`. No binary edits by hand.
- Units are built by MiniMax M3.1 workers from `briefs/`, reviewed by the lead with screenshots,
  telemetry and tests, then sent back with numbered feedback until they pass.
- Every unit has a fallback stub; the game always boots (`tools/godot.sh play`).
- Commits: the lead commits after each accepted milestone (`git` in `~/m/skyrush`).
