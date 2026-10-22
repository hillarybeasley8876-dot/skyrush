# police-layers — a cop under a deck does not bust the player above

## Plan
1. Write `game/ai/police/tests/test_layers.gd` (6 checks: hiding same level / hiding on the deck,
   busted same level / busted with the cop under the deck, HUD same level / HUD cop under the deck).
   Verify: `python tools/gd.py test res://ai/police/tests/test_layers.gd` → the 3 wrong-level
   checks FAIL, the 3 same-level checks PASS, the run ends `POLICE LAYER TESTS FAILED` (exit 1).
2. `game/ai/police/police_pursuit.gd`: add `const LEVEL := 4.0`, use it in `_update_hiding_spot`
   and in `update_busted` (the 3D distance stays as it is).
   Verify: `python tools/gd.py check --only=res://ai/police/` → `CHECK N files, 0 failed, 0 engine errors`.
3. `game/ui/hud/hud_pursuit.gd`: the same level test for the busted warning (reads
   `PolicePursuit.LEVEL`).
   Verify: `python tools/gd.py check --only=res://ui/hud/` → `CHECK N files, 0 failed, 0 engine errors`
   and `python tools/gd.py test res://ai/police/tests/test_layers.gd` → `POLICE LAYER TESTS OK`.
4. Whole folders: `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out
   F:/dev/skyrush-out/tmp/police-layers/tests --allow-fail test_perf` → `RUN_TESTS_RATCHET OK`, and
   the same for `res://ui/hud/` with `--allow-fail test_hud_perf`.
5. `python tools/mutation_check.py --test res://ai/police/tests/test_layers.gd --files auto`
   → `MUTATION_CHECK OK` (the test fails on the old code).

## Done
- The test was written FIRST and run on the old code: the 3 wrong-level checks failed, the 3
  controls passed (`POLICE LAYER TESTS FAILED`, exit 1). The controls (same level) are the proof
  that the fix does not switch the rules off for everybody.
- `game/ai/police/police_pursuit.gd`: `const LEVEL := 4.0` (the one place the rule lives).
  - `_update_hiding_spot`: a spot only hides the player when `absf(player.y - spot.y) <= LEVEL`;
    the 3D distance (`HIDE_RADIUS`) is unchanged.
  - `update_busted`: a unit only counts when `absf(unit.y - player.y) <= LEVEL`; the 3D distance
    (`BUST_RANGE`) is unchanged. The "never busted while airborne / in a sky lane" rule is
    untouched, and the fill rates, `BUST_RANGE` and `HIDE_RADIUS` are untouched.
  - No new allocation in the per-tick loops (only `absf` on two floats).
- `game/ui/hud/hud_pursuit.gd`: `const BUSTED_LEVEL: float = PolicePursuit.LEVEL` (one rule, one
  place) and the same level test in the loop that counts the units close to the player.
- `game/ai/police/tests/test_layers.gd` (new): the six checks of the brief. The cop is a
  `TestCop` (a `PoliceCar` without the car physics), the player is the stub car of the core
  (`gravity_scale = 0.0`, frozen), so nothing moves between the ticks.

## In progress / next
Nothing: the job is finished. The lead commits.

## How to test (exact commands)
- `python tools/gd.py test res://ai/police/tests/test_layers.gd`
- `python tools/gd.py check --only=res://ai/police/`
- `python tools/gd.py check --only=res://ui/hud/`
- `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/police-layers/tests --allow-fail test_perf`
- `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/police-layers/tests_hud --allow-fail test_hud_perf`
- `python tools/mutation_check.py --test res://ai/police/tests/test_layers.gd --files auto`

## Evidence (key output lines)
Test BEFORE the fix (old code):
```
PASS a player next to a spot on the same level is hidden
FAIL a spot under the deck does not hide a player on the deck
PASS the meter fills for a cop on the same level (0.67)
FAIL the meter stays empty for a cop under the deck (0.67)
PASS the HUD warns about a cop on the same level (0.33)
FAIL the HUD does not warn about a cop under the deck (0.33)
POLICE LAYER TESTS FAILED
```
Test AFTER the fix:
```
PASS a player next to a spot on the same level is hidden
PASS a spot under the deck does not hide a player on the deck
PASS the meter fills for a cop on the same level (0.67)
PASS the meter stays empty for a cop under the deck (0.00)
PASS the HUD warns about a cop on the same level (0.33)
PASS the HUD does not warn about a cop under the deck (0.00)
POLICE LAYER TESTS OK (0 failures)
```
Checks:
```
CHECK 65 files, 0 failed, 0 engine errors, 0 warnings      (res://ai/police/)
CHECK 31 files, 0 failed, 0 engine errors, 0 warnings      (res://ui/hud/)
```
Folders:
```
19 tests, 19 passed, 0 failed or timed out
RUN_TESTS_RATCHET OK (0 failing, all of them on the allow list)      (res://ai/police/)
3 tests, 3 passed, 0 failed or timed out
RUN_TESTS_RATCHET OK (0 failing, all of them on the allow list)      (res://ui/hud/)
```
Mutation:
```
mutating: game/ai/police/police_pursuit.gd game/ui/hud/hud_pursuit.gd
MUTATION_CHECK OK: the test fails on the old code of eaa43d596b (3 FAIL lines,
first: FAIL a spot under the deck does not hide a player on the deck)
```

## Known issues
- None. Nothing of the brief is left undone: the HUD check (item 5) is done, the HUD helper
  `hud_pursuit.gd` is a `RefCounted` and can be called without the whole HUD scene, so the test
  calls it directly (no `## Not done` entry needed).
- `game/world/tests/probe_path_blockers.gd.uid` appeared as an untracked file: it is the `.uid`
  of a tracked script of another unit, generated by the Godot import of this worktree. It is
  not a change of mine.

## Requests
- None.
