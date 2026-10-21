"""SKYRUSH voice-line generator — Chinese announcer + police radio via the internal TTS.

Run:  /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/gen_voice.py
  - downloads each line from https://ys-api.xaminim.com/api/minimax_tts (no key, IOA VPN)
  - processes it offline (announcer: light compression; radio: band-pass + saturation + static)
  - writes game/audio/voice/<id>.ogg and the manifest game/audio/voice/voice_lines.gd
Already-downloaded lines are cached in tmp/audio/voice/ so a re-run does not re-hit the API.
"""
import json
import os
import ssl
import subprocess
import sys
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import SR, read_wav, save, write_wav
from dsp import (bandpass, compressor, fast_compressor, highpass, lowpass,
                 noise, normalize_peak, one_pole_lp, peaking, soft_clip)
from mastering import master


def _ssl_context():
    """CA bundle for HTTPS (Blender's bundled interpreter has no system trust store by default)."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        if os.path.exists("/etc/ssl/cert.pem"):
            return ssl.create_default_context(cafile="/etc/ssl/cert.pem")
        return ssl.create_default_context()


SSL_CTX = _ssl_context()

TTS_URL = "https://ys-api.xaminim.com/api/minimax_tts"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tmp", "audio", "voice")
ANNOUNCER_VOICES = ["Chinese (Mandarin)_Male_Announcer", "presenter_male"]
RADIO_VOICES = ["Chinese (Mandarin)_Wise_Women", "female-shaonv", "presenter_female"]
OUT = "voice"
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "audio", "voice", "voice_lines.gd")


def tts(text, voices, speed, emotion, retries=2):
    """POST the TTS endpoint, trying each candidate voice id. Returns the mp3 url."""
    payload_base = {"text": text, "speed": speed, "emotion": emotion}
    for attempt in range(retries):
        for voice in voices:
            body = dict(payload_base)
            body["voice_id"] = voice
            req = urllib.request.Request(
                TTS_URL, data=json.dumps(body).encode("utf-8"),
                headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=90, context=SSL_CTX) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
            except Exception as exc:  # network hiccup -> try the next voice
                print("   tts error (%s): %s" % (voice, exc))
                continue
            if data.get("success") and data.get("data"):
                return data["data"]
            print("   tts refused voice=%s" % voice)
    return None


def fetch(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 1024:
        return dest
    with urllib.request.urlopen(url, timeout=120, context=SSL_CTX) as resp:
        blob = resp.read()
    with open(dest, "wb") as fh:
        fh.write(blob)
    return dest


def decode_mp3(mp3_path, wav_path):
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", mp3_path,
                    "-ac", "1", "-ar", str(SR), "-c:a", "pcm_s16le", wav_path], check=True)
    x, _ = read_wav(wav_path)
    return x


def trim_silence(x, sr=SR, thresh_db=-42.0, pad=0.04):
    """Cut leading/trailing silence so the line triggers tight."""
    if len(x) == 0:
        return x
    amp = np.abs(x)
    peak = float(np.max(amp))
    if peak < 1e-6:
        return x
    idx = np.where(amp > peak * (10.0 ** (thresh_db / 20.0)))[0]
    if len(idx) == 0:
        return x
    a = max(0, int(idx[0]) - int(pad * sr))
    b = min(len(x), int(idx[-1]) + int(pad * sr))
    return x[a:b]


#: Integrated loudness targets (LUFS) and the true-peak ceiling for the two voice kinds.
ANNOUNCER_LUFS = -16.0
RADIO_LUFS = -18.0
VOICE_TP_CEILING_DB = -1.5
#: Radio band: a steep high-pass and low-pass (a telephone band) plus a presence bump. The
#: cascade is five sections each, which puts the radio lines at least 25 dB below 250 Hz and
#: 30 dB above 3.5 kHz.
RADIO_HP_HZ = 320.0
RADIO_LP_HZ = 2800.0
RADIO_SECTIONS = 5
RADIO_PEAK_HZ = 1800.0
RADIO_PEAK_DB = 3.0


def process_announcer(x, sr=SR):
    """Broadcast announcer: trim, top control, compression, then master to -16 LUFS."""
    x = trim_silence(x, sr)
    x = highpass(x, 90.0, 0.7, sr)
    x = one_pole_lp(x, 9000.0, sr)
    x = compressor(x, thresh_db=-20.0, ratio=3.0, attack=0.004, release=0.12, sr=sr)
    x, _ = master(x, sr, target_lufs=ANNOUNCER_LUFS, tp_ceiling_db=VOICE_TP_CEILING_DB)
    return x


def process_radio(x, sr=SR):
    """Police radio: 4th-order band limit, saturation, a presence bump and carrier hiss."""
    x = trim_silence(x, sr, thresh_db=-40.0, pad=0.03)
    # the compressor runs before the band limit, so the saturation products cannot put energy
    # back below 250 Hz
    x = compressor(x, thresh_db=-22.0, ratio=4.0, attack=0.003, release=0.1, sr=sr)
    x = soft_clip(x * 2.6, 2.2)          # radio distortion
    # a steep high-pass at 320 Hz (five cascaded 2-pole sections)
    for _section in range(RADIO_SECTIONS):
        x = highpass(x, RADIO_HP_HZ, 0.707, sr)
    # a steep low-pass at 2.8 kHz, then the presence bump at 1.8 kHz
    for _section in range(RADIO_SECTIONS):
        x = lowpass(x, RADIO_LP_HZ, 0.707, sr)
    x = peaking(x, RADIO_PEAK_HZ, RADIO_PEAK_DB, 1.0, sr)
    hiss = bandpass(noise(len(x), seed=909), 1800.0, q=0.7, sr=sr) * 0.004
    x += hiss
    tail = int(0.12 * sr)
    if len(x) > tail:
        x[-tail:] *= np.linspace(1.0, 0.0, tail)   # squelch tail
    x, _ = master(x, sr, target_lufs=RADIO_LUFS, tp_ceiling_db=VOICE_TP_CEILING_DB)
    return x


def write_manifest(lines):
    rows = []
    for (lid, text, en, kind, _emotion, _speed) in lines:
        rows.append('\t&"%s": {"file": "res://audio/voice/%s.ogg", "text": "%s", "en": "%s", "kind": "%s"},'
                    % (lid, lid, text, en, kind))
    body = "\n".join(rows)
    out = '''extends RefCounted
## Manifest of the Chinese voice lines: id -> {file, text, en, kind}.
## Generated by tools/audio/gen_voice.py — do not hand-edit; re-run the generator instead.
## Load it with: const VoiceLines = preload("res://audio/voice/voice_lines.gd")
##
## kind: "announcer" (race commentator) | "radio" (police dispatcher, radio-processed)

const LINES: Dictionary = {
%s
}


## Returns the manifest entry for `id`, or an empty dictionary when the id is unknown.
static func get_line(id: StringName) -> Dictionary:
	return LINES.get(id, {})


## Every known line id.
static func ids() -> Array:
	return LINES.keys()
''' % body
    os.makedirs(os.path.dirname(os.path.abspath(MANIFEST)), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as fh:
        fh.write(out)
    return MANIFEST


def main():
    from voice_lines_data import LINES
    os.makedirs(CACHE, exist_ok=True)
    failures = []
    for (lid, text, en, kind, emotion, speed) in LINES:
        voices = RADIO_VOICES if kind == "radio" else ANNOUNCER_VOICES
        mp3 = os.path.join(CACHE, lid + ".mp3")
        wav = os.path.join(CACHE, lid + ".wav")
        if not os.path.exists(mp3):
            url = tts(text, voices, speed, emotion)
            if url is None:
                failures.append(lid)
                print("FAIL %-20s (no tts url)" % lid)
                continue
            try:
                fetch(url, mp3)
            except Exception as exc:
                failures.append(lid)
                print("FAIL %-20s (download: %s)" % (lid, exc))
                continue
        raw = decode_mp3(mp3, wav)
        out = process_radio(raw) if kind == "radio" else process_announcer(raw)
        path = save(lid, out, folder=OUT)
        print("%-20s %5.2fs %s" % (lid, len(out) / SR, os.path.basename(path)))
    write_manifest(LINES)
    print("manifest: %s (%d lines)" % (os.path.basename(MANIFEST), len(LINES)))
    if failures:
        print("FAILED: %s" % ", ".join(failures))
        sys.exit(1)


if __name__ == "__main__":
    main()

