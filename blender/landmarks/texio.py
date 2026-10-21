"""PNG io and the colour/data encoders for the SKYRUSH landmark textures.

Colour maps (albedo, emission) go through the sRGB curve; data maps (normal,
roughness, metallic, AO) are written LINEAR, so a flat normal is (128, 128,
255) and never (188, 188, 255).

    python3 -c "import texio; texio.write_png('x.png', texio.data_to_bytes(a))"
"""
import os
import struct
import zlib

import numpy as np

def write_png(path, img):
    """img: uint8 array (h, w), (h, w, 3) or (h, w, 4).

    The file is only written when its bytes change (the IMPORT-CHURN lead
    note): a rebuild must not touch the files that did not change, or Godot
    re-imports them and fills the team-wide import lock."""
    if img.ndim == 2:
        img = img[:, :, None]
    h, w, c = img.shape
    ctype = {1: 0, 3: 2, 4: 6}[c]
    raw = np.zeros((h, w * c + 1), dtype=np.uint8)
    if c == 1:
        raw[:, 1:] = img.reshape(h, w)
    else:
        raw[:, 1:] = img.reshape(h, w * c)
    comp = zlib.compress(raw.tobytes(), 6)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    blob = b"\x89PNG\r\n\x1a\n"
    blob += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
    blob += chunk(b"IDAT", comp)
    blob += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        with open(path, "rb") as fh:
            if fh.read() == blob:
                return path          # unchanged: do not touch the file
    with open(path, "wb") as fh:
        fh.write(blob)
    return path


def srgb_to_bytes(lin):
    """Linear float 0..1 -> sRGB uint8."""
    c = np.clip(lin, 0.0, 1.0)
    s = np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)
    return np.clip(s * 255.0 + 0.5, 0, 255).astype(np.uint8)


def data_to_bytes(a):
    """Linear float 0..1 -> uint8 WITHOUT the sRGB curve.

    Normal / roughness / metallic / AO maps are data, not colour: the glTF
    loader and Godot read them linearly. A flat normal is (128, 128, 255);
    writing it through srgb_to_bytes gives (188, 188, 255) and shades every
    surface as if it were tilted about 34 deg."""
    return np.clip(np.asarray(a, dtype=np.float32) * 255.0 + 0.5, 0, 255).astype(np.uint8)


def rgba_bytes(rgb_srgb_lin, alpha):
    """RGBA uint8: RGB through the sRGB curve, alpha kept LINEAR (it is a mask)."""
    rgb = srgb_to_bytes(rgb_srgb_lin)
    a = data_to_bytes(alpha)
    out = np.concatenate([rgb, a[:, :, None]], axis=2)
    return out.astype(np.uint8)


def read_png(path):
    """Minimal PNG reader (8-bit grey/RGB/RGBA, no interlace) -> uint8 array."""
    with open(path, "rb") as fh:
        blob = fh.read()
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a png: " + path)
    pos = 8
    idat = b""
    w = h = depth = ctype = 0
    while pos < len(blob):
        (ln,) = struct.unpack(">I", blob[pos:pos + 4])
        tag = blob[pos + 4:pos + 8]
        data = blob[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", data[:10])
        elif tag == b"IDAT":
            idat += data
        elif tag == b"IEND":
            break
    if depth != 8 or ctype not in (0, 2, 6):
        raise ValueError("unsupported png: %s (depth %d ctype %d)" % (path, depth, ctype))
    nch = {0: 1, 2: 3, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * nch
    out = np.zeros((h, stride), np.uint8)
    prev = np.zeros(stride, np.int32)
    p = 0
    for y in range(h):
        ft = raw[p]
        line = np.frombuffer(raw[p + 1:p + 1 + stride], np.uint8).astype(np.int32)
        p += 1 + stride
        if ft == 0:
            cur = line
        elif ft == 1:
            cur = line.copy()
            for i in range(nch, stride):
                cur[i] = (cur[i] + cur[i - nch]) & 0xFF
        elif ft == 2:
            cur = (line + prev) & 0xFF
        elif ft == 3:
            cur = line.copy()
            for i in range(stride):
                left = cur[i - nch] if i >= nch else 0
                cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            cur = line.copy()
            for i in range(stride):
                a = cur[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 0xFF
        else:
            raise ValueError("bad filter %d in %s" % (ft, path))
        out[y] = cur.astype(np.uint8)
        prev = cur
    return out.reshape(h, w, nch)


def assert_linear_normals(paths):
    """Guard: every *_nor.png must have a median R and G of 126-130 (a flat normal).

    Catches a map that was written through the sRGB curve by mistake."""
    bad = []
    for p in paths:
        img = read_png(p)
        med_r = float(np.median(img[:, :, 0]))
        med_g = float(np.median(img[:, :, 1]))
        if not (126.0 <= med_r <= 130.0 and 126.0 <= med_g <= 130.0):
            bad.append("%s median=(%.1f, %.1f)" % (os.path.basename(p), med_r, med_g))
    if bad:
        raise AssertionError("normal maps are not linear: " + "; ".join(bad))
    return len(paths)


def hexlin(code):
    """'#RRGGBB' -> linear float triple."""
    c = [int(code[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def copy_if_changed(src, dst):
    """Copy a file only when its bytes differ (the IMPORT-CHURN lead note).

    Godot re-imports every file whose mtime changes, so a rebuild must not
    touch the files that did not change."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src, "rb") as fh:
        blob = fh.read()
    if os.path.exists(dst):
        with open(dst, "rb") as fh:
            if fh.read() == blob:
                return dst
    with open(dst, "wb") as fh:
        fh.write(blob)
    return dst
