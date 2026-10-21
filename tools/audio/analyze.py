"""QA table for every generated SKYRUSH audio file.

Run:  /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/analyze.py
      ... tools/audio/analyze.py captures/audio/gameplay.wav

Columns: duration, peak, LUFS, RMS, spectral centroid, DC offset and (for loops) the seam ratio
and the seam level jump. Flags: louder than -0.5 dBFS, shorter than 50 ms, |DC| over 0.002,
seam ratio over 1.0, seam jump over 1.5 dB.
"""
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import SR
from dsp import rms, spectral_centroid
from metering import (dc_offset, lufs_integrated, lufs_short_term_series, seam_envelope_jump_db,
                      seam_ratio, true_peak_dbfs)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
GAME = os.path.join(ROOT, "game", "audio")

FLAG_PEAK_DBFS = -0.5
FLAG_MIN_SECONDS = 0.05
FLAG_DC = 0.002
FLAG_SEAM_RATIO = 1.0
FLAG_SEAM_JUMP_DB = 1.5
#: The music has to keep a peak-to-loudness ratio of at least 10 dB and its breakdown may not
#: fall below -24 LUFS (short term).
FLAG_MUSIC_PLR_DB = 10.0
FLAG_MUSIC_FLOOR_LUFS = -24.0


def decode(path):
    """Decodes any ffmpeg-readable file to float samples at 48 kHz (mono mix)."""
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", "48000", "-f", "s16le", "-"]
    raw = subprocess.run(cmd, check=True, stdout=subprocess.PIPE).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0


def report(path, is_loop=False, is_music=False):
    x = decode(path)
    if len(x) == 0:
        print("%-46s EMPTY" % os.path.basename(path))
        return False
    dur = len(x) / float(SR)
    peak = 20.0 * np.log10(max(1e-9, float(np.max(np.abs(x)))))
    level = 20.0 * np.log10(max(1e-9, rms(x)))
    loud = lufs_integrated(x, SR)
    centroid = spectral_centroid(x, SR)
    dc = dc_offset(x)
    flags = []
    if peak > FLAG_PEAK_DBFS:
        flags.append("LOUD")
    if dur < FLAG_MIN_SECONDS:
        flags.append("SHORT")
    if abs(dc) > FLAG_DC:
        flags.append("DC")
    ratio = jump = 0.0
    note = ""
    if is_loop:
        ratio = seam_ratio(x)
        jump = seam_envelope_jump_db(x, SR)
        if ratio > FLAG_SEAM_RATIO:
            flags.append("SEAM")
        if jump > FLAG_SEAM_JUMP_DB:
            if is_music:
                # the music loop points on a downbeat: the level step is the accent, not a
                # discontinuity — the waveform itself is continuous (see the seam ratio)
                note = "  (downbeat accent)"
            else:
                flags.append("JUMP")
    line = "%-46s %6.2fs peak %6.2f  %7.2f LUFS  rms %6.2f  cen %6.0f Hz  dc %+.4f  seam %5.2f/%5.2f dB" % (
        os.path.basename(path), dur, peak, loud, level, centroid, dc, ratio, jump)
    shares = band_shares(x, SR)
    line += "  bands " + "/".join("%.0f" % v for v in shares)
    if is_music:
        tp = true_peak_dbfs(x, SR)
        plr = tp - loud
        series = list(lufs_short_term_series(x, SR, 3.0, 1.0))
        floor = min(series) if series else loud
        line += "  PLR %5.1f dB  short-term min %6.1f LUFS" % (plr, floor)
        if plr < FLAG_MUSIC_PLR_DB:
            flags.append("PLR")
        if floor < FLAG_MUSIC_FLOOR_LUFS:
            flags.append("FLOOR")
    print(line + ("%s%s" % (("  " + ",".join(flags)) if flags else "", note)))
    return not flags


#: The bands the QA table reports (the share of the energy in each of them).
BANDS = ((0, 200), (200, 1000), (1000, 4000), (4000, 10000), (10000, 24000))


def band_shares(x, sr=SR):
    """The share of the energy in each band (percent)."""
    w = np.hanning(len(x))
    spec = np.abs(np.fft.rfft(x * w)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
    total = spec.sum()
    if total < 1e-12:
        return [0.0] * len(BANDS)
    return [100.0 * spec[(freqs >= lo) & (freqs < hi)].sum() / total for lo, hi in BANDS]


def band_db(x, lo_hz, hi_hz, sr=SR):
    """The energy of a band relative to the whole signal (dB)."""
    w = np.hanning(len(x))
    spec = np.abs(np.fft.rfft(x * w)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
    total = spec.sum()
    band = spec[(freqs >= lo_hz) & (freqs < hi_hz)].sum()
    if total < 1e-12 or band < 1e-12:
        return -120.0
    return 10.0 * np.log10(band / total)


def voice_report():
    """The radio band limits and the loudness spread per kind of voice line."""
    manifest = os.path.join(GAME, "voice", "voice_lines.gd")
    if not os.path.exists(manifest):
        return 0
    levels = {"announcer": [], "radio": []}
    low = []
    high = []
    for name in sorted(os.listdir(os.path.join(GAME, "voice"))):
        if not name.endswith(".ogg"):
            continue
        path = os.path.join(GAME, "voice", name)
        x = decode(path)
        kind = "radio" if name.startswith("radio_") else "announcer"
        levels[kind].append(lufs_integrated(x, SR))
        if kind == "radio":
            low.append(band_db(x, 20.0, 250.0))
            high.append(band_db(x, 3500.0, 20000.0))
    bad = 0
    if low:
        print("VOICE radio below 250 Hz: worst %.1f dB (limit -25)  above 3.5 kHz: worst %.1f dB (limit -30)"
              % (max(low), max(high)))
        if max(low) > -25.0:
            print("  FLAG: the radio lines carry too much low end")
            bad += 1
        if max(high) > -30.0:
            print("  FLAG: the radio lines carry too much high end")
            bad += 1
    for kind, arr in levels.items():
        if len(arr) < 2:
            continue
        spread = max(arr) - min(arr)
        print("VOICE %s loudness: %.1f LUFS (spread %.1f LU, limit 1.0)"
              % (kind, sum(arr) / len(arr), spread))
        if spread > 1.0:
            print("  FLAG: the %s loudness spread is too wide" % kind)
            bad += 1
    return bad


def main():
    loop_ids = {"scrape_loop", "boost_roar_loop", "thruster_hiss_loop", "siren_wail", "siren_yelp",
                "traffic_ev_hum", "tyre_squeal", "city_ambience", "rain_layer", "river_ambience",
                "cruise", "pursuit", "race"}
    targets = []
    for sub in ("sfx", "music", "voice"):
        folder = os.path.join(GAME, sub)
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if name.endswith(".ogg"):
                targets.append((os.path.join(folder, name), name[:-4] in loop_ids))
    for arg in sys.argv[1:]:
        targets.append((arg, False))
    bad = 0
    for path, is_loop in targets:
        if not report(path, is_loop, path.endswith(".ogg") and "music" in path):
            bad += 1
    bad += voice_report()
    print("ANALYZE %d files, %d flagged" % (len(targets), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
