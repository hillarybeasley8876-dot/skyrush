"""Shared DSP helpers for the SKYRUSH audio generators.

Pure numpy + stdlib so it runs under Blender's bundled interpreter:
  /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 -I tools/audio/x.py
Signals are float64 in [-1, 1]; anything written to disk is clipped, never silently normalised.
"""
import math
import os
import subprocess
import wave

import numpy as np

SR = 48000
FFMPEG = "ffmpeg"
VOICE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "audio")


# --- io -------------------------------------------------------------------------------------------------
def write_wav(path, x, sr=SR):
    """Write a float signal to 16-bit PCM WAV. Mono (n,) or stereo (n,2)."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    """Read a 16-bit PCM WAV -> float64 (n,) mono or (n,2) stereo."""
    with wave.open(path, "rb") as w:
        nch = w.getnchannels()
        sr = w.getframerate()
        raw = w.readframes(w.getnframes())
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if nch > 1:
        data = data.reshape(-1, nch)
    return data, sr


def to_ogg(wav_path, ogg_path, loop=False, quality=4, sr=SR, channels=2):
    """Encode WAV -> OGG (Vorbis).

    This ffmpeg build has no libvorbis, so we use ffmpeg's native `vorbis` encoder, which only
    accepts 2 channels — mono material is therefore written as dual mono (L == R), which Godot
    plays correctly in 3D (and gives a centred image if a stereo stream is spatially panned).
    """
    os.makedirs(os.path.dirname(os.path.abspath(ogg_path)), exist_ok=True)
    cmd = [FFMPEG, "-y", "-v", "error", "-i", wav_path,
           "-c:a", "vorbis", "-strict", "-2", "-q:a", str(quality), "-ar", str(sr), "-ac", "2"]
    if loop:
        # Godot 4.7 reads the loop region from the vorbis comments (LOOPSTART/LOOPEND in samples)
        frames = _frames(wav_path)
        cmd += ["-metadata", "LOOPSTART=0", "-metadata", "LOOPEND=%d" % (frames - 1)]
    cmd += [ogg_path]
    subprocess.run(cmd, check=True)
    return ogg_path


def _frames(wav_path):
    with wave.open(wav_path, "rb") as w:
        return w.getnframes()


def save(name, x, sr=SR, loop=False, quality=4, folder="sfx", channels=2, keep_wav=False):
    """Write a signal straight to game/audio/<folder>/<name>.ogg (temp wav in tmp/audio).

    The intermediate wav is deleted afterwards (only the voice cache is kept).
    """
    out_dir = os.path.abspath(os.path.join(VOICE_DIR, folder))
    wav = os.path.join(os.path.abspath(os.path.join(VOICE_DIR, "..", "..", "tmp", "audio")), name + ".wav")
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    write_wav(wav, x, sr)
    ogg = os.path.join(out_dir, name + ".ogg")
    to_ogg(wav, ogg, loop=loop, quality=quality, sr=sr, channels=channels)
    if not keep_wav and os.path.exists(wav):
        os.remove(wav)
    return ogg
