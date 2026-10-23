# hud-health-hop — the health bar and the HOP hint

## Plan
1. Write `game/ui/hud/tests/test_health_hop.gd` FIRST (health values/colour/change counter, HOP
   cases). Verify it FAILS: `python tools/gd.py test res://ui/hud/tests/test_health_hop.gd`
   -> expect `FAIL` lines, exit 1.
2. New widget `game/ui/hud/health_bar.gd`: a thin bar, the caption `HP`, the number, the colour
   green > 60 %, amber 25..60 %, red < 25 %; the number is written only when the integer percent
   changes (a write counter in the widget); hidden while the health is 0 and in the menu.
3. New widget `game/ui/hud/hop_hint.gd`: `跳！HOP ▲` + the distance, amber, slow pulse (1.5 Hz);
   the gates: n2 >= 50, on the ground, a site within 150 m, less than 35 deg off the forward
   axis, less than 4 m of the car's level; the scan runs 5 times a second over a cached list.
   The sites of the world are read by `game/ui/hud/hop_sites.gd` (the roadblock sites + the `toll`
   POIs) once the world is ready, and then cached.
4. Wire both into `game/ui/hud/hud.gd` (build + per-frame update) and show the prompt in the demo.
5. Run the whole HUD folder + the acceptance commands.

## Done
- `game/ui/hud/health_bar.gd` (new, 79 lines): the bar, the caption `HP`, the number, the three
  colours, the write counter `text_writes`, hidden at 0 HP and in the menu.
- `game/ui/hud/hop_hint.gd` (new, 147 lines): the prompt, the gates, the 5 Hz scan, the pulse.
- `game/ui/hud/hop_sites.gd` (new, 37 lines): reads the roadblock sites and the `toll` POIs of
  the world (the POI `position` may be a Vector3 or a Vector2), and the readiness of the world.
- `game/ui/hud/hud.gd`: builds the two widgets (the bar in the bottom centre between the N2
  cluster and the speed cluster, the prompt centred in the upper third) and updates them.
- `game/ui/hud/demo/hud_demo.gd`: the demo hands its toll plaza to the prompt.
- `game/ui/hud/tests/test_health_hop.gd` (new, 253 lines): 24 checks.

## In progress / next
Nothing: the job is finished, the lead commits.

## How to test (exact commands)
- `python tools/gd.py check --only=res://ui/hud/`
- `python tools/gd.py test res://ui/hud/tests/test_health_hop.gd`
- `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/hud-health-hop/tests --allow-fail test_hud_perf`
- `python tools/mutation_check.py --test res://ui/hud/tests/test_health_hop.gd --files auto`
- screenshot: `python tools/gd.py shot --scene=res://ui/hud/demo/hud_demo.tscn --out=hud_demo2 --times=6.0,11.0 --warm=60 --size=1920x1080`
  (the prompt: `F:/dev/skyrush-out/captures/hop_hint_t2_0.jpg`, the bar: `.../hud_demo2_t6_0.jpg`)

## Evidence (key output lines)
- before the fix: `FAIL the HUD has a health bar` / `FAIL the HUD has a HOP hint` /
  `HUD HEALTH HOP TESTS FAILED (5 failures)` (the test could fail).
- `python tools/gd.py test res://ui/hud/tests/test_health_hop.gd` ->
  `PASS the bar is green above 60 %`, `PASS the bar is amber between 25 and 60 %`,
  `PASS the bar is red below 25 %`, `PASS a wrecked car hides the health bar`,
  `PASS the number is written once for 100 identical updates (1)`,
  `PASS the hint shows for a roadblock 120 m ahead`, `PASS the hint shows the distance (120 m)`,
  `PASS a roadblock behind the car hides the hint`,
  `PASS a roadblock on another level hides the hint`,
  `PASS a roadblock 200 m ahead hides the hint`, `PASS without 50 N2 the hint hides`,
  `PASS an airborne car hides the hint`, `PASS a flying car hides the hint`,
  `PASS a toll plaza ahead shows the hint`, `PASS the nearest site decides the distance (60 m)`,
  `HUD HEALTH HOP TESTS OK (0 failures)`.
- `python tools/gd.py check --only=res://ui/hud/` -> `CHECK 39 files, 0 failed, 0 engine errors, 0 warnings`.
- `python tools/run_tests.py --filter res://ui/hud/ ...` -> `6 tests, 6 passed, 0 failed or timed out`
  and `RUN_TESTS_RATCHET OK (0 failing, all of them on the allow list)`.
- `python tools/mutation_check.py --test res://ui/hud/tests/test_health_hop.gd --files auto` ->
  `MUTATION_CHECK OK: the test fails on the old code of 0b5c8247bc (5 FAIL lines, first: FAIL the HUD has a health bar)`.
- `python tools/gd.py test res://ai/police/tests/test_pursuit_end.gd` -> `PURSUIT END TESTS OK (0 failures)`
  (the other unit that builds the HUD is not broken).

## Known issues
- The dossier puts the hop prompt at (960, 620) (above the car); the brief asks for the upper
  third, so it sits at 9 % of the height (under the score readout, over the toasts). On a window
  shorter than ~690 px the toasts (at 24 % of the height) can reach the prompt.
- The health bar sits in the bottom centre: the dossier reserves the bottom centre for the
  pursuit bar (600 x 18 px at y 1010) — that bar does not exist yet; when it is added the HP bar
  has to move (it is 28 px tall at y = height - 76).
- The toll POIs of the world carry the y of the JSON (0), so a plaza that is not on a ground
  level road would not show the prompt (the only plaza of `data/city/city.json` is 6.6 m from a
  road at y 0).

## Requests
- None.
