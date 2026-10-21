"""Synth voices for the SKYRUSH procedural music (additive, band-limited, no samples).

All voices are pure functions returning float64 mono buffers; the sequencer in gen_music.py
places them into the track buffer.
"""
import math

import numpy as np

from common import SR
from dsp import exp_decay, noise, one_pole_lp
MAX_HARM = 0.45 * SR


def midi_hz(note):
    """MIDI note number -> Hz (A4 = 69 = 440 Hz)."""
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def _additive(freq, n, harmonics, sr=SR, phase=0.0, detune=0.0):
    """Additive oscillator: `harmonics` is a list of (ratio, amplitude) pairs."""
    t = np.arange(n) / float(sr)
    out = np.zeros(n)
    for ratio, amp in harmonics:
        f = freq * ratio * (1.0 + detune)
        if f > MAX_HARM:
            break
        out += amp * np.sin(2.0 * math.pi * f * t + phase)
    return out


def saw(freq, n, sr=SR, harmonics=14, phase=0.0):
    """Band-limited saw (1/k roll-off)."""
    hs = [(k, 1.0 / k) for k in range(1, harmonics + 1)]
    return _additive(freq, n, hs, sr, phase)


def square(freq, n, sr=SR, harmonics=9, phase=0.0):
    """Band-limited square (odd harmonics only)."""
    hs = [(k, 1.0 / k) for k in range(1, harmonics + 1, 2)]
    return _additive(freq, n, hs, sr, phase)


def triangle(freq, n, sr=SR, harmonics=8, phase=0.0):
    """Band-limited triangle (odd harmonics, 1/k^2)."""
    hs = [(k, 1.0 / (k * k)) for k in range(1, harmonics + 1, 2)]
    return _additive(freq, n, hs, sr, phase)


def pluck(freq, n, sr=SR, phase=0.0, cutoff=0.0):
    """Synthwave pluck: saw with a fast decay and a closing filter.

    `cutoff` (Hz) scales the opening of the filter, so an LFO can sweep the brightness.
    """
    x = saw(freq, n, sr, 12, phase)
    x *= exp_decay(n, sr, tau=0.11, attack=0.003)
    # closing filter: sweep a one-pole low-pass from bright to dark
    top = max(1200.0, cutoff)
    a = np.exp(-2.0 * math.pi * np.linspace(top, min(top, 1400.0), n) / sr)
    y = np.empty(n)
    acc = 0.0
    for i in range(n):
        acc = (1.0 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


def pad(freq, n, sr=SR, phase=0.0):
    """Wide pad: three detuned saws, slow tremolo."""
    x = (saw(freq, n, sr, 10, phase)
         + saw(freq, n, sr, 10, phase + 1.1) * 0.85
         + saw(freq * 0.5, n, sr, 8, phase) * 0.25)
    t = np.arange(n) / float(sr)
    x *= 0.85 + 0.15 * np.sin(2.0 * math.pi * 0.25 * t + phase)
    return x


def bass(freq, n, sr=SR, phase=0.0):
    """Sub bass: sine body + a touch of saw grit."""
    t = np.arange(n) / float(sr)
    x = np.sin(2.0 * math.pi * freq * t + phase) * 0.9
    x += saw(freq, n, sr, 6, phase) * 0.25
    return x


def lead(freq, n, sr=SR, phase=0.0):
    """Bright lead: square + a fifth, slight vibrato."""
    t = np.arange(n) / float(sr)
    vib = 1.0 + 0.004 * np.sin(2.0 * math.pi * 5.5 * t)
    x = square(freq * vib[0], n, sr, 9, phase)
    x += square(freq * 1.5 * vib[0], n, sr, 6, phase + 0.4) * 0.35
    return x


def kick(sr=SR, tone=1.0):
    """Synth kick: pitch drop + click."""
    n = int(0.42 * sr)
    t = np.arange(n) / sr
    f = 48.0 + 120.0 * np.exp(-t / 0.028)
    x = np.sin(2.0 * math.pi * np.cumsum(f) / sr) * exp_decay(n, sr, tau=0.10, attack=0.001)
    click = noise(n, seed=401) * exp_decay(n, sr, tau=0.002) * 0.25
    return (x * 0.9 + click) * tone


def snare(sr=SR, tone=1.0):
    """Synth snare: body tone + noise burst."""
    n = int(0.28 * sr)
    t = np.arange(n) / sr
    body = (np.sin(2.0 * math.pi * 195.0 * t) * 0.5 + np.sin(2.0 * math.pi * 290.0 * t) * 0.3)
    body *= exp_decay(n, sr, tau=0.055, attack=0.001)
    rattle = noise(n, seed=402) * exp_decay(n, sr, tau=0.075, attack=0.001)
    rattle = one_pole_lp(rattle, 9000, sr)
    return (body * 0.5 + rattle * 0.8) * tone


def hat(sr=SR, tone=1.0, open_hat=False):
    """Closed/open hi-hat from high-passed noise."""
    n = int((0.26 if open_hat else 0.07) * sr)
    x = noise(n, seed=403 if open_hat else 404) * exp_decay(n, sr, tau=0.09 if open_hat else 0.016)
    x = one_pole_lp(x, 12000, sr)
    y = np.empty(n)
    prev_in = 0.0
    prev_out = 0.0
    for i in range(n):
        cur = x[i]
        y[i] = cur - prev_in + 0.92 * prev_out
        prev_in = cur
        prev_out = y[i]
    return y * 0.6 * tone


def crash(sr=SR, tone=1.0):
    """Crash: bright noise with a long decay."""
    n = int(0.9 * sr)
    x = noise(n, seed=405) * exp_decay(n, sr, tau=0.28, attack=0.002)
    x = one_pole_lp(x, 14000, sr)
    return x * 0.5 * tone
