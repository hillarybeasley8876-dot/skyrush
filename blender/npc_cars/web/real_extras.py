"""The parts the converter adds to a car: the police look (the 天巡 SKYPOL livery cut into the body, the light bar, the
Siren, the push bar of the heavy SUV), the roof sign of the taxi, the roof LiDAR of the robotaxi and the dark plates behind
a lattice grille.

The police livery follows ref/art/DOSSIER.md 4.8: a white body (SH_car_paint_police), a navy (#1B2A4E) band along the lower
doors and a yellow (#F5C400) pinstripe above it that runs to the rear. The band is not a texture: the flanks of the Body are
cut along the edges of the band and the faces between the cuts wear the navy or the yellow material. No emblem, no text.

The light bar is two lenses on a black base: LightBar_Red (the left half) and LightBar_Blue (the right half) are one material
each (the police unit duplicates surface 0 of each to drive the strobe); the base and its feet are joined to the Body, whose
police black they share (no draw call of their own).
"""
import bmesh
import bpy
import numpy as np
from mathutils import Vector

import real_mesh as rm

BAND_HEIGHT = 0.45      # m, the navy band (dossier 4.8)
STRIPE_HEIGHT = 0.03    # m, the yellow pinstripe
STRIPE_GAP = 0.025      # m, between the band and the stripe
BELT_GAP = 0.13         # m, between the top of the band and the lower edge of the side windows
ARCH_GAP = 0.06         # m, between the band and a wheel arch
FLANK = 0.35            # a face whose normal has |x| above this is on a flank


def axles(parts):
    """{'F': (y, radius), 'R': (y, radius)} from the wheel nodes."""
    out = {}
    for key, name in (("F", "Wheel_FL"), ("R", "Wheel_RL")):
        ob = parts[name]
        lo, hi = rm.bounds_of(rm.vertices(ob.data))
        out[key] = (ob.location.y, (hi[2] - lo[2]) * 0.5)
    return out


def belt(parts):
    """The height of the lower edge of the side windows."""
    me = parts["Glass"].data
    co = rm.vertices(me)
    n = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("normal", n)
    n = n.reshape(-1, 3)
    side = [p for p in me.polygons if abs(n[p.index][0]) > 0.5]
    if not side:
        return float(co[:, 2].min())
    return float(min(co[v][2] for p in side for v in p.vertices))


def livery(parts, material_for):
    """Cuts the navy band and the yellow pinstripe into the flanks of the Body."""
    body = parts["Body"]
    me = body.data
    ax = axles(parts)
    top = belt(parts)
    band_y = (ax["R"][0] + ax["R"][1] + ARCH_GAP, ax["F"][0] - ax["F"][1] - ARCH_GAP)
    lo_body, hi_body = rm.bounds_of(rm.vertices(me))
    stripe_y = (lo_body[1] + 0.04, band_y[1])
    band_hi = top - BELT_GAP
    paint = next(i for i, m in enumerate(me.materials) if m.name.startswith("SH_car_paint"))
    me.materials.append(material_for("navy"))
    navy = len(me.materials) - 1
    me.materials.append(material_for("yellow"))
    yellow = len(me.materials) - 1
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    # the sill: the lowest flank of the doors
    door = [f for f in bm.faces if f.material_index == paint and abs(f.normal.x) > FLANK
            and band_y[0] < f.calc_center_median().y < band_y[1]]
    sill = float(np.percentile([f.calc_center_median().z for f in door], 2)) if door else 0.3
    band_lo = max(band_hi - BAND_HEIGHT, sill + 0.03)
    stripe_lo = band_hi + STRIPE_GAP
    stripe_hi = stripe_lo + STRIPE_HEIGHT

    def zone():
        return [f for f in bm.faces if abs(f.normal.x) > FLANK and band_lo - 0.2 < f.calc_center_median().z < stripe_hi + 0.2]

    for axis, value in ((2, band_lo), (2, band_hi), (2, stripe_lo), (2, stripe_hi), (1, band_y[0]), (1, band_y[1]),
                        (1, stripe_y[0])):
        faces = zone()
        verts = list({v for f in faces for v in f.verts})
        edges = list({e for f in faces for e in f.edges})
        co = Vector((0.0, 0.0, 0.0))
        no = Vector((0.0, 0.0, 0.0))
        co[axis] = value
        no[axis] = 1.0
        bmesh.ops.bisect_plane(bm, geom=verts + edges + faces, plane_co=co, plane_no=no, dist=0.0005)
        bm.normal_update()
    counts = [0, 0]
    for f in bm.faces:
        if f.material_index != paint or abs(f.normal.x) < FLANK:
            continue
        c = f.calc_center_median()
        if band_lo < c.z < band_hi and band_y[0] < c.y < band_y[1]:
            f.material_index = navy
            counts[0] += 1
        elif stripe_lo < c.z < stripe_hi and stripe_y[0] < c.y < stripe_y[1]:
            f.material_index = yellow
            counts[1] += 1
    bm.to_mesh(me)
    bm.free()
    print("   livery: band %.2f..%.2f m (%d faces), stripe %.2f..%.2f m (%d faces), doors y %.2f..%.2f" % (
        band_lo, band_hi, counts[0], stripe_lo, stripe_hi, counts[1], band_y[0], band_y[1]))
    if not counts[0] or not counts[1]:
        raise RuntimeError("the livery found no flank to paint")


def roof(parts):
    """(y, z, half width) of the crest of the roof: the highest point of the Body near the middle line."""
    me = parts["Body"].data
    co = rm.vertices(me)
    mid = co[np.abs(co[:, 0]) < 0.15]
    crest = mid[mid[:, 2].argmax()]
    near = co[(np.abs(co[:, 1] - crest[1]) < 0.25) & (co[:, 2] > crest[2] - 0.05)]
    return float(crest[1]), float(crest[2]), float(np.abs(near[:, 0]).max())


def roof_height(parts, x, y):
    z = rm.ray_down([parts["Body"]], x, y)
    return z if z is not None else roof(parts)[1]


def light_bar(parts, material_for, y=None):
    """The light bar on the roof: the black base and its feet (joined to the Body), LightBar_Red, LightBar_Blue and the
    Siren empty above them."""
    ry, rz, half = roof(parts)
    y = ry if y is None else y
    length = min(1.16, 2.0 * half * 0.8)
    depth = 0.26
    ends = [roof_height(parts, sx * length * 0.42, y) for sx in (-1.0, 1.0)]
    base_z = rz + 0.035
    out = []
    bm = bmesh.new()
    rm.bevel_box(bm, (length, depth, 0.03), (0.0, y, base_z + 0.015), bevel=0.008)
    for sx, z in zip((-1.0, 1.0), ends):
        h = base_z - z + 0.01
        rm.bevel_box(bm, (0.08, 0.16, h), (sx * length * 0.42, y, z + h * 0.5 - 0.01), bevel=0.0)
    # the base is part of the Body (its black is a material the Body has anyway: no draw call of its own)
    base = rm.new_object("LightBarBase", bm, material_for("police_black"))
    rm.smooth_by_angle(base.data, 35.0)
    parts["Body"] = rm.join([parts["Body"], base], "Body")
    lens_z = base_z + 0.03 + 0.035
    for name, sx, role in (("LightBar_Red", -1.0, "bar_red"), ("LightBar_Blue", 1.0, "bar_blue")):
        bm = bmesh.new()
        w = length * 0.5 - 0.03
        rm.bevel_box(bm, (w, depth - 0.02, 0.07), (sx * (w * 0.5 + 0.015), y, lens_z), bevel=0.015, segments=2)
        out.append(rm.new_object(name, bm, material_for(role)))
    for ob in out:
        rm.smooth_by_angle(ob.data, 35.0)
    out.append(rm.empty("Siren", (0.0, y, lens_z + 0.08)))
    return out


def taxi_sign(parts, material_for):
    """The lit roof sign of the taxi (a plain glowing box, the fleet has no texture for the text)."""
    ry, rz, half = roof(parts)
    y = ry + 0.12
    bm = bmesh.new()
    w, d, h = 0.60, 0.22, 0.17
    corners = [roof_height(parts, sx * w * 0.5, y + sy * d * 0.5) for sx in (-1, 1) for sy in (-1, 1)]
    z0 = min(corners) - 0.005
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        top = v.co.z > 0
        sx = 0.82 if top else 1.0
        sy = 0.7 if top else 1.0
        v.co = Vector((v.co.x * w * sx, v.co.y * d * sy, (v.co.z + 0.5) * (h + rz - z0) + z0))
        v.co.y += y
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    ob = rm.new_object("TaxiSign", bm, material_for("taxi_sign"))
    rm.smooth_by_angle(ob.data, 30.0)
    return [ob]


def lidar(parts, material_for):
    """The roof LiDAR of the robotaxi: a black puck on a low base with a lit cyan window ring."""
    ry, rz, half = roof(parts)
    y = ry + 0.05
    z0 = roof_height(parts, 0.0, y) - 0.01
    bm = bmesh.new()
    rm.cylinder(bm, 0.19, 0.17, 0.05, (0.0, y, z0 + 0.025), segments=20, material_index=0)
    rm.cylinder(bm, 0.145, 0.14, 0.05, (0.0, y, z0 + 0.075), segments=20, material_index=0)
    rm.cylinder(bm, 0.152, 0.152, 0.035, (0.0, y, z0 + 0.1175), segments=20, material_index=1)
    rm.cylinder(bm, 0.14, 0.12, 0.04, (0.0, y, z0 + 0.155), segments=20, material_index=0)
    ob = rm.new_object("Lidar", bm, [material_for("black"), material_for("lidar")])
    rm.smooth_by_angle(ob.data, 30.0)
    return [ob]


BACKING_GROW = 0.08   # m, how far a backing plate reaches beyond the lattice (the opening is wider than its lattice)
BACKING_DEPTH = 0.05  # m, how far behind the back of the lattice the plate stands


def backing(parts, plates, material_for):
    """Dark plates behind the openings of a lattice grille (Ctx.back_openings): 2 cm thick, BACKING_DEPTH behind the back
    of the piece and BACKING_GROW wider than it on every side, joined to the part that holds the grille."""
    for node, lo, hi in plates:
        bm = bmesh.new()
        size = (hi[0] - lo[0] + 2.0 * BACKING_GROW, 0.02, hi[2] - lo[2] + 2.0 * BACKING_GROW)
        centre = ((lo[0] + hi[0]) * 0.5, lo[1] - BACKING_DEPTH, (lo[2] + hi[2]) * 0.5)
        rm.bevel_box(bm, size, centre)
        plate = rm.new_object("Backing", bm, material_for("black"))
        parts[node] = rm.join([parts[node], plate], node)


def push_bar(parts, material_for):
    """The ram bar of the heavy police SUV (briefs/npc_cars.md): black tubes in front of the front bumper, part of Bumper_F
    (it comes off with it)."""
    bumper = parts["Bumper_F"]
    lo, hi = rm.world_bounds(bumper)
    y = hi[1] + 0.07
    top = min(hi[2] + 0.22, 0.98)
    bottom = lo[2] + 0.12
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        rm.tube(bm, (sx * 0.30, y, bottom), (sx * 0.30, y, top), 0.035)
        rm.tube(bm, (sx * 0.30, y, bottom + 0.12), (sx * 0.30, hi[1] - 0.12, bottom + 0.12), 0.03)
    for z in (bottom + 0.30, top - 0.04):
        rm.tube(bm, (-0.46, y + 0.01, z), (0.46, y + 0.01, z), 0.03)
    bar = rm.new_object("PushBar", bm, material_for("police_black"))
    rm.smooth_by_angle(bar.data, 35.0)
    parts["Bumper_F"] = rm.join([bumper, bar], "Bumper_F")


def build(model_id, cfg, parts, material_for):
    """The extra nodes of a model (after the normals are restored)."""
    out = []
    if cfg.get("push_bar"):
        push_bar(parts, material_for)
    if cfg.get("police"):
        out += light_bar(parts, material_for)
    if cfg.get("taxi_sign"):
        out += taxi_sign(parts, material_for)
    if cfg.get("lidar"):
        out += lidar(parts, material_for)
    return out
