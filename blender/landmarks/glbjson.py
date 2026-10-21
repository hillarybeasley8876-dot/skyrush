"""Inspect a .glb: material textures, alpha modes, emissive, image sizes.

    python3 tmp/landmarks/lm_glbjson.py game/assets/landmarks/*.glb
"""
import json
import struct
import sys


def read_glb(path):
    with open(path, "rb") as fh:
        blob = fh.read()
    magic, ver, length = struct.unpack("<III", blob[:12])
    assert magic == 0x46546C67, "not a glb"
    pos = 12
    js = None
    while pos < length:
        clen, ctype = struct.unpack("<II", blob[pos:pos + 8])
        data = blob[pos + 8:pos + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(data.decode("utf-8"))
        pos += 8 + clen
        pos += (4 - pos % 4) % 4
    return js


def report(path):
    js = read_glb(path)
    print("=== %s" % path)
    imgs = js.get("images", [])
    print("  images: %d" % len(imgs))
    for i, im in enumerate(imgs):
        print("    [%d] %s %s" % (i, im.get("name", "?"), im.get("mimeType", "")))
    mats = js.get("materials", [])
    for m in mats:
        pbr = m.get("pbrMetallicRoughness", {})
        tex = pbr.get("metallicRoughnessTexture")
        occ = m.get("occlusionTexture")
        norm = m.get("normalTexture")
        base = pbr.get("baseColorTexture")
        emi = m.get("emissiveTexture")
        em = m.get("emissiveFactor")
        parts = []
        if base:
            parts.append("base=%d" % base["index"])
        if tex:
            parts.append("orm=%d" % tex["index"])
        if norm:
            parts.append("normal=%d" % norm["index"])
        if occ:
            parts.append("AO=%d str=%s" % (occ["index"], occ.get("strength", 1.0)))
        if emi:
            parts.append("emit=%d" % emi["index"])
        if em:
            parts.append("emissive=%s" % [round(v, 3) for v in em])
        print("  mat %-26s alpha=%-7s %s" % (m.get("name", "?"),
                                            m.get("alphaMode", "OPAQUE"), " ".join(parts)))
    meshes = js.get("meshes", [])
    for me in meshes:
        tris = 0
        for pr in me.get("primitives", []):
            idx = pr.get("indices")
            if idx is None:
                tris += len(pr["attributes"]["POSITION"].split(","))
            else:
                tris += js["accessors"][idx]["count"]
        print("  mesh %-34s tris=%d" % (me.get("name", "?"), tris // 3))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
