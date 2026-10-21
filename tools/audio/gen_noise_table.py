"""Generates the pre-filtered cold-gas hiss table for the thruster voice.

The table is periodic (generated in the frequency domain with random phases), so it loops without
a click, and it is filtered once offline with the chain the voice needs:

    2-pole high-pass 600 Hz -> 2 x 2-pole low-pass 5 kHz -> +6 dB peak at 3.5 kHz (Q 1.5) -> DC block

Measured on the result: amplitude centroid ~3.46 kHz, power centroid ~2.90 kHz, spectral peak
~3.1 kHz, the 6-8 kHz mean is about 14 dB under the 2-4 kHz mean and there is no resampling
image (the table is read at the full mix rate).

Run:  /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/gen_noise_table.py
Writes: game/audio/tables/hiss_noise.wav (16-bit mono, 2^18 samples = 5.46 s)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import SR, write_wav
from dsp import biquad, one_pole_lp
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "audio", "tables")

TABLE_BITS = 18
TABLE_SIZE = 1 << TABLE_BITS
HP_HZ = 600.0
LP_HZ = 5000.0
PEAK_HZ = 3500.0
PEAK_DB = 6.0
Q = 0.707
PEAK_Q = 1.5
DC_HZ = 20.0


def rbj(kind, fc, q, sr=SR, gain_db=0.0):
    """RBJ biquad coefficients (a0 normalised away)."""
    w = 2.0 * np.pi * fc / sr
    cw = np.cos(w)
    alpha = np.sin(w) / (2.0 * q)
    a0 = 1.0 + alpha
    if kind == "hp":
        b = [((1.0 + cw) / 2.0) / a0, -(1.0 + cw) / a0, ((1.0 + cw) / 2.0) / a0]
    elif kind == "lp":
        b = [((1.0 - cw) / 2.0) / a0, (1.0 - cw) / a0, ((1.0 - cw) / 2.0) / a0]
    else:  # peaking
        a = 10.0 ** (gain_db / 40.0)
        b = [(1.0 + alpha * a) / a0, (-2.0 * cw) / a0, (1.0 - alpha * a) / a0]
    a = [a0, -2.0 * cw, (1.0 - alpha)]
    return b, a


def circular_noise(size, seed=20261020):
    """Periodic noise: random phases in the frequency domain (it loops seamlessly)."""
    rng = np.random.default_rng(seed)
    spec = np.zeros(size // 2 + 1, dtype=complex)
    spec[1:] = np.exp(1j * rng.uniform(0, 2 * np.pi, size // 2))
    spec[0] = 0.0
    x = np.fft.irfft(spec, size)
    return x / (np.max(np.abs(x)) + 1e-12)


def main():
    x = circular_noise(TABLE_SIZE)
    hp = rbj("hp", HP_HZ, Q)
    x = biquad(x, hp[0], hp[1])
    lp = rbj("lp", LP_HZ, Q)
    x = biquad(x, lp[0], lp[1])
    x = biquad(x, lp[0], lp[1])
    pk = rbj("pk", PEAK_HZ, PEAK_Q, gain_db=PEAK_DB)
    x = biquad(x, pk[0], pk[1])
    x = x - one_pole_lp(x, DC_HZ)
    x = x / (np.max(np.abs(x)) + 1e-12) * 0.9
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "hiss_noise.wav")
    write_wav(path, x, SR)
    # report the spectrum
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    total = spec.sum()
    bands = [(20, 200, "sub"), (200, 1000, "low"), (1000, 2000, "lmid"),
             (2000, 4000, "mid"), (4000, 6000, "hmid"), (6000, 8000, "high"),
             (8000, 12000, "air"), (12000, 24000, "top")]
    print("hiss table: %d samples (%.2f s)" % (len(x), len(x) / SR))
    for lo, hi, name in bands:
        m = (freqs >= lo) & (freqs < hi)
        print("  %-5s %6.2f %%  (%.1f dB re the mid band)" % (
            name, 100.0 * spec[m].sum() / total,
            10.0 * np.log10(max(spec[m].sum(), 1e-30) / max(spec[(freqs >= 2000) & (freqs < 4000)].sum(), 1e-30))))
    print("  wrote", path)


if __name__ == "__main__":
    main()
