"""Atlas helpers shared by the sign, prop, cloth and interior sheets."""
import json
import os


def slot(w, h, x0, y0, cw, ch):
    """UV rect of an atlas cell, flipped for Blender's bottom-left origin."""
    u0 = x0 / float(w)
    u1 = (x0 + cw) / float(w)
    v1 = 1.0 - y0 / float(h)
    v0 = 1.0 - (y0 + ch) / float(h)
    assert 0.0 <= u0 <= u1 <= 1.0 and 0.0 <= v0 <= v1 <= 1.0, "slot outside the atlas"
    return (round(u0, 6), round(v0, 6), round(u1, 6), round(v1, 6))


def grid_cells(count, cols, rows):
    """(index, x0, y0) of every cell of a cols x rows atlas, in reading order."""
    for i in range(count):
        if i >= cols * rows:
            return
        yield i, (i % cols), (i // cols)


def write_manifest(out_dir, name, entries):
    """Write the cell manifest of an atlas next to it."""
    path = os.path.join(out_dir, name + ".json")
    with open(path, "w") as fh:
        json.dump(entries, fh, ensure_ascii=False, indent=1)
    return path
