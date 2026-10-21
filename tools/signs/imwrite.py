"""Write an image only when its bytes change (lead note: IMPORT-CHURN).

Godot re-imports a file when its mtime moves, so rewriting an identical
texture on every build makes the whole project re-import. These helpers keep
the mtime of unchanged files.

    from imwrite import save
    save(img, path, format="JPEG", quality=86)
"""
import io
import os


def encode(img, format=None, **opts):
    """The bytes PIL would write for `img`."""
    buf = io.BytesIO()
    if format is None:
        format = "PNG" if img.mode in ("RGBA", "LA", "P") else "JPEG"
    img.save(buf, format=format, **opts)
    return buf.getvalue()


def save(img, path, format=None, **opts):
    """Save `img` to `path` only when the bytes differ from the file on disk."""
    data = encode(img, format=format, **opts)
    if os.path.exists(path):
        with open(path, "rb") as fh:
            if fh.read() == data:
                return path
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)
    return path
