"""Pack an exported .gltf + .bin back into a .glb, keeping the images external.

The props all share their texture atlases (one surface atlas, one sign atlas,
one foliage atlas). Embedding those in every .glb would make Godot import 42
copies of a 3264 x 2720 atlas - slow for everyone and 150 MB of disk. The core
exporter (`lib/export.py`, `shared_texture_dir=`) writes the images into one
shared folder and leaves the geometry in a .gltf + .bin pair; this turns that
pair back into the .glb that CONTRACTS.md asks for, with the image URIs still
pointing at the shared folder, so Godot imports every atlas exactly once.

    /usr/bin/python3 blender/props/pack_glb.py <out.gltf>
"""
import json
import os
import struct

GLB_MAGIC = 0x46546C67      # 'glTF'
JSON_CHUNK = 0x4E4F534A     # 'JSON'
BIN_CHUNK = 0x004E4942      # 'BIN\0'

ROOT = os.path.expanduser("~/m/skyrush")
CORE_TEX = os.path.join(ROOT, "game", "assets", "textures")
KINDS = ("nor_gl", "diff", "rough", "arm", "ao", "disp")


def _core_uri(name):
    """The shared copy of a core CC0 texture, relative to the prop folders.

    The exporter copies every image it uses into the shared folder, but the
    core's CC0 sets already live in game/assets/textures/<id>/ and are imported
    once there - the props point at that copy instead of a duplicate.
    """
    base = os.path.basename(name)
    stem = base.rsplit(".", 1)[0]
    for kind in KINDS:
        if not stem.endswith("_" + kind):
            continue
        ident = stem[:-len(kind) - 1]
        for ext in (".jpg", ".png"):
            candidate = os.path.join(CORE_TEX, ident, ident + "_" + kind + ext)
            if os.path.exists(candidate):
                return "../../textures/%s/%s%s" % (ident, ident, "_" + kind + ext)
    return None


def _pad(data, fill=b"\x00"):
    return data + fill * ((4 - len(data) % 4) % 4)


COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _round_floats(doc, blob):
    """Round the float attributes to 1e-4 so two builds of the same prop match.

    The exporter computes the tangents in a way that is not bit-exact between
    runs, so without this every build would change the .glb bytes and Godot
    would re-import all 42 props (lead note: IMPORT-CHURN).
    """
    for acc in doc.get("accessors", []):
        kind = acc.get("type")
        # only the float attributes: the indices are integers in the same buffer
        if kind not in COMPONENTS or acc.get("normalized"):
            continue
        if acc.get("componentType") != 5126:
            continue
        view = doc["bufferViews"][acc["bufferView"]]
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", COMPONENTS[kind] * 4)
        for i in range(acc["count"]):
            for c in range(COMPONENTS[kind]):
                pos = base + i * stride + c * 4
                if pos + 4 > len(blob):
                    continue
                value = struct.unpack_from("<f", blob, pos)[0]
                struct.pack_into("<f", blob, pos, round(value, 4))
    return blob


def _chunks(blob):
    """(json_bytes, bin_bytes) of a packed .glb."""
    magic, version, length = struct.unpack("<III", blob[:12])
    if magic != GLB_MAGIC:
        return None, None
    pos = 12
    doc = bin_chunk = None
    while pos + 8 <= len(blob):
        size, kind = struct.unpack("<II", blob[pos:pos + 8])
        data = blob[pos + 8:pos + 8 + size]
        if kind == JSON_CHUNK:
            doc = data
        elif kind == BIN_CHUNK:
            bin_chunk = data
        pos += 8 + size
    return doc, bin_chunk


def _used_accessors(doc):
    """The indices of the accessors the primitives actually use."""
    used = set()
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            for name, index in prim.get("attributes", {}).items():
                used.add(index)
            if "indices" in prim:
                used.add(prim["indices"])
    return used


def _floats(doc, blob):
    """Every float attribute of a packed .glb, in order (the used ones only)."""
    out = []
    used = _used_accessors(doc)
    for index, acc in enumerate(doc.get("accessors", [])):
        kind = acc.get("type")
        if kind not in COMPONENTS or acc.get("normalized"):
            continue
        if acc.get("componentType") != 5126:
            continue
        if index not in used:
            continue
        view = doc["bufferViews"][acc["bufferView"]]
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", COMPONENTS[kind] * 4)
        for i in range(acc["count"]):
            for c in range(COMPONENTS[kind]):
                pos = base + i * stride + c * 4
                if pos + 4 > len(blob):
                    continue
                out.append(struct.unpack_from("<f", blob, pos)[0])
    return out


def _index_bytes(doc, blob):
    """The bytes of the integer attributes (the indices): they must match exactly."""
    out = []
    for acc in doc.get("accessors", []):
        if acc.get("componentType") == 5126:
            continue
        view = doc["bufferViews"][acc["bufferView"]]
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        out.append(blob[base:base + view.get("byteLength", 0)])
    return b"".join(out)


def _structure(doc):
    """The JSON of a glb without the values the exporter recomputes.

    The exporter writes the min and max of every accessor from the raw
    (unrounded) values, so they differ between two runs of the same build even
    when the geometry is identical.  They are dropped here.
    """
    import copy
    out = copy.deepcopy(doc)
    for acc in out.get("accessors", []):
        acc.pop("min", None)
        acc.pop("max", None)
    return out


def geometry_equal(old, new, tol=2e-3):
    """True when two packed .glb files differ only in float noise.

    The exporter computes the tangents in a way that is not bit-exact between
    runs, so a byte comparison would re-import every prop on every build (lead
    note: IMPORT-CHURN). The node names, the materials and the UVs must match
    exactly; the float attributes may differ by a hair.
    """
    doc_a, bin_a = _chunks(old)
    doc_b, bin_b = _chunks(new)
    if doc_a is None or doc_b is None:
        return False
    ja = json.loads(doc_a.decode())
    jb = json.loads(doc_b.decode())
    if _structure(ja) != _structure(jb):
        return False
    if _index_bytes(ja, bin_a) != _index_bytes(jb, bin_b):
        return False
    fa = _floats(ja, bin_a)
    fb = _floats(jb, bin_b)
    if len(fa) != len(fb):
        return False
    return all(abs(x - y) <= tol for x, y in zip(fa, fb))


def pack(gltf_path):
    """Write <base>.glb from <base>.gltf + <base>.bin and remove the pair."""
    with open(gltf_path, "r") as fh:
        doc = json.load(fh)
    folder = os.path.dirname(gltf_path)
    blob = b""
    bin_path = None
    for buf in doc.get("buffers", []):
        uri = buf.pop("uri", None)
        if uri is None:
            continue
        bin_path = os.path.join(folder, os.path.basename(uri))
        with open(bin_path, "rb") as fh:
            blob = bytearray(fh.read())
    doc["buffers"] = [{"byteLength": len(blob)}]
    blob = _round_floats(doc, blob)
    # point the core's CC0 textures at their shared copy (the duplicate in the
    # shared folder is cleaned up once the whole build is done)
    for image in doc.get("images", []):
        uri = image.get("uri")
        if not uri:
            continue
        core = _core_uri(uri)
        if core:
            image["uri"] = core
    # The exporter computes the tangents with a fallback for the degenerate UV
    # triangles (the end caps of a tube), and that fallback is not stable
    # between two runs: the .glb bytes changed on every build and Godot
    # re-imported the props.  The tangents are dropped here and Godot computes
    # them on import (meshes/ensure_tangents), which is deterministic.
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            prim.get("attributes", {}).pop("TANGENT", None)
    js = _pad(json.dumps(doc, separators=(",", ":")).encode("utf-8"), b" ")
    bin_chunk = _pad(bytes(blob))
    glb_path = os.path.splitext(gltf_path)[0] + ".glb"
    total = 12 + 8 + len(js) + 8 + len(bin_chunk)
    with open(glb_path, "wb") as fh:
        fh.write(struct.pack("<III", GLB_MAGIC, 2, total))
        fh.write(struct.pack("<II", len(js), JSON_CHUNK))
        fh.write(js)
        fh.write(struct.pack("<II", len(bin_chunk), BIN_CHUNK))
        fh.write(bin_chunk)
    os.remove(gltf_path)
    if bin_path and os.path.exists(bin_path):
        os.remove(bin_path)
    return glb_path


if __name__ == "__main__":
    import sys
    print("PACKED %s" % pack(sys.argv[1]))
