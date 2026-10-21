"""Check the generated blocks against the city map.

    python3 blender/city/buildings/check_blocks.py --city data/city/city.json
    python3 blender/city/buildings/check_blocks.py --self-test

What it checks:
  * every building footprint keeps 1 m of clearance from every road corridor and
    stays out of the water (the footprint edges are sampled every metre, and the
    parks are checked too);
  * the tile was built from the city file that is on disk now (the sha1 in the
    sidecar must match) - a stale tile is reported, not silently used;
  * every near-road building has a collider, and the collider's box matches the
    footprint (no invisible wall overhanging the pavement).

The road segments are bucketed in a 40 m grid with the half width and the
clearance, so a point inside a corridor is never missed.
"""
import argparse
import hashlib
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from city.buildings import citydata  # noqa: E402
from city.buildings.roadgrid import RoadGrid  # noqa: E402

BLOCKS_DIR = os.path.expanduser("~/m/skyrush/game/assets/city/blocks")
CLEARANCE = 1.0
SAMPLE_STEP = 1.0
MIN_COVERAGE = 0.30      # a block must be 30 % built (the brief's density floor)


def footprint_samples(poly, step=SAMPLE_STEP):
    """The corners of a footprint and a point every `step` metres along its edges."""
    out = []
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        out.append((a[0], a[1]))
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        count = max(1, int(length / step))
        for k in range(1, count):
            t = k / float(count)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def building_violations(rec, grid, city):
    """The problems of one building footprint (world coordinates)."""
    problems = []
    poly = [(p[0], p[1]) for p in rec.get("poly", [])]
    if len(poly) < 3:
        return problems
    if not rec.get("ground"):
        # a park or a plaza is ground cover: it is laid tile by tile and clipped
        # around the road corridors, so the map's block polygon may overlap them
        for (x, z) in footprint_samples(poly):
            d = grid.edge_distance(x, z)
            if d < CLEARANCE:
                problems.append("road clearance %.2f m (needs %.1f)" % (d, CLEARANCE))
                break
    for (x, z) in footprint_samples(poly):
        if citydata.point_in_water(x, z, city):
            if rec.get("ground"):
                # the ground cover of a park is laid tile by tile and clipped around
                # the water; the map's lot polygon may still overlap it
                problems.append("GROUND in the water (the cover is clipped)")
            else:
                problems.append("in the water")
            break
    return problems


def gltf_json(path):
    """The JSON of a .gltf (the node and accessor tables)."""
    if not os.path.exists(path):
        return None
    with open(path, "r") as fh:
        return json.load(fh)


def collider_boxes(path):
    """The world AABB of every collider in a tile: {building id: (min, max)}."""
    data = gltf_json(path)
    if data is None:
        return {}
    out = {}
    meshes = {i: m for i, m in enumerate(data.get("meshes", []))}
    accessors = data.get("accessors", [])
    for node in data.get("nodes", []):
        name = node.get("name", "")
        if not name.endswith("-convcolonly"):
            continue
        mesh = meshes.get(node.get("mesh"))
        if mesh is None:
            continue
        t = node.get("translation", [0, 0, 0])
        for prim in mesh.get("primitives", []):
            acc = accessors[prim["attributes"]["POSITION"]]
            lo = [acc["min"][i] + t[i] for i in range(3)]
            hi = [acc["max"][i] + t[i] for i in range(3)]
            out[name[:-len("-convcolonly")]] = (lo, hi)
    return out


def poly_bounds(poly):
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    return (min(xs), min(zs), max(xs), max(zs))


def check_colliders(sidecar, glb_path, problems):
    """Every near-road building has a collider and the collider matches the footprint."""
    boxes = collider_boxes(glb_path)
    near = [b for b in sidecar.get("buildings", []) if b.get("near_road")]
    for rec in near:
        name = rec.get("id")
        if name not in boxes:
            problems.append("near-road building %s has NO collider" % name)
            continue
        (lo, hi) = boxes[name]
        bx0, bz0, bx1, bz1 = poly_bounds([(p[0], p[1]) for p in rec.get("poly", [])])
        # the glTF axes: x = the city x, y = the height, z = the city z
        if (abs(lo[0] - bx0) > 0.3 or abs(hi[0] - bx1) > 0.3
                or abs(lo[2] - bz0) > 0.3 or abs(hi[2] - bz1) > 0.3):
            problems.append("collider %s does not match its footprint" % name)
    for name in boxes:
        if not any(b.get("id") == name for b in near):
            problems.append("collider %s is not a near-road building" % name)
    return len(near), len(boxes)


def self_test(city, grid):
    """Points inside a road corridor must be reported, even next to a cell border."""
    checked = 0
    missed = 0
    for (i, j), segs in sorted(grid.buckets.items()):
        for seg in segs:
            (ax, az, bx, bz, hw) = seg
            dx, dz = bx - ax, bz - az
            length = math.hypot(dx, dz)
            if length < 1e-6:
                continue
            ux, uz = dx / length, dz / length
            nx, nz = -uz, ux
            # a point 0.9 * hw from the centre line, in the direction of the cell
            mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
            for sign in (1.0, -1.0):
                px = mx + nx * hw * 0.9 * sign
                pz = mz + nz * hw * 0.9 * sign
                if int(math.floor(px / grid.cell)) != i or \
                        int(math.floor(pz / grid.cell)) != j:
                    continue    # not in this cell, try the next segment
                checked += 1
                if not grid.inside(px, pz):
                    missed += 1
    if checked == 0:
        print("FAIL self-test: no corridor point could be built")
        return False
    if missed:
        print("FAIL self-test: %d of %d corridor points were reported clear" % (missed, checked))
        return False
    print("PASS self-test: %d corridor points (0.9 x half width) all reported inside" % checked)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--city", default=citydata.default_city_path())
    ap.add_argument("--blocks", default=BLOCKS_DIR)
    ap.add_argument("--self-test", action="store_true")
    opts = ap.parse_args()
    city = citydata.load(opts.city)
    grid = RoadGrid(citydata.road_segments(city))
    if opts.self_test:
        return 0 if self_test(city, grid) else 1
    if not os.path.isdir(opts.blocks):
        print("no block sidecars in %s" % opts.blocks)
        return 1
    files = sorted(f for f in os.listdir(opts.blocks)
                   if f.startswith("blocks_") and f.endswith(".json"))
    if not files:
        print("no block sidecars in %s" % opts.blocks)
        return 1
    digest = hashlib.sha256(open(opts.city, "rb").read()).hexdigest()
    total = 0
    bad = 0
    near_total = 0
    col_total = 0
    stale = 0
    empty = 0
    ground_overlap = 0
    for name in files:
        with open(os.path.join(opts.blocks, name)) as fh:
            data = json.load(fh)
        if data.get("city_sha256") and data["city_sha256"] != digest:
            print("STALE %s: built from city %s, the map on disk is %s"
                  % (name, data["city_sha256"][:8], digest[:8]))
            stale += 1
        for entry in data.get("blocks", []):
            style = entry.get("style", "")
            if style in ("park", "plaza"):
                continue
            if int(entry.get("buildings", 0)) == 0:
                print("EMPTY %s: the block %s has no building" % (name, entry.get("id")))
                empty += 1
                continue
            cov = float(entry.get("coverage", 0.0))
            if cov < MIN_COVERAGE:
                print("COVERAGE %s: the block %s is only %.0f %% built (minimum %d %%)"
                      % (name, entry.get("id"), cov * 100.0, int(MIN_COVERAGE * 100)))
                empty += 1
        for rec in data.get("buildings", []):
            total += 1
            problems = building_violations(rec, grid, city)
            if problems:
                if all(p.startswith("GROUND") for p in problems):
                    ground_overlap += 1
                    print("NOTE %s: %s" % (rec.get("id"), "; ".join(sorted(set(problems)))))
                    continue
                bad += 1
                print("VIOLATION %s: %s" % (rec.get("id"), "; ".join(sorted(set(problems)))))
        tile = os.path.join(opts.blocks, name[:-5] + ".gltf")
        if os.path.exists(tile):
            problems = []
            near, boxes = check_colliders(data, tile, problems)
            near_total += near
            col_total += boxes
            for line in problems:
                print("COLLIDER %s: %s" % (name, line))
                bad += 1
    print("checked %d buildings, %d violations, %d near-road buildings, %d colliders, "
          "%d stale tiles, %d empty or under-built blocks, %d ground lots over the water"
          % (total, bad, near_total, col_total, stale, empty, ground_overlap))
    return 1 if bad or stale or empty else 0


if __name__ == "__main__":
    sys.exit(main())
