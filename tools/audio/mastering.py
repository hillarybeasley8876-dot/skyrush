"""Mastering helpers for the SKYRUSH audio assets: circular loops and loudness masters.

  circularize()  turns a rendered buffer into a seamless loop (equal-power wrap crossfade)
  master()       DC block -> gain to a LUFS target -> true-peak ceiling
"""
import math

import numpy as np

from common import SR
from metering import dc_block, lufs_integrated, true_peak_dbfs


def circularize(x, sr=SR, xfade_s=0.15):
    """Make a buffer of N + tail samples loop seamlessly over N samples.

    The first `xfade` samples are replaced by an equal-power crossfade between the head and the
    material that follows the loop point, so the wrap is continuous in value and in slope.
    """
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    f = int(xfade_s * sr)
    if f <= 1 or n < 2 * f:
        return x
    tail = x[n - f:]
    head = x[:f]
    w = (np.arange(f) + 1.0) / float(f + 1.0) * (math.pi * 0.5)
    blended = tail * np.cos(w) + head * np.sin(w)
    out = x.copy()
    out[:f] = blended
    return out


def loop_length(x, sr=SR, xfade_s=0.15):
    """Length of the loop that `circularize` produces from a buffer (the buffer minus the tail)."""
    return len(x) - int(xfade_s * sr)


def soft_limit(x, threshold=0.9, ceiling=None):
    """Smooth peak limiter (a tanh knee, so the peaks do not fold back).

    Below `threshold` the signal is untouched; above it the excess is compressed towards
    `ceiling` with a hyperbolic tangent, so the limiter adds far less distortion than a
    hard-knee compressor.
    """
    if ceiling is None:
        ceiling = threshold
    a = np.abs(x)
    over = a > threshold
    y = x.copy()
    if np.any(over):
        span = max(ceiling - threshold, 1e-6)
        excess = a[over] - threshold
        y[over] = np.sign(x[over]) * (threshold + np.tanh(excess / span) * span)
    return y


def master(x, sr=SR, target_lufs=-14.0, tp_ceiling_db=-1.5, plr_min_db=None, dc_hz=25.0):
    """Master a buffer: DC block, then gain to `target_lufs`, then hold the true peak.

    Returns (mastered, info) where info carries the measured loudness.
    """
    y = dc_block(np.asarray(x, dtype=np.float64), sr, dc_hz)
    current = lufs_integrated(y, sr)
    if current > -70.0:
        y = y * (10.0 ** ((target_lufs - current) / 20.0))
    # hold the true peak under the ceiling with a smooth limiter, then re-check
    ceiling = 10.0 ** (tp_ceiling_db / 20.0)
    for _ in range(8):
        tp = true_peak_dbfs(y, sr)
        if tp <= tp_ceiling_db:
            break
        peak = float(np.max(np.abs(y))) if y.size else 0.0
        threshold = max(1e-6, ceiling * (0.82 if peak > ceiling else 0.95))
        y = soft_limit(y, threshold, ceiling)
    # the limiter works on the samples, so the inter-sample peak can still be over the
    # ceiling: a small gain reduction brings the true peak under it (the loudness and the
    # crest factor drop by the same amount)
    tp = true_peak_dbfs(y, sr)
    if tp > tp_ceiling_db:
        y = y * (10.0 ** ((tp_ceiling_db - tp) / 20.0))
    info = {
        "lufs": lufs_integrated(y, sr),
        "tp": true_peak_dbfs(y, sr),
        "peak_dbfs": 20.0 * math.log10(max(1e-9, float(np.max(np.abs(y))))),
    }
    if plr_min_db is not None:
        info["plr"] = info["tp"] - info["lufs"]
    return y, info
