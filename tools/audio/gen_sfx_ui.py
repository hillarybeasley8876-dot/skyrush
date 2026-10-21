"""SKYRUSH interface sound generator (menu clicks, transitions, the race countdown).

Run:  /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/gen_sfx_ui.py
Writes game/audio/sfx/*.ogg. Deterministic (fixed seeds) — rebuilds byte-identically.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import SR, save
from dsp import adsr, bandpass, exp_decay, fade, noise, one_pole_lp, peak_dbfs, sine, soft_clip
from mastering import master

OUT = "sfx"


# --- the interface sounds ------------------------------------------------------------------------------
def ui_click():
    sr = SR
    n = int(0.11 * sr)
    click = bandpass(noise(n, seed=81), 3200, q=1.2, sr=sr) * exp_decay(n, sr, tau=0.006)
    blip = sine(n, 2400, sr) * exp_decay(n, sr, tau=0.012) * 0.35
    x = click * 0.7 + blip
    x = fade(x, 0.0005, 0.02, sr)
    return master(x, sr, target_lufs=-30.0, tp_ceiling_db=-8.0)[0]


def ui_hover():
    sr = SR
    n = int(0.17 * sr)
    x = sine(n, 1760, sr) * exp_decay(n, sr, tau=0.045) * 0.5
    x = fade(x, 0.002, 0.05, sr)
    return master(x, sr, target_lufs=-32.0, tp_ceiling_db=-10.0)[0]


def ui_confirm():
    sr = SR
    n = int(0.6 * sr)
    x = np.zeros(n)
    for i, f in enumerate((659.3, 987.8)):
        start = int(i * 0.09 * sr)
        ln = n - start
        x[start:] += sine(ln, f, sr) * exp_decay(ln, sr, tau=0.16) * 0.6
    x = fade(x, 0.002, 0.1, sr)
    return master(x, sr, target_lufs=-28.0, tp_ceiling_db=-8.0)[0]


def ui_back():
    sr = SR
    n = int(0.55 * sr)
    x = np.zeros(n)
    for i, f in enumerate((784.0, 523.3)):
        start = int(i * 0.08 * sr)
        ln = n - start
        x[start:] += sine(ln, f, sr) * exp_decay(ln, sr, tau=0.14) * 0.55
    x = fade(x, 0.002, 0.1, sr)
    return master(x, sr, target_lufs=-28.0, tp_ceiling_db=-8.0)[0]


def ui_whoosh():
    sr = SR
    n = int(0.6 * sr)
    t = np.arange(n) / sr
    x = bandpass(noise(n, seed=82), 1200, q=0.6, sr=sr)
    x *= np.sin(np.pi * np.clip(t / 0.6, 0, 1)) ** 1.5
    x = bandpass(x, 2500, q=0.5, sr=sr)
    x = fade(x, 0.02, 0.08, sr)
    return master(x, sr, target_lufs=-32.0, tp_ceiling_db=-12.0)[0]


def countdown_beep():
    """Race countdown 'tick' (三 / 二 / 一)."""
    sr = SR
    n = int(0.32 * sr)
    x = soft_clip(sine(n, 880, sr), 1.8) * adsr(n, sr, a=0.004, d=0.05, s=0.75, r=0.1)
    x = fade(x, 0.002, 0.06, sr)
    return master(x, sr, target_lufs=-26.0, tp_ceiling_db=-6.0)[0]


def countdown_go():
    """'出发' — bright double tone."""
    sr = SR
    n = int(0.65 * sr)
    x = np.zeros(n)
    for i, f in enumerate((1046.5, 1568.0)):
        start = int(i * 0.02 * sr)
        ln = n - start
        x[start:] += soft_clip(sine(ln, f, sr), 1.8) * adsr(ln, sr, a=0.004, d=0.12, s=0.6, r=0.18)
    x = fade(x, 0.002, 0.1, sr)
    return master(x, sr, target_lufs=-24.0, tp_ceiling_db=-5.0)[0]


def main():
    jobs = [
        ("ui_click", ui_click(), False),
        ("ui_hover", ui_hover(), False),
        ("ui_confirm", ui_confirm(), False),
        ("ui_back", ui_back(), False),
        ("ui_whoosh", ui_whoosh(), False),
        ("countdown_beep", countdown_beep(), False),
        ("countdown_go", countdown_go(), False),
    ]
    for name, data, loop in jobs:
        path = save(name, data, loop=loop, folder=OUT)
        print("%-22s %5.2fs peak %6.2f dBFS  %s" % (
            name, len(data) / SR, peak_dbfs(data), os.path.basename(path)))


if __name__ == "__main__":
    main()
