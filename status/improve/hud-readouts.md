# hud-readouts — the HUD shows the state of the mode (score, laps and place, takedowns and time)

## Plan
1. Read SPEC/CONTRACTS, `game/core/events.gd` (the `mode_status` contract), the HUD unit and the
   existing HUD tests. [done]
2. Write `game/ui/hud/tests/test_mode_status.gd` (the 5 groups of the brief) and run it on the
   OLD code: every check must FAIL with a FAIL line (no script error). [done: 10 FAIL lines]
3. `game/ui/hud/mode_status_readout.gd` (new): the score / goal / countdown rows
   (`ScoreLabel`, `GoalLabel`, `TimeLabel`), the text is only written when the data changed.
   [done]
4. `game/ui/hud/hud_events.gd`: connect `Events.mode_status`, keep `status_kind` / `status`, set
   `laps` / `lap` and the place of the race panel. [done]
5. `game/ui/hud/race_panel.gd`: `set_place(position, racers)` / `clear_place()` — the mode status
   wins over the standings. [done]
6. `game/ui/hud/hud.gd`: build the readout, hand it to the bus, keep `_route_laps()` only as the
   fallback of a race without a status. [done]
7. `game/ui/hud/demo/`: the demo fires the mode status too (the race that runs, the goal and the
   countdown of the pursuit, the score of the free roam). [done]
8. Run the new test, the whole HUD folder, `gd.py check --only=res://ui/hud/` and the mutation
   check. [done]

## Done
- `mode_status_readout.gd` (new, 150 lines): the readout of the mode status. Three rows in the
  HUD's own face and colours: `SCORE  1250` in the middle of the top row (nothing else is drawn
  there, in any mode), `TAKEDOWNS  1 / 3` and `TIME  01:23` under the pursuit panel (the left
  column). The value of a row is written only when the data changed (the perf test), the rows
  are hidden when they do not belong to the running mode (`free` / `pursuit` / `none`), a
  countdown of `-1` (or less) is never drawn and a goal of `0` is not drawn either.
  `format_countdown()` is `mm:ss` of the seconds left, floored and never negative.
- `hud_events.gd`: `Events.mode_status` is connected; the last status is kept in `status_kind` /
  `status`. A race status sets `laps` and `lap` (the laps of the race that runs, not of the first
  route of the world) and the place of the race panel; any other kind gives the place back to
  the standings.
- `race_panel.gd`: `set_place(position, racers)` writes the place ("4TH" / "第4名" / "/6") and
  locks it, `clear_place()` unlocks it. The rows of the standings keep on updating.
- `hud.gd`: the readout is built and handed to the bus; `_route_laps()` is only the fallback of a
  race without a status; the race panel is also shown when the status says "race".
- `demo/demo_steps.gd` + `demo/hud_demo.gd`: the demo fires the mode status (the race that runs
  with three laps, the goal and the countdown of the pursuit, the score of the free roam at the
  end of the race), so the new readouts are in the captures.
- `tests/test_mode_status.gd` (new): 21 checks — the score of the free roam (and that it follows
  the bus), the hidden readouts without a mode, the goal and the countdown of a pursuit (and the
  two "no goal" / "no limit" cases and the negative time), the laps / lap / place of a race and
  the switch between two kinds. The labels are found by their node name, so a missing node is a
  FAIL line and not a script error.

## In progress / next
- nothing. The job is done; the lead commits.

## How to test (exact commands)
- `python tools/gd.py test res://ui/hud/tests/test_mode_status.gd`
- `python tools/gd.py check --only=res://ui/hud/`
- `python tools/mutation_check.py --test res://ui/hud/tests/test_mode_status.gd --files auto`
- `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/hud-readouts/tests --allow-fail test_hud_perf`
- `python tools/gd.py shot --scene=res://ui/hud/demo/hud_demo.tscn --out=hud_mode --times=5,14,16,21 --warm=30`

## Evidence (key output lines)
- the new test on the OLD code: `FAIL the HUD has a ScoreLabel` ... `HUD STATUS TESTS FAILED (10 failures)`
- the new test now: `PASS the score shows 1250 (1250)`, `PASS the goal shows the takedowns and the
  target (1 / 3)`, `PASS the countdown shows 01:23 (01:23)`, `PASS the lap counter says 3 laps (3)`,
  `PASS the race panel shows the 4th place (4TH)`, `HUD STATUS TESTS OK (0 failures)`
- `CHECK 33 files, 0 failed, 0 engine errors, 0 warnings`
- `4 tests, 4 passed, 0 failed or timed out` / `RUN_TESTS_RATCHET OK (0 failing, all of them on the allow list)`
- `MUTATION_CHECK OK: the test fails on the old code of b649a54f45 (10 FAIL lines, first: FAIL the HUD has a ScoreLabel)`
- the captures (in `F:/dev/skyrush-wt/skyrush-out/captures/`): `hud_mode_t5_0.jpg` (the race:
  "1ST /2" and the lap counter "2/3"), `hud_mode_t14_0.jpg` (the pursuit: "TAKEDOWNS 1/3" and
  "TIME 01:30" under the pursuit panel), `hud_mode_t21_0.jpg` (the free roam: "SCORE 24850" in
  the middle of the top row).

## Known issues
- the place of the race panel comes from the mode status while a race status runs; the standings
  are the fallback (they are what the panel used before). Both say the same thing in the demo.
- the modes unit (`job/modes-status`) is not in this branch yet: the readouts are driven by the
  bus alone, the HUD never reads the mode session.

## Requests
- none.
