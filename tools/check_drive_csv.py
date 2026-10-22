#!/usr/bin/env python3
"""check_drive_csv — is a scripted drive physically sane? (reads the telemetry csv of `gd.py drive --log=...`)

    python tools/check_drive_csv.py <run.csv> [--max-speed 340] [--max-jump-kmh 80] [--max-step-m 10] [--min-health 20]

Columns: t,x,y,z,speed_kmh,drift_state,n2,airborne,flying,boost_kind,health. Fails when
  * any speed is above --max-speed km/h (the game's hard cap is 330),
  * the speed rises by more than --max-jump-kmh between two consecutive rows (a collision slows a car down;
    a nitro boost rises gradually; +700 km/h in 0.13 s is a solver explosion),
  * the position moves more than --max-step-m between two consecutive rows (a teleport; rows are ~0.05 s apart),
  * the health ever falls below --min-health (one 65 km/h bump must not kill the car).
Prints the worst values either way and ends with DRIVE_SANE OK or DRIVE_SANE FAIL.
"""
import csv
import math
import sys


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda n, d: float(argv[argv.index(n) + 1]) if n in argv else d  # noqa: E731
    for n in ("--max-speed", "--max-jump-kmh", "--max-step-m", "--min-health"):
        if n in argv:
            args.remove(argv[argv.index(n) + 1])
    rows = list(csv.DictReader(open(args[0], encoding="utf-8")))
    if len(rows) < 20:
        print("DRIVE_SANE FAIL: only %d telemetry rows" % len(rows))
        return 1
    max_speed, max_jump, max_step, min_health = opt("--max-speed", 340.0), opt("--max-jump-kmh", 80.0), opt("--max-step-m", 10.0), opt("--min-health", 20.0)
    worst_speed = worst_jump = worst_step = 0.0
    health_min = 1e9
    drops = 0
    prev = None
    bad = []
    for r in rows:
        t, x, y, z = float(r["t"]), float(r["x"]), float(r["y"]), float(r["z"])
        v, h = float(r["speed_kmh"]), float(r["health"])
        worst_speed = max(worst_speed, v)
        health_min = min(health_min, h)
        if prev is not None:
            dv = v - prev[4]
            step = math.dist((x, y, z), prev[1:4])
            worst_jump = max(worst_jump, dv)
            worst_step = max(worst_step, step)
            if dv < -15.0:
                drops += 1
            if dv > max_jump:
                bad.append("t=%.2f: speed rises %.0f km/h in one row (%.0f -> %.0f)" % (t, dv, prev[4], v))
            if step > max_step:
                bad.append("t=%.2f: the car moves %.1f m in one row (a teleport)" % (t, step))
        prev = (t, x, y, z, v)
    if worst_speed > max_speed:
        bad.append("top speed %.0f km/h is above %.0f" % (worst_speed, max_speed))
    if health_min < min_health:
        bad.append("health falls to %.0f (limit %.0f)" % (health_min, min_health))
    print("rows %d, top speed %.0f km/h, biggest speed rise %.0f km/h, biggest step %.1f m, lowest health %.0f, slowdowns %d" % (
        len(rows), worst_speed, worst_jump, worst_step, health_min, drops))
    for line in bad[:8]:
        print("FAIL", line)
    print("DRIVE_SANE %s" % ("FAIL" if bad else "OK"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
