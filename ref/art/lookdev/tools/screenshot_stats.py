#!/usr/bin/env python3
"""SKYRUSH art-critic helper: measures a night screenshot against the DOSSIER section 8 targets.

Usage:  python3 -I screenshot_stats.py shot1.png [shot2.jpg ...] [--zone nanjing]
Needs ffmpeg/ffprobe on PATH. Pure standard library (no PIL). Prints one verdict block per image.

Targets come from measuring 12 real Shanghai night photos + 11 genre references (ref/art/img):
display-referred luminance percentiles and the share of "saturated-bright" pixels (S > 0.45 and V > 0.55),
which is our emissive/neon budget.
"""
import colorsys
import subprocess
import sys

TARGETS = {  # name: (min, max)
    "P5": (0.02, 0.10),     # blacks: deep but not crushed
    "P50": (0.10, 0.24),    # mid-tones of a playable night frame
    "P95": (0.40, 0.78),    # lit surfaces / reflections
    "P99": (0.55, 0.97),    # highlight headroom (neon cores, lamps)
    "SAT": (2.0, 15.0),     # % saturated-bright pixels = emissive budget
    "HUES80": (1, 3),       # hue families needed to cover 80 % of saturated-bright pixels
}
ZONE_OVERRIDES = {"nanjing": {"P50": (0.12, 0.30), "SAT": (8.0, 26.0), "HUES80": (2, 4)},  # Nanjing Rd neon set-piece
                  "underdeck": {"P50": (0.12, 0.30), "SAT": (5.0, 26.0)},  # under the blue-lit elevated soffit
                  "flight": {"P50": (0.06, 0.20), "SAT": (1.0, 10.0)}}     # aerial view over the street grid


def load_rgb(path, width=320):
    probe = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                     "stream=width,height", "-of", "csv=p=0", path]).decode().strip()
    w, h = (int(v) for v in probe.split(",")[:2])
    height = max(2, int(round(h * width / w / 2.0)) * 2)
    raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", path, "-vf", "scale=%d:%d:flags=area" % (width, height),
                                   "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
    return [(raw[i], raw[i + 1], raw[i + 2]) for i in range(0, len(raw), 3)]


def measure(pixels):
    lum = sorted(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in pixels)
    pct = lambda q: lum[int(q * (len(lum) - 1))] / 255.0
    bins = [0] * 12
    for r, g, b in pixels:
        hh, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
        if s > 0.45 and v > 0.55:
            bins[int(hh * 12) % 12] += 1
    sat_total = sum(bins)
    hues80, acc = 0, 0
    for count in sorted(bins, reverse=True):
        if sat_total == 0 or acc >= 0.8 * sat_total:
            break
        acc += count
        hues80 += 1
    return {"P5": pct(0.05), "P50": pct(0.50), "P95": pct(0.95), "P99": pct(0.99),
            "SAT": 100.0 * sat_total / len(pixels), "HUES80": hues80}


def verdict(stats, zone):
    targets = dict(TARGETS)
    targets.update(ZONE_OVERRIDES.get(zone, {}))
    lines, failed = [], 0
    for key, (lo, hi) in targets.items():
        ok = lo <= stats[key] <= hi
        failed += 0 if ok else 1
        lines.append("  %-6s %7.3f  target %g..%g  %s" % (key, stats[key], lo, hi, "ok" if ok else "FAIL"))
    return failed, lines


def main(argv):
    zone = ""
    if "--zone" in argv:
        i = argv.index("--zone")
        zone = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    if not argv:
        print(__doc__)
        return 2
    worst = 0
    for path in argv:
        failed, lines = verdict(measure(load_rgb(path)), zone)
        worst = max(worst, failed)
        print("%s  [%s]  %s" % (path, zone or "default", "PASS" if failed == 0 else "%d FAIL" % failed))
        print("\n".join(lines))
    return 1 if worst else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
