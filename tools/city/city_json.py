"""city_json — the JSON reader and writer of the city map.

The map holds ~90 000 road control points, so the point arrays are written
on one line: the pretty printer would triple the size of the file.
"""
import json


def load_json(path):
    """Read a JSON file and return the parsed object."""
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def save_json(path, data):
    """Write data as UTF-8 JSON (deterministic key order as inserted)."""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(_dump(data, 0))
        fh.write("\n")


def _dump(data, level):
    """A small JSON writer that keeps the point arrays on one line."""
    pad = " " * level
    inner = " " * (level + 1)
    if isinstance(data, dict):
        if not data:
            return "{}"
        items = []
        for key, value in data.items():
            items.append("%s%s: %s" % (inner, json.dumps(key, ensure_ascii=False),
                                       _dump(value, level + 1)))
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(data, list):
        if not data:
            return "[]"
        if all(isinstance(v, (int, float)) for v in data):
            return "[" + ", ".join(json.dumps(v) for v in data) + "]"
        if all(isinstance(v, list) and all(isinstance(n, (int, float))
                                           for n in v) for v in data):
            return "[" + ", ".join(_dump(v, level) for v in data) + "]"
        items = [inner + _dump(v, level + 1) for v in data]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(data, ensure_ascii=False)
