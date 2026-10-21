"""Loudness, peak and seam metering for the SKYRUSH audio pipeline (ITU-R BS.1770-4).

Used by the generators (mastering targets) and by analyze.py (the QA table).
Pure numpy. Mono input is measured as dual mono, which is how the game plays it.
"""
import math

import numpy as np

from common import SR
from dsp import biquad, one_pole_lp
# BS.1770-4 K-weighting coefficients for 48 kHz.
_K_SHELF_B = (1.53512485958697, -2.69169618940638, 1.19839281085285)
_K_SHELF_A = (1.0, -1.69065929318241, 0.73248077421585)
_K_HPF_B = (1.0, -2.0, 1.0)
_K_HPF_A = (1.0, -1.99004745483398, 0.99007225036621)

_GATE_ABSOLUTE = -70.0
_GATE_RELATIVE = -10.0
_BLOCK_SECONDS = 0.4
_BLOCK_STEP_SECONDS = 0.1


def as_stereo(x):
    """(n,) -> (n,2) dual mono; (n,2) stays as it is."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        return np.stack([x, x], axis=1)
    return x


def k_weight(x, sr=SR):
    """K-weighting filter (shelf + high-pass) per channel."""
    st = as_stereo(x)
    out = np.empty_like(st)
    for c in range(st.shape[1]):
        y = biquad(st[:, c], _K_SHELF_B, _K_SHELF_A, sr)
        out[:, c] = biquad(y, _K_HPF_B, _K_HPF_A, sr)
    return out


def _block_ms(weighted, sr=SR):
    """Mean square per block per channel (BS.1770 sums the channels)."""
    block = int(_BLOCK_SECONDS * sr)
    step = int(_BLOCK_STEP_SECONDS * sr)
    if len(weighted) < block:
        # shorter than one block: measure the whole thing as a single block
        if len(weighted) == 0:
            return []
        ms = float(np.sum(np.mean(np.square(weighted), axis=0)))
        return [ms]
    out = []
    for start in range(0, len(weighted) - block + 1, step):
        seg = weighted[start:start + block]
        out.append(float(np.sum(np.mean(np.square(seg), axis=0))))
    return out


def lufs_integrated(x, sr=SR):
    """Gated integrated loudness (LUFS)."""
    ms = _block_ms(k_weight(x, sr), sr)
    if not ms:
        return -70.0
    blocks = [-0.691 + 10.0 * math.log10(max(m, 1e-12)) for m in ms]
    abs_gate = [b for b in blocks if b > _GATE_ABSOLUTE]
    if not abs_gate:
        return -70.0
    rel_gate = float(np.mean(abs_gate)) + _GATE_RELATIVE
    kept = [m for m, b in zip(ms, blocks) if b > rel_gate]
    if not kept:
        return -70.0
    return -0.691 + 10.0 * math.log10(max(float(np.mean(kept)), 1e-12))


def lufs_short_term_series(x, sr=SR, window=3.0, step=0.1):
    """Short-term loudness over time (one value per `step` seconds)."""
    n = int(window * sr)
    step_n = int(step * sr)
    weighted = k_weight(x, sr)
    if len(weighted) < n:
        ms = float(np.sum(np.mean(np.square(weighted), axis=0)))
        return [-0.691 + 10.0 * math.log10(max(ms, 1e-12))]
    out = []
    for start in range(0, len(weighted) - n + 1, step_n):
        seg = weighted[start:start + n]
        ms = float(np.sum(np.mean(np.square(seg), axis=0)))
        out.append(-0.691 + 10.0 * math.log10(max(ms, 1e-12)))
    return out


def lufs_short_term(x, sr=SR, seconds=3.0):
    """Mean short-term loudness over the whole signal (3 s windows, LUFS)."""
    series = lufs_short_term_series(x, sr, seconds)
    if not series:
        return -70.0
    return float(np.mean(series))


def _true_peak_filter(taps=48, cutoff=0.5):
    """A windowed sinc low-pass with the cutoff at the Nyquist of the original rate."""
    n = np.arange(taps) - (taps - 1) / 2.0
    h = np.sinc(2.0 * cutoff * n) * 2.0 * cutoff
    h *= np.blackman(taps)
    return h / np.sum(h)


def true_peak_dbfs(x, sr=SR, oversample=4):
    """Inter-sample true peak (dBTP).

    The signal is oversampled with a windowed sinc filter (the same idea as the EBU R128
    true-peak measurement), so the reading matches what a decoder measures. A cubic
    interpolation under-reads the peaks by about 0.8 dB.
    """
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 2:
        x = x.max(axis=1)
    if len(x) < 4:
        return -200.0
    up = np.zeros(len(x) * oversample)
    up[::oversample] = x
    y = np.convolve(up, _true_peak_filter(), mode="same")
    peak = float(np.max(np.abs(y)))
    peak = max(peak, float(np.max(np.abs(x))))
    return 20.0 * math.log10(max(peak, 1e-9))


def dc_offset(x):
    """Mean value of the signal (the DC offset)."""
    x = np.asarray(x, dtype=np.float64)
    if x.size == 0:
        return 0.0
    return float(np.mean(x))


def seam_ratio(x):
    """Ratio of the second difference at the loop point to the file's p99.9.

    1.0 means the seam is indistinguishable from the file's own worst transient.
    """
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 2:
        x = x.max(axis=1)
    if len(x) < 8:
        return 0.0
    d2 = np.abs(np.diff(x, n=2))
    seam = float(d2[0])
    p999 = float(np.percentile(d2, 99.9))
    if p999 < 1e-9:
        return 0.0
    return seam / p999


def seam_envelope_jump_db(x, sr=SR, window=0.05):
    """Level jump across the loop point (dB) between the last and the first window."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 2:
        x = x.max(axis=1)
    n = int(window * sr)
    if len(x) < 2 * n:
        return 0.0
    tail = float(np.sqrt(np.mean(np.square(x[-n:]))))
    head = float(np.sqrt(np.mean(np.square(x[:n]))))
    if tail < 1e-9 or head < 1e-9:
        return 0.0
    return 20.0 * math.log10(head / tail)


def dc_block(x, sr=SR, fc=25.0):
    """Remove the DC offset with a 1-pole high-pass (FFT, so it is fast enough for long beds)."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 2:
        return np.stack([dc_block(x[:, c], sr, fc) for c in range(x.shape[1])], axis=1)
    return x - one_pole_lp(x, fc, sr)
