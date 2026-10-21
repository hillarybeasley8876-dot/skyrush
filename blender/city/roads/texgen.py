"""The texture sets of the road kit: albedo, normal and ORM for every material.

The sets are generated with numpy and written into a scratch folder; the glTF
exporter copies them into the shared city texture folder (game/assets/city/_tex),
so every tile shares ONE imported copy of each image.

Two rules from the lead's import note:
  * a file is only written when its bytes change (a rebuild that changes nothing
    must not make Godot re-import the city);
  * the small parts use 512 px and the hero surfaces 1024 px, and every map is
    at least 512 px per metre of its UV scale.

The albedo of the opaque surfaces is a neutral detail map: the real colour of
the material lives in the glTF's baseColorFactor, so a white pot is white
because the factor says so, not because the texture is white.
"""
import os

import numpy as np

from city.roads import texsets
from city.roads.texbase import BIG, SMALL, fbm, normal_from_height, orm_pack, write


def _normal_group(name):
    """The normal map of a group of surfaces."""
    if name == "leaf":
        h = fbm(SMALL, SMALL, 24, 4, 201)
        return normal_from_height(h, 3.0)
    if name == "metal":
        _rgb, _a, height, _r, _ao = texsets.steel()
        return normal_from_height(height, 2.0)
    if name == "concrete":
        _rgb, _a, height, _r, _ao = texsets.enamel()
        return normal_from_height(height, 2.5)
    if name == "pot":
        _rgb, _a, height, _r, _ao = texsets.pot()
        return normal_from_height(height, 2.0)
    _rgb, _a, height, _r, _ao = texsets.soil()
    return normal_from_height(height, 3.0)


def _orm_group(name):
    """The ORM map of a group of surfaces (R = AO, G = roughness, B = metallic)."""
    metal = 0.65 if name == "metal" else 0.0
    if name == "leaf":
        rough = np.clip(0.68 + 0.20 * fbm(SMALL, SMALL, 40, 3, 202), 0.05, 1.0)
    elif name == "metal":
        rough = np.clip(0.38 + 0.30 * fbm(SMALL, SMALL, 20, 3, 203), 0.05, 1.0)
    elif name == "concrete":
        rough = np.clip(0.32 + 0.28 * fbm(SMALL, SMALL, 16, 3, 204), 0.05, 1.0)
    elif name == "pot":
        rough = np.clip(0.44 + 0.20 * fbm(SMALL, SMALL, 16, 3, 205), 0.05, 1.0)
    else:
        rough = np.clip(0.86 + 0.10 * fbm(SMALL, SMALL, 30, 3, 206), 0.05, 1.0)
    ao = 0.82 + 0.18 * fbm(SMALL, SMALL, 8, 3, 207)
    return orm_pack(ao, rough, np.full_like(ao, metal))


# the normal and ORM group of every set
NOR_GROUP = {
    "tactile": "concrete", "pot": "pot", "soil": "soil", "leaf_boug": "leaf",
    "leaf_privet": "leaf", "ivy": "leaf", "steel": "metal", "joint": "metal",
    "enamel": "concrete", "dark": "concrete", "stripe": "concrete", "row": "leaf",
}
ORM_GROUP = dict(NOR_GROUP)

# every set: the generator of its albedo
GENERATORS = {
    "tactile": texsets.tactile,
    "pot": texsets.pot,
    "soil": texsets.soil,
    "leaf_boug": lambda: texsets.foliage((0.14, 0.30, 0.12), (0.76, 0.09, 0.36), 0.42, 61),
    "leaf_privet": lambda: texsets.foliage((0.40, 0.52, 0.12), (0.71, 0.77, 0.20), 0.10, 71),
    "ivy": texsets.ivy,
    "steel": texsets.steel,
    "joint": texsets.joint,
    "enamel": texsets.enamel,
    "dark": texsets.dark,
    "stripe": texsets.stripe,
    "row": texsets.row,
}


def build_all(out_dir):
    """Generate every texture set; returns {set: {"diff": path, "nor": path, "orm": path}}.

    The files are written into a scratch folder: the glTF exporter copies them
    into the shared city texture folder, and only the copies that changed are
    moved into the project.
    """
    os.makedirs(out_dir, exist_ok=True)
    out = {}
    normals = {}
    orms = {}
    for name, fn in GENERATORS.items():
        rgb, alpha, height, rough, ao = fn()
        suffix = ".png" if alpha is not None else ".jpg"
        diff = write(os.path.join(out_dir, "road_%s_diff%s" % (name, suffix)), rgb, alpha)
        group = NOR_GROUP[name]
        if group not in normals:
            normals[group] = write(os.path.join(out_dir, "road_nor_%s.png" % group),
                                   _normal_group(group))
        if group not in orms:
            orms[group] = write(os.path.join(out_dir, "road_orm_%s.png" % group),
                                _orm_group(group))
        out[name] = {"diff": diff, "nor": normals[group], "orm": orms[group]}
    # the tactile paving keeps the bumps of its own library normal map
    lib = os.path.join(texsets.LIBRARY_TACTILE, "TactilePaving003_nor_gl.jpg")
    nrm = texsets._load_rgb(lib, SMALL, SMALL)
    height = 1.0 - np.clip(nrm[..., 2], 0.0, 1.0)
    out["tactile"]["nor"] = write(os.path.join(out_dir, "road_nor_tactile.png"),
                                  normal_from_height(height, 2.0))
    return out


def size_m(name):
    """The world size (metres) the map of a set covers: the UV scale of a material."""
    return SET_SIZE_M.get(name, 1.0)


# the world size of every set: the map is at least 512 px per metre
SET_SIZE_M = {
    "tactile": 0.6, "pot": 0.6, "soil": 0.5, "leaf_boug": 0.5, "leaf_privet": 0.5,
    "ivy": 1.0, "steel": 1.5, "joint": 0.6, "enamel": 1.2, "dark": 2.0,
    "stripe": 0.5, "row": 9.0,
}
