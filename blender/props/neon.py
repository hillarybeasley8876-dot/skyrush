"""Neon and hologram props for the SKYRUSH props unit.

Art dossier §4.5 (neon tubes with a darker unlit backing and mounting brackets)
and §4.6 (holographic billboards: additive, scanlines, never fully opaque).
"""
import math

import bmesh

from . import kit, materials as M

DARK = "steel_dark"


def neon_blade_frame():
    """A vertical blade sign on a facade: dark backing, neon tube border and letters."""
    p = kit.Prop("NeonBladeFrame")
    w, h = 1.20, 4.00
    p.box("Backing", (0.0, 0.06, h * 0.5), (w, 0.10, h), M.surface(), bevel=0.02,
          surface=DARK)
    p.box("Bracket", (0.0, 0.18, h * 0.22), (w * 0.8, 0.16, 0.08), M.surface(),
          bevel=0.01, surface=DARK)
    p.box("Bracket2", (0.0, 0.18, h * 0.78), (w * 0.8, 0.16, 0.08), M.surface(),
          bevel=0.01, surface=DARK)
    p.quad("Face", w - 0.10, h - 0.12, M.sign_lit(), (0.0, 0.005, h * 0.5),
           board="neon_blade")
    neon = M.neon((1.0, 0.17, 0.84))
    for sx in (-w * 0.5 + 0.05, w * 0.5 - 0.05):
        p.tube("Tube%d" % int(sx > 0), (sx, -0.02, 0.08), (sx, -0.02, h - 0.08), 0.035,
               neon, segments=6)
    p.tube("TubeTop", (-w * 0.5 + 0.05, -0.02, h - 0.08), (w * 0.5 - 0.05, -0.02, h - 0.08),
           0.035, neon, segments=6)
    p.empty("Light", (0.0, -0.20, h * 0.5), direction=(0.0, -1.0, 0.0), size=0.3)
    return p.finalize("NeonBladeFrame")


def hologram_projector():
    """A kerbside hologram projector: a pylon unit throwing a volumetric cone."""
    p = kit.Prop("HologramProjector")
    p.box("Base", (0.0, 0.0, 0.09), (0.56, 0.56, 0.18), M.surface(), bevel=0.02,
          surface=DARK)
    p.cyl("Pylon", (0.0, 0.0, 0.62), 0.13, 0.90, M.surface(), segments=12, r2=0.11,
          surface=DARK)
    p.box("Head", (0.0, 0.0, 1.12), (0.36, 0.30, 0.26), M.surface(), bevel=0.02,
          surface=DARK)
    p.cyl("Lens", (0.0, -0.16, 1.12), 0.10, 0.04, M.hologram(), axis="Y", segments=14)
    p.cyl("Collar", (0.0, 0.0, 1.00), 0.16, 0.05, M.surface(), segments=12,
          surface="alu")
    bm = bmesh.new()
    kit.add_quad(bm, 2.20, 1.60, (0.0, -0.95, 1.12), (math.radians(74.0), 0.0, 0.0))
    p.mesh("Cone", bm, M.hologram(), box_map=False)
    p.quad("Screen", 1.10, 0.78, M.sign_lit(), (0.0, -0.155, 1.30),
           board="projector_screen")
    p.empty("Light", (0.0, -0.40, 1.05), direction=(0.0, -1.0, -0.25), size=0.3)
    return p.finalize("HologramProjector")


BUILDERS = {
    "neon_blade_frame": neon_blade_frame,
    "hologram_projector": hologram_projector,
}
