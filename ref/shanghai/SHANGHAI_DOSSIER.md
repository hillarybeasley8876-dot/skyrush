# SKYRUSH: NEON SHANGHAI — Shanghai Roads + Landmarks Dossier (v1, 2026-10-19)

For the implementer (Blender procedural Python + Godot 4.7.2). Read §0 first. Every number is tagged:
**(src)** = from a cited source, **(est.)** = my estimate (from photos/OSM/engineering norms),
**(unverified)** = plausible but not confirmed. **GAME** = the value you should actually build.

Companion files (all under `/Users/minimax/m/skyrush/ref/shanghai/`):
- `build/map_layout_v1.json` — every game coordinate in this doc, machine-readable (river banks, roads, landmarks).
- `build/map_sketch_v1.png` — top-down sketch of the game map (north up, 500 m grid).
- `img/INDEX.md` — 86 reference photos in 9 topic folders (`img/01_…` to `img/09_…`), licence + source per photo.
- `sheets/*.jpg` — contact sheets of those photos (fast visual lookup); `sheets/c_pillar.jpg` = dragon-pillar close-ups.
- `scripts/` — how OSM data was turned into game coordinates (`maplib.py`, `build_river.py`, `build_map.py`).

Contents: §0 conventions · §1 dragon-pillar interchange · §2 elevated-road kit · §3 Nanpu + spiral, Lupu ·
§4 tunnels · §5 the Bund · §6 Lujiazui · §7 toll plaza · §8 gas + EV charging · §9 street kit ·
§10 GAME MAP (coordinates) · §11 night palette · §12 do/don't · §13 sources · §14 open questions ·
§15 **texture & material detail spec** (read it before making any texture).

---------------------------------------------------------------------------------------------------
## 0. Conventions (non-negotiable)

1. Units = metres. Axes: **X = east, Z = south, Y = up** (Godot default: north = −Z). Origin (0,0,0) =
   centre of the junction of Yan'an East Rd (延安东路) and Zhongshan East-1 Rd (中山东一路, the Bund), at ground.
2. Ground is flat: **Y = 0** everywhere on land (Shanghai is flat). Huangpu water surface **Y = −3.0** (est.).
   Bund flood-wall promenade top **Y = +2.5** (est.).
3. **Objects keep REAL size** (buildings, bridges, piers, lamps, signs, cars). Only the *distances between districts*
   are compressed (§10). Never scale a landmark to make it fit; move it.
4. Night is the default time of day. Every material needs a night look (emission or lit-by-lamps). Palette: §11.
5. Text on signs: use **real Chinese + English** pairs for place names (外滩 The Bund). Brand names must be **parody**
   (§8, §9). Fonts: Chinese = Source Han Sans SC Bold (思源黑体 Bold); Latin = a DIN-like condensed bold
   (e.g. "Barlow Semi Condensed Bold"), as stand-ins for the official 交通标志专用字体 (est.).

---------------------------------------------------------------------------------------------------
## 1. Yan'an Rd / N–S Elevated interchange (延安路立交, "延中立交") and the Dragon Pillar (龙柱)

### 1.1 Facts
| item | value | source |
|---|---|---|
| what | fully directional ("全互通/定向式") stack, Yan'an Elevated (E–W) × N–S Elevated (成都路高架) | (src) 吴念祖 via 上海纪实 2017; 赵志荣 via 解放日报 2015 |
| support concept | **one central pillar + four "T-piers" (T墩) on the four sides** carry all ramps | (src) 赵志荣, jfdaily 2015-04-20 |
| levels | ground roads; **Yan'an Elevated on level 2; left-turn ramps on levels 3 and 4; N–S Elevated on level 5 (top)** | (src) 赵志荣 |
| level count / height | "5 levels, 31 m high, tallest in Asia when built" | (src) 张耿耿, 瞭望东方周刊 2019 |
| "six-level stack" | Wikipedia counts the surface service road + footbridge too | (src) en.wikipedia "Stack interchange" |
| pillar (PM109墩) | **Ø 5.0 m, height 32 m, pile length 62 m**; other accounts say Ø 4.2 m | (src) zh.wikipedia 延安高架路; 赵志荣 (5 m); 吴念祖/张耿耿 (4.2 m) |
| foundation | 36 steel pipe piles Ø 0.9 m × 64 m (张耿耿) / 28 piles in an octagon of 14.5 m side (zh.wiki) | (src) |
| cladding | stainless steel ("白钢") with forged-brass/bronze relief ("黄铜锻造的祥龙腾云") | (src) zh.wikipedia |
| artwork | 《龙腾万里 日月同辉》 by sculptor **赵志荣** (上海油画雕塑院); dragons copied from **Spring-and-Autumn bronze vessels** (archaic 夔龙 style), *not* Ming/Qing dragons; >9 dragons big and small, plus phoenix + sun/moon motifs; drawn flat then "rolled" around the column; ~10 months to make | (src) 赵志荣 interview, jfdaily 2015 |
| opened | N–S Elevated south section 10 Dec 1995 (pillar built 1995) | (src) en/zh wikipedia |

Photo reading (`sheets/c_pillar.jpg`, `img/01_dragon_pillar_interchange/pillar_day_2022.jpg`): today the column reads as
**brushed silver steel** with **very dark bronze/black relief** (not shiny gold), relief in panels between deck levels,
interlaced angular hooks + spirals (雷纹 thunder pattern). Decks are beige-grey concrete with **white planter boxes** on
top of every parapet. Under-deck: thin LED strip along deck edges; piers wrapped in ivy.

### 1.2 GAME build spec — pillar
- Cylinder **Ø 5.0 m**, from Y = 0 to Y = 29.4 (underside of the top deck), 48 radial segments.
- Plinth: Ø 6.4 m × 0.6 m, dark granite `#3A3A3C`, roughness 0.6.
- Base material: brushed stainless `#B9BCBE`, metallic 1.0, roughness 0.30, vertical brushing (anisotropy or a
  stretched noise in the roughness map).
- Relief material: dark patinated bronze `#3B2F25`, metallic 1.0, roughness 0.45; raised edges `#8A6A3E`
  (curvature mask). Relief = normal + displacement map, depth 0.12 m (est.), wrapped as one 15.7 m × 29 m texture
  (circumference × height). Content: **9 serpentine dragons spiralling upward** (body width 0.45–0.6 m, length 6–8 m),
  background filled with square spirals/hooks; a sun disc (Ø 1.2 m) near the top on the east face, a moon on the west.
- **DO**: archaic, angular, flat-relief bronze-vessel dragons. **DON'T**: gold Chinese-restaurant dragon with whiskers,
  pearl, flames, or any emissive glow on the relief.
- Night: 4 ground uplights at the plinth, 3000 K `#FFC98A`, 25° beams; plus deck-underside light. Pillar must read as
  a warm silver column with dark ornament.

### 1.3 GAME build spec — deck levels and ramps (local frame: pillar at (0,0); real size)
| level | what | deck surface Y | deck depth | notes |
|---|---|---|---|---|
| L0 | Yan'an Rd / Chongqing Rd surface roads | 0 | – | 4+4 lanes + bike lanes |
| L1 | pedestrian footbridge (glass + steel rails) | 5.5 | 1.0 | optional; ring around the junction (src photo) |
| L2 | Yan'an Elevated main line, 3+3 lanes, 27 m GAME (real 25.5 m) | **9.0** | 1.8 | (est.) |
| L3 | left-turn ramps (1–2 lanes, 8.0–10.5 m) | **16.5** | 1.6 | (est.) |
| L4 | left-turn ramps | **24.0** | 1.6 | (est.) |
| L5 | N–S Elevated main line, 2+2 lanes inside the junction (OSM) | **31.0** | 1.6 | (src) 31 m height |
Spacing ≈ 7.3 m per level → ≥ 5.5 m clearance under every deck (Shanghai minimum for motor lanes: 5.0 m (src)).

Plan (from OSM 2026 + aerial photo): the N–S line crosses the junction diagonally **NNW→SSE** (it jogs ~300 m east,
from Chengdu Rd in the north to Chongqing Rd in the south); the Yan'an line crosses **WSW→ENE**. Left-turn ramps
(L3/L4) sweep in arcs of **R ≈ 60–80 m** (est.) and pass *over the central pillar*, forming a pinwheel; right-turn
ramps are outer arcs **R ≈ 110–150 m** (est.) on L2–L3, supported by the four T-piers placed ~45 m (est.) from the
pillar on the four diagonals. GAME simplification:
- 4 left-turn ramps: EB→NB and WB→SB cross the centre on L3; NB→WB and SB→EB cross on L4. Each ramp leaves its
  main line **300 m before** the pillar, climbs/descends at ≤ 5 % while curving (90° arc, R = 70 m, the arc midpoint
  passing ≤ 3 m from the pillar axis, so every ramp is stacked over the pillar — that is the whole point), then keeps
  climbing/descending at ≤ 5 % to merge into the other main line **300 m after** the pillar.
  Example EB→NB: Y 9.0 (Yan'an, L2) → 16.5 over the pillar (L3) → 31.0 (N–S, L5); 22 m over ~600 m ≈ 3.7 %.
- 4 right-turn ramps outside the T-piers, R = 120 m, each linking L2 (Y 9) ↔ L5 (Y 31) over ≥ 450 m (≤ 5 %).
- T-pier: rectangular column 2.4 × 3.2 m + hammerhead cap 2.0 m deep × 16 m long (est.), concrete `#BDB7AA`.
- Grades on all ramps ≤ 5 % (GAME); vertical curves ≥ 40 m long at every grade change.
Game anchor of the pillar: **(−1299, 687)** in the map frame (§10). Junction footprint ≈ 340 m × 300 m.

---------------------------------------------------------------------------------------------------
## 2. Elevated expressways (延安高架 / 南北高架 / 内环高架) — the standard kit

### 2.1 Facts
| item | value | source |
|---|---|---|
| Yan'an Elevated | ~14.5–15 km E–W; **deck 25.5 m, 3+3 lanes**; design 60–80 km/h (east section 60), posted max 80; east section first built 18 m / 2+2, later partly widened to 25.5 m / 3+3; opened 1996–99 | (src) zh.wikipedia 延安高架路; en.wikipedia |
| N–S Elevated | south section 8.45 km opened 10 Dec 1995, built as **3+3 lanes** (upgraded from 2+2 plan in 1993); cast-in-place deck | (src) 上海纪实 2017; zh.wikipedia |
| Inner Ring | 47.7 km loop, **2+2 lanes**, 80 km/h; Puxi 1994, Pudong 2009; crosses the river on Nanpu + Yangpu bridges | (src) zh/en wikipedia |
| lane width | car-only urban expressway design 3.5 m (est., CJJ 37); some Shanghai elevated sections narrowed to **2.7–2.8 m** | (src) CJJ 37 commentary (Beijing transport commission PDF) |
| min clearance under decks | 5.0 m for motor lanes | (src) Shanghai gov. engineering notice |
| pier greenery | ivy/Virginia creeper on piers, average 7.6 m high | (src) zh.wikipedia |
| 2022–27 "rejuvenation" (Inner Ring) | precast parapets, crash level SA, **1.0 m above deck**, C50 fair-faced concrete + self-cleaning coat, relief pattern on the outer face; planter trough + smart irrigation on top; new noise barriers; LED street lamps; repainted beams/caps/piers | (src) whb.cn 2024-01; people.cn 2024-12 |
| parapet colour | standard colour named **"高架灰" (elevated grey)** (expressway city-entry barriers repainted every 3 years); the 2018 project "unified the colour standard of all elevated parapets" | (src) Shanghai expressway maintenance standard PDF (snippet); cnr.cn 2018-10-23 |

### 2.2 GAME cross-section (standard 6-lane deck; use everywhere unless stated)
West→east across a N-bound deck (mirror for the other side), total **27.0 m** (GAME widened from real 25.5 m):
`drip 0.25 | parapet 0.50 | edge strip 0.50 | 3 lanes × 3.75 = 11.25 | inner strip 0.50 | median barrier 0.50 (half of 1.0)`
- Real 25.5 m version: lanes 3.5 m. Use GAME 3.75 m because arcade speeds/drifting need it.
- 4-lane decks (Inner Ring, Nanpu spiral loops, single ramps): 2+2 → 19.0 m GAME; 1-lane ramp 8.0 m; 2-lane ramp 10.5 m.
- Deck surface **Y = 10.0** standard (Yan'an/Inner Ring); N–S Elevated **Y = 12.0** away from the interchange (est.).
- Superstructure: concrete box girder, depth 2.0 m, bottom flange 60 % of deck width, **cantilever wings 3.5 m each
  side** (est.) — the wing undersides carry the blue light band (§2.5).
- Asphalt: dark grey `#2B2C30`, roughness 0.85; wet-look variant roughness 0.35 for rain.

### 2.3 Piers
- Typical: **single column + T (hammerhead) cap**. Column 2.0 × 3.0 m (rounded corners R 0.4), cap 2.0 m deep ×
  16 m long tapering to 1.2 m at the tips; concrete `#BDB7AA` (photos `img/02_elevated_roads/`). (est.)
- Span (pier spacing) **30 m** standard (est.; Gonghexin Rd elevated uses 30 m standard spans (src cnssce)).
- Variants: twin columns or portal frames where the road below is wide (photo `under_elevated_2009.jpg`).
- 50 % of piers: ivy texture from Y = 0 to 7.6 m (`#2F5A2A` leaves).

### 2.4 Parapets, planters, lamps, noise walls
- Parapet: concrete safety shape, **1.0 m** above deck, 0.5 m wide at the base, 0.25 m at the top; colour "高架灰"
  ≈ `#B9BBB6` (est.), outer face slightly lighter `#C8C9C4` with a shallow wave relief (Inner Ring only).
- **Planters (iconic!)**: white boxes `#EDEDE8`, 0.60 × 0.25 × 0.25 m (est.), continuous row sitting on the outer top
  edge of every parapet, both sides of the deck. Real numbers (src shanghai.gov.cn 2026-05-15): ~118,000 pots on
  Yan'an, Inner Ring, Humin, N–S elevated + Hongqiao hub; **26,000 pots on Yan'an Elevated alone**; since 2021 a
  **"10+5" rhythm**: 10 pots of rose 'Fairy' (仙境, double, rose-pink) + 5 pots of golden privet (亮金女贞) or abelia;
  roses Apr–Jun (peak 27 Apr–10 May), **bougainvillea (三角梅) summer–autumn**, evergreens in winter.
  GAME (October night): repeat [10 × magenta bougainvillea `#C2185B` on green `#3E7D32`] + [5 × yellow-green
  privet `#B5C534`]. One instanced mesh per pot; LOD to a textured strip beyond 80 m.
- Street lamps on decks: median double-arm poles **11 m** high, arms 2.5 m, spacing **32 m** (est.); LED 4000 K
  `#FFE9C8` (older sodium look `#FFB04A` allowed for "retro" districts). Near the Shanghai Exhibition Centre the real
  road has no poles (lamps in the barrier) (src) — use barrier lamps on the 400 m east of the dragon interchange.
- Noise barriers: transparent panels 3.5 m high on grey steel posts every 2 m (est.), tinted `#9FC3D0` 30 % opacity;
  put them only beside residential blocks (≈ 20 % of elevated length).

### 2.5 Night lighting of the elevated roads (signature look)
- **"高架蓝光" under-deck band**: since 2010, LED tubes (1 m long, 27 × 1 W LEDs each) along **both deck edges**,
  lighting the cantilever undersides as **two ~4 m wide bands**; colour **blue-violet** continuing the 1990s
  blue-purple fluorescent tubes (src 东方早报 2010-01-12). Since 2018 ~12 km of the "申" network uses **35,500
  full-colour fixtures** (Yan'an Kaixuan Rd–Jiangxi Rd, N–S Fengyang Rd–Quxi Rd) with weekday / holiday / late-night
  modes (src cnr.cn 2018-10-23). The Yan'an blue neon appears in *Skyfall* (src en.wikipedia).
- GAME: emissive strip on the underside edge of every deck, colour `#5A3DFF` (default), energy so that it lights
  the wing underside (use a long thin area light or a baked emissive + light probe); holiday mode cycles
  `#5A3DFF → #FF3FD8 → #29D3FF` over 20 s.
- Pier caps and columns: soft uplight 3000 K, very low intensity. Planters are lit only by deck lamps.

### 2.6 Gantries, signs and markings
- Guide signs on urban expressways: **green background, white text/arrows** (src GB 5768.2; Shanghai gov 2026-07-30).
  Green `#00704A` (est.), white `#FFFFFF`, retro-reflective (emission 0.15 at night under headlights).
- Gantry: grey galvanized steel truss (0.9 × 0.9 m box truss) spanning the full deck at Y = 5.5 m clearance
  (sign bottom ≥ 5.5 m above deck), posts on the parapets; one gantry every ~500 m + 300 m / 100 m before exits.
- Sign layout: Chinese line (cap height 0.55 m) above English line (0.28 m); arrows per lane. Texts to use:
  `延安高架路 Yan'an Elevated Rd` · `南北高架路 N-S Elevated Rd` · `外滩 The Bund` · `陆家嘴 Lujiazui` ·
  `出口 EXIT` · `西藏中路 出口 500m` · `内环高架 Inner Ring` · `南浦大桥 Nanpu Bridge` ·
  `延安东路隧道 Yan'an E. Rd Tunnel` · `外滩隧道 Bund Tunnel` · `虹桥机场 Hongqiao Airport` · `G50 沪渝高速`.
- Variable message sign (可变情报板): black box 8 × 2.5 m with an LED road schematic in green/yellow/red bars
  (`#2BFF6A` / `#FFD23F` / `#FF2A2A`) — real system since 2003 (src zh.wikipedia).
- Markings (GB 5768.3, src): lane lines **white, 15 cm wide, dashed 6 m line / 9 m gap** (roads ≥ 60 km/h);
  urban <60 km/h: 2 m / 4 m; edge lines solid white 20 cm; left edge next to the median **solid yellow 15 cm**
  (unverified for Shanghai elevated, standard on Chinese expressways); gore areas: white chevrons 45°, 45 cm bars.
- Ramps: max grade **4 % up / 3.5 % down** on Nanpu approaches (src); GAME ≤ 5 %; to climb 10 m at 4.5 %:
  222 m + two 40 m vertical curves. Off-ramp taper 1:25; on-ramp acceleration lane 150 m (est.).

---------------------------------------------------------------------------------------------------
## 3. Nanpu Bridge (南浦大桥) + the Puxi spiral, and Lupu Bridge (卢浦大桥)

### 3.1 Nanpu facts
| item | value | source |
|---|---|---|
| type / opened | double-tower, double-plane **steel–concrete composite cable-stayed**; opened 1 Dec 1991 | (src) zh.wikipedia; thepaper 2021 |
| lengths | main bridge **846 m**, **main span 423 m** (side spans ≈ 211.5 m each, derived); whole route 8,346 m (2021: 10,288 m with new links); Puxi approach **3,754 m**, Pudong approach 3,746 m | (src) zh.wikipedia; hbtmjzxh; people.cn 2021 |
| deck | **30.35 m** wide incl. 2 × 2.0 m sidewalks; carriageway 23.45 m; 6 lanes → **7 lanes since 2001** (3 to Puxi + 4 to Pudong) | (src) zh.wikipedia; thepaper 2021 |
| clearance | **46 m** navigation clearance, 340 m navigable width, design water level +4.0 m | (src) baike; zh.wikipedia |
| towers | **H-shaped with bent (折线) legs**, reinforced concrete, **150 m** (one source 154 m) | (src) zh.wikipedia (150); thepaper (154) |
| cables | 22 pairs per side per plane + 1 vertical cable at each tower, **fan** layout; 180 cables; thickest Ø 146 mm (265 × Ø7 mm wires, 21 t), longest 223 m | (src) zh.wikipedia; hbtmjzxh |
| name sign | 「南浦大桥」 by Deng Xiaoping in **red**, on the upper crossbeam, each character 16 m² | (src) hbtmjzxh |
| Puxi spiral | compound-curve **spiral, "upper and lower two rings"**, 1 main + 5 branch ramps, links Zhongshan S Rd, Inner Ring and Lujiabang Rd; en.wiki: diameter 180 m | (src) thepaper 2021; en.wikipedia |
| approach design | lanes 6 / 4 / 2 by segment; **max grade 4 % up, 3.5 % down**; 40 km/h | (src) thepaper 2021 (林元培 design paper) |
| OSM measurement | spiral loops: inner R ≈ 100 m, outer R ≈ 130–150 m (2026 OSM) | (est.) |
| night | normal mode warm/white mono; holiday: deck sides **red, yellow, blue** ("盘龙昂首"), towers **white** wash, underside lit; late night only the name sign | (src) wenhui 2021-09-30 |
Photos: `img/03_nanpu_lupu_bridges/` — `nanpu_2019_01.jpg` (blue LED deck line, orange-lit underside),
`nanpu_spiral_youspinmeround_2008.jpg` (spiral), `nanpu_1_2020.jpg` (towers, day).

### 3.2 GAME spec — Nanpu (bridge-local frame: origin = main-span midpoint, +U = towards Pudong)
- Map anchors (§10): main-span mid **(1330, 1430)**, axis **U = (0.901, 0.434)**; Puxi tower **(1139.4, 1338.2)**;
  Pudong tower **(1520.6, 1521.8)**; Puxi deck end / spiral junction **(960.1, 1251.8)**; Pudong deck end
  **(1655.7, 1586.9)** (Pudong side span shortened to 150 m to fit the map — GAME).
- Deck: 30.35 m wide, 3+3 lanes 3.75 m + 2 m sidewalks + cable zones; steel edge girders 2.5 m deep, painted
  `#9AA4AE`; soffit Y = 43.0 at midspan → road **Y = 45.5 at midspan, 44.0 at towers, 42.5 at the Puxi deck end**.
- Tower (each): total height 150 m from Y = −3 (water/footing) — legs 6.0 × 4.5 m at the base tapering to
  4.0 × 3.5 m at the top; **below the deck the legs splay outward** (leg centres ±21 m at the base, ±17.2 m at the
  deck); **above the deck the legs are vertical** at ±17.2 m. Lower crossbeam just under the deck (Y = 40.5),
  upper crossbeam Y = 128–134 carrying 「南浦大桥」 in red `#D9161C` (4 m characters, lit at night). Concrete
  `#D8D8D2`. (geometry est. from photos)
- Cables: per tower 2 planes × 2 sides × 22 = 88 + 2 vertical; tower anchors from Y = 95 to Y = 145 every 2.3 m;
  deck anchors every 9.6 m on the main span (6.8 m on the shortened side spans); cable Ø 0.18 m render,
  white `#F2F2F0`; at night lit from the deck by small floods (thin bright lines).
- Night: towers washed white 4000 K; continuous LED line on both deck edges `#3D7BFF`; underside floods
  `#FF8A2A`; name sign emissive red. Holiday mode: deck edge cycles red `#FF2A2A` / yellow `#FFD23F` / blue `#3D7BFF`.

### 3.3 GAME spec — the Puxi spiral (centre **(1021.3, 1124.8)**, real size)
- Circulation (towards Pudong): **counter-clockwise seen from above with north up**.
- **Upper loop**: centreline **R = 141 m**, 2+2 lanes 19 m deck. The Inner Ring arrives at the loop's **south point
  (1021.3, 1265.8) at Y = 10 heading east**, the loop sweeps **334°** (S → E → N → W → SSW) climbing Y = 10 → 42.5
  (822 m, 3.95 %), and leaves **tangentially** at **(960.1, 1251.8) heading U = (0.901, 0.434)** — it passes 32 m
  above its own entry. Then 199 m straight to the Puxi tower.
- **Lower loop**: centreline R = 95 m (concentric), ¾ turn, climbs Y = 0 → 10 from Zhongshan S Rd / Lujiabang Rd and
  merges into the upper loop just after the south point, 2 lanes. Zhongshan S Rd itself passes **under** the loops at
  grade (as in reality) — keep ≥ 5.5 m clearance and put the loop columns outside its 30 m corridor.
- **Pudong side (the real Pudong approach is an oval loop)**: from the Pudong deck end (1655.7, 1586.9) the road turns
  **left into a descending loop**: centre **(1699.1, 1496.8)**, R = 100 m, counter-clockwise, **1.5 turns (540°)**,
  Y 42.5 → 0 (942 m, 4.5 %), exit at (1742.5, 1406.7) heading WNW, then a right-hand curve R = 80 m to heading north,
  joining Pudong South Rd at (1690, 1280).
- Superelevation 4 %; single columns + T caps every 30 m (≈ 31 columns on the upper loop); deck edge LED lines
  as §3.2 so the spiral reads as glowing rings from above (the famous TikTok look, src xinhuanet 2021).
- Spiral must never exceed 4 % grade; use the full turn even if it feels long — it is the landmark.

### 3.4 Lupu Bridge (brief; backdrop only)
- Steel **half-through (中承式) arch**, main span **550 m**, side spans 100 m, main bridge 750 m, width 28.75 m,
  3+3 lanes, opened 28 Jun 2003; clearance 46 m; arch rib box **9 m high × 5 m wide**; rise-to-span 1/5.5 →
  **rise ≈ 100 m** (derived); twin ribs leaning towards each other ("basket handle"); 367 steps to a top deck
  (src zh/en wikipedia; cnssce). Colour white/silver-white `#E8EAEA`, 「卢浦大桥」 in red on the arch (photo).
- Night: "rainbow" LEDs running along the arch (light posts every 2 m, mono strip + layered rainbow head),
  hangers lit, laser-washed underside (src wenhui 2021; zhihu 2019).
- Real position ≈ 4.6 km south of the origin → outside the map. Place as a **far silhouette** at map (−300, 2900),
  axis E–W, real size, low-poly, emissive rainbow arch so it is visible from the Nanpu deck.

---------------------------------------------------------------------------------------------------
## 4. Tunnels

| item | Yan'an East Rd Tunnel (延安东路隧道) | Bund Tunnel (外滩隧道) |
|---|---|---|
| opened | north tube 1 May 1989; south tube 29 Nov 1996 | 28 Mar 2010 |
| length | **2,261 m**, of which **1,476 m under the river** | **3.3 km** |
| lanes | 2 per tube, 4 total; roadway **7.5 m wide, 4.5 m high** per tube | double-deck N of Yan'an Rd (3 lanes per deck, one direction each); single deck 2+2 S of Yan'an Rd |
| portals | Puxi: Yan'an E Rd / Fujian Rd; Pudong: Century Ave / Yincheng Rd (Pearl Ring) | S: Zhongshan S Rd / Dongmen Rd; SW: Yan'an E Rd; N: Wusong Rd / Haining Rd |
| source | zh.wikipedia 延安东路隧道 | en/zh.wikipedia Bund Tunnel |
Interior look (est. — no interior photo found; portal photos in `img/04_tunnels/`):
- Walls: white enamel panels `#ECEFF0` from Y = 0.5 to 3.2 m with a 0.3 m colour stripe at Y = 1.2 m
  (Yan'an: blue `#2C6BD8`; Bund Tunnel: green `#2BA36B`); kerb 0.3 m concrete; above 3.2 m dark grey `#3A3D42`.
- Lights: two continuous rows of LED luminaires (4000 K) at the ceiling corners, 1.2 m long every 2.4 m; portal
  zones brighter (×4 over the first 150 m). Lane-control signals (green ↓ / red ✕) every 150 m; jet fans
  (Ø 1.2 m, 5 m long, pairs) every 250 m; green emergency-exit signs every 80 m.
- Portals: concrete U-trough at 5 % grade, height-limit gantry (yellow/black, sign "限高 4.2m" (est.)), green guide
  sign `外滩隧道 Bund Tunnel` / `延安东路隧道` with blue regulatory signs (photos).
GAME: Yan'an tunnel = 2 circular bores Ø 11.0 m (shield, est.), 2 lanes each, centrelines 15 m apart; Puxi portal at
**(−459.8, 184.4)** facing west, Pudong portal at **(759.0, −462.4)** facing east; lowest road level **Y = −28**
under the river (est.); grades ≤ 4.5 %.

---------------------------------------------------------------------------------------------------
## 5. The Bund (外滩, 中山东一路)

### 5.1 Facts
- Zhongshan East-1 Rd: **1,108 m** from Yan'an E Rd (S) to Waibaidu Bridge (N) (src zh.wikipedia). Since the 2010
  rebuild the surface road went from 10–11 lanes to **2+2 lanes** (src 新民周刊 2017; a 2017 paper says 6 lanes and
  carriageway 36 → 20 m, the freed 16 m became promenade). Through traffic is in the Bund Tunnel below.
- Flood wall (built 1989–93): reinforced-concrete **double-deck hollow box (空箱)**, crest **+6.9 m** (Wusong datum),
  ~1,700 m long; promenade on top with **32 semicircular viewing balconies with cast-iron railings, 64 palace
  lanterns (宫灯), 8 granite art lamp columns**, coloured tiles + granite paving, 21 bowl planters (src 新民周刊).
  2010 added four plazas: Huangpu Park entrance, **Chen Yi Square** (+⅓), **Bund Financial Plaza with the
  "Bund Bull"** at Fuzhou Rd (4,900 m²), **Meteorological Signal Tower plaza** at Yan'an Rd (2,566 m²) (src).
- Photos: the riverside face of the flood wall is washed **blue/cyan** at night (`img/05_bund/hsbc_customs_night_2026.jpg`).

### 5.2 GAME cross-section (perpendicular to the Bund road, west → east)
`building facade | sidewalk 6 m | kerb | 2+2 lanes 3.5 m + 2 turn/bus lanes = 20 m carriageway | tree strip 3 m |
lawn/planters 8 m | stairs/ramps up | promenade deck 20–25 m at Y = +2.5 | balustrade 1.1 m | water at Y = −3.0`
Road centreline = `roads.bund_zhongshan_e1` in the JSON: (4.2,−10.2) → (−111.3,−245.7) → (−145.3,−524.4) →
(−135.2,−628.1) → (−128.3,−707.2) → (−153.0,−839.8) → (−147.6,−914.4) = south end of Waibaidu Bridge.
Building front facades sit **16 m west of the road centreline**, parallel to the road. Promenade lamps: black
cast-iron double-lantern posts 4.5 m every 15 m (est.), warm 2700 K.

### 5.3 Building list, south → north (GAME z-centre; frontage already ×0.85; heights REAL)
| No. | building (today) | z | front x | frontage | depth | height (m) | style / roof cue | facade |
|---|---|---|---|---|---|---|---|---|
| 1 | Asia Bldg 亚细亚大楼 (1916) | −32 | −22.5 | 38 | 40 | 31 (est.) | eclectic baroque, central attic + pediment | grey granite `#C9C3B6` |
| 2 | Shanghai Club 上海总会 → Waldorf (1910) | −59 | −35.7 | 27 | 40 | 30 (est.) | English classical, **two small corner cupolas** | cream `#E3DDCF` |
| 3 | Union Bldg 有利大楼 / Three on the Bund (1922) | −91 | −51.4 | 38 | 38 | 30 (est.) | Renaissance, 6 floors | granite `#CFC8B8` |
| 5 | Nisshin Bldg 日清大楼 (1925) | −120 | −65.7 | 22 | 30 | 28 (est.) | Japanese-western, 6–7 floors | granite `#CCC5B5` |
| 6 | Commercial Bank of China 中国通商银行 (1897) | −140 | −75.5 | 21 | 25 | 20 (est.) | **Victorian Gothic, pointed gables** | red brick `#A2493A` + white bands |
| 7 | Great Northern Telegraph 大北电报 (1908) | −181 | −95.6 | 19 | 25 | 22 (est.) | Renaissance, small corner dome | white `#E6E2D8` |
| 9 | China Merchants 轮船招商局 (1901) | −207 | −108.3 | 17 | 22 | 20 (est.) | Renaissance, 4–5 floors | red/white brick |
| 12 | **HSBC Bldg 汇丰银行大楼** (1923) | −268 | −130.0 | 76 | 70 | cornice 32, **dome top 50** (est.) | neoclassical, **Greek dome on drum, pediment, 6 Ionic columns** (single-double-double-single) (src) | granite `#D6CEBC` |
| 13 | **Customs House 江海关大楼** (1927) | −328 | −137.3 | 42 | 60 | **main 36.2, clock tower top 79.2** (src zh.wiki; en.wiki says tower 90 m) | 5-storey square clock tower, 4 clock faces Ø 5.4 m (est.), stepped top + mast | granite `#D2CBBB` |
| 14 | Bank of Communications 交通银行 (1948) | −366 | −142.0 | 34 | 40 | 36 (est.) | Art Deco, vertical fins | pale granite `#D9D4C8` |
| 15 | Russo-Chinese Bank 华俄道胜 (1903) | −418 | −148.3 | 34 | 35 | 20 (est.) | classical, 3 floors | white glazed tile `#ECE8DE` |
| 16 | Bank of Taiwan 台湾银行 (1924) | −447 | −151.9 | 20 | 30 | 22 (est.) | Greek columns | granite |
| 17 | North China Daily News 字林大楼 (1924) | −465 | −154.1 | 26 | 35 | 40, towers 46 (est.) | 9 floors, **two small rooftop towers** (src) | granite |
| 18 | Bund 18 麦加利银行 (1923) | −488 | −156.9 | 26 | 40 | 26 (est.) | Renaissance, 2 Ionic columns | granite |
| 19 | Palace Hotel 汇中饭店 / Peace Hotel South (1908) | −518 | −160.5 | 30 | 75 | **30** (src) | Renaissance, 6 floors | **white tiles + red-brick bands** `#EDE9E0`/`#9C4A3A` |
| — | Nanjing East Rd 南京东路 (centreline) | −540 | — | road 16 m | | | | |
| 20 | **Sassoon House 沙逊大厦 / Peace Hotel North** (1929) | −569 | −157.0 | 42 | 90 | **77 to pyramid top**; **19 m dark-green copper pyramid roof** (src zh.wiki; en.wiki: ~10 m) | Art Deco, 13 floors riverside | granite `#CBBFA6` |
| 23 | **Bank of China 中国银行大楼** (1937) | −600 | −153.9 | 24 | 60 | **≈ 77** (1 ft lower than Sassoon, src) | Art Deco + Chinese hipped pyramidal roof, 15 floors | granite `#C9BCA2` |
| 24 | Yokohama Specie Bank 横滨正金 → ICBC (1924) | −628 | −151.2 | 34 | 45 | 30 (est.) | neoclassical, Greek columns, 6 floors | granite |
| 26 | Yangtze Insurance 扬子大楼 (1918) | −655 | −148.9 | 18 | 25 | 30 (est.) | eclectic | granite |
| 27 | Jardine Matheson 怡和洋行 (1922) | −683 | −146.4 | 34 | 45 | 32 (est.) | Renaissance, 6+2 floors | rough granite base |
| — | Beijing East Rd 北京东路 | −703 | — | road 14 m | | | | |
| 28 | Glen Line Bldg 格林邮船 (1922) | −720 | −146.7 | 24 | 30 | **27.5** (src) | 7 floors, balconies | granite + quartz render |
| 29 | Banque de l'Indochine 东方汇理 (1914) | −744 | −151.2 | 20 | 25 | 18 (est.) | baroque, 3 floors | white |
| 33 | former British Consulate 英国领事馆 (1873) | −808 | −163.1 (set back 40 m in a lawn) | 30 | 20 | 12 (est.) | 2-storey colonial verandas | red brick + white |
| 32 | The Peninsula 半岛酒店 (2010) | −837 | −168.5 | 40 | 50 | 60 (est.) | modern Art Deco, 14 floors | granite `#CFC4AE` |
| — | **Waibaidu Bridge 外白渡桥** | −912 → −1000 | x ≈ −146 → −133 | | | | §5.5 | |
| — | **Broadway Mansions 上海大厦** (1934), N of Suzhou Creek | −1051 | x ≈ −156 (centre) | 60 | 40 | **77**, 21 floors, set back from floor 11 up (src) | Art Deco ziggurat | dark-red granite base, **coffee-brown tile** `#7A4A32` |
Gaps between buildings that are not listed = cross streets 12–16 m wide (Guangdong Rd, Fuzhou Rd, Hankou Rd, Jiujiang Rd,
Dianchi Rd). Behind the front row: 6–10-storey 1920s–30s blocks + a few 20–30-storey modern towers.

### 5.4 Bund night look (photos `img/05_bund/*night*`)
- **Only warm white/gold on the historic facades.** Floodlights from the sidewalk + cornice grazers, 2700–3000 K,
  colour `#FFC873` (lit stone reads `#F6B04A` → `#FFE2A8` at hot spots). Each building: brightest at the crown
  (dome, tower, cupolas), columns grazed from below, windows mostly dark/amber `#FF9F40` at 30 %.
- Accents: Peace Hotel pyramid lit **green `#21C08B`**; Customs House clock faces backlit `#FFF6E0`; red flags on the
  roofs; the river face of the flood wall washed **blue/cyan `#1E8BFF` → `#29D3FF`** (2026 photos).
- **DON'T** put neon, RGB or animated colour on the Bund buildings — that belongs to Pudong and Nanjing Rd.
- Lit hours in reality ≈ dusk–23:00 (unverified); game: always on.

### 5.5 Waibaidu Bridge (外白渡桥, Garden Bridge) — real size (src zh.wikipedia 外白渡桥)
- **104.39 m** long, **2 equal spans of 52.18 m** (clear 50.90 m), steel **through truss, riveted**, 11 panels per
  span at **4.744 m**; trusses **unequal height — 9.144 m at mid-span** (curved top chord, ~5 m at the ends (est.));
  truss centre spacing **12.192 m**; carriageway **11.2 m** (3 lanes) + **2 × 3.0 m** sidewalks with **9 cm timber
  planks**; deck grade 4 %; 40 km/h; ~900 t; centre pier 10.1 m high, abutments 9.1 / 8.7 m.
- Paint: **silver-grey anti-rust** (restored 2009) `#9AA0A6`, metallic 0.6, roughness 0.5, rivet normal map.
- Night: LED, **main tone warm yellow** (`#FFC24D`); festivals blue / silver-white / purple (src 新民周刊);
  a 2019 photo shows **red** (`img/05_bund/waibaidu_bridge_night_2019.jpg`).
- GAME: real length 104.4 m centred on the creek at (−140, −966), along the road direction (0.145, −0.989):
  ends (−147.6, −914.4) → (−132.4, −1017.6); Suzhou Creek here is 70 m wide, centre pier mid-creek.

---------------------------------------------------------------------------------------------------
## 6. Lujiazui (陆家嘴)

### 6.1 Oriental Pearl Tower 东方明珠 — **468 m**, game centre **(637.5, −634.9)**
| part | real geometry | source |
|---|---|---|
| main tubes | **3 vertical concrete tubes Ø 9 m**, in a triangle ("品字形", 7 m apart) | (src) zh.wikipedia; hbtmjzxh |
| braces | **3 inclined tubes Ø 7 m at 60° to the ground**, from the base to the lower sphere | (src) zh.wikipedia |
| lower sphere | **Ø 50 m, Y 68–118 (centre 93)** | (src) baike; hbtmjzxh |
| 5 small spheres | **Ø 12 m**, between Y 118 and 210 (Space Hotel) | (src) zh.wikipedia |
| upper sphere | **Ø 45 m, Y 250–295 (centre 272.5)**; observation 263 m, revolving restaurant 267 m, glass walkway 259 m | (src) baike; zh.wikipedia |
| space module | **Ø 14 m, Y 335–349**; top observation 350 m | (src) hbtmjzxh (some sources say Ø 16 m) |
| antenna | **118 m** mast, 350 → 468 m | (src) |
| finish | spheres = steel space frame clad with aluminium honeycomb panels and **laminated red glass** | (src) en/zh.wikipedia |
GAME: small spheres at Y = 130, 150, 170, 190, 210 on the tube axis (est.); tubes `#D2D2D0`; sphere glass base colour
`#B0306A` (pink-magenta, metallic 0.3, roughness 0.15) with silver aluminium bands `#C8CCD0`; base podium Ø 100 m ×
12 m (est.) with three small Ø 8 m spheres at ground level (unverified). Night: **animated LED dot grids** on the
spheres cycling **pink `#FF3FA4` → violet `#8A3CFF` → blue `#2E7BFF`** (40 s loop), tubes lit by vertical strips
`#7A4CFF`; antenna tip red aviation light. (photos `img/06_lujiazui/opt_night_2014.jpg`, `lujiazui_night_2023.jpg`)

### 6.2 The super-tall trio (real sizes; footprints est.)
| tower | height | game centre | footprint (est.) | shape cue | night |
|---|---|---|---|---|---|
| **Jin Mao 金茂大厦** (1999) | **420.5 m**, 88 fl (+5 spire fl) | (1133.0, −199.8) | octagon from two overlapping squares, 54 m across | **13 tiers** stepping in "four corners inward" like a pagoda (src); 16 segments, each 1/8 shorter than the 16-storey base (src); steel crown/spire **50.4 m** (src) | warm gold `#FFD27A` on every setback corner, crown brightest |
| **SWFC 环球金融中心** (2008) | **492 m**, 101 fl | (1262.2, −136.0) | square 58 m | square prism cut by two sweeping arcs, narrows to a blade at the top; **inverted-trapezoid aperture** at the top; observation 423 / 439 / **474 m** (100F skywalk ≈ 55 m long) (src) | cool white edge lines `#DDEEFF` along the two arcs + aperture outline |
| **Shanghai Tower 上海中心** (2015) | **632 m**, 128 fl; structure 580 m | (1122.8, −42.5) | rounded triangle, circumradius 42 m at the base → 21 m at 580 m | outer glass skin **twists 120°** while tapering (src); continuous V-notch at one corner; crown 546–632 m of steel fins (src) | white dotted floor bands `#E6F2FF`, notch line brighter, crown wash |
GAME details (est.):
- Jin Mao tier heights (m, bottom→top): 64, 56, 49, 42, 35, 28, 21, 17, 14, 11, 8, 6, 4 (= 355) + spire 65.5 →
  420.5; tier width shrinks 2.5 m per tier; mullions = vertical aluminium fins every 1.5 m; glass `#3E4A52`.
- SWFC aperture: bottom edge Y = 440 (width 30 m), top edge Y = 472 (width 50 m), top beam 472–492 (holds the
  skywalk). Podium 4 floors, 15.8 m (src). Glass `#5C7A8C`, very reflective (roughness 0.08).
- Shanghai Tower: build as 120 stacked rings, 4.83 m each (0–580 m); ring i (0..119): rotation = i/119 × 120°,
  scale = 1 − 0.5 × i/119; crown fins 580–632 m continue the twist; glass `#9DB7C6`, double skin.
  Do **not** make it a plain cylinder.

### 6.3 Pearl Ring skybridge (明珠环) and boulevards
- **Pearl Ring: circular steel pedestrian bridge, Ø 117.5 m, deck 9.7 m wide**, spans Century Ave, Lujiazui Ring Rd
  and Lujiazui W Rd; span joined (合龙) 7 Jan 2010, opened Apr 2010 (src zh.wikipedia 陆家嘴中心区二层步行连廊).
  Plus Century Bridge (Y-shaped, 280 m × 9 m) and Century Corridor (543 m × 9 m) linking IFC, Jin Mao, SWFC (src).
  GAME: centre **(748.0, −488.8)**, deck top **Y = 6.5** (est.), white steel box girder 1.2 m deep `#F0F0EE`, glass
  balustrade 1.3 m, 8 pairs of Y-columns, LED handrail line `#E6F2FF`. Stairs + escalators at 4 points.
  Below it: the roundabout with a flower bed (photo `lujiazui_intersection_ring_2014.jpg`).
- **Century Avenue 世纪大道: 100 m wide** (src SWFC official site). GAME: 4+4 lanes 3.75 m, central median 10 m,
  north side 30 m of sidewalk/green, south side 15 m (est.). Polyline `roads.century_ave`.
- Lujiazui Ring Rd: 3+3 lanes loop around the core (`roads.lujiazui_ring_rd`).
- Binjiang Ave 滨江大道: riverside promenade, 25 m wide, terraced lawns, along the Pudong bank from (300, −600)
  to (700, 150) (GAME). Extra background towers (IFC twins ~250 m, HSBC Pudong 250 m, CMB 230 m (OSM) etc.)
  as generic glass boxes 150–260 m with white crown lights.

### 6.4 Skyline placement relative to the river bend (GAME frame)
```
            N (−Z)                         The Huangpu bends around the Lujiazui peninsula:
   Waibaidu ■ (−140,−956)                  it flows N past the Bund, turns E at the Suzhou Creek mouth.
            |  river turns east →  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   BUND     |  ~~~~~                 ● OPT (638,−635)
   (x≈−150) | ~~~~~ (river 330–400 m)      ◎ Pearl Ring (748,−489)
            |~~~~~                              ▲ Jin Mao (1133,−200)   ▲ SWFC (1262,−136)
   origin ✚ (0,0) ~~~~                          ▲ Shanghai Tower (1123,−43)
            \  ~~~~~~  river runs SE ↘ to Nanpu (1330,1430)
```
Seen from the Bund promenade looking east: OPT is front-left (close to the water), the trio stands behind and to
the right, Shanghai Tower is the tallest and rightmost of the three — keep this order or the view is "wrong".

---------------------------------------------------------------------------------------------------
## 7. Expressway toll plaza (G2/G60-style main-line station) — game-only placement

### 7.1 Facts
- G2 Jiangqiao (江桥) main-line station is one of Shanghai's busiest: peak ~110,000 veh/day; Dec 2023 "1+2+3"
  upgrade: 1 km **ETC-only lane** upstream (first in Shanghai), ETC pre-transaction gantry, CPC pre-billing,
  **folding LED lane-info screens**, card-issuing robots; ETC ≈ 70 % of exits (src gzw.sh.gov.cn 2024-01-31).
- G15 Jiading–Jinshan: 12 toll stations, 149 lanes (≈ 12 per station), 38 ETC (src suog.cn). Manual lanes renamed
  **"混合车道 (ETC/人工)"** (src cqcb 2020).
- National signs (GB 5768.2 draft, src): toll-station advance signs at **2 km, 1 km, 500 m and the taper start**;
  **ETC lane indication sign 300 m before the taper**, green guide sign with **yellow arrows over ETC lanes**.
  Lane control lights: **green ↓ arrow = open, red ✕ = closed** (src baike 红色叉形灯).
- Look (photos `img/07_toll_plaza/`): long **flat canopy with a rounded bull-nose fascia**, silver-grey metal, round
  columns on the islands; small lane-signal boxes under the fascia; green LED text strip "ETC"; booths of glass +
  white panels; **red/white or yellow/black striped crash cushions** at island noses; lifting barrier arms;
  camera/antenna gantry ~30 m before the canopy.

### 7.2 GAME spec (centre (−2070, 728); traffic runs E–W; plaza = x −2150…−1990)
- Approach 3+3 lanes widen to **10 + 10 lanes** over a **150 m taper** each side; lane width 3.2 m (1 truck lane
  per direction 4.5 m); islands **2.2 m × 30 m**, kerb height 0.25 m, island nose crash cushion yellow/black.
- Canopy: **110 m wide (N–S) × 20 m deep (E–W)**, underside **clearance 5.5 m** (est.), fascia 2.4 m tall,
  bull-nose radius 1.2 m, colour `#A7ACB1` metallic 0.7; underside white panels `#F2F2F2` with bright LED troffers
  (4000 K, ≥ 300 lux: emission strong); columns Ø 0.8 m on every island.
- Fascia content: centre panel **"申城西收费站 SHENCHENG WEST TOLL"** (fictional) white on green `#00704A`;
  over each lane a 0.8 × 0.8 m signal box (red ✕ `#FF2A2A` / green ↓ `#20E070`) and a lane label:
  ETC lanes "ETC 专用" (white on blue `#1F57C3`; real colour varies by province — unverified), mixed lanes
  "ETC/人工".
- Booths: 1.8 × 3.0 × 2.8 m, glass 50 %, white `#EDEDED`, red stripe `#D9161C`; barrier arm 3.0 m red/white bands
  0.5 m, pivots up on approach (gameplay: arm breaks off physically if hit — realistic crash fodder).
- Plaza pavement: concrete `#BDB9B1` with 4 m joint grid; asphalt outside `#2B2C30`. High-mast lights 30 m, 6 heads,
  4 masts around the plaza (est.). ETC gantry 30 m before the canopy (grey truss with antennas + cameras).
- Gameplay hook: the Yan'an Elevated ramp starts climbing right after the plaza at x = −1990 (Y 0 → 10 by
  x = −1740), so players can hop the canopy (top of canopy Y = 5.5 + 2.4 ≈ 8.0).

---------------------------------------------------------------------------------------------------
## 8. Gas station and EV charging (parody brands — copy the visual language, never the logos)

### 8.1 Roadside gas station (Sinopec / PetroChina style)
- Rules: canopy clearance **≥ 4.5 m** when the entrance has no height limiter (src GB 50156-2021); real canopies
  often 5.5–7.3 m (one built example 7.3 m, src environmental report); canopy edge ≥ 2 m beyond dispensers;
  islands ≥ 1.2 m wide, 0.15–0.20 m high; canopy columns ≥ 0.6 m from island ends (src Shanxi safety standard).
- Sinopec look (src sheitc.sh.gov.cn 2023; photos `img/08_fuel_and_charging/sinopec_*`): large canopy with a
  **red fascia band, white characters**, logo at the ends; standing brand pylon at the entrance; 2023 "new image"
  keeps **China red**, red high-gloss aluminium-plastic panels on columns; staff in red. PetroChina look: **red +
  yellow** fascia with rounded ends.
- GAME (rect x −1940…−1860, z 760…830; entry from the frontage road at z = 752):
  canopy 60 × 30 m, underside Y = 6.0, fascia 1.4 m tall red `#E60012`, text "中国石华 SINOPEX" white;
  underside white `#F4F4F4` with 24 square LED downlights (5000 K); 6 columns 0.6 × 0.6 m silver `#D7DADD`;
  3 islands × 2 dispensers (2.3 × 1.0 × 0.5 m, red/white, small green LED price window); yellow/black bollards;
  pylon 9 m × 2.2 m red with a price board (92# 95# 98# 0#, red digits `#FF3B30`); store 25 × 12 × 4.5 m, glass front,
  red/white band "易快 EZ-JOY"; car-wash bay at the back (optional).
- Alt brand for variety: "中国石由 PETROCHINO" red `#D7000F` + yellow `#FFCC00`, rounded canopy ends.

### 8.2 EV charging (Tesla V4 + Chinese "闪充/超充" language)
- Tesla V4 in China since **30 Jun 2025** (first 7 sites/30 posts; Shanghai among them), rated peak **500 kW**,
  1000 V / 615 A plate, **cable 3.0 m** (V3: 1.98 m), open to all brands (src tesla.cn; ifeng 2025-07-29;
  notateslaapp). Look: **slim, fully enclosed white post**, **red "TESLA" lettering that lights up**; datasheet
  dimensions 334 × 891 × 1946 mm (src caltrans datasheet snippet; axis order unverified) → GAME post 0.34 × 0.60 ×
  1.95 m (est.). Photos `tesla_v4_post_2024.jpg`, `tesla_v4_wiesbaden_2025.jpg`.
- BYD **兆瓦闪充 (megawatt flash charging)**: launched 17 Mar 2025, 1,000 kW, "1 s = 2 km"; 2026 demo at 1,500 kW;
  15,000 stations planned with partners (src byd.com; baike). Look (`byd_flash_1500kw_2026.jpg`): **teal canopy on
  a single post with an overhead cable boom**, tall white dispenser, dual guns ("双枪充得更快").
- Li Auto 5C supercharging: >4,000 stations / 22,000 posts by Feb 2026 (src baike) — white/black minimal.
- GAME station "SKY 闪充 FLASH" (rect x 1700…1780, z 380…460, entry from Pudong South Rd): white canopy 70 × 24 m,
  underside Y = 5.0, fascia with a **continuous cyan LED line `#00E5FF`**; 12 bays 3.0 × 5.5 m painted green
  `#1E9E5A` with white numbers; 6 slim white posts (TESLA-like, logo text "VOLTA" red `#E31937`, lit) + 6 tall
  dispensers 2.2 m with an overhead cable boom (BYD-like, teal `#00A6A6`); each post shows a big digital "kW"
  readout; totem 7 m with a lightning bolt; under-canopy light 5500 K. Flash-charge VFX: cyan arc from boom to car.

---------------------------------------------------------------------------------------------------
## 9. Street-level kit (instance these everywhere at ground level)

| item | spec (GAME) | basis |
|---|---|---|
| standard street lamp | grey galvanized steel pole `#8E9297`, 11 m, single arm 2 m (one side) or double arm (median), spacing 30 m, LED 4000 K `#FFE9C8` | (est.) typical 8–12 m poles at 25–35 m (src b2b standard summaries) |
| Bund / heritage lamp | black cast-iron post `#1C1C1E` 4.5 m, 2 arms, glass lantern heads 0.5 m, 2700 K `#FFC873` | (src) "64 宫灯" on the promenade; shape (est.) |
| magnolia lamp 玉兰灯 | Shanghai's flower; pole 9 m with **9 white petal globes** (1 top + 8 around), opal glass `#F4F1EA`, 3000 K; use on Yan'an Rd surface road and Century Ave | (src) baike 玉兰灯 (6–12 heads, 5–15 m) |
| traffic lights | grey mast arm 7 m reach, **vertical 3-aspect heads** (red top) with arrow lenses + countdown digit box beside; red `#FF2A2A`, amber `#FFB000`, green `#20E070` | (unverified for Shanghai specifics; vertical heads visible in `interchange_night_6658.jpg`) |
| street-name sign 路名牌 | **E–W streets: blue top panel; N–S streets: green top panel**; white Chinese name; side cells with direction + door numbers ("西 80 / 东 58"); white lower strip with pinyin/English in black ("W Xianggang Rd. E"); 1.2 × 0.5 m on a 2.6 m stainless post | (src) national place-name standard / baike 路名牌; photo `road_name_sign_xianggang_rd_2016.jpg` |
| bus stop | stainless + grey shelter 8 × 1.6 × 2.6 m, glass roof, backlit ad panel 1.2 × 1.8 m, route board, digital arrival screen | photo `bus_shelter_2026.jpg` |
| plane trees 法国梧桐 | London plane: trunk Ø 0.5–0.7 m, mottled bark (cream `#CFC7A8`, olive `#7D7A5A`, grey `#9A9A8E` patches), canopy 14 m high × 10 m wide, every **7 m** both sides; October leaves yellow-green `#B7A84A`; use in Puxi side streets W of x = −300 | (est.) photo `yongkang_road_planetrees.jpg` |
| shikumen 石库门 row houses | 2–3 storeys, eaves 9–10 m; house module 4.0 m wide × 12 m deep; grey-blue brick `#6F757B` with red-brick bands `#9A4A3A`; **stone door frame** `#D9D2C0` with carved pediment around **black lacquer double doors** `#1E1A17` (1.4 × 2.6 m); lane (弄堂) 3–4 m wide entered through an arched gate with the lane name | (est.) photo `shikumen_xintiandi_2012.jpg` |
| Nanjing Rd neon | **vertical blade signs** 1.0–1.5 m wide × 3–8 m tall stacked on facades; Chinese characters in parody shop names (e.g. "老凤翔", "王开花照相"); colours red `#FF2A3A`, magenta `#FF3FD8`, cyan `#29D3FF`, yellow `#FFD23F`, green `#39FF88`; plus big LED screens | photos `nanjing_road_*.jpg` |
| metro entrance | glass + stainless canopy over stairs, free-standing totem 3.5 m with a **red Shanghai-Metro-style logo** (parody: red circle + white "M" wave), white station name, exit number | (est.) photo `metro_exit_century_ave_2025.jpg` |
| taxi | sedan/MPV; **lower body skirt "diamond silver-grey" `#A9ADB1` for ALL companies**; upper colour per company (src zh.wikipedia 上海出租车): Dazhong 大众 **mint-teal 薄荷青 `#7CCFC2`**, Qiangsheng 强生 **lemon-gold 吉祥黄 `#F2C230`** (older 富贵绿 `#3E9A5C`), Jinjiang 锦江 **white `#F2F2EF`** (new: gold + magnolia), Haibo 海博 **violet-blue `#4A3F9E`**, Blue Alliance 印加蓝 `#2F5DA8`, Falan 法兰红 `#B02A3A`, others Indian red `#A8473C`, suburban taxis orange; roof box with LED "待运 / 电调 / 停运" | hex (est.) from photos |
| police car | **2004-style livery: white body + dark navy-blue `#102A5C` graphics + small yellow accents**, emblem + **"公安"** on front doors, **"POLICE"** on hood and boot, 4-digit roof number; light bar 1.2 m: left red `#FF1E28`, right blue `#1E4BFF`, white centre panel printed "POLICE" | (src) 2004 MPS standard (sohu/xinhua 2004-08-31); photos `police_*.jpg`. Use a **fictional shield emblem** |
| bus | 12 × 2.55 × 3.2 m battery bus, white body with green/blue lower band, LED route display (amber) | photo `bus_yutong_e10_2018.jpg` (est.) |

---------------------------------------------------------------------------------------------------
## 10. Game map layout (4.0 km × 3.0 km)

### 10.1 Window, compression and what is fictional
- Window: **X −2200 … +1800, Z −1200 … +1800** (4,000 × 3,000 m). North edge cuts just north of Broadway Mansions;
  south edge just south of the Nanpu Bridge; west edge = toll plaza; east edge = beyond the Lujiazui trio.
- Real positions come from OpenStreetMap (WGS-84, extract 2026-10-19), converted to metres around the origin,
  then compressed with **T** (applied to anchors and road/river polylines only — never to objects):
  - X: `x < −600 → −510 + 0.5·(x+600)` · `−600…1500 → 0.85·x` · `x > 1500 → 1275 + 0.5·(x−1500)`
  - Z: `z ≤ 600 → 0.85·z` · `z > 600 → 510 + 0.5·(z−600)`
  So the **core (Bund – river – Lujiazui) is 0.85×**, everything west/south/east of it is **0.5×**.
- Real vs game distances: origin→dragon pillar **2.37 km → 1.47 km**; origin→OPT 1.06 → 0.90 km;
  origin→Waibaidu 1.14 → 0.97 km; origin→Nanpu spiral **2.93 km → 1.52 km**; Huangpu width real **308–467 m
  (mean 407 m, OSM)** → game ≈ 330–400 m in the core.
- Fictional / moved (state this in credits): Nanpu bridge moved ~380 m north-east of its compressed position so the
  Pudong landing fits; Pudong side span shortened 211.5 → 150 m; the Inner Ring segment between the N–S Elevated
  and the spiral is re-routed E–W along the south edge; the **toll plaza is invented** (the real one, at the far
  west end of Yan'an Elevated, closed in 2005, src zh.wikipedia); gas + charging stations invented; "Pudong South Rd"
  re-aligned 1 km closer to the river.

### 10.2 Anchors (GAME X, Z; Y = ground unless stated) — same numbers in `build/map_layout_v1.json`
| anchor | X | Z | note |
|---|---|---|---|
| ORIGIN Bund × Yan'an E Rd | 0 | 0 | |
| Dragon pillar (interchange centre) | −1299 | 687 | §1 |
| Yan'an tunnel Puxi portal (faces W) | −460 | 184 | §4 |
| Yan'an tunnel Pudong portal (faces E) | 759 | −462 | next to the Pearl Ring |
| HSBC dome / Customs clock tower | −149 / −159 | −268 / −328 | building centres ~35 m behind the facade |
| Peace Hotel N pyramid / Bank of China | −183 / −173 | −561 / −600 | |
| Waibaidu Bridge (centre, real length 104.4 m along the road) | −140 | −966 | ends (−147.6,−914.4) → (−132.4,−1017.6) |
| Broadway Mansions | −156 | −1051 | N of Suzhou Creek |
| Oriental Pearl Tower | 638 | −635 | |
| Pearl Ring centre (Y = 6.5) | 748 | −489 | |
| Jin Mao / SWFC / Shanghai Tower | 1133 / 1262 / 1123 | −200 / −136 / −43 | |
| Nanpu main-span mid (road Y = 45.5) | 1330 | 1430 | axis U = (0.901, 0.434) |
| Nanpu towers W / E | 1139 / 1521 | 1338 / 1522 | |
| Nanpu deck ends W (Y 42.5) / E | 960 / 1656 | 1252 / 1587 | |
| Nanpu Pudong descending loop centre | 1699 | 1497 | R 100, 540°, Y 42.5 → 0 |
| Nanpu spiral centre | 1021 | 1125 | loops R 95 (lower) / 141 (upper); entry S point (1021,1266) |
| Toll plaza centre | −2070 | 728 | §7 |
| Gas station rectangle | −1940…−1860 | 760…830 | §8.1 |
| Charging station rectangle | 1700…1780 | 380…460 | §8.2 |
| Lupu Bridge silhouette (backdrop) | −300 | 2900 | outside window, §3.4 |

### 10.3 Roads (centrelines, GAME X,Z) and their height profiles
- **Yan'an Elevated** 3+3 (27 m deck): (−1798,728) (−1568,725) (−1434,730) (−1395,732) (−1316,711) (−1216,664)
  (−1040,581) (−666,235) (−550,183) (−385,201) (−287,144). West extension at grade: (−1990,728) → (−2200,728) = G50.
  Y: 0 at x = −1990 → **10** at x = −1740 (4 %) · **9** within 150 m of the pillar (L2) · **10** to (−500,190) ·
  ramps down to **0** at (−287,144) (4.5 %). Surface Yan'an Rd (3+3 + bike lanes, 30 m) runs underneath the whole way.
  Ramp pairs (GAME): Xizang Rd at x ≈ −720 (both directions), Chongqing Rd at x ≈ −1080 (westbound off / eastbound on).
- **Yan'an East Rd (surface)**: (−287,144) (−163,118) (−88,82) (0,0); 3+3 lanes.
- **N–S Elevated** 3+3: north edge (−1660,−1200) → (−1628,−1019) (−1530,−473) (−1434,−116) (−1402,202) (−1387,533)
  (−1370,594) (−1343,642) [pillar] (−1230,769) (−1202,808) (−1177,877) (−1162,936) (−1178,1034) (−1228,1256)
  (−1195,1393) (−1122,1510). Y: **12** north of (−1402,202) → **31** at the pillar (3.7 %) → **12** at (−1228,1256)
  (3.1 %) → **10** at (−1122,1510). Crosses Suzhou Creek at ≈ (−1580,−770) on a long bridge section.
- **Inner Ring (re-routed)** 2+2 (19 m): (−1122,1510) (−1000,1640) (−600,1680) (200,1660) (600,1560) (780,1380)
  (900,1290) (1021,1266) → joins the spiral's upper loop at its south point at Y = 10. Y = 10 throughout.
- **Zhongshan E-2 / S Rd (riverside surface road)** 3+3: (0,0) (106,99) (284,298) (560,545) (650,634) (903,804)
  (1204,1196) (1193,1281) (1142,1335) (948,1434) (802,1490) — feeds the spiral's lower loop.
- **Bund (Zhongshan E-1 Rd)** 2+2(+2): (4,−10) (−111,−246) (−145,−524) (−135,−628) (−128,−707) (−153,−840) (−148,−914).
- **Century Ave** (100 m corridor): (748,−489) (786,−475) (998,−381) (1100,−309) (1250,−249) (1342,−196) (1390,−181)
  (1540,−78) (1725,51).
- **Lujiazui Ring Rd** (closed loop, 3+3): (728,−499) (803,−631) (1070,−839) (1196,−682) (1263,−578) (1312,−422)
  (1349,−230) (1362,−29) (1333,2) (786,−104) (730,−193) (717,−277) (707,−412) (728,−499).
- **Pudong South Rd (re-aligned)** 3+3: (1540,−78) (1600,100) (1650,500) (1680,900) (1690,1280); the Nanpu
  Pudong descending loop (§3.3) lands here at (1690,1280).
- **Yan'an E Rd Tunnel**: (−460,184) (−354,209) (−163,118) (−37,84) (2,26) (411,−332) (617,−455) (759,−462);
  Y: 0 at portals, −28 under the river (≤ 4.5 %).
- **Bund Tunnel (optional shortcut)**: (−180,120) (−60,20) (−60,−300) (−95,−700) (−110,−1100) (−120,−1200), Y −12.
- **Puxi street grid (GAME, simplified, 2+2 lanes, 16 m, Y = 0)** — N–S streets from Yan'an Rd (z ≈ 150) north to
  Suzhou Creek: Sichuan Rd x = −255, Henan Rd x = −408, Fujian Rd x = −535, Xizang Rd x = −720 (est. from real
  positions through T). E–W streets from the Bund road west to x = −900: Guangdong Rd z = −110, Fuzhou Rd
  z = −230, Jiujiang Rd z = −430, **Nanjing E Rd z = −540** (pedestrian W of Henan Rd), Beijing E Rd z = −703.

### 10.4 Water
- **Huangpu west (Puxi) bank**: (682,1957) (770,1871) (814,1840) (1045,1618) (1189,1463) (1270,1358) (1288,1321)
  (1312,1180) (1283,1043) (1220,962) (1087,830) (1012,786) (827,646) (574,496) (208,177) (166,130) (96,39) (3,−109)
  (−30,−179) (−74,−332) (−93,−500) (−86,−597) (−55,−732) (19,−873) (76,−958) (191,−1055) (427,−1190) (458,−1204)
  (507,−1184) (686,−1281).
- **Huangpu east (Pudong) bank**: (975,2058) (1141,1884) (1218,1794) (1270,1720) (1467,1317) (1492,1181) (1460,1010)
  (1402,876) (1386,816) (1332,725) (1270,644) (1088,495) (999,392) (984,360) (935,304) (768,159) (674,58) (477,−107)
  (457,−134) (414,−144) (350,−242) (308,−296) (280,−374) (269,−452) (274,−538) (299,−601) (386,−713) (462,−764) (852,−972).
  Close the water polygon outside the window. Water Y = −3.0; bank walls vertical 3 m (Bund side: flood wall).
- **Suzhou Creek** (centreline, width 70 m): (40,−901) (2,−910) (−299,−1030) (−376,−1047) (−417,−1044) (−471,−1031)
  (−519,−1006) (−540,−983) (−613,−868) (−689,−712) (−746,−659) (−774,−650) (−796,−655) (−832,−673) (−924,−758)
  (−952,−771) (−1014,−773) (−1074,−745) (−1204,−587) (−1245,−565) (−1287,−564) (−1327,−583) (−1422,−705)
  (−1491,−748) (−1561,−774) (−1603,−762) (−1675,−707) (−1752,−541) → continue W/NW off-map.

### 10.5 Districts (filler zones; rectangles [x_min, x_max, z_min, z_max] also in the JSON `design.districts`)
| id | rect | what to fill with |
|---|---|---|
| D1 Bund heritage blocks | −420…−170, −1000…0 | 6–10-storey 1920s–30s stone blocks, 12–16 m streets, heritage lamps, few neon |
| D2 Nanjing Rd neon | −900…−170, −560…−520 | pedestrian street (no cars W of x = −350), vertical neon blades both sides, LED screens |
| D3 Huangpu mid-rise | −1150…−420, −900…100 | 15–40-storey towers mixed with 6-storey blocks; People's Square park at (−900,−350) 300 × 300 m |
| D4 Shikumen + plane trees | −1200…−320, 250…1150 | shikumen lanes (§9), plane-tree avenues every 200 m, 2–3 towers 30 storeys |
| D5 Jing'an towers | −2200…−1650, −1200…400 | 30–60-storey glass towers, warm office lights, rooftop red aviation lights |
| D6 South Bund / old city | −300…850, 150…1350 | 2–6-storey old city + 25-storey riverside apartments; curved-eave roofs (est.) |
| D7 Lujiazui CBD | 500…1800, −1150…120 | §6 + generic 150–260 m towers; Pudong skyline must be dense and coloured |
| D8 Pudong residential | 1500…1800, 120…1800 | 18–30-storey residential slabs, warm windows |
| D9 West edge industrial | −2200…−1650, 450…1800 | warehouses, sound walls, billboards, the toll plaza, the gas station |
Rule: **clip every district rectangle against the water polygon** (several rectangles overlap the river) and keep
a 10 m setback from every road edge and 15 m from elevated-deck edges. Block size 60–120 m between streets.

### 10.6 Suggested routes (lengths est. from the polylines)
- **Grand Loop ≈ 12 km** (~4 min at 180 km/h): Bund southbound → Yan'an E Rd → Yan'an Elevated W → dragon
  interchange (left-turn ramp L3/L4) → N–S Elevated S → Inner Ring E → spiral (1 turn up) → Nanpu Bridge →
  Pudong ramp → Pudong South Rd N → Century Ave W → Pearl Ring → Yan'an tunnel W → Henan Rd N (x ≈ −400) →
  Nanjing Rd E → Bund. Contains every landmark.
- **Elevated Sprint ≈ 3.5 km** (point-to-point): toll plaza → Yan'an Elevated E → dragon interchange → Bund.
- **River Loop ≈ 9.5 km**: Bund S → Zhongshan E-2/S Rd → spiral (lower + upper loop) → Nanpu → Pudong South Rd →
  Century Ave → tunnel → Bund. Police-chase default.

---------------------------------------------------------------------------------------------------
## 11. Night palette (master list; emission colours unless "albedo")
| use | hex | note |
|---|---|---|
| sky zenith / horizon glow | `#070B1A` / `#3A1F4A` | city glow is purple-magenta near the horizon over Pudong |
| river water (albedo, very glossy) | `#0B1620` | reflections do the work; add vertical streak reflections |
| elevated under-deck band | `#5A3DFF` | holiday cycle `#5A3DFF → #FF3FD8 → #29D3FF` |
| deck street lamps | `#FFE9C8` (4000 K) | retro sodium `#FFB04A` |
| Bund facades flood | `#FFC873` (hot spots `#FFE2A8`) | warm only |
| Peace Hotel pyramid | `#21C08B` | |
| flood wall river face | `#1E8BFF` → `#29D3FF` | |
| Waibaidu Bridge | `#FFC24D` | festivals blue/silver/purple, sometimes red |
| OPT spheres | `#FF3FA4` → `#8A3CFF` → `#2E7BFF` | 40 s loop |
| Jin Mao | `#FFD27A` | |
| SWFC edges / Shanghai Tower bands | `#DDEEFF` / `#E6F2FF` | |
| Nanpu deck edge / underside / name | `#3D7BFF` / `#FF8A2A` / `#FF2020` | |
| Lupu arch | rainbow running lights | |
| neon blades | `#FF2A3A` `#FF3FD8` `#29D3FF` `#FFD23F` `#39FF88` | Nanjing Rd only |
| guide signs (albedo) | `#00704A` + white | |
| toll lane lights | `#20E070` / `#FF2A2A` | |
| gas fascia / charging LED | `#E60012` / `#00E5FF` | |
| police light bar | `#FF1E28` / `#1E4BFF` | alternate 2 Hz |

## 12. Do / Don't (read before modelling anything)
- DO keep landmarks at real size and in real relative order; DON'T rescale them to fit the compressed map.
- DO put white planter boxes with magenta flowers on **every** elevated parapet — it is the most "Shanghai" detail
  of the elevated roads. DON'T use generic Jersey barriers without planters.
- DO make the dragon pillar brushed steel + dark archaic bronze relief; DON'T make a gold cartoon dragon.
- DO light the Bund warm gold only; DON'T put RGB/neon on the Bund facades. Colour lives in Pudong, the elevated
  undersides and Nanjing Rd.
- DO give the Nanpu spiral a full real-scale turn (R 141 m, 334°) — it is a landmark, not a ramp; DON'T shortcut it with
  a steep straight ramp.
- DO use Chinese + English on every sign (real place names); DON'T copy real logos (Sinopec sun, PetroChina petals,
  Tesla T, police emblem) — use the parody names in §8/§9.
- DO keep grades ≤ 5 % and vertical curves ≥ 40 m on all roads; DON'T create kinks where decks meet.
- DO model OPT spheres as glossy pink-magenta glass with dot-grid LEDs; DON'T make them matte red balls.
- DO make Shanghai Tower twist 120° with a corner notch; DON'T use a plain cylinder or box.
- DON'T place anything inside the river polygon except bridge piers/towers and boats.

---------------------------------------------------------------------------------------------------
## 13. Sources (accessed 2026-10-19; "snippet" = only the search-result excerpt was readable)
Dragon pillar / interchange
- 解放日报/上观 2015-04-20 (赵志荣, 张耿耿 interviews): https://www.jfdaily.com/wx/detail.do?id=4610
- 瞭望东方周刊 2019 (张耿耿 oral history): https://finance.ifeng.com/c/7pCvuLcqhaj
- 上海纪实 2017 陆幸生 "上海快速路网是怎样建成的": http://shjs.myhuayu.com/html/shjs18/8b4a0cf3d0387f15fe7ae5fcbece905b.html
- zh.wikipedia 延安高架路 (PM109, Ø5 m/32 m/62 m, 28 piles): https://zh.wikipedia.org/wiki/延安高架路
- en.wikipedia "Stack interchange", "Yan'an Elevated Road", "North–South Elevated Road", "Inner Ring Road (Shanghai)"
Elevated roads
- 东方早报 2010-01-12 高架蓝光: https://news.sina.cn/sa/2010-01-12/detail-ikmyaawa2479542.d.html
- 央广网 2018-10-23 申字型高架景观: http://www.cnr.cn/shanghai/tt/20181023/t20181023_524393179.shtml
- 上海市政府 2026-05-15 高架月季: https://www.shanghai.gov.cn/nw4411/20260515/4b5020ed59a24e08a45d2b41892bfc1f.html
- 人民网 2024-12-24 内环年轻化: http://sh.people.com.cn/n2/2024/1224/c134768-41085972.html ; 文汇 2024-01 (snippet): https://www.whb.cn/commonDetail/915374
- 高速公路设施整治提升标准 "高架灰" (snippet): https://www.shanghai.gov.cn/cmsres/56/561a8d3683fc4e4db7ace91fa40796d7/218209a6d506e5c2910e330b2e505276.pdf
- 上海市政府 2026-07-30 交通标志颜色: https://www.shanghai.gov.cn/nw17239/20260730/8f202f90b674446399ad2845c50f513c.html
- GB 5768.2 draft (MOT, downloaded, ETC/toll signs): https://xxgk.mot.gov.cn/jigou/kjs/202006/P020200623760741738973.pdf
- GB 5768.3 6 m/9 m lane line (snippet): https://29229836.s21i.faiusr.com/61/ABUIABA9GAAg98e11AYonO6y6gU.pdf
- CJJ 37 commentary, Shanghai lanes 2.7–2.8 m (snippet): http://jtw.beijing.gov.cn/csdlyh/zlybz/202111/P020211109557720142032.pdf
- 共和新路高架 30 m spans (snippet): https://www.cnssce.org/50/201308/1204.html
Bridges / tunnels
- 澎湃 2021 南浦大桥三十而立: https://m.thepaper.cn/baijiahao_15681180 ; 湖北土建学会: http://www.hbtmjzxh.com/news/show.php?itemid=3497
- zh.wikipedia 南浦大桥, 卢浦大桥, 延安东路隧道, 外滩隧道, 外白渡桥; en.wikipedia Nanpu Bridge, Lupu Bridge, Bund Tunnel
- 文汇 2021-09-30 四座大桥景观灯: https://wenhui.whb.cn/third/baidu/202109/30/426670.html
- 光臣照明 Nanpu LED (20,000 RGB floods): https://www.gclhgc.com/Mobile/MArticles/shnpdq_1_page1.html
- 卢浦大桥 f/L = 1/5.5 (snippet): https://www.cnssce.org/52/201102/1159.html
Bund / Lujiazui
- 新民周刊 2017 外滩综合改造: https://www.xinminweekly.com.cn/tegao/2017/11/08/9413.html
- zh.wikipedia 外滩 (building list), 中山东一路, 江海关大楼, 沙逊大厦, 中国银行大楼 (上海), 汇中饭店大楼, 格林邮船大楼,
  字林大楼, 滙豐銀行大樓 (上海), 上海大厦; en.wikipedia Peace Hotel, Custom House Shanghai, Broadway Mansions, Bank of China Building Shanghai
- 东方明珠 dimensions: http://www.hbtmjzxh.com/news/show.php?itemid=3453 ; baike 东方明珠 (snippet); zh.wikipedia 东方明珠广播电视塔
- en.wikipedia Shanghai Tower, Shanghai World Financial Center, Jin Mao Tower; SWFC official (snippet): https://swfc-shanghai.com/about_intro.php
- zh.wikipedia 陆家嘴中心区二层步行连廊 (Pearl Ring Ø 117.5 m)
Toll / fuel / charging / street
- 上海国资委 2024-01-31 G2 江桥: https://www.gzw.sh.gov.cn/shgzw_zxzx_gqdt/20240131/8db8097fcc494414a1e92300e22b9bcc.html ; https://www.suog.cn/site/service_business_load/1
- GB 50156-2021 canopy ≥ 4.5 m (snippet): https://zhuanlan.zhihu.com/p/1979223625010786401
- 上海经信委 2023 中国石化新形象: https://www.sheitc.sh.gov.cn/djjcdt/20230103/9e4274f3e3824cc39aa1e4fda93fda90.html
- Tesla V4: https://auto.ifeng.com/c/8lONqJ2TMmN ; https://www.notateslaapp.com/news/1269/tesla-v4-superchargers-power-design-and-cable-length-revealed
- BYD flash charging (snippets): https://www.byd.com/cn/news/2025/detail567 , https://www.byd.com/cn/news/2025/detail588
- zh.wikipedia 上海出租车 (company colours); 2004式警车 (xinhua via sohu): http://news.sohu.com/20040831/n221824551.shtml
- baike 路名牌, 玉兰灯 (snippets)
Geometry: © OpenStreetMap contributors (ODbL), Overpass extracts 2026-10-19 in `dl/osm_1…osm_6/`.
Photos: Wikimedia Commons, licences per file in `img/INDEX.md` (reference only — do not ship).

## 14. Open questions / known gaps
1. Pillar Ø 5.0 m (赵志荣, zh.wiki) vs 4.2 m (吴念祖, 张耿耿) — maybe 4.2 m concrete + cladding; GAME uses 5.0.
2. Interchange deck heights per level are estimates; only "5 levels, 31 m" is sourced.
3. Relief colour: texts say gold/brass ("金色"), 2022–25 photos read dark bronze — weathering or lighting? Need a
   high-res close-up before texturing.
4. ETC lane label colour on Shanghai canopies (blue vs purple vs green) and signal-head orientation/countdown style
   in Shanghai: unverified.
5. Heights of most minor Bund buildings and the HSBC dome are estimates; tunnel interiors have no photo.
6. Tesla V4 datasheet axis order (334 × 891 × 1946 mm) unverified; Chinese V4 posts may differ from EU ones.
7. Real Bund promenade height above the road (+2.5 m used) unverified.
8. Real-height Lujiazui (632 m) needs camera far plane ≥ 6 km and LODs — confirm with the tech lead.

---------------------------------------------------------------------------------------------------
## 15. Texture & material detail spec (the user asked: "贴图纹理什么都要细化" — every texture must be detailed)
General rules (GAME; numbers are targets, est.):
- **Texel density**: hero/near-road surfaces **512 px/m** (roads, parapets, piers, Bund ground floors, toll plaza,
  gas/charging stations); upper facades **256 px/m** via trim sheets; far skyline 64 px/m. Cars 2048² per car body.
- Every material = albedo + normal + ORM (occlusion/roughness/metal) **+ a detail normal** (tiling 0.5–1 m) **+ a
  grime/variation mask** (world-space noise) so no two 30 m spans look identical. No flat colours anywhere.
- Night: every lit asset has an **emission mask** (windows, signs, LED lines) — emission never on bare concrete.
- Godot: BC7 (desktop) compression, mipmaps on, **anisotropic filtering 16×** (roads at grazing angles at 300 km/h),
  trim sheets 4096² for facades, decals via `Decal` nodes or a decal atlas 4096².
- Make textures from scratch or CC0 (Poly Haven etc.). The photos in `img/` are **reference only**.

| asset | maps & detail to include (all REQUIRED) | reference photo |
|---|---|---|
| asphalt (deck + streets) | 4 × 4 m tile, 2048²; aggregate grain in normal; darker wheel-path bands (0.8 m wide at 1/4 and 3/4 lane), lighter worn centre; decals: **skid marks**, oil drips in lane centres, **patch repairs** 1–3 m (darker, sharper edges), crack lines, **manhole covers Ø 0.7 m** (cast-iron pattern, text "上海市政 雨水" (est.)), rain-wet variant (roughness 0.35 + puddle masks) | `yanan_elev_east_of_*_2025.jpg` |
| lane markings | separate decal layer, thermoplastic white `#EDEDE6` (yellow `#E8B830`), edges slightly rough, 15 % wear noise, glass-bead sparkle (tiny specular noise) | GB 5768.3 numbers §2.6 |
| elevated expansion joints | steel finger joint 0.30 m wide across the full deck **every 30 m** (at each pier), dark rubber strip, metal teeth in normal map; car "thump" SFX hook | (est.) |
| concrete piers / caps / deck soffit | 4 × 4 m tile; **formwork panel grid 1.2 × 2.4 m with tie holes Ø 3 cm**, pour lines; **rain streaks** under every deck edge and cap end (dark vertical drips 2–4 m); efflorescence at joints; moss/dirt 0–0.4 m at the base; ivy decals on 50 % of piers; **pier number plates** (white 0.6 × 0.3 m, black text, e.g. "PM109", "YA-243") | `pillar_day_2022.jpg`, `under_elevated_2009.jpg` |
| parapets ("高架灰") | painted concrete, slight roller marks, grey-brown dirt gradient upward from the deck (spray), reflective delineator every 4 m (amber/white 10 cm discs), emergency phone box every 500 m | `yanan_elev_east_of_xizang_2025.jpg` |
| planter boxes | white plastic `#EDEDE8` with brown soil stains running down the outer face, drip-irrigation pipe (black Ø 2 cm) along the top; plants = alpha cards in a 2048² atlas (bougainvillea bracts, rose heads, privet leaves) + 2 LODs | `interchange_ground_2025.jpg` |
| dragon pillar | brushed steel anisotropic + relief: **4096 × 8192** height/normal (≈ 260 px/m) wrapped once around; bronze cavity darkening + edge wear highlights; dust on upward faces | `sheets/c_pillar.jpg` |
| Bund granite facades | trim sheet 4096²: **rusticated blocks 0.6 × 1.2 m with 1 cm joints**, cornices, dentils, Ionic/Corinthian capitals, balustrades, window surrounds; ±5 % per-block albedo variation; black soot in recesses; brass door frames; **windows with interior mapping** (warm rooms, 30 % lit) | `hsbc_customs_day_2015.jpg`, `peace_hotel_day_2019.jpg` |
| brick (shikumen, Commercial Bank) | grey-blue brick 240 × 53 mm, Flemish bond, red-brick courses, lime mortar 10 mm; stone door frames with carved pediment (normal + AO) | `shikumen_xintiandi_2012.jpg` |
| glass curtain walls (Pudong) | procedural grid: mullion every **1.5 m**, floor-to-floor **4.0–4.2 m**, spandrel band 1.0 m; per-pane tint noise; emission mask with **30–60 % offices lit** (5000 K), per-floor random; reflections via reflection probes + SSR | `lujiazui_skyline_day_2023.jpg` |
| LED media / OPT spheres | emissive pixel-grid shader, **dot pitch 0.4 m** visible up close, animated UV; OPT glass: glossy pink with **visible honeycomb panel grid 1.2 m** | `opt_night_2014.jpg` |
| riveted steel (Waibaidu, toll gantry) | plates with **rivets Ø 2.5 cm every 10 cm** along plate edges (normal map), silver paint chipping at edges, rust streaks under joints, bird droppings on top chords | `waibaidu_bridge_day_2019.jpg` |
| signs | vector-sharp text at ≥ 2048 px per sign face; retro-reflective sheeting micro-pattern in normal; dirt gradient at the bottom; bolts + rear bracing modelled | `yanan_elev_entrance_changde_2025.jpg` |
| water (Huangpu, creek) | 2 scrolling normal layers (8 m and 1.5 m), murky green-brown deep colour `#0B1620`, foam lines at banks and around piers/towers, light reflections stretched vertically | `bund_night_2023.jpg` |
| canopies (toll, gas, charging) | aluminium composite panels 1.2 × 0.6 m with visible seams, rain stains under edges, underside light panels with emission; columns with scuffs at 0–1 m | `toll_g4_xinyang_2023.jpg`, `sinopec_hangzhou_2018.jpg` |
| vehicles | paint with clear-coat; decals: parody taxi company name + fictional phone (e.g. "6688 1234"), roof light "TAXI"; police "公安/POLICE" + 4-digit number; **Shanghai plates "沪A·12345": blue with white text (fuel), green gradient with black text and 6 characters after 沪A (EV)** (unverified, common knowledge) | `taxi_*.jpg`, `police_*.jpg` |
Every one of these needs a **close-up check at 2 m camera distance** and a **speed check at 300 km/h** (no shimmering:
mipmaps + anisotropic + TAA). If a texture looks flat in either check, add a detail normal or a decal pass.
