"""SKYRUSH world SFX generator (police siren, horns, traffic hum, squeal, city/river beds).

Run:  /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/gen_world.py
Writes game/audio/sfx/*.ogg.

Sound design notes (review round 1):
  * the tyre squeal is a stick-slip tone (900-1300 Hz random walk) with a scrub layer;
  * the city bed is 60 s of traffic wash with 6-10 scattered events (horns, a siren pass,
    doppler pass-bys) instead of a constant AM siren;
  * the river bed has water lapping, wind and Huangpu ship horns;
  * every loop is rendered with a tail, made circular and mastered (DC blocked, peak limited).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import SR, save
from dsp import (bandpass, exp_decay, fade, highpass, hiss_filter, lowpass, noise,
                 normalize_peak, one_pole_lp, peak_dbfs, peaking, saturate, simple_reverb,
                 sine, slow_swell, soft_clip)
from mastering import circularize, master

OUT = "sfx"
LOOP_TAIL_S = 0.3


def periodic_tone(n, f_curve, sr=SR, harmonics=(1.0, 0.45, 0.25, 0.12)):
    """Additive tone whose instantaneous frequency follows f_curve(t) (Hz)."""
    phase = np.cumsum(f_curve) / sr
    out = np.zeros(n)
    for k, amp in enumerate(harmonics, start=1):
        out += amp * np.sin(2.0 * math.pi * k * phase)
    return out


def dual_horn(n, sr=SR, f1=420.0, f2=500.0, tau=0.35):
    """A distant two-tone car horn (420/500 Hz) with a soft attack."""
    t = np.arange(n) / sr
    x = np.sin(2 * np.pi * f1 * t) + 0.8 * np.sin(2 * np.pi * f2 * t)
    return x * exp_decay(n, sr, tau=tau, attack=0.05)


def siren_wail():
    """Chinese police siren: two-tone wail, 4 s loop (700 Hz <-> 1400 Hz)."""
    sr = SR
    n = int(4.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    f = 1050.0 + 350.0 * np.cos(np.pi * t / 2.0)
    tone = periodic_tone(n, f, sr, harmonics=(1.0, 0.6, 0.4, 0.22, 0.1))
    air = hiss_filter(noise(n, seed=201), sr) * 0.1
    x = soft_clip(tone * 0.5 + air, 1.4)
    x = lowpass(x, 5200, 0.8, sr)
    x = circularize(x, sr, LOOP_TAIL_S)[: int(4.0 * sr)]
    return master(x, sr, target_lufs=-20.0, tp_ceiling_db=-4.0)[0]


def siren_yelp():
    """Fast two-tone yelp, 2 s loop."""
    sr = SR
    n = int(2.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    f = 1050.0 + 350.0 * np.tanh(6.0 * np.sin(2.0 * math.pi * 2.0 * t))
    tone = periodic_tone(n, f, sr, harmonics=(1.0, 0.6, 0.4, 0.2))
    air = hiss_filter(noise(n, seed=202), sr) * 0.08
    x = soft_clip(tone * 0.5 + air, 1.4)
    x = lowpass(x, 5200, 0.8, sr)
    x = circularize(x, sr, LOOP_TAIL_S)[: int(2.0 * sr)]
    return master(x, sr, target_lufs=-21.0, tp_ceiling_db=-4.0)[0]


def band_saw(n, phase, harmonics=12, tilt=0.7):
    """A band-limited sawtooth at the given phase.

    The harmonic amplitudes fall with `tilt` (1.0 is a true saw): a smaller tilt keeps the
    upper harmonics strong, which is what makes a horn sound like a buzzing diaphragm.
    """
    out = np.zeros(n)
    for k in range(1, harmonics + 1):
        out += np.sin(2.0 * math.pi * k * phase) / (k ** tilt)
    return out


def diaphragm_horn(n, sr=SR, f1=415.0, f2=523.0, harmonics=12, hold_s=0.9,
                   attack_s=0.03, release_s=0.08, vibrato_hz=5.5, vibrato_cents=7.0,
                   peak_hz=2500.0, peak_db=6.0, lp_hz=3000.0, drive=1.6):
    """A sustained car horn: a band-limited saw pair, a flat sustain, a slow vibrato.

    A real horn is a reed against a diaphragm: it is held, it is buzzy and it has a formant
    around 2.5 kHz. A decaying sine chord (the old version) sounds like a door chime.
    """
    t = np.arange(n) / sr
    # a few cents of pitch wander (the reed is never perfectly steady)
    vib = 1.0 + (10.0 ** (vibrato_cents / 1200.0) - 1.0) * np.sin(2 * np.pi * vibrato_hz * t)
    x = np.zeros(n)
    for f, amp in ((f1, 1.0), (f2, 0.78)):
        phase = np.cumsum(f * vib) / sr
        x += amp * band_saw(n, phase, harmonics=harmonics)
    # the formant of the horn and the roll-off of the small speaker
    x = peaking(x, peak_hz, peak_db, q=1.5, sr=sr)
    x = lowpass(x, lp_hz, 0.707, sr)
    x = saturate(x, drive=drive)
    # the envelope: a quick attack, a flat sustain, a short release
    env = np.ones(n)
    a = min(n, int(attack_s * sr))
    env[:a] = np.linspace(0.0, 1.0, a)
    r = min(n, int(release_s * sr))
    env[n - r:] = np.linspace(1.0, 0.0, r)
    # the hold: the sound is cut when the driver lets go of the button
    hold = min(n, int(hold_s * sr))
    env[hold:] = 0.0
    return x * env


def police_horn():
    """Two-tone air horn (police / 消防 style), 1.6 s."""
    sr = SR
    n = int(1.6 * sr)
    x = diaphragm_horn(n, sr, f1=350.0, f2=440.0, harmonics=14, hold_s=1.4,
                       peak_hz=2500.0, peak_db=7.0, lp_hz=3200.0, drive=1.8)
    x = simple_reverb(x, sr, room=0.5, damp=0.4, mix_amt=0.2)
    x = fade(x, 0.01, 0.12, sr)
    return master(x, sr, target_lufs=-22.0, tp_ceiling_db=-4.0)[0]


def traffic_horn(double=False):
    """Ordinary car horn (low, two-tone, held while the driver presses the button)."""
    sr = SR
    n = int(1.4 * sr)
    x = diaphragm_horn(n, sr, f1=415.0, f2=523.0, harmonics=10, hold_s=1.2,
                       peak_hz=2500.0, peak_db=6.0, lp_hz=3000.0, drive=1.6)
    if double:
        gap = np.zeros(int(0.28 * sr))
        x = np.concatenate([x[: int(0.45 * sr)], gap, x[: int(0.45 * sr)], np.zeros(int(0.2 * sr))])
    x = fade(x, 0.005, 0.06, sr)
    return master(x, sr, target_lufs=-26.0, tp_ceiling_db=-8.0)[0]


def traffic_ev_hum():
    """4 s loop: the electric hum of a traffic car (motor + tyre roll)."""
    sr = SR
    n = int(4.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    motor = periodic_tone(n, np.full(n, 120.0), sr, harmonics=(1.0, 0.5, 0.28, 0.12, 0.05))
    whine = periodic_tone(n, np.full(n, 960.0), sr, harmonics=(1.0, 0.3)) * 0.18
    roll = lowpass(noise(n, seed=203), 900, 0.8, sr) * 0.35
    x = motor * 0.45 + whine + roll
    x = circularize(x, sr, LOOP_TAIL_S)[: int(4.0 * sr)]
    return master(x, sr, target_lufs=-30.0, tp_ceiling_db=-14.0)[0]


def tyre_squeal():
    """2 s loop: a stick-slip tyre squeal (900-1300 Hz random walk + scrub noise)."""
    sr = SR
    n = int(2.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    # the slip frequency wanders +-60 Hz at 6-12 Hz
    walk = one_pole_lp(noise(n, seed=210, color="brown"), 9.0, sr)
    walk = walk / (np.max(np.abs(walk)) + 1e-9)
    f = 1100.0 + 60.0 * walk
    phase = np.cumsum(f) / sr
    tone = (np.sin(2 * np.pi * phase)
            + 0.45 * np.sin(2 * np.pi * 2.0 * phase)
            + 0.22 * np.sin(2 * np.pi * 3.01 * phase))
    # the scrub layer sits 10 dB under the tone
    scrub = bandpass(noise(n, seed=211), 2600, q=1.2, sr=sr) * 0.3
    x = tone * 0.9 + scrub
    x = highpass(x, 700, 0.7, sr)
    x = circularize(x, sr, LOOP_TAIL_S)[: int(2.0 * sr)]
    return master(x, sr, target_lufs=-24.0, tp_ceiling_db=-6.0)[0]


def pass_by(n, sr=SR, seed=212, dur=2.2):
    """A doppler pass-by: a band of noise sweeping up and back down."""
    t = np.arange(n) / sr
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.6
    x = bandpass(noise(n, seed=seed), 1400, q=0.5, sr=sr) * env
    x += bandpass(noise(n, seed=seed + 1), 3200, q=0.8, sr=sr) * env * 0.5
    return x


def city_ambience():
    """60 s city bed: traffic wash, metro rumble and 6-10 scattered events."""
    sr = SR
    length = 60.0
    n = int(length * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    # --- the traffic wash: brown noise low-passed, plus a mid hiss ---
    rumble = lowpass(noise(n, seed=210, color="brown"), 220, 0.8, sr) * 0.55
    mid = bandpass(noise(n, seed=211), 900, q=0.4, sr=sr) * 0.2
    sparkle = highpass(noise(n, seed=212), 4000, 0.7, sr=sr) * 0.03
    # --- a slow random-walk level so the wash breathes ---
    swell = slow_swell(n, sr, depth=0.25, rate=0.35, seed=213)
    x = (rumble + mid + sparkle) * swell
    # --- metro rumble: a 32 Hz tone with a slow beat ---
    metro = np.sin(2 * np.pi * 32.0 * t) * (0.05 + 0.03 * np.sin(2 * np.pi * 0.11 * t))
    x += metro
    # --- scattered events -------------------------------------------------------
    events = [
        (3.4, "horn"), (11.2, "horn"), (19.8, "passby"), (24.0, "siren"),
        (31.5, "horn"), (37.2, "passby"), (44.0, "squeal"), (49.5, "passby"),
        (54.0, "squeal"),
    ]
    for i, (at, kind) in enumerate(events):
        start = int(at * sr)
        if kind == "horn":
            ln = int(1.6 * sr)
            ev = dual_horn(ln, sr) * 0.22
            ev = simple_reverb(ev, sr, room=0.6, damp=0.4, mix_amt=0.35)
        elif kind == "passby":
            ln = int(2.2 * sr)
            ev = pass_by(ln, sr, seed=220 + i) * 0.5
            ev = simple_reverb(ev, sr, room=0.5, damp=0.5, mix_amt=0.3)
        elif kind == "siren":
            ln = int(7.0 * sr)
            lt = np.arange(ln) / sr
            f = 1050.0 + 350.0 * np.cos(np.pi * lt / 3.5)
            ev = periodic_tone(ln, f, sr, harmonics=(1.0, 0.5, 0.3)) * 0.06
            ev = simple_reverb(ev, sr, room=0.7, damp=0.4, mix_amt=0.4)
        else:
            ln = int(1.6 * sr)
            ev = bandpass(noise(ln, seed=230 + i), 2400, q=2.5, sr=sr) * 0.12
            ev *= np.exp(-np.arange(ln) / (0.35 * sr))
        end = min(n, start + len(ev))
        x[start:end] += ev[: end - start]
    x = lowpass(x, 6000, 0.8, sr)
    x = simple_reverb(x, sr, room=0.55, damp=0.5, mix_amt=0.22)
    x = circularize(x, sr, LOOP_TAIL_S)[: int(length * sr)]
    return master(x, sr, target_lufs=-28.0, tp_ceiling_db=-16.0)[0]


def rain_layer():
    """20 s rain layer: hiss on the deck plus a low roar on the asphalt."""
    sr = SR
    n = int(20.0 * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    hiss = highpass(noise(n, seed=220), 2600, 0.7, sr=sr) * 0.55
    roar = bandpass(noise(n, seed=221), 1200, q=0.5, sr=sr) * 0.35
    patter = bandpass(noise(n, seed=222), 5200, q=0.8, sr=sr) * 0.12
    swell = slow_swell(n, sr, depth=0.2, rate=0.5, seed=223)
    x = (hiss * 0.6 + roar + patter) * swell
    x = circularize(x, sr, LOOP_TAIL_S)[: int(20.0 * sr)]
    return master(x, sr, target_lufs=-32.0, tp_ceiling_db=-18.0)[0]


def river_ambience():
    """30 s river bed: water lapping, wind and Huangpu ship horns."""
    sr = SR
    length = 30.0
    n = int(length * sr) + int(LOOP_TAIL_S * sr)
    t = np.arange(n) / sr
    body = lowpass(noise(n, seed=230, color="brown"), 400, 0.8, sr) * 0.5
    swell = slow_swell(n, sr, depth=0.4, rate=0.3, seed=231)
    x = body * swell
    # water lapping: short noise bursts between 200 Hz and 1.5 kHz
    rng = np.random.default_rng(232)
    for i in range(70):
        at = int(rng.uniform(0.0, length) * sr)
        ln = int(rng.uniform(0.08, 0.3) * sr)
        burst = bandpass(noise(ln, seed=240 + i), rng.uniform(200.0, 1500.0), q=1.2, sr=sr)
        burst *= np.exp(-np.arange(ln) / (0.08 * sr)) * rng.uniform(0.1, 0.35)
        end = min(n, at + ln)
        x[at:end] += burst[: end - at]
    # wind over the water
    x += bandpass(noise(n, seed=233), 700, q=0.5, sr=sr) * 0.12
    # two Huangpu ship horns
    for at in (6.5, 21.0):
        ln = int(3.0 * sr)
        lt = np.arange(ln) / sr
        horn = (np.sin(2 * np.pi * 135.0 * lt) * 0.8 + np.sin(2 * np.pi * 180.0 * lt) * 0.4)
        horn *= np.exp(-np.arange(ln) / (1.4 * sr))
        horn[: int(0.3 * sr)] *= np.linspace(0.0, 1.0, int(0.3 * sr))
        horn = simple_reverb(horn, sr, room=0.7, damp=0.35, mix_amt=0.35) * 0.3
        start = int(at * sr)
        end = min(n, start + ln)
        x[start:end] += horn[: end - start]
    x = simple_reverb(x, sr, room=0.7, damp=0.3, mix_amt=0.25)
    x = circularize(x, sr, LOOP_TAIL_S)[: int(length * sr)]
    return master(x, sr, target_lufs=-30.0, tp_ceiling_db=-18.0)[0]


def radio_squelch():
    """0.4 s radio squelch that precedes a police radio line."""
    sr = SR
    n = int(0.45 * sr)
    static = bandpass(noise(n, seed=240), 2200, q=0.5, sr=sr) * exp_decay(n, sr, tau=0.05)
    click = bandpass(noise(n, seed=241), 1500, q=1.5, sr=sr) * exp_decay(n, sr, tau=0.006)
    x = static * 0.7 + click
    x = fade(x, 0.001, 0.05, sr)
    return master(x, sr, target_lufs=-30.0, tp_ceiling_db=-12.0)[0]


def main():
    jobs = [
        ("siren_wail", siren_wail(), True),
        ("siren_yelp", siren_yelp(), True),
        ("police_horn", police_horn(), False),
        ("horn_traffic", traffic_horn(False), False),
        ("horn_traffic_double", traffic_horn(True), False),
        ("traffic_ev_hum", traffic_ev_hum(), True),
        ("tyre_squeal", tyre_squeal(), True),
        ("city_ambience", city_ambience(), True),
        ("rain_layer", rain_layer(), True),
        ("river_ambience", river_ambience(), True),
        ("radio_squelch", radio_squelch(), False),
    ]
    for name, data, loop in jobs:
        path = save(name, data, loop=loop, folder=OUT)
        print("%-22s %5.2fs peak %6.2f dBFS  %s" % (
            name, len(data) / SR, peak_dbfs(data), os.path.basename(path)))


if __name__ == "__main__":
    main()
