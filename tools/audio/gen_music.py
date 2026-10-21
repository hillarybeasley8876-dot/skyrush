"""SKYRUSH procedural music generator — three seamless synthwave loops.

Run:  /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/gen_music.py
Writes game/audio/music/{cruise,pursuit,race}.ogg. Everything is synthesised from scratch
(bass, arps, pads, drums, lead) — no samples.

Arrangement (review round 1): every loop is A -> B -> breakdown -> A' so the sections differ in
energy and brightness, with fills on bars 4/8/12/16, a crash on each section start, a kick
side-chain on the pads, a gated-reverb snare and an 8-bar arp filter LFO. The loop always starts
and ends in section A, so the seam is clean.

Mastering: -14 LUFS integrated, true peak <= -1.5 dBTP, peak-to-loudness >= 10 dB.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import SR, save
from dsp import (bandpass, exp_decay, fade, fast_reverb, lowpass, noise,
                 one_pole_lp, peak_dbfs, saturate)
from mastering import master
from music_synth import (bass, crash, hat, kick, lead, midi_hz, pad, pluck, saw, snare, square)

MINOR = (0, 3, 7, 10)
MAJOR = (0, 4, 7, 11)

#: The breakdown keeps the pad, a filtered bass and a filtered arp (review round 2: the
#: breakdown must not be a 25 dB hole, it sits 6-10 LU under the full sections).
BREAK_BASS_GAIN = 0.9
BREAK_ARP_GAIN = 0.85
BREAK_PAD_GAIN = 4.0

#: (name, bars) — the loop always ends in section A so the seam matches.
STRUCTURE = {
    "cruise": [("A", 8), ("B", 8), ("break", 4), ("A2", 8)],
    "pursuit": [("A", 8), ("B", 8), ("break", 4), ("A2", 8), ("A", 4)],
    "race": [("A", 8), ("B", 8), ("break", 4), ("A2", 8), ("A", 4)],
}

# chord: (bass_midi, pad_midi, quality)
CRUISE = {
    "name": "cruise",
    "bpm": 95.0,
    "chords": [(45, 57, MINOR), (41, 53, MAJOR), (48, 60, MAJOR), (43, 55, MAJOR)],
    "chord_bars": 1,
    "bass_pattern": [0, 2, 4, 6, 7, 8, 10, 12, 14],
    "bass_octave": [7],
    "drums": "cruise",
    "lead_gain": 0.62,
    "arp_gain": 0.22,
    "pad_gain": 0.11,
    "bass_gain": 0.32,
    "drive": 0.9,
}

PURSUIT = {
    "name": "pursuit",
    "bpm": 124.0,
    "chords": [(38, 50, MINOR), (46, 58, MAJOR), (41, 53, MAJOR), (48, 60, MAJOR)],
    "chord_bars": 2,
    "bass_pattern": [0, 2, 3, 4, 6, 8, 10, 11, 12, 14],
    "bass_octave": [3, 11],
    "drums": "pursuit",
    "lead_gain": 0.66,
    "arp_gain": 0.2,
    "pad_gain": 0.12,
    "bass_gain": 0.34,
    "drive": 0.9,
}

RACE = {
    "name": "race",
    "bpm": 112.0,
    "chords": [(40, 52, MINOR), (48, 60, MAJOR), (43, 55, MAJOR), (50, 62, MAJOR)],
    "chord_bars": 1,
    "bass_pattern": [0, 2, 3, 6, 7, 8, 10, 11, 14],
    "bass_octave": [3, 7, 11, 15],
    "drums": "race",
    "lead_gain": 0.7,
    "arp_gain": 0.22,
    "pad_gain": 0.10,
    "bass_gain": 0.34,
    "drive": 0.9,
}

# lead riffs: (beat in the 4-bar phrase, midi, length in beats)
RIFF_A = [(0.0, 69, 1.5), (2.0, 72, 1.0), (3.0, 76, 1.0),
          (4.0, 74, 1.5), (6.0, 72, 1.0), (7.0, 69, 1.0),
          (8.0, 67, 1.5), (10.0, 69, 1.0), (11.0, 72, 1.0),
          (12.0, 76, 3.0)]
RIFF_B = [(0.0, 65, 1.0), (1.5, 69, 0.5), (2.0, 72, 2.0),
          (4.0, 74, 1.0), (5.5, 77, 0.5), (6.0, 79, 2.0),
          (8.0, 77, 1.0), (9.5, 74, 0.5), (10.0, 72, 1.0), (11.0, 69, 1.0),
          (12.0, 67, 3.0)]

DRUMS = {
    # list of (16th step, instrument): k = kick, s = snare, h = closed hat, oh = open hat
    "cruise": [(0, "k"), (4, "s"), (8, "k"), (12, "s"),
               (2, "h"), (6, "h"), (10, "h"), (14, "h"), (15, "h")],
    "pursuit": [(0, "k"), (4, "k"), (8, "k"), (12, "k"),
                 (4, "s"), (12, "s"),
                 (0, "h"), (2, "h"), (4, "h"), (6, "h"), (8, "h"), (10, "h"), (12, "h"), (14, "oh")],
    "race": [(0, "k"), (6, "k"), (8, "k"), (10, "k"), (14, "k"),
             (4, "s"), (12, "s"),
             (0, "h"), (2, "h"), (4, "h"), (6, "h"), (8, "h"), (10, "h"), (12, "h"), (14, "h"),
             (3, "h"), (7, "h"), (11, "h"), (15, "h")],
}

#: The section order is A -> B -> break -> A' -> (A). Every loop starts and ends in A.
SECTION_ALIAS = {"A2": "A"}


def place(buf, voice, start_sample, gain=1.0, pan_pos=0.0):
    """Mix a mono voice into the stereo track buffer at a sample offset."""
    start = int(start_sample)
    if start >= len(buf):
        return
    voice = np.asarray(voice, dtype=np.float64)
    seg = voice[: len(buf) - start] if len(voice) > len(buf) - start else voice
    if len(seg) == 0:
        return
    buf[start:start + len(seg), 0] += seg * gain * math.cos((pan_pos + 1.0) * 0.25 * math.pi)
    buf[start:start + len(seg), 1] += seg * gain * math.sin((pan_pos + 1.0) * 0.25 * math.pi)


def section_plan(cfg):
    """[(section_name, index_in_section, is_section_start)] for every bar of the loop."""
    plan = []
    for name, bars in STRUCTURE[cfg["name"]]:
        for i in range(bars):
            plan.append((name, i, i == 0))
    return plan


def gated_snare(sr=SR):
    """Snare with a short gated reverb tail (the tail is cut after ~0.2 s)."""
    body = snare(sr)
    n = len(body)
    verb = np.zeros(n)
    for tap, amp in ((0.031, 0.5), (0.047, 0.38), (0.073, 0.26)):
        d = int(tap * sr)
        if d < n:
            verb[d:] += body[: n - d] * amp
    gate = np.exp(-np.arange(n) / (0.11 * sr))
    gate[int(0.22 * sr):] = 0.0
    return body * 0.9 + verb * gate * 0.3


def riser(n, sr=SR, seed=777):
    """A noise riser: the filter opens while the level climbs."""
    t = np.arange(n) / sr
    env = (t / max(1e-9, t[-1])) ** 2.0
    x = bandpass(noise(n, seed=seed), 600, q=0.6, sr=sr)
    # a sweeping band: two band-passes blended by the envelope
    lo = bandpass(noise(n, seed=seed + 1), 500, q=0.8, sr=sr)
    hi = bandpass(noise(n, seed=seed + 2), 4000, q=0.8, sr=sr)
    x = lo * (1.0 - env) + hi * env
    return x * env


def kick_pump(n, bar_len, sr, pattern, depth=0.45, decay=0.22):
    """Side-chain envelope: the pad is ducked by every kick."""
    env = np.zeros(n)
    for step, inst in pattern:
        if inst != "k":
            continue
        at = int(step * bar_len / 16.0 * sr)
        ln = n - at
        if ln <= 0:
            continue
        env[at:] = np.maximum(env[at:], (1.0 - depth) * np.exp(-np.arange(ln) / (decay * sr)))
    return env


def render(cfg):
    """Render one track to a stereo float buffer."""
    bpm = cfg["bpm"]
    beat = 60.0 / bpm
    bar_len = beat * 4.0
    plan = section_plan(cfg)
    total = int(round(len(plan) * bar_len * SR))
    buf = np.zeros((total, 2))
    chords = cfg["chords"]
    chord_bars = cfg["chord_bars"]
    drum_pattern = DRUMS[cfg["drums"]]
    kick_env = np.tile(kick_pump(int(bar_len * SR), bar_len, SR, drum_pattern), chord_bars)
    snare_voice = gated_snare(SR)

    for bar, (section, idx_in_section, is_start) in enumerate(plan):
        bass_midi, pad_midi, quality = chords[(bar // chord_bars) % len(chords)]
        bar_start = int(round(bar * bar_len * SR))
        bar_n = int(bar_len * SR)
        is_break = section == "break"
        is_b = section == "B"
        is_a2 = section == "A2"
        # --- crash on every section start (not on the loop point: the last bar carries it) ---
        if is_start and bar > 0 and bar < len(plan) - 1:
            # no crash on the loop point: the loop runs A -> A and stays on a steady level
            place(buf, crash(SR), bar_start, 0.55, 0.0)
        # --- pad: sustained chord, side-chained by the kick ---
        if bar % chord_bars == 0:
            n = int(bar_len * chord_bars * SR)
            sweep = 1.0
            if is_break:
                # the pad opens its filter across the breakdown
                sweep = 0.3 + 0.5 * (idx_in_section / 3.0)
            for k, tone in enumerate(quality[:3]):
                v = pad(midi_hz(pad_midi + tone), n, SR, phase=k * 0.7)
                v *= sweep
                v = lowpass(v, 900.0 + 2600.0 * sweep, 0.7, SR)
                # a short ramp: the loop point has to stay on a steady level
                ramp = np.minimum(1.0, np.arange(n) / (0.04 * SR))
                v = v * ramp * np.minimum(1.0, np.arange(n)[::-1] / (0.3 * SR))
                if bar_n > 0:
                    v = v * kick_env[:n]
                pad_gain = cfg["pad_gain"] * (BREAK_PAD_GAIN if is_break else 1.0)
                place(buf, v, bar_start, pad_gain * 0.33,
                      pan_pos=-0.45 if k % 2 == 0 else 0.45)
        # --- bass ---
        pattern = cfg["bass_pattern"]
        octaves = cfg["bass_octave"]
        if is_b:
            # section B moves the octave to the off-beats
            pattern = [s + 1 for s in pattern]
            octaves = [s for s in cfg["bass_octave"] if s % 2 == 0]
        if is_break:
            # the breakdown keeps a filtered bass (it is the only low voice left)
            for step in pattern[::2]:
                n = int(beat * 0.5 * SR)
                v = bass(midi_hz(bass_midi), n, SR)
                v *= np.exp(-np.arange(n) / (0.085 * SR))
                v = lowpass(v, 420.0, 0.7, SR)
                place(buf, v, bar_start + int(step * beat * 0.25 * SR),
                      cfg["bass_gain"] * BREAK_BASS_GAIN, 0.0)
        else:
            for step in pattern:
                n = int(beat * 0.5 * SR)
                note = bass_midi + (12 if step in octaves else 0)
                v = bass(midi_hz(note), n, SR)
                v *= np.exp(-np.arange(n) / (0.085 * SR))
                place(buf, v, bar_start + int(step * beat * 0.25 * SR), cfg["bass_gain"], 0.0)
        # --- arp: 16ths with an 8-bar filter LFO ---
        tones = list(quality) + [12, 12 + quality[1], 12 + quality[2]]
        step_len = beat / 4.0
        lfo = 0.5 + 0.5 * math.sin(2.0 * math.pi * (bar / 8.0))
        cutoff = 1200.0 + 3600.0 * lfo if is_b else 4800.0
        arp_gain = cfg["arp_gain"]
        if is_break:
            # the breakdown keeps a filtered, quieter arp
            cutoff = 900.0 + 900.0 * (idx_in_section / 3.0)
            arp_gain *= BREAK_ARP_GAIN
        for i in range(int(bar_len / step_len)):
            note = pad_midi + tones[i % len(tones)]
            n = int(step_len * 1.6 * SR)
            v = pluck(midi_hz(note), n, SR, phase=i * 0.35, cutoff=cutoff)
            pos = 0.35 if (i % 2 == 0) else -0.35
            place(buf, v, bar_start + int(i * step_len * SR), arp_gain, pos)
        # --- drums (with a fill on every 4th bar) ---
        if not is_break:
            fill = (bar % 4 == 3)
            for step, inst in drum_pattern:
                if fill and step >= 12:
                    # the last beat becomes a snare fill
                    place(buf, snare_voice, bar_start + int(step * beat * 0.25 * SR), 0.42, 0.0)
                    continue
                at = bar_start + int(step * beat * 0.25 * SR)
                if inst == "k":
                    place(buf, kick(SR), at, 1.15, 0.0)
                elif inst == "s":
                    place(buf, snare_voice, at, 0.68, 0.0)
                elif inst == "h":
                    place(buf, hat(SR), at, 0.4, 0.15)
                elif inst == "oh":
                    place(buf, hat(SR, open_hat=True), at, 0.34, -0.15)
        elif bar % 4 == 3:
            # the breakdown ends with a snare roll into the next section
            for step in range(8, 16):
                place(buf, snare_voice, bar_start + int(step * beat * 0.25 * SR),
                      0.25 + 0.03 * step, 0.0)
        # --- riser through the breakdown ---
        if is_break and idx_in_section >= 2:
            place(buf, riser(bar_n, SR, seed=780 + bar), bar_start, 0.1, 0.0)
        # --- lead ---
        if not is_break:
            riff = RIFF_B if is_b else RIFF_A
            if bar % 4 == 0:
                phrase_start = bar * bar_len
                octave = 12 if is_a2 else 0
                for beat_off, midi, dur in riff:
                    at = int(round((phrase_start + beat_off * beat) * SR))
                    n = int(dur * beat * SR)
                    v = lead(midi_hz(midi + octave), n, SR)
                    v *= np.minimum(1.0, np.arange(n) / (0.01 * SR))
                    place(buf, v, at, cfg["lead_gain"] * 0.4, 0.12)

    # --- bus: echo, reverb, soft clip, master ---
    echo_len = int(beat * 0.75 * SR)
    for ch in range(2):
        wet = buf[:, ch].copy()
        tap = np.zeros_like(wet)
        tap[echo_len:] = buf[: len(wet) - echo_len, ch] * 0.22
        tap2 = np.zeros_like(wet)
        d2 = echo_len * 2
        tap2[d2:] = buf[: len(wet) - d2, ch] * 0.1
        buf[:, ch] = wet + tap + tap2
    mono = buf.mean(axis=1)
    tail = mono[: int(2.0 * SR)]
    rev = fast_reverb(np.concatenate([mono, tail]), SR, room=0.8, damp=0.45, mix_amt=0.1)[: len(mono)]
    buf += np.stack([rev, rev], axis=1) * 0.8
    buf = saturate(buf, cfg["drive"])
    # the true peak ceiling is set below -1.5 dBTP: the vorbis encoder overshoots the peaks
    # of a dense mix by about 0.5 dB, so the delivered file lands at -1.5 dBTP (round 2)
    out, info = master(buf, SR, target_lufs=-14.0, tp_ceiling_db=-3.3, plr_min_db=10.0)
    return out, info


def main():
    for cfg in (CRUISE, PURSUIT, RACE):
        data, info = render(cfg)
        path = save(cfg["name"], data, loop=True, quality=8, folder="music")
        print("%-10s %5.2fs  %6.2f LUFS  TP %6.2f dBTP  PLR %5.1f dB  %s" % (
            cfg["name"], len(data) / SR, info["lufs"], info["tp"], info.get("plr", 0.0),
            os.path.basename(path)))


if __name__ == "__main__":
    main()
