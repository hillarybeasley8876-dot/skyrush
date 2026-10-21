"""SKYRUSH one-shot SFX generator (impacts, vehicle sounds, player transients).

Run:  /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/gen_sfx.py
Writes game/audio/sfx/*.ogg. Deterministic (fixed seeds) — rebuilds byte-identically.

Sound design notes (review round 1):
  * impacts are three layers: a body thump, inharmonic metal modes, scattered debris;
  * the chirps (小喷, hop release) are band-limited and never cross 0 Hz;
  * the boost roar is pink-noise based with a 120-600 Hz body and a matched hiss layer;
  * every loop is rendered with a tail and made circular with an equal-power wrap crossfade;
  * everything is DC blocked and peak limited.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import SR, save
from dsp import (adsr, bandpass, exp_decay, fade, highpass, hiss_filter, lowpass,
                 noise, normalize_peak, one_pole_lp, peak_dbfs, simple_reverb, sine,
                 slow_swell, soft_clip)
from mastering import circularize, master

OUT = "sfx"
#: Extra tail rendered for the loops so the wrap crossfade has material to work with.
LOOP_TAIL_S = 0.25


def metallic(freqs, taus, seed=0, sr=SR, detune=0.01, length=None):
    """Sum of inharmonic decaying partials — the body of every metal impact."""
    rng = np.random.default_rng(seed)
    n = int(max(taus) * sr * 4) if length is None else int(length)
    out = np.zeros(n)
    for f, tau in zip(freqs, taus):
        d = 1.0 + detune * rng.uniform(-1.0, 1.0)
        tone = sine(n, f * d, sr, phase=rng.uniform(0, 2 * np.pi))
        out += tone * exp_decay(n, sr, tau=tau, attack=0.001)
    return out


def metal_modes(seed, count, f_lo, f_hi, tau_lo, tau_hi, length, sr=SR):
    """Logarithmically spread inharmonic metal modes with randomised decay times."""
    rng = np.random.default_rng(seed)
    freqs = np.geomspace(f_lo, f_hi, count)
    taus = rng.uniform(tau_lo, tau_hi, count)
    return metallic(list(freqs), list(taus), seed=seed + 7, sr=sr, length=length)


def clicks(n, count, seed, sr=SR, lo=2500, hi=9000, spread=0.4, level=1.0):
    """Scattered short debris ticks (metal shards, glass pieces)."""
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    for _ in range(count):
        pos = int(rng.uniform(0.02, max(0.03, spread)) * sr)
        length = int(rng.uniform(0.004, 0.02) * sr)
        g = rng.uniform(0.25, 1.0) * level
        tick = noise(length, seed=int(rng.integers(0, 1 << 30))) * exp_decay(length, sr, tau=0.004)
        tick = bandpass(tick, rng.uniform(lo, hi), q=1.4, sr=sr)
        end = min(n, pos + length)
        out[pos:end] += tick[: end - pos] * g
    return out


def body_thump(n, f_hi, f_lo, sr=SR, tau=0.2, shape=0.14):
    """Pitch-drop thump: the low body of an impact."""
    t = np.arange(n) / sr
    return np.sin(2 * np.pi * (f_hi * t + (f_lo - f_hi) / (2.0 * shape) * t ** 2)) * exp_decay(n, sr, tau=tau)


def impact(severity, seed):
    """severity: 0 light panel tap, 1 medium crunch, 2 heavy crash.

    Three layers: body thump (60-120 Hz), inharmonic metal modes (300 Hz - 6 kHz) and debris.
    """
    sr = SR
    if severity == 0:
        n = int(0.28 * sr)
        x = body_thump(n, 150.0, 70.0, sr, tau=0.07, shape=0.03) * 0.5
        x += metal_modes(seed, 6, 900.0, 4200.0, 0.03, 0.09, n) * 0.5
        x += clicks(n, 4, seed + 1, spread=0.16) * 0.35
        x = fade(x, 0.001, 0.04, sr)
        return master(x, sr, target_lufs=-22.0, tp_ceiling_db=-3.0)[0]
    if severity == 1:
        n = int(0.85 * sr)
        x = body_thump(n, 165.0, 62.0, sr, tau=0.16) * 0.75
        crunch = bandpass(noise(n, seed=seed + 2), 950, q=0.55, sr=sr) * exp_decay(n, sr, tau=0.07)
        x += crunch * 0.55
        x += metal_modes(seed, 10, 320.0, 5200.0, 0.12, 0.45, n) * 0.35
        x += clicks(n, 8, seed + 5, spread=0.5) * 0.5
        x = simple_reverb(x, sr, room=0.45, damp=0.5, mix_amt=0.18)
        x = fade(x, 0.001, 0.06, sr)
        return master(x, sr, target_lufs=-20.0, tp_ceiling_db=-2.0)[0]
    n = int(1.8 * sr)
    x = body_thump(n, 120.0, 45.0, sr, tau=0.42, shape=0.2) * 0.9
    x += np.sin(2 * np.pi * 48.0 * np.arange(n) / sr) * exp_decay(n, sr, tau=0.6) * 0.35
    crunch = lowpass(noise(n, seed=seed + 6), 2600, 0.8, sr) * exp_decay(n, sr, tau=0.2)
    x += crunch * 0.5
    x += metal_modes(seed, 14, 300.0, 6000.0, 0.2, 1.2, n) * 0.3
    x += clicks(n, 18, seed + 9, spread=1.1) * 0.55
    x = simple_reverb(x, sr, room=0.6, damp=0.45, mix_amt=0.3)
    x = fade(x, 0.001, 0.12, sr)
    return master(x, sr, target_lufs=-18.0, tp_ceiling_db=-2.0)[0]


def glass_break(seed):
    sr = SR
    n = int(1.3 * sr)
    x = bandpass(noise(n, seed=seed), 5200, q=0.8, sr=sr) * exp_decay(n, sr, tau=0.012) * 0.8
    x += clicks(n, 28, seed + 1, lo=3200, hi=11000, spread=0.9, level=0.85)
    x += bandpass(noise(n, seed + 2), 7000, q=0.5, sr=sr) * exp_decay(n, sr, tau=0.18) * 0.3
    x = simple_reverb(x, sr, room=0.7, damp=0.3, mix_amt=0.3)
    x = fade(x, 0.001, 0.1, sr)
    return master(x, sr, target_lufs=-22.0, tp_ceiling_db=-3.0)[0]


def scrape_loop():
    """2 s seamless metal scrape (car dragging along a barrier)."""
    sr = SR
    n = int(2.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    base = bandpass(noise(n, seed=21), 2600, q=1.1, sr=sr)
    rasp = bandpass(noise(n, seed=22), 1100, q=2.2, sr=sr) * 0.7
    # slow random-walk amplitude (circular, so the loop stays seamless)
    wob = slow_swell(n, sr, depth=0.2, rate=2.5, seed=24)
    metal = metal_modes(23, 4, 1400.0, 4300.0, 0.03, 0.06, n) * 0.3
    x = (base * 0.6 + rasp + metal) * wob
    x = one_pole_lp(x, 6000, sr)
    x = circularize(x, sr, LOOP_TAIL_S)[: int(2.0 * sr)]
    return master(x, sr, target_lufs=-26.0, tp_ceiling_db=-6.0)[0]


# --- player transients ---------------------------------------------------------------------------------
def boost_ignite():
    """N₂ ignition punch: a 45-70 Hz pitch-drop burst plus a filtered air blast."""
    sr = SR
    n = int(0.7 * sr)
    x = body_thump(n, 70.0, 45.0, sr, tau=0.18, shape=0.05) * 0.9
    blast = bandpass(noise(n, seed=31), 1800, q=0.45, sr=sr) * exp_decay(n, sr, tau=0.13) * 0.6
    x += blast
    x = fade(x, 0.002, 0.08, sr)
    return master(x, sr, target_lufs=-18.0, tp_ceiling_db=-2.0)[0]


def boost_roar_loop():
    """2 s seamless N₂ roar: pink noise, a 120-600 Hz body with 2-7 Hz turbulence and a hiss."""
    sr = SR
    n = int(2.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    pink = noise(n, seed=33, color="pink")
    body = bandpass(pink, 300.0, q=0.5, sr=sr) * 1.35
    turbulence = 1.0 + 0.16 * np.sin(2 * np.pi * 3.0 * t) + 0.1 * np.sin(2 * np.pi * 6.5 * t + 1.1)
    body *= turbulence
    hiss = hiss_filter(noise(n, seed=34), sr) * 0.4
    x = body * 0.85 + hiss
    x = one_pole_lp(x, 9000.0, sr)
    x = circularize(x, sr, LOOP_TAIL_S)[: int(2.0 * sr)]
    return master(x, sr, target_lufs=-22.0, tp_ceiling_db=-5.0)[0]


def mini_pssh():
    """小喷 — a short compressed-air puff: a band-limited chirp that never crosses 0 Hz."""
    sr = SR
    n = int(0.45 * sr)
    t = np.arange(n) / sr
    # a downward band sweep between 2.6 kHz and 900 Hz: air leaving a valve
    f = 2600.0 * (900.0 / 2600.0) ** (t / 0.3)
    chirp = np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t / 0.07) * 0.45
    air = bandpass(noise(n, seed=41), 2000, q=0.6, sr=sr) * exp_decay(n, sr, tau=0.06) * 0.7
    chuff = bandpass(noise(n, seed=42), 1100, q=0.9, sr=sr) * exp_decay(n, sr, tau=0.02) * 0.4
    x = air + chirp + chuff
    x = fade(x, 0.002, 0.05, sr)
    return master(x, sr, target_lufs=-24.0, tp_ceiling_db=-4.0)[0]


def land_whoomp():
    """Landing: suspension thump + body whoomp."""
    sr = SR
    n = int(0.8 * sr)
    x = body_thump(n, 135.0, 55.0, sr, tau=0.22, shape=0.1) * 0.9
    x += bandpass(noise(n, seed=51), 700, q=0.6, sr=sr) * exp_decay(n, sr, tau=0.1) * 0.5
    x += bandpass(noise(n, seed=52), 2400, q=3.0, sr=sr) * exp_decay(n, sr, tau=0.09) * 0.25
    x = fade(x, 0.002, 0.08, sr)
    return master(x, sr, target_lufs=-19.0, tp_ceiling_db=-2.5)[0]


def hop_release():
    """Cold-gas cut-off: a pneumatic pop, band-limited (never a 0 Hz-crossing chirp)."""
    sr = SR
    n = int(0.45 * sr)
    t = np.arange(n) / sr
    pop = bandpass(noise(n, seed=61), 1400, q=0.8, sr=sr) * exp_decay(n, sr, tau=0.03)
    # a short falling band from 1.5 kHz to 600 Hz
    f = 1500.0 * (600.0 / 1500.0) ** (t / 0.12)
    fall = np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t / 0.05) * 0.3
    x = pop + fall
    x = fade(x, 0.001, 0.05, sr)
    return master(x, sr, target_lufs=-22.0, tp_ceiling_db=-3.0)[0]


def charge_zap():
    """闪充 electric zap: crackle over a rising zip (the zip stays above 400 Hz)."""
    sr = SR
    n = int(0.9 * sr)
    t = np.arange(n) / sr
    f = 400.0 * (7.5 ** (t / 0.55))
    f = np.where(t < 0.55, f, 3000.0)
    zip_ = np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t / 0.3) * 0.45
    buzz = np.sign(np.sin(2 * np.pi * 120 * t)) * 0.1 * np.exp(-t / 0.25)
    crack = clicks(n, 18, 71, lo=1800, hi=9000, spread=0.6, level=0.9) * 0.8
    x = zip_ + buzz + crack
    x = fade(x, 0.001, 0.08, sr)
    return master(x, sr, target_lufs=-20.0, tp_ceiling_db=-3.0)[0]


def charge_chime():
    """Rising three-note chime for a completed flash charge."""
    sr = SR
    n = int(1.2 * sr)
    x = np.zeros(n)
    for i, f in enumerate((784.0, 1046.5, 1568.0)):
        start = int(i * 0.11 * sr)
        ln = n - start
        bell = (sine(ln, f, sr) * 0.6 + sine(ln, f * 2.01, sr) * 0.22
                + sine(ln, f * 3.02, sr) * 0.08) * exp_decay(ln, sr, tau=0.34)
        x[start:] += bell
    x = simple_reverb(x, sr, room=0.5, damp=0.4, mix_amt=0.2)
    x = fade(x, 0.002, 0.15, sr)
    return master(x, sr, target_lufs=-22.0, tp_ceiling_db=-4.0)[0]


def battery_low():
    """Low-battery warning: two clipped beeps."""
    sr = SR
    n = int(0.6 * sr)
    x = np.zeros(n)
    for i, start_s in enumerate((0.0, 0.22)):
        start = int(start_s * sr)
        ln = n - start
        x[start:] += soft_clip(sine(ln, 1180, sr), 2.2) * exp_decay(ln, sr, tau=0.09)
    x = fade(x, 0.001, 0.04, sr)
    return master(x, sr, target_lufs=-26.0, tp_ceiling_db=-6.0)[0]


def near_miss_whoosh():
    """0.7 s doppler swish as a car passes close by."""
    sr = SR
    n = int(0.75 * sr)
    t = np.arange(n) / sr
    env = np.sin(np.pi * np.clip(t / 0.75, 0, 1)) ** 1.8
    x = bandpass(noise(n, seed=83), 1800, q=0.45, sr=sr) * env
    x += bandpass(noise(n, seed=84), 3200, q=0.7, sr=sr) * env * 0.5
    x = one_pole_lp(x, 7000, sr)
    x = fade(x, 0.03, 0.1, sr)
    return master(x, sr, target_lufs=-26.0, tp_ceiling_db=-9.0)[0]


def thruster_hiss_loop():
    """2 s seamless cold-gas hiss reference: 600 Hz-4 kHz band, centroid ~2.9 kHz.

    Mirrors the filter design used by the in-game ThrusterSynth (game/audio/synth/).
    """
    sr = SR
    n = int(2.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    x = hiss_filter(noise(n, seed=91), sr)
    x = x * (0.85 + 0.15 * np.sin(2 * np.pi * 2.0 * t))
    x = circularize(x, sr, LOOP_TAIL_S)[: int(2.0 * sr)]
    return master(x, sr, target_lufs=-28.0, tp_ceiling_db=-8.0)[0]


def road_roll_loop():
    """2 s seamless tyre/road roll: the bed under the motor whine.

    A real tyre roar sits between 300 Hz and 1.2 kHz, so the energy is kept below 1 kHz
    (a brown-noise rumble would be all sub-bass).
    """
    sr = SR
    n = int(2.0 * sr) + int(LOOP_TAIL_S * sr)
    body = bandpass(noise(n, seed=41, color="brown"), 400, q=0.7, sr=sr) * 0.9
    grit = bandpass(noise(n, seed=42), 600, q=1.0, sr=sr) * 0.25
    swell = slow_swell(n, sr, depth=0.15, rate=0.6, seed=43)
    x = (body + grit) * swell
    x = circularize(x, sr, LOOP_TAIL_S)[: int(2.0 * sr)]
    return master(x, sr, target_lufs=-26.0, tp_ceiling_db=-8.0)[0]


def wind_rush_loop():
    """2 s seamless wind bed: a rush of air around the car.

    The rush is the hiss around the bodywork, the buffeting is the low pressure that shakes
    the car (80-500 Hz with slow 0.3-2 Hz gusts).
    """
    sr = SR
    n = int(2.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    rush = bandpass(noise(n, seed=44), 700, q=0.7, sr=sr) * 0.40
    whistle = bandpass(noise(n, seed=45), 2600, q=1.6, sr=sr) * 0.05
    # the buffeting is the low pressure that shakes the car: it lives below 320 Hz
    buffeting = one_pole_lp(noise(n, seed=47, color="brown"), 320.0, sr) * 1.25
    gust = 1.0 + 0.5 * np.sin(2 * np.pi * 0.6 * t) + 0.3 * np.sin(2 * np.pi * 1.7 * t + 0.7)
    swell = slow_swell(n, sr, depth=0.2, rate=0.4, seed=46)
    x = (rush * swell) + whistle + buffeting * gust
    x = circularize(x, sr, LOOP_TAIL_S)[: int(2.0 * sr)]
    return master(x, sr, target_lufs=-26.0, tp_ceiling_db=-8.0)[0]


def main():
    jobs = [
        ("impact_light", impact(0, 101), False),
        ("impact_medium", impact(1, 102), False),
        ("impact_heavy", impact(2, 103), False),
        ("glass_break", glass_break(104), False),
        ("scrape_loop", scrape_loop(), True),
        ("boost_ignite", boost_ignite(), False),
        ("boost_roar_loop", boost_roar_loop(), True),
        ("mini_pssh", mini_pssh(), False),
        ("land_whoomp", land_whoomp(), False),
        ("hop_release", hop_release(), False),
        ("charge_zap", charge_zap(), False),
        ("charge_chime", charge_chime(), False),
        ("battery_low", battery_low(), False),
        ("near_miss_whoosh", near_miss_whoosh(), False),
        ("thruster_hiss_loop", thruster_hiss_loop(), True),
        ("road_roll", road_roll_loop(), True),
        ("wind_rush", wind_rush_loop(), True),
    ]
    for name, data, loop in jobs:
        path = save(name, data, loop=loop, folder=OUT)
        print("%-22s %5.2fs peak %6.2f dBFS  %s" % (
            name, len(data) / SR, peak_dbfs(data), os.path.basename(path)))


if __name__ == "__main__":
    main()
