"""Smaller crown forms and facade features for the Bund buildings (bund unit)."""
from . import parts, profiles, columns


def gable(asm, yc, x0, x1, z0, width, height, mat="stone"):
    """A steep gothic gable: a pointed arch prism standing on the facade."""
    hw = width * 0.5
    asm.prism_x(mat, [(yc - hw, z0), (yc + hw, z0), (yc, z0 + height)], x0, x1)
    # a hood mould over the gable
    for sy in (-1.0, 1.0):
        asm.box(mat, ((x0 + x1) * 0.5, yc + sy * hw * 0.72, z0 + height * 0.42),
                (x1 - x0, 0.22, 0.22))


def gables(asm, s, n=3):
    """Victorian gothic gables along the facade (Commercial Bank of China)."""
    w = s["frontage"]
    for i in range(n):
        yc = -w * 0.5 + (i + 0.5) * (w / n)
        gable(asm, yc, -0.35, 0.45, s["cornice"] - 0.4, w / n * 0.62, w / n * 0.85)


def roof_towers(asm, s, n=2):
    """Two small rooftop towers with their own cornice and a cap (North China Daily News)."""
    w, d = s["frontage"], s["depth"]
    z = s["cornice"]
    th = max(3.0, min(6.0, s["height"] - s["cornice"] - 1.0))
    for i in range(n):
        yc = (-0.28 if i == 0 else 0.28) * w
        x = -d * 0.45
        asm.box("stone", (x, yc, z + th * 0.5), (6.0, 5.0, th))
        asm.prism("stone", profiles.cornice(0.7, 0.55), yc - 2.6, yc + 2.6, x_off=x + 3.0,
                  z_off=z + th)
        asm.lathe("roof", [(0.0, 0.0), (2.2, 0.0), (0.0, 2.2)], 10, (x, yc, z + th + 0.7))


def hip_low(asm, s):
    """A low hipped roof (British Consulate)."""
    w, d = s["frontage"], s["depth"]
    z = s["cornice"]
    parts.pyramid(asm.bm("roof"), (d * 0.5 + 0.6, w * 0.5 + 0.6), 3.4, 0.18, (-d * 0.5, 0.0, z))


def deco_crown(asm, s, x, y, z0):
    """The stepped Art Deco crown under the Bank of China roof (dossier 5.3)."""
    w = s["frontage"]
    for k, (sc, hh) in enumerate(((1.0, 1.0), (0.86, 0.8), (0.72, 0.7))):
        asm.gbox("stone", (x - 0.3, y, z0 + 0.4 + k * 0.8), (1.6 + 0.8 * k, w * sc, hh), 1.5)
    n = max(5, int(w / 1.6))
    for i in range(n):
        yc = -w * 0.5 + (i + 0.5) * (w / n)
        asm.box("stone", (x + 0.9, yc, z0 + 1.1), (0.5, 0.34, 2.0))


def deco_fins(asm, s):
    """Art Deco vertical fins on the facade (Bank of Communications)."""
    w = s["frontage"]
    n = max(4, int(w / 1.7))
    for i in range(n):
        yc = -w * 0.5 + (i + 0.5) * (w / n)
        asm.box("stone", (0.22, yc, (s["base_h"] + s["cornice"]) * 0.5),
                (0.44, 0.34, s["cornice"] - s["base_h"]))
    for i in range(n):
        yc = -w * 0.5 + (i + 0.5) * (w / n)
        asm.box("stone", (0.30, yc, s["cornice"] + 0.35), (0.5, 0.42, 0.7))


def attic_pediment(asm, s):
    """A central attic storey with a pediment (Asia Building)."""
    w = s["frontage"]
    aw = w * 0.34
    z = s["cornice"]
    # the attic has to fit inside the dossier height
    h = max(1.6, min(3.4, s["height"] - z - 0.8))
    asm.box("stone", (-0.4, 0.0, z + h * 0.5), (0.8, aw, h))
    for sy in (-1.0, 1.0):
        asm.box("stone", (0.1, sy * aw * 0.5, z + h * 0.55), (0.4, 0.4, h * 0.8))
    prof = profiles.pediment(aw, aw * 0.30, 0.5, 0.3)
    parts.prism(asm.bm("stone"), prof, -aw * 0.5, aw * 0.5, x_off=0.3, z_off=z + h)
    asm.box("stone", (0.05, 0.0, z + h + 0.1), (0.3, aw + 0.4, 0.2))


def balcony_run(asm, s, floors=(1,)):
    """A continuous balcony with an iron railing (Glenn Line, Palace Hotel)."""
    w = s["frontage"]
    fh = s["floor_h"]
    for f in floors:
        z = s["base_h"] + f * fh
        asm.box("stone", (0.75, 0.0, z), (1.6, w, 0.24))
        n = int(w / 1.1)
        for i in range(n + 1):
            y = -w * 0.5 + w * i / n
            columns.baluster(asm, "iron", 1.45, y, z + 0.12, 0.55, 0.055)
        asm.box("iron", (1.45, 0.0, z + 0.72), (0.08, w, 0.08))


def arcade(asm, s):
    """A ground-floor arcade of round arches (Banque de l'Indochine, Palace Hotel).

    Each bay is a round-headed pane with a ring of voussoir stones around it."""
    w = s["frontage"]
    n = max(3, int(w / 3.4))
    base_h = s["base_h"]
    r = min(1.5, w / n * 0.42)
    z_spring = base_h * 0.52
    for i in range(n):
        yc = -w * 0.5 + (i + 0.5) * (w / n)
        parts.arch_glass(asm.loose_bm("glassdark"), -0.28, yc, z_spring, r, 0.25, 10)
        parts.voussoirs(asm.bm("stone"), -0.34, 0.12, yc, z_spring, r + 0.06, 9, 0.30)
        # the pier between the arches
        asm.box("stone", (0.02, yc + w / n * 0.5, base_h * 0.5), (0.44, 0.42, base_h))
