"""Inspect an exported NPC .glb: node names, UV maps, tangents, materials.

    python3 blender/npc_cars/check_glb.py game/assets/cars/npc/*.glb

Prints one line per problem so it can be used as a build gate. Checks:
  * no duplicated contract node names
  * every TEXCOORD_n a material uses exists on its primitive
  * every primitive that uses a normal map carries tangents
  * no material is left double sided (backface culling on)
  * the node names the brief requires are present
  * the bounding box matches the size table in spec.py
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec as specs  # noqa: E402

# the brief's size table (L x W x H in metres)
SIZES = {
    "sedan_ev": (1.90, 1.47, 4.85), "suv_ev": (1.93, 1.68, 4.75),
    "hatch_ev": (1.77, 1.55, 3.95), "taxi": (1.90, 1.63, 4.85),
    "robotaxi": (1.90, 1.55, 4.20), "van": (2.00, 2.10, 5.30),
    "truck": (2.35, 3.30, 7.50), "bus": (2.55, 3.20, 12.00),
    "police_patrol": (1.90, 1.50, 4.85),
    "police_interceptor": (1.98, 1.25, 4.70),
    "police_suv": (2.10, 1.95, 5.20), "police_drone": (1.60, 0.40, 1.60),
}
REQUIRED = {
    "sedan_ev": ["Body", "Glass", "Bumper_F", "Bumper_R", "Lamp_F", "Lamp_R",
                 "Light_Front", "Light_Rear", "Wheel_FL", "Wheel_FR",
                 "Wheel_RL", "Wheel_RR", "Hood", "Door_FL", "Door_FR",
                 "Door_RL", "Door_RR"],
    "police_patrol": ["LightBar", "LightBar_Red", "LightBar_Blue", "Siren"],
    "police_interceptor": ["LightBar_Red", "LightBar_Blue", "Siren"],
    "police_suv": ["LightBar_Red", "LightBar_Blue", "Siren"],
    "taxi": ["RoofSign", "RoofSignFace"],
    "robotaxi": ["LiDAR", "Door_FL", "Door_FR"],
    "van": ["Cab", "Door_FL", "Door_FR", "Livery"],
    "truck": ["Cab", "Door_FL", "Door_FR"],
    "bus": ["Roof", "SignRoute", "SignRouteSide", "Door_FR", "Door_RR"],
    "police_drone": ["Spot", "Strobe_Red", "Strobe_Blue", "Rotor_FL",
                     "Rotor_FR", "Rotor_RL", "Rotor_RR"],
}


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, "not a glb"
    offset = 12
    gltf = None
    while offset < length:
        chunk_len, chunk_type = struct.unpack("<II", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:
            gltf = json.loads(body.decode("utf-8"))
        offset += 8 + chunk_len + (-chunk_len % 4)
    return gltf


def material_texcoords(mat):
    """The TEXCOORD indices every texture of a material reads."""
    used = set()
    for value in mat.values():
        if isinstance(value, dict) and "texCoord" in value:
            used.add(value["texCoord"])
    return used


def has_normal_map(mat):
    return "normalTexture" in mat


def check(path):
    """Return the list of problems of one glb."""
    gltf = read_glb(path)
    name = os.path.basename(path)[:-4]
    materials = gltf.get("materials", [])
    meshes = gltf.get("meshes", [])
    nodes = [n.get("name", "") for n in gltf.get("nodes", [])]
    issues = []
    counts = {}
    for n in nodes:
        counts[n] = counts.get(n, 0) + 1
    for key, value in counts.items():
        if value > 1 and key:
            issues.append("duplicate node name %r (%d)" % (key, value))
    for node in REQUIRED.get(name, []):
        if node not in counts:
            issues.append("missing the contract node %r" % node)
    for mesh in meshes:
        for prim in mesh.get("primitives", []):
            attrs = prim.get("attributes", {})
            index = prim.get("material")
            mat = materials[index] if index is not None else None
            if mat is None:
                issues.append("%s: a primitive has no material" % mesh.get("name"))
                continue
            for tex_coord in material_texcoords(mat):
                if "TEXCOORD_%d" % tex_coord not in attrs:
                    issues.append("%s: %s reads TEXCOORD_%d but the primitive "
                                  "has no such attribute"
                                  % (mesh.get("name"), mat.get("name"), tex_coord))
            if has_normal_map(mat) and "TANGENT" not in attrs:
                issues.append("%s: %s has a normal map but no tangents"
                              % (mesh.get("name"), mat.get("name")))
            if mat.get("doubleSided", False) and mat.get("alphaMode") != "BLEND":
                issues.append("%s: %s is double sided"
                              % (mesh.get("name"), mat.get("name")))
    want = SIZES.get(name)
    if want:
        # the glTF is Y-up: x is the width, y the height, z the length
        # the width of the brief is the width of the body; the box vehicles
        # add their mirror arms on top of it
        wide = 0.60 if name in ("bus", "van", "truck") else 0.30
        lo, hi = bounds(gltf, skip=("Mirror_L", "Mirror_R", "MirrorGlass_L",
                                    "MirrorGlass_R", "MirrorLamp_L",
                                    "MirrorLamp_R"))
        size = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
        for i, (axis, tol) in enumerate((("width", wide), ("height", 0.12),
                                         ("length", 0.10))):
            if abs(size[i] - want[i]) > tol:
                issues.append("the %s is %.2f (the brief says %.2f)"
                              % (axis, size[i], want[i]))
    return issues, len(meshes), count_prims(meshes)


def count_prims(meshes):
    return sum(len(m.get("primitives", [])) for m in meshes)


def bounds(gltf, skip=()):
    """The bounding box of the file, with the node transforms applied.

    `skip` holds the node names that are left out (the mirrors stick out on
    purpose, but the width of the brief is the width of the body).
    """
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    found = False
    for node in gltf.get("nodes", []):
        if "mesh" not in node:
            continue
        if node.get("name", "") in skip:
            continue
        matrix = node.get("matrix")
        xform = matrix_to_list(matrix) if matrix else \
            translation_scale(node.get("translation"), node.get("scale"))
        mesh = gltf["meshes"][node["mesh"]]
        for prim in mesh.get("primitives", []):
            index = prim.get("attributes", {}).get("POSITION")
            if index is None:
                continue
            acc = gltf["accessors"][index]
            if "min" not in acc:
                continue
            found = True
            for cx in (acc["min"][0], acc["max"][0]):
                for cy in (acc["min"][1], acc["max"][1]):
                    for cz in (acc["min"][2], acc["max"][2]):
                        p = transform(xform, cx, cy, cz)
                        for i in range(3):
                            lo[i] = min(lo[i], p[i])
                            hi[i] = max(hi[i], p[i])
    return (lo, hi) if found else (None, None)


def matrix_to_list(matrix):
    """A glTF column-major matrix as a row-major 4x4 list."""
    return [[matrix[c * 4 + r] for c in range(4)] for r in range(4)]


def translation_scale(translation, scale):
    """A matrix for a node with only a translation and a scale."""
    t = translation or [0.0, 0.0, 0.0]
    s = scale or [1.0, 1.0, 1.0]
    return [[s[0], 0.0, 0.0, t[0]],
            [0.0, s[1], 0.0, t[1]],
            [0.0, 0.0, s[2], t[2]],
            [0.0, 0.0, 0.0, 1.0]]


def transform(m, x, y, z):
    """A point through a row-major 4x4 matrix."""
    return [m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
            m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
            m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3]]


def main():
    problems = 0
    for path in sys.argv[1:]:
        issues, meshes, prims = check(path)
        name = os.path.basename(path)
        print("%-28s meshes=%d prims=%d %s"
              % (name, meshes, prims, "OK" if not issues else "PROBLEMS"))
        for issue in issues:
            print("   - %s" % issue)
        problems += len(issues)
    print("total problems: %d" % problems)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
