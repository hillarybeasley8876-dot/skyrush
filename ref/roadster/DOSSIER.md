# Tesla Roadster (2nd gen, revealed 2026-10-15) - DESIGN DOSSIER for SKYRUSH: NEON SHANGHAI

Audience: the implementer building the hero car in Blender (procedural Python) and its thruster/flight
VFX + HUD in Godot 4.7. Everything is numeric on purpose. Follow the numbers; do not "improve" the design.

Legend: **(src)** = stated by Tesla/press (URL given) · **(meas.)** = measured by me from press photos,
+-3..5 % · **(est.)** = my estimate/inference · **(unverified)** = plausible but not confirmed by any source.

Companion files (same folder):
- `roadster_loft.json` - machine-readable copy of every coordinate in sections 2, 4, 5 (load this in the
  Blender script instead of retyping numbers).
- `img/INDEX.md` - 34 reference photos (front 3/4, side, rear, top, wheels, wing, thrusters, interior,
  livestream HUD) + `img/annotated/` measurement sheets with pixel grids and video bursts.
- `scripts/validate_loft.py` - re-checks the loft against the photos (side silhouette MAE 4 mm,
  top outline MAE 18 mm, rear silhouette +24 mm at the time of writing); `scripts/loft_check.py` builds
  the loft exactly as section 8.1 says and prints volume/bbox (run both after editing the JSON).
  Other scripts (sheet/gridcrop/hcat/vcat/sample) made the annotated sheets and colour samples.
- Video timestamps "t=NNN s" refer to the Bilibili recap `../video/roadster.mp4` (182 s, 1920x864).

---------------------------------------------------------------------------------------------------

## 1. Facts

| item | value | source |
|---|---|---|
| Reveal | 2026-10-15, SpaceX McGregor test site (outside Waco), Texas; production "2028, actually" | TechCrunch [1], paultan [5] |
| Design cues | SR-71 Blackbird + F-35 (Tesla); Cybertruck/Cybercab facet language; looks like the white Lotus Esprit S1 | [1], [2], [8] |
| Layout | 2-door coupe, rear-motor RWD, 2 motors (one per rear wheel, torque vectoring), 800-1000 V | Top Gear via Wikipedia [9], notateslaapp [6] |
| Power / torque | >1 MW (~1,341 hp), ~960 lb-ft base, >1,032 lb-ft upper trims; execs also quote 1,500 hp | [6], C&D [3] |
| Mass | ~3,700 lb (C&D); target <1,700 kg (Top Gear) | [3], [9] |
| 0-60 mph | Performance <1.6 s · Thrust <0.9 s (0.85 s quoted) · Rocket <0.59 s · live demo 0.81 s (first recorded run 1.0 s) | [6], [5], [2] |
| Top speed | ">230 mph" on stage (all trims, TechCrunch); spec details seen by notateslaapp: 214 mph now, 330 mph version planned; Musk wants Mach 0.5 (383 mph) | [1], [6], [2] |
| Range / charging | >300 mi (Tesla); 310-320 mi (Top Gear); 15-85 % in ~10 min / >500 kW | [1], [9], [6] |
| Trims | **Performance** "road ready", 2 seats, active aero + multi-mode suction (fans), $50k reservation. **Thrust** "race ready", 2 seats, + rear cold-gas thrusters, limited, $250k. **Rocket** "air ready", 1 seat, invite-only, +perimeter thrusters, "not approved for public road use". Top Gear also mentions a 4th base "Standard" car. | [1], [2], [6], [9] |
| Thrusters per trim | Thrust: **4 rear** nozzles in the rear diffuser (main/acceleration). Rocket: 4 rear + **6 perimeter = 10 total**: "one at each corner to push the car up and two in the front for yaw control" | [2], [6], [9] |
| Gas storage | Thrust: one 200 L carbon-overwrapped pressure vessel (COPV) in the trunk/rear-seat space. Rocket: + 400 L where the passenger seat was = **600 L**, **~250 kg of air**, 2 COPVs | [3], [6], [9] |
| Pressure | Track screen in official photo reads "Thruster 5,500 psi" (~380 bar) (paultan); Top Gear says ~10,000 psi nitrogen for Thrust. CONFLICT - use 5,500 psi in our HUD | [5], [9] |
| Thrust force | "over 80 kN" total; Tesla: thrusters give 4-5x the force the tyres can transmit | [2], Electrek [7] |
| Burn time | one fill = one ~5 s use (Thrust); refill 2-6 h; car "can recharge its air tank" | [9], [6], [2] |
| Exhaust | cold gas (no combustion), exits supersonic -> Mach diamonds visible (Tesla, quoted by paultan) | [5] |
| Fans (suction) | 4 fans in the rear diffuser, 20 kW each (derived from the 12 kW heat-pump compressor motor); pull air from under the car; >2 g cornering 0-50 mph ("sucker mode"); holds the car upside down at standstill. Mode 1 = low-speed suction; mode 2 = high speed, front + rear parts of the suction system open for more underbody flow | [3], [5] |
| Livestream telemetry | ramp climb peak: DOWNFORCE ~4,700 kg at PITCH 170 deg, ~21 m (68-69 ft) up; drop with thruster braking peaked at 3.3 g at ~6.5 m; kickflip over 5 vehicles peaked ~7 m | [5] + video t=84-118 |
| Active aero ("Hidden Aero") | movable skirts front/sides/rear (seal for suction), fender panels that open, vent hood that opens, front wing, barge boards, active rear wing; Track Mode lowers the car; modes Road / High-Downforce / Low-Drag | [6], [8], [5] |
| Rear wing | 2 modes: high drag and high downforce, automatic pitch (C&D). Patent US 2026/0285418: two-element (main + slat, 3-15 mm gap), flush with the deck lid in road mode, 4-bar linkage, stowed->deployed <3 s, angle change <0.25 s, 0 kg (DRS) to 700 kg (>100 mph) | [2], [10] |
| Doors | upward-opening: "butterfly" (C&D, Wikipedia) / "manual scissor-style" (notateslaapp); hinge at the A-pillar base, open ~75 deg up (meas. from photo 02) | [2], [6] |
| Roof | fixed roof with removable T-top glass panels | [9], [8] |
| Cockpit | steer-by-wire yoke LEFT of a large horizontal centre touchscreen; 2 small displays ahead of the driver; small red display at the windshield base (speed/lap); brake- and throttle-by-wire; red UI text | [2], [6] |
| Seats | moulded into the chassis (fixed; only backrests adjust, pedals move); "Supersonic" interior: white upholstery + grey microsuede; red ROADSTER logo on headrests | [6], [8], photos 21-23 |
| Paint / glass | "Ano White" (aerospace-coating inspired); gold-tinted glass (spacesuit visor), titanium accents | [6], [7] |
| Lights | hidden pop-down headlights (2 small triangular panels at the front corners drop to reveal "jewel" lamps), slim full-width FRONT light bar, full-width REAR light bar | [6], [8], MotorTrend snippet [11] |
| Wheels / tyres | stage car: "super light wheels with thin spokes"; stunt car: flat aero hub caps like Cybercab. Tyres Pirelli P Zero Trofeo RS "Elect"; staggered 295/30 R20 front, 335/30 R21 rear (Teslarati post, unverified) | [2], [5], [12] |
| Brakes / suspension | carbon-ceramic brakes; double-wishbone front | [6] |

---------------------------------------------------------------------------------------------------

## 2. Proportions (metres)

Method: Top Gear's wheelbase (2.825 m) is the only official length. Every other number is scaled from it
using (a) side photo 01 (wheel-hub centres 832 px apart -> 3.395 mm/px), (b) the livestream X-ray plan
view 26, (c) the drone top view 12 (856 px nose->tail -> 5.117 mm/px), (d) the daylight rear view 08
(US plate 305 mm wide = 219 px -> 1.39 mm/px; tyre-to-tyre 1393 px). Cross-checks agree within ~3 %.

| dimension | value | how / confidence |
|---|---|---|
| Wheelbase | **2.825** | Top Gear (src) [9] |
| Overall length, body | **4.38** (nose Y=+2.29, tail Y=-2.09) | meas.: side 4.31, X-ray 4.36, top 4.38-4.47 -> 4.38 +-0.08 |
| Length incl. deployed wing | 4.66 (wing trailing edge ~0.28 behind the tail) | meas. photo 02 (est.) |
| Length incl. diffuser fins | 4.49 (fins stick out ~0.11 behind the rear face) | meas. X-ray (est.) |
| Width, body max | **1.98** over the rear arch lips; white upper body 1.92 at the rear haunch | meas. rear view + top view; Top Gear says "about 2.0" |
| Width, front fenders | 1.87 at the black arch lips; white fender tops 1.78-1.82 | meas. top view |
| Width, cabin (beltline) | 1.62 at the glass base (X = +-0.81) | meas. top view |
| Width, roof | 0.94 roof glass (+-0.47); 1.24 incl. roof rails (+-0.62) | meas. top view |
| Mirrors | **NONE** (no side mirrors in any photo; cameras) | photos |
| Height (roof peak) | **1.15** at Y=0 (mid-wheelbase) | meas. side, +-0.03 |
| Front track | 1.56 (est., low confidence; X-ray suggests up to 1.63) | constrained so 295 tyres sit inside the front lips |
| Rear track | **1.63** | meas. rear view (1.632) and X-ray (1.631) |
| Front overhang | **0.88** | meas. (side 0.81-0.86, X-ray 0.90) |
| Rear overhang | **0.68** (body) | meas. (side 0.68, X-ray 0.64) |
| Front tyre | 295/30 R20 -> diameter 0.685, width 0.295, rim 0.508 (20") | size unverified [12]; photos consistent |
| Rear tyre | 335/30 R21 -> diameter 0.734, width 0.335, rim 0.533 (21") | size unverified [12]; rear tyre visibly larger |
| Wheel centres | front (+-0.78, +1.4125, 0.3425); rear (+-0.815, -1.4125, 0.367) | derived |
| Wheel-arch radius | front 0.385, rear 0.41 (tyre radius + ~0.04) | est.; arch tops Z 0.728 / 0.777 |
| Ground clearance | 0.12 at the side skirts and diffuser lip (road mode) | meas. rear view (0.10-0.12) |
| White body lower edge | Z = 0.27 along the doors (black sill/skirt below) | meas. side |
| Hood (nose -> windshield base) | 0.68 long (Y +2.29 -> +1.61), rising Z 0.485 -> 0.70 | meas. side + top |
| Windshield | base Y=+1.61 Z=0.70 -> header Y=+0.38 Z=1.10; rake ~18 deg from horizontal; 1.0 m wide at the header (Y +0.40); at the base 1.0 m along the cowl line, widening to 1.26 m at the lower A-pillar corners (Y +1.46) | meas. |
| Canopy (all glass, plan) | Y +1.61 -> -1.745 (3.36 m long!), max half-width 0.63 at Y +1.46, tapering to 0.24 at the rear | meas. top view |
| Side window (DLO) | arrowhead: front tip Y=+0.90 Z=0.91, deepest 0.27 tall at Y~+0.4, sharp rear tip Y=-0.97 Z=1.015 | meas. side (glass-tint segmentation) |
| Deck (backlight end -> tail) | 0.345 long (Y -1.745 -> -2.09) = the stowed wing panel | meas. top view |
| Doors | front cut Y=+0.80..+0.89, rear cut Y=-0.17 (bottom) .. -0.34 (top); ~1.15 long | meas. side (panel-gap detection) |

Ratios to sanity-check your model: L/WB = 1.55, H/L = 0.263, W/L = 0.45, windshield-base sits only
0.20 m ahead of the front axle (cab-forward), roof peak exactly mid-wheelbase.

---------------------------------------------------------------------------------------------------

## 3. Form language by view

Overall character: a low, long-cabin WEDGE built from big FLAT facets joined by CRISP creases (Cybertruck
/ Cybercab language), with round wheel arches cut cleanly into the facets, a huge gold-bronze glass canopy
like a fighter cockpit (SR-71/F-35), a white upper body over a black lower body, and light only as thin
full-width bars. No chrome, no grille, no logo on the nose, no mirrors, no visible door handles.

### Front (photos 03, 06, 15)
- Nose face: blunt, slightly V-shaped in plan (centre most forward at Y=+2.29, corners swept back to
  Y=+2.09 at X=+-0.67). White top lip Z 0.40-0.485; black lower fascia Z 0.12-0.40 with a wide low intake
  slot (Z 0.18-0.32, X +-0.55, est.) and a thin black splitter lip at Z 0.12 protruding to Y=+2.31.
  A small front camera sits in the black fascia (Tesla has a front bumper camera [6]; exact spot unverified,
  put a 25 mm black lens at (0, +2.28, 0.36)).
- Front light bar: ONE thin white line, 12 mm tall, Z = 0.44, running the full nose width X +-0.70,
  following the swept face, directly under the hood's leading edge. Cool white emission.
- Headlamps: at each front corner a small TRIANGULAR panel (~0.20 m sides) on the fender tip, between the
  hood edge and the outer corner, rear edge at Y=+1.97. Lamp "jewel" (small bright LED cluster,
  ~0.06 x 0.03 m) at (+-0.63, +2.12, 0.47); panel drops ~25 deg when lights are on.
- Hood: flat trapezoid, 1.20 wide at the nose (X +-0.60 at Y=+2.17) narrowing to 0.95 at the cowl
  (X +-0.47 at Y=+1.61). Rises 16-17 deg toward the windshield. A transverse panel line at Y=+1.80 = front
  edge of the opening "vent hood". Hood centre sits ~0.02-0.06 below the fender ridges (shallow trough).
- Fenders: crisp ridge lines run from the nose corners (Z 0.50) up and back to a peak Z=0.78 directly over
  the front axle, then continue as the shoulder line along the whole car.
- Windshield (front view): big trapezoid, A-pillars converge strongly upward: ~1.25 wide at the base,
  1.00 wide at the header, very raked (18 deg). Gold-bronze tint.

### Side (photos 01, 02, 14)
- Silhouette: short low hood -> long straight 18 deg windshield -> roof peak 1.147 at mid-wheelbase ->
  long gentle fall to Y=-1.02 (1.067) -> steeper drop to the haunch (0.95 at Y=-1.36) -> nearly flat
  deck (0.93 -> 0.875) to a cut-off vertical tail. (Exact polyline in section 4.)
- Shoulder/beltline: a strong upward-facing band (70-100 mm) just below the side glass catches light;
  its lower crease runs from the front fender peak (Z 0.78) back at Z~0.75, then rises to 0.85 (Y=-0.8)
  and merges into the rear haunch top (~0.92).
- Body side below the shoulder: flat, tilted ~5-8 deg inward toward the bottom (tumble-under), so it
  reads darker than the shoulder in studio light; ends at a black sill/skirt band Z 0.12-0.27 (inset 3 cm).
- Side glass (DLO): long ARROWHEAD/teardrop - blunt front tip at the A-pillar (Y +0.90, Z 0.91),
  deepest near Y +0.4 (Z 0.80-1.06), top edge almost level, bottom edge rising steadily to a SHARP rear
  point at Y=-0.97, Z=1.015. Glass leans in ~34 deg from vertical (top edge at X 0.63, bottom at X 0.80).
- Door: front cut from the A-pillar (Y +0.54, Z 0.98) diagonally down-forward to the arch top
  (Y +0.89, Z 0.65), then down to the sill (Y +0.80, Z 0.285); rear cut from (Y -0.34, Z 0.98) slanting
  forward to (Y -0.17, Z 0.33). The rear quarter glass behind the door is fixed.
- Wheel arches: perfect circles (R 0.385 front / 0.41 rear) with a thin black lip; the arch cut is a
  hard edge through the flat facets. Amber side marker 0.12 x 0.018 m on the front fender just behind the
  arch at (0.915, +1.02, 0.655).
- Small flush feature (camera or aero flap, unverified) on the haunch at (0.90, -0.77, 0.93), ~0.08 x 0.03.

### Top (photos 12, 07, 11, X-ray 26)
- Plan: blunt arrow nose -> widest at the front arch lips (1.87) -> slight waist along the doors (1.80-1.84)
  -> widest at the rear haunch (1.98 over the lips) -> square tail with 0.15 m chamfered corners.
- Canopy glass occupies the whole centre: windshield + 2 removable T-top panels (between Y +0.38 and
  -0.46, either side of a 0.24 m wide centre T-bar) + a long backlight tapering from 0.87 wide (Y -1.10)
  to 0.48 wide at its square-cut rear end (Y -1.745). Body-colour roof rails X 0.47-0.62.
- Rear haunches rise as sharp "buttress" ridges (X~0.72-0.74, Z~0.93-0.96) flanking the backlight;
  they are solid sail panels (no see-through flying-buttress gap visible - unverified).
- Deck behind the glass = the stowed wing main element (full width +-0.78, Y -1.745 -> -2.09) with a
  subtle centre V-keel.

### Rear (photos 08, 09, 16, 17)
- Rear face Y=-2.09, vertical. From top: deck trailing edge Z 0.875 -> full-width RED light bar
  (Z 0.843-0.857, X +-0.845, one continuous line, nothing else lit) -> black trim strip ~20 mm ->
  white bumper band Z 0.59-0.82 with a US-size plate "RDSTR" (0.305 x 0.152) centred at Z 0.66 and a
  small camera above it -> BLACK lower valance Z 0.12-0.59.
- Black valance: 4 round nozzles in a row at Z=0.50 (X +-0.12, +-0.36), titanium bezel OD 80 mm with a
  gold-anodised throat; below them 4 suction-fan outlets (Z 0.30, X +-0.15, +-0.45, ~0.24 dia, est.)
  separated by 5 vertical diffuser strakes (X 0, +-0.30, +-0.58, est.) that stick out to Y=-2.20.
- Thin red reflector strips 0.12 x 0.012 at the outer bottom corners of the white band (X +-0.84, Z 0.61).
- Tyres fill the haunches: the rear tyre outer faces are flush with the body edge (X +-0.98).
- Wing deployed (photo 08): a wide flat plate 1.80 m span with endplates that hang down and splay out to
  1.94 m at their bottoms (Z 0.81); two struts at X +-0.44. Stowed, the endplates form the angled upper
  corners of the tail and the main plane is the deck lid.

### 3/4 views (photos 03, 05, 10, 33)
- The key read is the contrast: tall gold canopy + white faceted shell + black base. From the front 3/4
  the hood is tiny and the windshield huge; from the rear 3/4 the haunches are clearly wider than the
  cabin (tumblehome ~0.17 m per side from the haunch to the glass base).

### Wheels (photos 13, 01)
- Stage/hero wheel: 6-spoke star. Each spoke = a pair of thin dark spokes with a broad WHITE triangular
  aero blade between neighbouring spokes (6 blades), gold/bronze accents visible deeper in the wheel,
  dark hexagonal centre cap with the Tesla "T". Rim face nearly flat (aero).
- Stunt/flight car: flat aero disc covers like Cybercab/Cybertruck (C&D [2]). Use as an optional variant.
- Tyres: low profile (front sidewall 88 mm, rear 100 mm), white "P ZERO TROFEO RS" sidewall lettering.

---------------------------------------------------------------------------------------------------

## 4. Loft / blockout table

Frame: X = right, Y = forward, Z = up, metres, origin on the ground midway between the axles.
Front axle Y=+1.4125, rear axle Y=-1.4125. Right half only (x >= 0); mirror for the left.
Same data in `roadster_loft.json` (use the JSON, not this text, in code). Confidence: centreline and
plan +-2-4 cm (validated against photos); section interiors (crease positions) +-5 cm (est.).

### 4.1 Side-profile polylines (Y, Z)
- **Centreline top** (hood -> windshield -> roof -> backlight -> deck):
  (2.29,0.485) (2.17,0.525) (2.10,0.545) (1.97,0.59) (1.85,0.635) (1.80,0.645) (1.65,0.69)
  (1.61,0.70 cowl) (1.41,0.77) (1.19,0.842) (1.02,0.905) (0.85,0.962) (0.68,1.017) (0.51,1.067)
  (0.38,1.10 header) (0.17,1.138) (0.00,1.147 peak) (-0.17,1.147) (-0.34,1.14) (-0.46,1.13 T-top end)
  (-0.68,1.112) (-0.85,1.093) (-1.02,1.067) (-1.19,1.005) (-1.36,0.952) (-1.53,0.93)
  (-1.745,0.915 glass end / wing LE) (-1.90,0.90) (-2.04,0.883) (-2.09,0.875 tail)
- **Fender ridge + shoulder crease** (outer upper edge, X 0.6 -> 0.93):
  (2.25,0.475) (2.10,0.545) (1.97,0.60) (1.87,0.655) (1.70,0.723) (1.53,0.76) (1.36,0.78 peak)
  (1.20,0.775) (1.05,0.765) (0.70,0.755) (0.20,0.75) (-0.30,0.79) (-0.80,0.85) (-1.00,0.88)
  (-1.15,0.90) (-1.41,0.92) (-1.70,0.915) (-1.90,0.90) (-2.09,0.875)
- **DLO top** (side-glass upper edge, X~0.63): (0.90,0.91) (0.68,0.985) (0.54,1.022) (0.34,1.056)
  (0.07,1.097) (-0.14,1.097) (-0.41,1.083) (-0.61,1.063) (-0.82,1.035) (-0.97,1.015)
- **DLO bottom = beltline** (X~0.80): (0.90,0.91) (0.70,0.845) (0.54,0.805) (0.34,0.80) (0.07,0.828)
  (-0.14,0.856) (-0.41,0.889) (-0.61,0.917) (-0.82,0.964) (-0.97,1.015)
- **Rocker**: white body ends at Z 0.27 from Y +1.00 to -0.98; black sill/skirt Z 0.12-0.27, 3 cm inset.
- **Nose face** Y=+2.29 from Z 0.12 to 0.485 (splitter tip Y=+2.31 at Z 0.12).
  **Tail face** Y=-2.09 from Z 0.875 down to 0.12; black below Z 0.59; diffuser strakes to Y=-2.20.

### 4.2 Top-view outline (X, Y), right half, nose -> tail
Max extent INCLUDING the black arch lips (covers the tyres):
(0.00,2.29) (0.30,2.275) (0.46,2.245) (0.56,2.21) (0.67,2.09) (0.77,1.93) (0.81,1.85) (0.89,1.80)
(0.935,1.72) (0.935,1.10) (0.92,1.03) (0.91,0.70) (0.92,0.28) (0.915,-0.33) (0.90,-0.95) (0.93,-1.00)
(0.985,-1.08) (0.99,-1.41) (0.985,-1.74) (0.97,-1.78) (0.93,-1.84) (0.86,-1.95) (0.80,-2.05)
(0.72,-2.09) (0.00,-2.09)
White upper body only (fender tops / haunch tops, what the photo shows from above):
(0.00,2.29) (0.30,2.275) (0.46,2.245) (0.56,2.21) (0.67,2.09) (0.77,1.87) (0.87,1.61) (0.89,1.41)
(0.90,1.30) (0.88,1.10) (0.90,0.70) (0.92,0.28) (0.915,-0.33) (0.895,-0.95) (0.90,-1.15) (0.955,-1.36)
(0.96,-1.46) (0.88,-1.56) (0.86,-1.66) (0.84,-1.77) (0.835,-1.90) (0.82,-1.97) (0.72,-2.07) (0.00,-2.09)
Canopy glass plan (windshield + T-tops + backlight): (0.00,1.61) (0.50,1.59) (0.63,1.46) (0.63,1.10)
(0.61,0.95) (0.51,0.43) (0.47,0.00) (0.46,-0.59) (0.435,-1.10) (0.38,-1.30) (0.32,-1.51) (0.25,-1.71)
(0.24,-1.745) (0.00,-1.745). Side glass in plan: strip X 0.63 (top edge) -> 0.80 (bottom edge),
Y +0.90 -> -0.97.

### 4.3 Cross-sections (loft-ready): 10 key points K0..K9 per half-section, (x, z)
Every section has the SAME 10 points in the same order, so a script can bridge S01..S15 1:1 (quads).
K0 bottom centre · K1 floor outer edge · K2 sill top (white starts) · K3 lower side · K4 upper side ·
K5 shoulder crease · K6 beltline/glass base · K7 side-glass top · K8 roof-glass edge · K9 top centre.
Repeated points (e.g. K6 = K7 where there is no side glass) are intentional: merge-by-distance AFTER
bridging. `bands` = material of the 9 strips between consecutive points: B = black trim, W = Ano White,
G = gold glass. `well` = a wheel well crosses this station (do NOT model it in the section; cut it
afterwards, see 8.1 step 2).

| id | Y | K0 .. K9 (x,z) | bands | well | note |
|---|---|---|---|---|---|
| S01 | +2.25 | (0,0.12) (0.38,0.12) (0.43,0.16) (0.44,0.3) (0.44,0.4) (0.435,0.45) (0.43,0.485) (0.43,0.485) (0.3,0.49) (0,0.497) | BBBBWWWWW | - | nose; light bar on the face at z 0.44 |
| S02 | +2.10 | (0,0.12) (0.55,0.12) (0.64,0.17) (0.665,0.3) (0.665,0.4) (0.665,0.42) (0.655,0.5) (0.62,0.545) (0.59,0.547) (0,0.545) | BBBBWWWWW | - | headlamp triangle x 0.56-0.665 z 0.47-0.545 |
| S03 | +1.85 | (0,0.12) (0.62,0.12) (0.8,0.18) (0.81,0.3) (0.81,0.42) (0.775,0.6) (0.7,0.665) (0.7,0.665) (0.53,0.655) (0,0.635) | BBBBWWWWW | - | fender ridge K6 x 0.70, hood edge K8 x 0.53 |
| S04 | +1.65 | (0,0.12) (0.8,0.12) (0.935,0.25) (0.935,0.45) (0.935,0.646) (0.88,0.69) (0.78,0.735) (0.78,0.735) (0.48,0.7) (0,0.69) | BBWWWWWWW | front | front arch, front half |
| S05 | +1.41 | (0,0.12) (0.82,0.12) (0.935,0.25) (0.935,0.5) (0.935,0.728) (0.9,0.76) (0.84,0.785) (0.72,0.775) (0.7,0.776) (0,0.77) | BBWWWWWWG | front | front axle; windshield base region |
| S06 | +1.05 | (0,0.12) (0.86,0.12) (0.89,0.27) (0.92,0.5) (0.92,0.7) (0.9,0.765) (0.7,0.85) (0.64,0.875) (0.63,0.878) (0,0.886) | BBWWWWWWG | - | A-pillar base |
| S07 | +0.70 | (0,0.12) (0.86,0.12) (0.89,0.27) (0.93,0.5) (0.93,0.72) (0.91,0.755) (0.8,0.845) (0.66,0.98) (0.59,0.996) (0,1.017) | BBWWWWGWG | - | door; A-pillar between K7 and K8 |
| S08 | +0.20 | (0,0.12) (0.86,0.12) (0.89,0.27) (0.93,0.5) (0.935,0.73) (0.915,0.75) (0.8,0.818) (0.63,1.08) (0.47,1.12) (0,1.14) | BBWWWWGWG | - | T-top glass x 0.12-0.47, black T-bar x < 0.12 |
| S09 | -0.30 | (0,0.12) (0.86,0.12) (0.89,0.27) (0.93,0.5) (0.935,0.76) (0.91,0.79) (0.8,0.873) (0.64,1.086) (0.47,1.128) (0,1.145) | BBWWWWGWG | - | T-top glass x 0.12-0.47, black T-bar x < 0.12 |
| S10 | -0.80 | (0,0.12) (0.85,0.12) (0.88,0.27) (0.905,0.5) (0.905,0.8) (0.88,0.85) (0.79,0.957) (0.7,1.038) (0.45,1.09) (0,1.1) | BBWWWWGWG | - | fixed rear quarter glass |
| S11 | -1.15 | (0,0.12) (0.86,0.12) (0.95,0.27) (0.985,0.5) (0.985,0.62) (0.95,0.7) (0.9,0.85) (0.74,0.96) (0.43,1.012) (0,1.02) | BBWWWWWWG | rear | buttress ridge = K7 |
| S12 | -1.41 | (0,0.12) (0.86,0.12) (0.96,0.27) (0.99,0.5) (0.985,0.62) (0.94,0.78) (0.89,0.86) (0.72,0.935) (0.35,0.945) (0,0.95) | BBWWWWWWG | rear | rear axle; widest station |
| S13 | -1.78 | (0,0.12) (0.8,0.12) (0.93,0.3) (0.97,0.45) (0.97,0.6) (0.92,0.7) (0.87,0.85) (0.78,0.905) (0.7,0.907) (0,0.912) | BBBBWWWWW | rear | deck = stowed wing main element x < 0.78 |
| S14 | -2.00 | (0,0.12) (0.62,0.12) (0.8,0.3) (0.84,0.59) (0.845,0.7) (0.845,0.82) (0.8,0.865) (0.8,0.865) (0.7,0.875) (0,0.885) | BBBWWWWWW | - | light bar on rear face z 0.843-0.857 |
| S15 | -2.09 | (0,0.12) (0.55,0.12) (0.7,0.3) (0.72,0.59) (0.72,0.7) (0.72,0.82) (0.7,0.86) (0.7,0.86) (0.65,0.87) (0,0.875) | BBBWWWWWW | - | rear face (flat cap); corners chamfered back to S14 |

Notes for lofting: keep EVERY key point as a hard vertex (sharp edge); between sections interpolate
linearly (this design is ruled surfaces, not soft curves). The only curved parts are the wheel arches
(circles), the windshield/backlight crown (max 1-2 cm) and the light-bar ends. Close the front with a
cap from S01 to the centre tip (x = 0 at Y = +2.29, same z values) and the rear with a flat cap on S15.
Validation at writing time: side silhouette MAE 4 mm vs photo 01, white plan outline MAE 18 mm vs
photo 12, rear silhouette +24 mm vs photo 08 (photo 08 under-reads by ~2-3 % due to perspective).

---------------------------------------------------------------------------------------------------

## 5. Thrusters (and fans)

Evidence: rear nozzles measured in daylight rear photo 08 (ring OD 57-58 px = 80 mm, centres 172 px =
0.24 m apart, Z 0.50). Perimeter set: Tesla/Top Gear say 6 extra = 4 corner LIFT + 2 front YAW [6][9];
studio photo 18 shows 4 straight-down plumes seen from behind at X ~+-0.57 (front pair, seen under the
car) and +-0.73 (rear pair); livestream frame 27 shows plumes leaving just AHEAD of the front wheel and
just BEHIND the rear wheel; paultan: "thrusters at all four corners firing downwards to control the
landings" [5]. Exact perimeter positions are (est.); yaw nozzle position is (unverified).

| node | trim | position (x, y, z) | direction | bore / bezel | role |
|---|---|---|---|---|---|
| Nozzle_R1 | Thrust+Rocket | (-0.36, -2.085, 0.50) | (0,-1,0) | 0.055 / 0.080 OD | main thrust (launch, boost, braking-in-air) |
| Nozzle_R2 | Thrust+Rocket | (-0.12, -2.085, 0.50) | (0,-1,0) | same | main |
| Nozzle_R3 | Thrust+Rocket | (+0.12, -2.085, 0.50) | (0,-1,0) | same | main |
| Nozzle_R4 | Thrust+Rocket | (+0.36, -2.085, 0.50) | (0,-1,0) | same | main |
| Nozzle_P1 | Rocket | (-0.57, +1.95, 0.15) | (0,0,-1) | 0.055 / 0.080 (est.) | front-left lift |
| Nozzle_P2 | Rocket | (+0.57, +1.95, 0.15) | (0,0,-1) | same | front-right lift |
| Nozzle_P3 | Rocket | (-0.73, -1.95, 0.15) | (0,0,-1) | same | rear-left lift |
| Nozzle_P4 | Rocket | (+0.73, -1.95, 0.15) | (0,0,-1) | same | rear-right lift |
| Nozzle_P5 | Rocket | (-0.68, +2.02, 0.30) | (-1,0,0) | 0.035 / 0.055 (est.) | front yaw, fires left |
| Nozzle_P6 | Rocket | (+0.68, +2.02, 0.30) | (+1,0,0) | same | front yaw, fires right |
| Fan_R1..R4 | Perf. and up | X -0.45/-0.15/+0.15/+0.45, Y -2.05, Z 0.30 | (0,-1,0) | 0.24 dia (est.) | suction fans exhausting rearward |
| FanIntake_F | Perf. and up | slot X +-0.45, Y +2.15, Z 0.13, 0.06 tall (est.) | - | - | front part of suction system; opens in high-speed mode |

- Rear nozzle look: recessed 30 mm in the black valance; bright titanium bezel ring (80 mm OD, 8 mm wide);
  inside a gold-anodised conical throat narrowing to a black 30 mm hole. 4 identical, evenly spaced.
- Lift nozzles: flush in the black underbody corners with an 80 mm titanium ring; invisible in normal
  driving. Yaw nozzles: small round ports in the black lower front corners (just under the light-bar ends).
- Combinations used in flight (my reading of the demo, est.): hover/landing = P1-P4 together; roll =
  left pair (P1+P3) vs right pair (P2+P4) differential; pitch = front pair vs rear pair; yaw = P5 or P6;
  forward boost/air-brake = R1-R4 (when the car is nose-down falling, R1-R4 also slow the fall).
- Game budget (est., arcade): R1-R4 total 50-60 kN (~3.4 g push for a 1,700 kg car, matches 0-60 in
  0.81 s); P1-P4 total 60-80 kN (3.6-4.8 g lift, so hover needs ~25 % throttle); one "tank" = 5 s of full
  burn, recharge over ~20-30 s in game (real car: hours). HUD tank pressure starts at 5,500 psi.

---------------------------------------------------------------------------------------------------

## 6. Flight / thruster VFX reference (with timestamps)

### 6.1 What the real plumes look like
| aspect | observation | where |
|---|---|---|
| Colour | NOT fire. White condensation vapour. Neutral light: core #EAF4FF, body #E4E7E6 -> #C6C9C5. Studio light: core #C9C7D6 (slight violet-blue). Stage light tints it: cyan #AFD9DE / #93C5CB, red from below #7E5C64 | photos 18, 27, 28, 29 (sampled) |
| Near-nozzle core | tight, straight, very bright for the first ~0.3-0.5 m, ~0.06-0.10 m wide; in photo 18 you can see 3-5 bright bands = Mach (shock) diamonds, Tesla confirms supersonic exit [5] | photo 18 |
| Spread | down-plumes widen to 0.4-0.8 m at 3-5 m length; the launch plume is a cone ~9 deg half-angle | photos 27, 28, 29 |
| Length | down-plumes reach the ground from 5-7 m altitude (>= 5 m visible column); launch plume trail at t=1.00 s is ~12-13 m long (= distance driven; the gas stays where it was emitted) and ~4-5 m wide at its far end | photos 27-29 |
| Opacity | core opaque; body 60-80 %; edges very soft, turbulent, billowing (no hard shapes) | all |
| Ground hit | huge white cloud: at touchdown it is ~2 car lengths wide; 1 s later 4-5 car lengths (~20 m) wide and ~2 car heights (~2.5 m) tall; persists 3-5 s, slowly thinning; car drives out of it | video t=118-123, t=138-143 |
| Sound | broadband roaring hiss (like an air-blast/RCS), spectrum flat, centroid ~2.5-3.3 kHz in the recap audio (mixed with crowd); fans add a high whine. No combustion rumble | recap audio t=111-117 (my FFT analysis) |

### 6.2 How the car moves (demo, for animation/physics reference)
- Ramp climb (t=62-98): drives up the curved wall on suction; HUD climbs to DOWNFORCE ~4,700 kg,
  PITCH 170 deg, ALTITUDE ~68-69 ft (21 m).
- Drop + thruster braking (t=116-120): leaves the top inverted at 67.5 ft (20.6 m), falls ~1.7 s
  (HUD 0.2-0.3 g = free fall), corner thrusters fire at ~21 ft (6.5 m) -> 3.3 g for ~0.7 s, touches
  down in its own cloud at ~t=118.5-119, drives out at t=120. (Check: free fall 14 m -> 16.6 m/s; 22.6 m/s2
  net decel stops it in 6.1 m - consistent.)
- Hover/translate (t=135-138): car flies level beside the ramp with thin straight horizontal jets
  (~1 car length long) - attitude/yaw firings; lands in a cloud at t=139-140.
- Final flip (t=146-153): leaves the ramp top, performs ~1 full roll in ~3 s (est. 120 deg/s average) with
  short corner bursts, lands upright in a smaller cloud at ~t=152, drives off (t=154).
- Kickflip over 5 vehicles (live stream, photo 28; not in the recap): peak ~7 m, one full roll.
- Game recommendation (arcade feel, est.): hop to 4-7 m in 0.8-1.0 s; barrel roll 360 deg in 1.2 s
  (300 deg/s peak); landing cushion burst 0.4-0.7 s at 3 g net; always land wheels-down with a
  0.15 s suspension squash (25 % compression) and a cloud burst.

### 6.3 Godot 4 recipe per nozzle (start here, tune by eye)
1. `JetCore` (MeshInstance3D, child of the nozzle Marker3D, -Z of the marker = nozzle direction):
   a cone/cylinder mesh, length 0.9 m at full thrust (rear R) / 0.6 m (lift P) / 0.35 m (yaw), radius
   0.03 -> 0.09 m. Unshaded, additive, `albedo #EAF4FF`, emission energy 3-4 (HDR so it blooms). Fade
   alpha along length with a gradient texture (1.0 at 0 m -> 0 at the tip). Add 4 shock "diamonds" as
   brighter rings at 0.06, 0.15, 0.24, 0.33 m from the exit (relative brightness 1.0, 0.7, 0.45, 0.25),
   each 0.03 m long; scale whole core length with throttle; flicker scale +-8 % at 25-35 Hz.
2. `JetVapour` (GPUParticles3D, `local_coords = false` so the trail stays in the world): emission
   300-600 particles/s per nozzle at full throttle (0 when off; ramp in 40 ms, out 120 ms); lifetime
   0.8-1.4 s; initial velocity along the nozzle axis: lift P1-P4 30-35 m/s, rear R1-R4 30 m/s, yaw P5/P6
   15 m/s; spread 7 deg; damping 100 (Godot damping is linear m/s2, so particles stop after v0/100 =
   0.15-0.35 s, having travelled v0^2/200 = 1-6 m: yaw ~1 m, rear 4-5 m, lift ~6 m = reaches the ground
   from hover height, like photos 27/28); scale curve 0.12 m -> 1.4 m; colour ramp #F2F6FA a=0.85 ->
   #D8DEE6 a=0.35 -> a=0;
   turbulence on (noise strength 2.5, scale 1.5, speed 0.6); billboard soft particles, LIT material
   (so neon signs and street lights tint it - the demo plumes turned cyan/red under stage lights).
3. `GroundCloud` (one-shot GPUParticles3D at the ray-hit point when any down-firing jet is <= 6 m above
   ground): 60-90 large particles; radial velocity 6-12 m/s, upward 1-3 m/s, damping 3; size 1.5 -> 5 m;
   lifetime 2.5-4 s; alpha 0.7 -> 0; colour #E6EAEE lit. Re-trigger every 0.25 s while firing. Target:
   ~20 m wide, ~2.5 m tall after 1 s. For the rear launch plume use the same but elongated along -Y.
4. Lights: a weak OmniLight3D at each firing nozzle (colour #CFE3FF, energy 0.5-1, range 2 m) - cold gas
   does not glow, this only fakes the reflected scene light. NO orange, NO heat haze, NO sparks.
5. Sound: looping filtered white noise (band 600 Hz-8 kHz, peak ~3 kHz), sharp 30 ms attack, 120 ms
   release + a pneumatic "chuff" on cut-off; pitch +-5 % with throttle. Fans: a separate 1.5-3 kHz whine
   that rises with suction mode.

### 6.4 Livestream HUD (quote this for our flight HUD; photo 30, video t=62-120)
- Layout at 16:9 (measured on 2560x1440, scale proportionally): two clusters on the bottom edge,
  gauge centres at y = 0.906 H. Left cluster: DOWNFORCE gauge at x = 0.091 W, car-attitude circle at
  x = 0.19 W. Right cluster: PITCH gauge at x = 0.815 W, ALTITUDE gauge at x = 0.910 W.
  "TESLA LIVE" bug bottom-right below/right of the gauges.
- Gauge: circle diameter 0.139 H (~200 px at 1440p, 150 px at 1080p); thin ring stroke ~2.5 px@1080p;
  ring is a 270 deg arc open at the bottom (gap from 4:30 to 7:30 o'clock), value part pure white
  #FFFFFF, remainder dim grey ~#5A5A5A; short end ticks.
- Text inside each gauge (white): label on top in small caps with wide tracking ("DOWNFORCE", "PITCH",
  "ALTITUDE", cap height ~0.009 H), big value in the middle (digit height ~0.028 H, squarish techno face,
  zero appears slashed: "17Ø", "68.Ø"), unit below ("KG", "DEG", "FT", ~0.008 H).
- Car-attitude circle: same diameter, dark translucent fill, thin outline; inside a white line-art SIDE
  silhouette of the Roadster rotated by the current pitch (shown nearly upside-down at 170 deg). During
  landings the telemetry graphic showed thruster firing at all four corners [5] -> draw small white
  plume ticks at the four corners of the icon when P1-P4 fire.
- Other readouts seen: a G gauge (values 0.2-3.3 during the drop, t=112-121), 0-60 timer "00:00:01:00"
  (photo 29). Values seen: DOWNFORCE 0 -> 4698 kg; PITCH 0 -> 170 deg; ALTITUDE 0 -> 68.0 ft;
  G 3.3 peak at 21.4 ft (t=118).
- Free fonts that match: "Oxanium" or "Share Tech Mono" (OFL) for values; any light wide grotesk for labels.

---------------------------------------------------------------------------------------------------

## 7. Materials (hex = sRGB sampled from press photos; lighting caveats noted)

| material (Blender name) | base colour | PBR | evidence / caveat |
|---|---|---|---|
| `M_AnoWhite` body paint | **#ECEDEF** (pure cool white; lit studio samples #F6F7F7-#FDFDFD, shade #AEADB2-#B8B7BC) | metallic 0, roughness 0.28, clearcoat 0.6 / clearcoat roughness 0.12, NO pearl flakes | photos 11-13 k-means; Tesla calls it an aerospace-style coating - reads satin-clean, not glittery |
| `M_BlackTrim` sills, lower fascia, rear valance, arch lips | **#111113** | metallic 0, roughness 0.55 (satin) | rear valance in shade #080606-#222225 |
| `M_Carbon` diffuser strakes, fan shrouds, splitter | #141416 + 2x2 twill weave normal (4 mm tows) | roughness 0.35, clearcoat 0.8 | weave texture visible in the diffuser in photos 08/09 (likely carbon) |
| `M_GlassGold` canopy + side glass | **#5A3F2A** tint (daylight top view #4E3828-#5D4433; studio side #181212) | Godot: transparency on, albedo #5A3F2A alpha 0.85, metallic 0.3, roughness 0.03 (the metallic term gives the gold mirror sheen #C89A5A). Blender preview: Principled, transmission 0.2, IOR 1.52, same colour/roughness. From outside it must read as dark bronze-gold, NOT see-through | spacesuit-visor gold glass [6] |
| `M_LightBarRear` | **#FF1A2A** emission, strength 8-12 (core sampled #FE0001 day, #FD3942 night) | unshaded/emissive, bloom on | photo 08 |
| `M_LightBarFront` + headlamp jewels | #F2F6FF emission, strength 6-10 | emissive | photos 03, 20 |
| `M_AmberMarker` | #FF8A00 emission 2 | emissive | photo 14 |
| `M_RedReflector` | #B00012 | roughness 0.2 | photo 08 |
| `M_Titanium` nozzle bezels, accents | **#9B958E** | metallic 1, roughness 0.30 | photo 08 ring sample |
| `M_GoldAnod` nozzle throats, wheel accents | **#B08458** (renders #52361D-#AD8765) | metallic 1, roughness 0.35 | photos 09, 13 |
| `M_WheelWhite` aero blades | #E6E6E8 | metallic 0, roughness 0.35 | photo 13 |
| `M_WheelDark` spokes, hub | #2A2B2E | metallic 0.8, roughness 0.4 | photo 13 |
| `M_Tyre` | #161616, sidewall text #D8D8D8 | roughness 0.85 | photos 01, 25 |
| `M_CaliperBronze` (carbon-ceramic calipers) | #6E4A2E (unverified, dark bronze glimpsed behind spokes) | metallic 0.6, roughness 0.4 | photo 01 crop |
| `M_Plate` | #E8E8E8 field, #5A5A5A embossed "RDSTR" | - | photo 08 |
| Interior: `M_SeatWhite` | #E4E4E6 (shade #AAAAB2) | roughness 0.8 (fabric) | photos 21-23 |
| Interior: `M_Microsuede` | #464551-#51545C | roughness 0.95 | |
| Interior: `M_CabinBlack` | #12141A | roughness 0.6 | |
| Interior: `M_RedAccent` ambient strips, ROADSTER logo, UI | #FF2A2A emission 1-2 | emissive | photos 21-23 |

Lighting caveat: studio photos are low-key (dark background, single key light) so whites read grey in
shade; desert daylight shots are backlit at the rear. The hexes above are the corrected base colours.

### 7.1 Texture detail spec (refine every map - user request "贴图纹理什么都要细化")
Texel density LOD0: body 1024 px/m (one 4096 atlas for Body + black trim), wheels 2048 per wheel set,
glass 1024, nozzles/fans/plate/lamps one 2048 trim sheet, interior 2048. Bake AO + curvature from the
bevelled high-poly; author everything else procedurally in Blender (noise/voronoi) then bake to images.

| part | maps to author | concrete detail |
|---|---|---|
| Ano White paint | base, roughness, normal, clearcoat | base flat #ECEDEF with 2 % large-scale value noise; orange-peel normal (noise scale 0.5 mm, strength 0.03); roughness 0.26-0.30 noise so neon reflections streak; optional wet-road grime mask on the lowest 0.3 m (darken 15 %, roughness 0.12 when wet) |
| Panel gaps | normal + AO lines | 4 mm wide, dark AO core #1A1A1A; all lines listed in 3/4.1 (doors, hood vent Y+1.80, cowl Y+1.61, headlamp triangles, T-tops Y+0.38/-0.46, wing edge Y-1.745) |
| Black trim / lower body | base, roughness, normal | satin #111113, roughness 0.5-0.6, fine 0.2 mm grain normal; arch lips slightly glossier (0.35) |
| Carbon (diffuser strakes, splitter, fan shrouds) | base, normal, clearcoat | 2x2 twill, 4 mm tow width, two tones #141416 / #232327, anisotropic clearcoat 0.8 |
| Gold glass | tint, roughness, frit mask | tint #5A3F2A, black ceramic frit band 30 mm wide with fading 3 mm dot gradient around windshield and backlight edges (est., typical Tesla glass); faint interior silhouette visible only at <30 deg viewing angle |
| Rear light bar | emission mask | thin 6 mm bright core line inside a 14 mm smoked-red lens; LED segmentation pitch 6 mm at 15 % contrast; housing #0B0B0C |
| Front light bar + jewels | emission mask | 4 mm white core line; each jewel = 3 small square LED cells in a row inside a black triangle pocket |
| Tyres | normal, base, roughness | semi-slick tread with 2 circumferential grooves (8 mm) per tyre, few lateral sipes; sidewall raised lettering at 25 % white (#D8D8D8): use FICTIONAL text (e.g. "SKYRUSH TROFEO") unless the project clears the Pirelli trademark; size text "295/30 R20" / "335/30 R21" |
| Wheels | base, roughness, normal | white aero blades #E6E6E8 with 1 mm chamfer highlight; dark spokes #2A2B2E satin metal; gold accents #B08458 brushed (anisotropic, radial); hex centre cap, emblem decal (decide: real "T" or fictional) |
| Brakes | base, normal | carbon-ceramic disc #3A3A3C mottled + 12 slots/holes ring (est.); caliper #6E4A2E bronze (unverified) |
| Nozzles | base, roughness, anisotropy | titanium ring #9B958E with concentric machining marks (anisotropy rotation radial); gold throat #B08458 grading to #2A1A0E deep inside; NO heat tint (cold gas) |
| Fans / grilles | base, normal, alpha | 11-blade fan (est.) dark metal; spinning state swaps to a radial motion-blur disc texture; 6 mm hex mesh grille |
| Plate | normal, base | embossed "RDSTR", 3 mm relief, field #E8E8E8, letters #5A5A5A |
| Interior | base, normal | seat fabric fine weave #E4E4E6; microsuede #4A4955 with soft noise; red #FF2A2A ambient strips; screen = emissive red UI on black (Godot ViewportTexture can drive it) |

---------------------------------------------------------------------------------------------------

## 8. Blender build plan (hero car, game-ready)

Target budget: LOD0 25-40k tris incl. wheels, LOD1 10k, LOD2 3k. Scale 1 unit = 1 m, +Y forward in
Blender (rotate the root -90 deg about Z only if the Godot pipeline needs -Z forward - decide once and
document it in the scene README). Origin = ground centre between axles (as in this dossier).

### 8.1 Build order
1. Load `roadster_loft.json`. For each of the 15 `sections` build the 10 key points K0..K9 at its Y,
   mirror them (x -> -x) to get a closed 18-point ring, and bridge ring i to ring i+1 vertex-to-vertex
   (BMesh quads). Cap the nose (fan to x=0 at Y=+2.29) and the tail (flat face on S15). Merge by
   distance 1 mm, then `bmesh.ops.recalc_face_normals` (the ring order above winds inward). No
   subdivision surface. Expected result (checked with `scripts/loft_check.py`): ~560 tris, closed,
   volume ~6.1 m3, bbox x +-0.99, y -2.09..+2.29, z 0.12..1.147, glass area ~4.2 m2.
2. Cut the 4 wheel wells with boolean DIFFERENCE cylinders (axis = X): front R 0.385 centred
   (+-0.78, +1.4125, 0.3425), rear R 0.41 centred (+-0.815, -1.4125, 0.367), spanning x 0.60 (front) / 0.62 (rear) -> 1.10
   (and mirrored). Add a black well liner (cylinder shell, inner radius = well radius, x 0.60 -> lip) and
   a black arch lip: 15 mm wide band, 8 mm proud, along each cut edge.
3. Materials: strip j of every section (between K[j] and K[j+1]) takes `bands[j]` of the section it
   starts from (B -> `M_BlackTrim`, W -> `M_AnoWhite`, G -> `M_GlassGold`); the nose cap is black below
   z 0.40, the tail cap black below z 0.59. Separate all G faces into the object `Glass`.
4. Mark creases: every section vertex row along Y = sharp edge; add a Bevel modifier 4 mm, 2 segments,
   limit by angle 25 deg, harden normals -> the facets catch highlights like the photos.
5. Panel gaps as 4 mm wide, 5 mm deep grooves (or a normal-map line): door cuts (section 4.1), hood vent
   line Y=+1.80, cowl Y=+1.61, headlamp panels, wing front edge Y=-1.745, T-top edges Y=+0.38/-0.46.
6. Details: light bars, headlamp jewels, plate, nozzles, fans, diffuser strakes, markers.
7. Wheels (1 front + 1 rear master, instanced), brakes, then doors (separate objects, pivots set),
   wing (separate object with poses), interior (low detail; only what is visible through gold glass).
8. Export glTF 2.0 (`.glb`) with named nodes below; apply scale; Y-up conversion handled by the exporter.

### 8.2 Parts list and node names (pivot = where the object rotates)
| node | contents | pivot / notes |
|---|---|---|
| `Roadster` (root Empty) | everything below | ground centre between axles |
| `Body` | shell incl. black lower parts as material slots | static |
| `Glass` | windshield, T-top panels, backlight, fixed rear quarter glass | static (T-tops could be separate) |
| `Door_L`, `Door_R` | outer skin between the cut lines + side glass above it | pivot at the door front edge, (+-0.90, +0.86, 0.66) (est.); open pose = rotate 75 deg about X so the rear end swings UP (scissor), then tilt the top 12 deg outward about Y (butterfly cant) - matches photos 02/04 |
| `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` | rim + tyre (+ optional aero disc variant `Wheel_*_Aero`) | wheel centre; FL = front-left (x<0) |
| `Caliper_FL/FR/RL/RR` | caliper + carbon-ceramic disc (front disc 0.41, rear 0.39 dia, est.) | wheel centre, does NOT spin |
| `Wing` | main element + slat + 2 endplates + 2 struts | pivot at the main element leading edge; the 2 Tesla modes = poses `high_downforce` (15 deg) and `air_brake` (= Tesla's "high drag", 60 deg); also make `stowed` (flush deck lid) and `low_drag` (DRS, ~1 deg). LE/TE coordinates in JSON `parts.wing.poses`; animate stowed->deployed in 2.5 s, pitch changes in 0.25 s (patent [10]) |
| `LightBar_Rear` | emissive strip 1.69 x 0.014, Z 0.85, on the rear face | static |
| `Lamp_Front` | front light bar (1.40, Z 0.44) + 2 jewel lamps | static |
| `HeadlampPanel_L/R` | triangular flaps | hinge on the panel's front edge; open = 25 deg down |
| `Nozzle_R1..R4`, `Nozzle_P1..P6` | bezel + throat mesh; ALSO export an Empty/Marker with the same name + `_FX` suffix whose -Z axis = jet direction | positions/directions section 5 |
| `Fan_R1..R4`, `FanIntake_F` | fan disc (spins), shroud, intake flap | fan centre |
| `Skirt_L/R` | black sill strip | can drop 0.08 in suction mode |
| `Interior` | 2 white seats (Rocket: 1 seat + COPV), yoke, horizontal screen, red strips | static, simplified |
| `Plate_Rear` | RDSTR plate | static |

### 8.3 What sells it at game camera distance (chase cam 5-7 m behind, 1.5-2 m up)
1. The full-width red rear light bar with bloom - #1 recognisable feature from behind.
2. Four titanium-ringed round nozzles in a pure black valance + plate + fans: high contrast, read as "rocket".
3. The white-over-black split: upper body white, a clean black band below (sills, rear valance).
4. The gold-bronze canopy: one continuous dark-gold glass shape, much narrower than the haunches.
5. Wide rear haunches with tyres flush to the body; slim cabin (tumblehome) - silhouette from behind.
6. Crisp facet creases catching neon highlights (bevels + harden normals; no smooth shading blobs).
7. The wing deploying/pitching (animated) and the white 6-blade wheels spinning.
8. Thruster plumes + ground cloud (section 6) - the money shot; budget particles for it.

### 8.4 Do / Don't
- DO keep facets flat and edges sharp; DON'T add a Subdivision Surface or auto-smooth everything.
- DO make the whole canopy one gold-tinted glass sheet from Y +1.61 to -1.745; DON'T add a B-pillar
  in body colour, a metal roof, or chrome window trim.
- DON'T add side mirrors, door handles, a front grille, a Tesla logo on the nose or "TESLA" lettering on
  the tail (the only T badge is on the wheel centre caps).
- DON'T split the rear light into separate lamps; it is one thin continuous bar (and the front is one thin
  white bar + two tiny corner jewels, no big headlights).
- DON'T make the arches square or flared like a Cybertruck - they are clean circles with a thin black lip.
- DON'T colour the plumes orange or add flame/heat haze - cold gas = white/blue vapour.
- DON'T copy the 2017 Roadster (curvy red concept) - completely different car.
- DO check in all four orthographic views against `img/01, 06, 08, 12`; side silhouette must match the
  4.1 centreline within 2 cm.

---------------------------------------------------------------------------------------------------

## 9. Open questions / unverified (decide in-game, do not block on these)
1. Exact perimeter nozzle positions (P1-P6) and the yaw-nozzle location: only "4 corners lift + 2 front
   yaw" is stated [6][9]; positions here come from plume locations in photos 18/27 (est.).
2. Front track (1.56 used) vs X-ray (~1.63): the photos show narrower white front fenders than the rear.
3. Tyre sizes (295/30 R20, 335/30 R21) come from a Teslarati social post, not Tesla.
4. Gas & pressure: "compressed air, 600 L, 250 kg" (Moravy, event) vs "nitrogen at ~10,000 psi" (Top
   Gear, Thrust trim) vs "Thruster 5,500 psi" track-screen readout. HUD uses 5,500 psi.
5. Top speed: ">230 mph" (stage) vs 214 mph spec / 330 mph planned (notateslaapp) - use 230+ in UI.
6. Fan count/size/position in the diffuser (4 x ~0.24 m at Z 0.30) is estimated from dark shaded photos.
7. Is the T-bar glass-black or body-white? Top view shows thin lines only - model it as black glass frame.
8. Small flush feature on the haunch (0.90, -0.77, 0.93): camera, vent or opening fender panel?
9. Hover/barrel-roll rates are eyeballed from a 30 fps recap; no official numbers.
10. IP: the car design, the Tesla "T" badge, the "RDSTR"/ROADSTER marks and Pirelli tyre text are
    third-party IP and the photos are press images for internal reference only. The project owner must
    decide whether the shipped model uses real badges/text or fictional ones (dossier marks both spots).

## 10. Sources
[1] TechCrunch, "Tesla reveals SpaceX-powered Roadster that flies and falls with style", 2026-10-15,
    https://techcrunch.com/2026/10/15/tesla-reveals-spacex-powered-roadster-that-flies-and-falls-with-style/
[2] Car and Driver, "Revealed! New Tesla Roadster Takes Flight with SpaceX Thrusters", 2026-10-16,
    https://www.caranddriver.com/news/a74145531/tesla-roadster-revealed/
[3] Car and Driver, "Explained: Here's How the Tesla Roadster Flies, Flips, and Sucks", 2026-10-17,
    https://www.caranddriver.com/news/a74165059/tesla-roadster-thrusters-fan-system-explained/
[4] Car and Driver, "Tesla Roadster Design: Bold Departure ... or Catfish of the Decade?", 2026-10-16,
    https://www.caranddriver.com/news/a74158531/2029-tesla-roadster-design-changes/
[5] paultan.org, "Tesla Roadster revealed - flies on SpaceX air thrusters, 0-96 km/h in 0.81s", 2026-10-16,
    https://paultan.org/2026/10/16/tesla-roadster-revealed-flies-on-spacex-air-thrusters-0-96-km-h-in-0-81s-production-2028/
    (telemetry numbers, Mach-diamond quote, 5,500 psi readout, Pirelli tyres, Dynamics menu, 40 official + 22 livestream images)
[6] Not a Tesla App, "New Tesla Roadster Specs: Battery, Range, Speed, Trims, and More", 2026-10-16,
    https://www.notateslaapp.com/news/4840/new-tesla-roadster-specs-battery-range-speed-trims-and-more
[7] Electrek, "Tesla unveils Cyberfied new Roadster that can kickflip", 2026-10-15,
    https://electrek.co/2026/10/15/tesla-unveils-cyberfied-new-roadster-kickflip/
[8] Not a Tesla App, "Tesla Roadster Old vs. New: How the Design Changed", 2026-10-17,
    https://www.notateslaapp.com/news/4846/tesla-roadster-old-vs-new-how-the-design-changed-photo-comparisons
[9] Wikipedia, "Tesla Roadster (second generation)" (raw wikitext fetched 2026-10-19; cites Top Gear video
    https://www.youtube.com/watch?v=JdkIOhFmbKI for wheelbase 2,825 mm, width ~2,000 mm, <1,700 kg, 200 L/400 L tanks)
[10] Electrek, "Tesla patent shows new Roadster with a hidden 700 kg-downforce rear wing", 2026-09-25,
    https://electrek.co/2026/09/25/tesla-patent-new-roadster-hidden-active-rear-wing-700-kg-downforce/
[11] MotorTrend first look (search snippet only, page blocked): "two small, triangular panels drop down to
    reveal bright jewellike headlights", https://www.motortrend.com/news/first-look-2028-tesla-roadster-performance-thrust-rocket
[12] Teslarati Facebook post (search snippet): "295/30 tires on 20-inch wheels up front and 335/30 tires on
    21-inch wheels in the rear", https://www.facebook.com/Teslarati/posts/tesla-is-not-putting-the-same-tires-on-all-four-corners-of-the-new-roadster-the-/1523297023153958/
Photos: Tesla press kit + livestream stills via [5] and the Car and Driver galleries
https://www.caranddriver.com/photos/a74152579/tesla-roadster-revealed-exterior-gallery/ and
https://www.caranddriver.com/photos/a74152694/tesla-roadster-revealed-interior-gallery/ (see img/INDEX.md).
Not reachable during research (403/timeouts): tesla.com/roadster, InsideEVs, Teslarati, MotorTrend, Hagerty.
