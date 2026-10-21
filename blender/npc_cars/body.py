"""Detail fitting for the NPC fleet (unit: npc_cars).

The bodies come from the shared generator (`lib/car_body.py`); this module
fits everything that sits on the skin: the door panels, the head and tail
lamps, the grille, the plates, the bumpers and the mirrors.

Every panel is fitted by ray-casting the finished body, so it follows the real
curvature: nothing floats off the car and nothing hides behind a fascia.
"""
import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from lib import common, uv

from . import atlas, meshutil

ARCH_MARGIN = 0.045       # gap between the tyre and the arch cut-out
PANEL_PROUD = 0.0025      # a detachable panel stands 2.5 mm proud of the skin
INNER_GAP = 0.024         # the dark inner surface behind a panel
DOOR_GAP = 0.0025         # the shut line around a door


# ---------------------------------------------------------------- surfaces


def body_bvh(body):
    """Ray-cast tree of the finished body shell."""
    deps = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(body, deps)


def sample_surface(bvh, origin, direction, fallback):
    """One surface sample: (point, normal). Falls back to a flat guess."""
    loc, nor, _, _ = bvh.ray_cast(Vector(origin), Vector(direction))
    if loc is None:
        return Vector(fallback[0]), Vector(fallback[1]).normalized()
    # the ray hit can wobble in the last bits between two builds; rounding
    # keeps the exported .glb byte identical (the import churn)
    return (Vector((round(loc.x, 5), round(loc.y, 5), round(loc.z, 5))),
            Vector((round(nor.x, 4), round(nor.y, 4), round(nor.z, 4))))


def flank_grid(bvh, side, y0, y1, z0_fn, z1_fn, ny=8, nz=5):
    """Sample the flank of the body: rows of (point, normal) for one side."""
    out = []
    direction = Vector((-side, 0.0, 0.0))
    for i in range(ny + 1):
        y = y0 + (y1 - y0) * i / ny
        z0, z1 = z0_fn(y), z1_fn(y)
        row = []
        for j in range(nz + 1):
            z = z0 + (z1 - z0) * j / nz
            row.append(sample_surface(bvh, (side * 3.0, y, z), direction,
                                      ((side * 0.9, y, z), (side, 0.0, 0.0))))
        out.append(row)
    return out


def end_grid(bvh, front, x0, x1, z0, z1, nx=12, nz=4, limit=1.0):
    """Sample the nose or the tail: a grid of (point, normal)."""
    out = []
    direction = Vector((0.0, -1.0 if front else 1.0, 0.0))
    y0 = 4.0 if front else -4.0
    for i in range(nx + 1):
        x = x0 + (x1 - x0) * i / nx
        row = []
        for j in range(nz + 1):
            z = z0 + (z1 - z0) * j / nz
            fb_x = max(-limit, min(limit, x))
            row.append(sample_surface(bvh, (x, y0, z), direction,
                                      ((fb_x, y0 * 0.4, z),
                                       (0.0, 1.0 if front else -1.0, 0.0))))
        out.append(row)
    return out


def top_grid(bvh, x_half, y0, y1, nx=6, ny=8):
    """Sample the upper surface (bonnet, roof): a grid of (point, normal)."""
    out = []
    for i in range(ny + 1):
        y = y0 + (y1 - y0) * i / ny
        hw = x_half(y) if callable(x_half) else x_half
        row = []
        for j in range(nx + 1):
            x = -hw + 2.0 * hw * j / nx
            loc, nor = sample_surface(bvh, (x, y, 4.0), (0.0, 0.0, -1.0),
                                      ((x, y, 1.0), (0.0, 0.0, 1.0)))
            if nor.z < 0.5:
                loc, nor = Vector((x, y, loc.z)), Vector((0.0, 0.0, 1.0))
            row.append((loc, nor))
        out.append(row)
    return out


def shell(name, grid, col, outer_mat, inner_mat, proud=PANEL_PROUD,
          depth=INNER_GAP, uv_rect=None, uv_size=1024, flip_u=False,
          split_mat=None, split_z=None):
    """A closed panel shell: the outer skin (proud of the body) and its back.

    `grid` is a rectangular array of (point, normal) samples. The result is a
    solid with a real thickness, so the detachable panel keeps the body's
    curvature and shows a shut line.  The back of the panel is the dark inner
    surface (material slot 1).

    `uv_rect` (x0, y0, x1, y1 in pixels of an atlas) maps the outer skin onto
    one rectangle of a shared sheet; without it the shell gets metre UVs for
    the tiling detail textures.  `flip_u` mirrors the rectangle: a front
    facing plate has to be mirrored, because the viewer of a -Z face sees
    +X on their left.
    """
    rows = len(grid)
    cols = len(grid[0])
    bm = bmesh.new()
    outer = [[bm.verts.new(tuple(loc + nor * proud)) for loc, nor in row] for row in grid]
    inner = [[bm.verts.new(tuple(loc - nor * depth)) for loc, nor in row] for row in grid]
    outer_faces = []
    for i in range(rows - 1):
        for j in range(cols - 1):
            f = bm.faces.new((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1],
                              outer[i][j + 1]))
            f.material_index = 0
            outer_faces.append(f)
            f = bm.faces.new((inner[i][j], inner[i][j + 1], inner[i + 1][j + 1],
                              inner[i + 1][j]))
            f.material_index = 1 if inner_mat is not None else 0
    rim = ([(0, j) for j in range(cols)] + [(i, cols - 1) for i in range(1, rows)] +
           [(rows - 1, j) for j in range(cols - 2, -1, -1)] +
           [(i, 0) for i in range(rows - 2, 0, -1)])
    for k in range(len(rim) - 1):
        a, b = rim[k], rim[k + 1]
        f = bm.faces.new((outer[a[0]][a[1]], outer[b[0]][b[1]],
                          inner[b[0]][b[1]], inner[a[0]][a[1]]))
        f.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if split_mat is not None:
        # the lower band of the panel wears its own material (the taxi skirt)
        for f in outer_faces:
            if f.calc_center_median().z < split_z:
                f.material_index = 2
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    common.link(obj, col)
    mesh.materials.append(outer_mat)
    if inner_mat is not None:
        mesh.materials.append(inner_mat)
    if split_mat is not None:
        mesh.materials.append(split_mat)
    if uv_rect is None:
        uv.box_uv(obj)
    else:
        _uv_rect_grid(obj, grid, uv_rect, uv_size, flip_u)
    meshutil.shade_smooth(obj, 40.0)
    return obj


def _uv_rect_grid(obj, grid, rect, size, flip_u=False):
    """Map a shell's outer skin onto one rectangle of a shared atlas."""
    u0, v0, u1, v1 = atlas.uv_rect(rect, size)
    rows = len(grid)
    cols = len(grid[0])
    layer = obj.data.uv_layers.get("UVMap") or obj.data.uv_layers.new(name="UVMap")
    n_outer = rows * cols
    for poly in obj.data.polygons:
        for li in poly.loop_indices:
            vi = obj.data.loops[li].vertex_index
            if vi >= n_outer:
                layer.data[li].uv = (u0, v0)
                continue
            i, j = divmod(vi, cols)
            u = u0 + (u1 - u0) * (i / max(1, rows - 1))
            if flip_u:
                u = u1 - (u1 - u0) * (i / max(1, rows - 1))
            layer.data[li].uv = (u, v0 + (v1 - v0) * (j / max(1, cols - 1)))
    return obj


# ---------------------------------------------------------------- panels


def door_z(pr, y):
    """The belt line of the door at y (the top edge of the panel)."""
    return pr.belt_z(y) + 0.012


def build_doors(pr, bvh, col, mats, spec):
    """The four doors: panels fitted to the flank, with a dark inner surface."""
    out = []
    for idx, (a, b) in enumerate(spec["doors"]):
        y0, y1 = a - DOOR_GAP, b + DOOR_GAP
        for side, tag in ((-1, "L"), (1, "R")):
            grid = flank_grid(
                bvh, side, y0, y1,
                lambda y: pr.floor_z(y) + 0.20,
                lambda y: door_z(pr, y), ny=8, nz=5)
            name = "Door_%s%s" % ("F" if idx == 0 else "R", tag)
            panel = shell(name, grid, col, mats["paint"], None,
                          split_mat=mats.get("skirt"), split_z=spec.get("skirt_z"))
            meshutil.bevel(panel, 0.006, 2, 50.0)
            uv.box_uv(panel)
            out.append(panel)
            inner = shell("Inner_" + name, grid, col, mats["inner"], None,
                          proud=-INNER_GAP + 0.002, depth=0.002)
            uv.box_uv(inner)
            out.append(inner)
    return out


def build_hood(pr, bvh, col, mats, spec):
    """The bonnet: a panel fitted to the upper surface (no bonnet on a pod)."""
    y_cowl = spec["cowl_y"]
    y_nose = spec["L"] * 0.5 - 0.42
    if y_nose - y_cowl < 0.25:
        return []
    def x_half(y):
        return pr.half_width(y) * 0.63
    grid = top_grid(bvh, x_half, y_cowl + 0.02, y_nose, nx=6, ny=6)
    panel = shell("Hood", grid, col, mats["paint"], None)
    meshutil.bevel(panel, 0.006, 2, 50.0)
    uv.box_uv(panel)
    inner = shell("Inner_Hood", grid, col, mats["inner"], None,
                  proud=-INNER_GAP + 0.002, depth=0.002)
    uv.box_uv(inner)
    return [panel, inner]


def add_livery_uv(obj, spec):
    """Second UV map for the livery sheet (a side projection in metres).

    u = (y - door_y + span/2) / span with span = length + 0.1 m, mirrored
    about the front door on the -X flank, so the door text lands on the front
    door of both sides. v = z / 2 m.
    """
    span = spec["L"] + 0.1
    doors = spec.get("doors") or [(0.0, 0.0)]
    door = 0.5 * (doors[0][0] + doors[0][1])
    me = obj.data
    layer = me.uv_layers.get("UV1") or me.uv_layers.new(name="UV1")
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            u = (v.y - door + span * 0.5) / span
            if v.x < 0.0:
                u = 1.0 - u
            layer.data[li].uv = (u, v.z / 2.0)
    return obj
