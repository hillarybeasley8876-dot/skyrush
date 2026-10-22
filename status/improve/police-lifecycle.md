# police-lifecycle — after a bust or an escape the pursuit resets

## Plan
1. Write `game/ai/police/tests/test_pursuit_end.gd` (HUD + dispatcher, busted/escaped/second
   chase). Run it BEFORE the fix: it must FAIL at step 4 (the state is still "busted" after 7 s).
   `python tools/gd.py test res://ai/police/tests/test_pursuit_end.gd`
2. Dispatcher: the aftermath timer (a new module `police_aftermath.gd`, the dispatcher calls
   `pursuit.reset()` when it runs out).
   `python tools/gd.py check --only=res://ai/police/` + the test of step 1.
3. HUD: the pursuit panel hides when the state is "none" (`hud.gd`, the panel visibility rule).
   `python tools/gd.py check --only=res://ui/hud/` + the test of step 1.
4. Whole folders: `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out
   F:/dev/skyrush-out/tmp/police-lifecycle/tests_police` and the same for `res://ui/hud/`.
5. `python tools/mutation_check.py --test res://ai/police/tests/test_pursuit_end.gd --files auto`

## Done
- `game/ai/police/police_aftermath.gd` (new, 38 lines): the timer of the aftermath.
  `const AFTERMATH_SECONDS := 6.0` (with a doc comment), `update(delta, pursuit_state)`:
  while the state is `busted`/`escaped` the timer runs, a NEW end state starts it again, and
  every other state (a new chase, a reset, another world) clears it. It returns true when the
  aftermath is over.
- `game/ai/police/police_director.gd` (399 lines, the contract limit is 400):
  - `var aftermath: PoliceAftermath = PoliceAftermath.new()` and, in the tick:
    `if aftermath.update(delta, pursuit.state): pursuit.reset()`. The dispatcher owns the
    decision: the state goes back to `none` (heat 0) 6 s after the bust or the escape, so
    `_update_spawning` runs again and `PoliceSpawner.update()` puts the patrols back on the
    road (1.2 s later, `FIRST_SPAWN`). No unit spawns during the aftermath: `_update_spawning`
    still returns early for `busted`/`escaped`.
  - `_clear_all()` (the world changed) now uses `pursuit.reset()` instead of zeroing the
    fields one by one. The file was at the 400-line limit, so the feature had to make room;
    the reset does the same and drops the box time and the sight of the old world with it.
- `game/ui/hud/hud.gd` (345 lines): `_update_pursuit()` hides the pursuit panel when the
  pursuit is over (heat 0 and the state `none` the bus delivered). While the state is
  `busted`/`escaped` the panel stays (as before) and the 60 % black dim stays (it is driven
  by `events.pursuit_state == &"busted"`, so it goes away with the state). The toasts are not
  touched.
- `game/ai/police/tests/test_pursuit_end.gd` (new, 150 lines): 25 checks — the chase, the
  bust (the dim on, the panel on, the units gone), the state still `busted` after 3 s, the
  state `none` after 7 s (the dim off, the panel off), the patrols back on the road, the same
  for `escaped`, a second chase, and a chase that starts inside the aftermath is not reset
  by it.

## In progress / next
Nothing. The job is finished; the only open point is the pre-existing `test_perf.gd` flake
(see "Known issues").

## How to test (exact commands)
- `python tools/gd.py test res://ai/police/tests/test_pursuit_end.gd`
- `python tools/gd.py check --only=res://ai/police/`
- `python tools/gd.py check --only=res://ui/hud/`
- `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/police-lifecycle/tests_police`
- `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/police-lifecycle/tests_hud`
- `python tools/mutation_check.py --test res://ai/police/tests/test_pursuit_end.gd --files auto`

## Evidence (key output lines)
- The test BEFORE the fix (base code): `FAIL the pursuit goes back to none after 7 s`,
  `FAIL the dim goes away with the pursuit`, `FAIL the pursuit panel goes away with the
  pursuit`, `FAIL the patrols are back on the road (40 s)`, `... PURSUIT END TESTS FAILED
  (6 failures)`.
- The test AFTER the fix: 25 `PASS` lines, `PURSUIT END TESTS OK (0 failures)`.
- `CHECK 64 files, 0 failed, 0 engine errors, 0 warnings` (police) and
  `CHECK 31 files, 0 failed, 0 engine errors, 0 warnings` (hud).
- `MUTATION_CHECK OK: the test fails on the old code of 62f6148e7f (6 FAIL lines, first:
  FAIL the pursuit goes back to none after 7 s)`.
- HUD folder: `3 tests, 3 passed, 0 failed or timed out`.
- Police folder: `18 tests, 17 passed, 1 failed or timed out` — the one failure is
  `test_perf.gd` (see "Known issues"), it is not my test.
- Modes folder (not mine, checked for safety): `test_pursuit_mode.gd` is `ok`; the only
  failure is `test_gate_layers.gd` of the layers-modes job (a car 10 m above a toll gate is
  counted) — it has nothing to do with the police or the HUD.

## Known issues
- `game/ai/police/tests/test_perf.gd` is load sensitive and fails in the folder run on this
  machine: `FAIL the police cost at most 2.0 ms of wall time (+2.043 / +2.379 / +2.195 /
  +2.063 ms)`. It is NOT caused by this job: with the BASE code (62f6148, `police_director.gd`
  and `hud.gd` reverted) the same command gives
  `FAIL the police cost at most 2.0 ms of wall time (+2.261 ms)`
  (log: F:/dev/skyrush-out/tmp/police-lifecycle/tests_police_base/). Alone
  (`gd.py test res://ai/police/tests/test_perf.gd`) it passes with both code versions
  (mine: +1.489 / +1.560 / +1.586 ms, base: +1.548 / +1.630 / +1.826 ms), and the dispatcher
  mean is the same (mine 0.647-0.922 ms, base 0.669-0.795 ms) — the new aftermath costs
  nothing. The test measures raw wall clock times of a shared machine, and
  `reviews/police-r3.md` item 12 already reports it over budget under load
  ("wall +2.252 / +3.233 / +2.881 ms ... budget 2.0"), with the required verification
  "three consecutive green runs with uptime printed in status (load < 12)".
  The occasional `FAIL the slowest dispatcher tick stays inside the peak (3.4-24.0 ms of
  3.0 ms)` is the same story (a GC/scheduler spike; the mean is 0.65-0.92 ms).
  I did not touch the perf test (read-only) and did not change the police tuning.
- `game/ui/hud/tests/test_hud_perf.gd` prints a pre-existing `SCRIPT ERROR: Invalid
  assignment of property or key 'speed_kmh' ... on a base object of type 'Nil'` at
  test_hud_perf.gd:226 (it reads `hud.get("telemetry_override")`, which is null by default).
  It does not fail the test (the coroutine aborts, the checks that matter still run) and it is
  in the base too.

## Requests
- None for the core. The lead should know that acceptance step 5 (the police folder) can fail
  on `test_perf.gd` on a loaded machine, with and without this job.

## Notes
- The import step of the tools rewrote the UIDs of seven `game/assets/city/_tex/*.import`
  files; I restored them to the committed state, so the diff is only my files.
- Two stray untracked `.uid` files (`game/modes/tests/test_gate_layers.gd.uid`,
  `game/world/tests/test_route_layers.gd.uid`) were created by the import step of the other
  units; they are not mine and I left them alone.
