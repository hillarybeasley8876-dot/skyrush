"""The signal processing helpers of the audio tools (the generators, the filters and the
shaping). The file io lives in common.py.
"""
import math

import numpy as np

from common import SR

# --- thruster hiss reference (shared with the in-game ThrusterSynth) -----------------------------------
HISS_HP_HZ = 600.0
HISS_LP_HZ = 4000.0

# --- generators -----------------------------------------------------------------------------------------
def noise(n, seed=0, color="white"):
    """Deterministic noise. color: white | pink | brown."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal(n)
    if color == "white":
        return w
    if color == "brown":
        return np.cumsum(w) / math.sqrt(n)
    if color == "pink":
        # Voss-McCartney style spectrum shaping in the frequency domain (deterministic).
        spec = np.fft.rfft(w)
        f = np.arange(spec.size)
        shape = np.ones_like(f, dtype=np.float64)
        shape[1:] = 1.0 / np.sqrt(f[1:])
        out = np.fft.irfft(spec * shape, n)
        return out / (np.max(np.abs(out)) + 1e-9)
    raise ValueError("unknown noise color: " + color)


def sine(n, f, sr=SR, phase=0.0):
    t = np.arange(n) / float(sr)
    return np.sin(2.0 * math.pi * f * t + phase)


def sweep(n, f0, f1, sr=SR, curve="exp"):
    """Frequency sweep from f0 to f1 (exp = exponential, lin = linear)."""
    t = np.arange(n) / float(sr)
    if curve == "lin":
        f = f0 + (f1 - f0) * t / max(1e-9, t[-1])
    else:
        f = f0 * (f1 / max(1e-9, f0)) ** (t / max(1e-9, t[-1]))
    return 2.0 * math.pi * np.cumsum(f) / sr


def adsr(n, sr, a=0.01, d=0.1, s=0.7, r=0.2):
    """Sample-accurate ADSR envelope; a/d/r in seconds, s is the sustain level 0..1."""
    na, nd, nr = int(a * sr), int(d * sr), int(r * sr)
    ns = max(0, n - na - nd - nr)
    env = np.concatenate([
        np.linspace(0.0, 1.0, na, endpoint=False) if na else np.zeros(0),
        np.linspace(1.0, s, nd, endpoint=False) if nd else np.zeros(0),
        np.full(ns, s),
        np.linspace(s, 0.0, nr) if nr else np.zeros(0),
    ])
    return env[:n] if len(env) >= n else np.pad(env, (0, n - len(env)))


def exp_decay(n, sr, tau=0.5, attack=0.002):
    """Percussive decay: fast attack, exponential tail."""
    env = np.exp(-np.arange(n) / (tau * sr))
    at = max(1, int(attack * sr))
    env[:at] *= np.linspace(0.0, 1.0, at)
    return env


def fade(x, fin=0.01, fout=0.05, sr=SR):
    """Linear fades so a one-shot never clicks."""
    n = len(x)
    ni, no = int(fin * sr), int(fout * sr)
    if ni > 0:
        x[:ni] *= np.linspace(0.0, 1.0, ni)
    if no > 0:
        x[n - no:] *= np.linspace(1.0, 0.0, no)
    return x


# --- filters -------------------------------------------------------------------------------------------
def biquad(x, b, a, sr=SR):
    """Biquad IIR via FFT (exact circular response — no per-sample Python loop).

    `b`/`a` are 3-element sequences; a[0] is normalised out. Length-changing filters are not
    supported: the result always has len(x) samples.
    """
    x = np.asarray(x, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64) / a[0]
    a = np.asarray(a, dtype=np.float64) / a[0]
    n = len(x)
    w = 2.0 * math.pi * np.fft.rfftfreq(n, 1.0 / sr) / sr  # rad/sample
    zi = np.exp(-1j * w)
    zi2 = zi * zi
    h = (b[0] + b[1] * zi + b[2] * zi2) / (1.0 + a[1] * zi + a[2] * zi2)
    return np.fft.irfft(np.fft.rfft(x) * h, n)


def _rbj(kind, fc, q, gain_db=0.0, sr=SR):
    w0 = 2.0 * math.pi * fc / sr
    cw, sw = math.cos(w0), math.sin(w0)
    alpha = sw / (2.0 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    else:  # peaking
        A = 10.0 ** (gain_db / 40.0)
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    return b, a


def lowpass(x, fc, q=0.707, sr=SR):
    return biquad(x, *_rbj("lp", fc, q, sr=sr), sr=sr)


def highpass(x, fc, q=0.707, sr=SR):
    return biquad(x, *_rbj("hp", fc, q, sr=sr), sr=sr)


def bandpass(x, fc, q=2.0, sr=SR):
    return biquad(x, *_rbj("bp", fc, q, sr=sr), sr=sr)


def peaking(x, fc, gain_db, q=1.0, sr=SR):
    return biquad(x, *_rbj("pk", fc, q, gain_db, sr=sr), sr=sr)


def one_pole_lp(x, fc, sr=SR):
    """One-pole low-pass via FFT (same response as y += (1-a)(x-y), a = exp(-2*pi*fc/sr)).

    Accepts (n,) or (n, channels); filtering runs along the first axis.
    """
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 2:
        return np.stack([one_pole_lp(x[:, c], fc, sr) for c in range(x.shape[1])], axis=1)
    n = len(x)
    a = math.exp(-2.0 * math.pi * fc / sr)
    w = 2.0 * math.pi * np.fft.rfftfreq(n, 1.0 / sr) / sr  # rad/sample
    zi = np.exp(-1j * w)
    h = (1.0 - a) / (1.0 - a * zi)
    return np.fft.irfft(np.fft.rfft(x) * h, n)


def slow_swell(n, sr=SR, depth=0.2, rate=0.4, seed=0):
    """A slow amplitude modulator with a mean of 1.

    The low-passed brown noise is normalised first: an un-normalised one has a huge amplitude,
    and multiplying the signal with it smears the spectrum over the whole band.
    """
    x = one_pole_lp(noise(n, seed=seed, color="brown"), rate, sr)
    x = x - float(np.mean(x))
    std = float(np.std(x))
    if std < 1e-9:
        return np.ones(n)
    return 1.0 + depth * np.clip(x / std, -2.0, 2.0)


def one_pole_hp(x, fc, sr=SR):
    return np.asarray(x, dtype=np.float64) - one_pole_lp(x, fc, sr)


def high_shelf(x, fc, gain_db, sr=SR):
    """One-pole shelf: boost above fc. Vectorised via FFT."""
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    a = math.exp(-2.0 * math.pi * fc / sr)
    g = 10.0 ** (gain_db / 20.0)
    w = 2.0 * math.pi * np.fft.rfftfreq(n, 1.0 / sr) / sr  # rad/sample
    zi = np.exp(-1j * w)
    h_lp = (1.0 - a) / (1.0 - a * zi)
    h = 1.0 + (g - 1.0) * h_lp
    return np.fft.irfft(np.fft.rfft(x) * h, n)


# --- shaping -------------------------------------------------------------------------------------------
def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / math.tanh(max(1.0, drive))


def saturate(x, drive=1.0):
    """Soft saturation with unity small-signal gain.

    Unlike soft_clip this does not lift the quiet parts, so the peak-to-loudness ratio of a
    mastered mix is preserved.
    """
    if drive <= 1.0:
        return x
    x = np.asarray(x, dtype=np.float64)
    t = 0.7 / drive
    a = np.abs(x)
    y = x.copy()
    over = a > t
    if np.any(over):
        y[over] = np.sign(x[over]) * (t + (1.0 - t) * np.tanh((a[over] - t) / (1.0 - t)))
    return y


def compressor(x, thresh_db=-18.0, ratio=4.0, attack=0.005, release=0.15, sr=SR):
    """Feed-forward compressor with log-domain gain computer."""
    env = np.abs(x)
    at = math.exp(-1.0 / (attack * sr))
    rel = math.exp(-1.0 / (release * sr))
    out = np.empty_like(x)
    envv = 0.0
    for i in range(len(x)):
        envv = at * envv + (1 - at) * env[i] if env[i] > envv else rel * envv + (1 - rel) * env[i]
        lvl = 20.0 * math.log10(max(1e-6, envv))
        gain_db = 0.0
        if lvl > thresh_db:
            gain_db = -(lvl - thresh_db) * (1.0 - 1.0 / ratio)
        out[i] = x[i] * 10.0 ** (gain_db / 20.0)
    return out


def normalize_peak(x, dbfs=-1.0):
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak < 1e-9:
        return x
    return x * (10.0 ** (dbfs / 20.0) / peak)


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)))) if len(x) else 0.0


def peak_dbfs(x):
    p = float(np.max(np.abs(x))) if len(x) else 0.0
    return 20.0 * math.log10(max(1e-9, p))


def spectral_centroid(x, sr=SR):
    """Amplitude-weighted mean frequency of the spectrum (Hz)."""
    w = np.hanning(len(x))
    spec = np.abs(np.fft.rfft(x * w))
    freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
    total = float(np.sum(spec))
    if total < 1e-12:
        return 0.0
    return float(np.sum(spec * freqs) / total)


def simple_reverb(x, sr=SR, room=0.5, damp=0.4, mix_amt=0.25):
    """Cheap Schroeder reverb: 4 combs + 2 allpasses. Enough for city ambience."""
    combs = [1557, 1617, 1491, 1422]
    allpass = [225, 556]
    wet = np.zeros(len(x))
    for d in combs:
        buf = np.zeros(d)
        out = np.zeros(len(x))
        idx = 0
        for i in range(len(x)):
            v = buf[idx]
            out[i] = v
            buf[idx] = x[i] + v * (1.0 - room)
            idx = (idx + 1) % d
        wet += out
    wet /= len(combs)
    for d in allpass:
        buf = np.zeros(d)
        out = np.zeros(len(x))
        idx = 0
        g = 0.6
        for i in range(len(x)):
            v = buf[idx]
            y = -g * wet[i] + v
            buf[idx] = wet[i] + g * y
            out[i] = y
            idx = (idx + 1) % d
        wet = out
    return (1.0 - mix_amt) * x + mix_amt * wet


def hiss_filter(x, sr=SR):
    """Cold-gas hiss colour: 2-pole high-pass 600 Hz + 4-pole low-pass 4 kHz.

    Verified centroid ~2.86 kHz (ref/roadster/DOSSIER.md §6.1 wants 2.5-3.3 kHz, "spectrum flat").
    The in-game ThrusterSynth (game/audio/synth/thruster_synth.gd) mirrors this chain.
    """
    y = highpass(x, HISS_HP_HZ, 0.7, sr)
    y = lowpass(y, HISS_LP_HZ, 0.7, sr)
    return lowpass(y, HISS_LP_HZ, 0.7, sr)


def fast_reverb(x, sr=SR, room=0.78, damp=0.35, mix_amt=0.25, taps=32):
    """Vectorised Schroeder reverb (comb bank only) — fast enough for 60 s music beds.

    Each comb is an exact strided geometric sum, so no per-sample Python loop is needed.
    """
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    out = np.zeros(n)
    for d in (1557, 1617, 1491, 1422, 1277, 1356):
        c = np.zeros(n)
        for k in range(taps):
            off = k * d
            if off >= n:
                break
            c[off:] += (room ** k) * x[: n - off]
        out += c
    out /= 6.0
    out = one_pole_lp(out, 7000.0 - 4000.0 * damp, sr)
    return (1.0 - mix_amt) * x + mix_amt * out


def fast_compressor(x, thresh_db=-16.0, ratio=3.0, attack_s=0.005, release_s=0.18, sr=SR):
    """Vectorised feed-forward compressor (envelope via FFT one-pole, gain applied in dB).

    Works on 1-D (n,) or 2-D (n, channels) buffers.
    """
    x = np.asarray(x, dtype=np.float64)
    flat = x.reshape(-1, x.shape[-1]) if x.ndim == 2 else x.reshape(-1, 1)
    env = one_pole_lp(np.abs(flat), 1.0 / max(1e-4, release_s), sr)
    lvl = 20.0 * np.log10(np.maximum(env, 1e-6))
    over = np.maximum(lvl - thresh_db, 0.0)
    gain_db = -over * (1.0 - 1.0 / ratio)
    out = flat * 10.0 ** (gain_db / 20.0)
    return out.reshape(x.shape)


def stereo_from_mono(x, width=0.35, sr=SR):
    """Cheap stereo widening: mid plus a delayed, inverted side signal."""
    d = int(0.012 * sr)
    side = np.concatenate([np.zeros(d), x[:-d]]) - x
    return np.stack([x + width * side, x - width * side], axis=1)


def pan(x, pos):
    """pos -1 (left) .. 1 (right) -> constant-power stereo."""
    a = (np.clip(pos, -1.0, 1.0) + 1.0) * 0.25 * math.pi
    return np.stack([x * math.cos(a), x * math.sin(a)], axis=1)

