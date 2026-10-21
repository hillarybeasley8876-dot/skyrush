# Blender 5.2 headless glTF export recipe (verified 2026-10-19 with Godot 4.7.2 import).
# Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#         --python blender_export_glb.py -- /abs/out/test_asset.glb
# Builds a small test asset that exercises everything the game pipeline needs:
#   - named node hierarchy (body -> 4 wheels), applied transforms, metres, +Y up after export
#   - 2 material slots on one mesh (paint + glass) and an emissive neon material
#   - Godot import suffixes: "-col" (mesh + trimesh collision), "-colonly" (collision only),
#     "-convcol" (mesh + convex collision)
#   - custom properties exported as glTF extras (-> Godot node metadata)
import sys
import bpy

out_path = sys.argv[sys.argv.index("--") + 1]

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
for block in (bpy.data.meshes, bpy.data.materials):
    for item in list(block):
        block.remove(item)


def make_material(name, rgba, metallic=0.0, roughness=0.5, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True                     # always-on (deprecated) in Blender 5.x
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if rgba[3] < 1.0:
        bsdf.inputs["Alpha"].default_value = rgba[3]
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"  # -> glTF alphaMode BLEND
    if emission:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def srgb(hexstr, a=1.0):
    """'#RRGGBB' (sRGB) -> linear RGBA for Blender colour sockets."""
    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    h = hexstr.lstrip("#")
    return tuple(lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (a,)


paint = make_material("M_Paint_Red", srgb("#B0001E"), metallic=0.6, roughness=0.25)
glass = make_material("M_Glass", srgb("#1A2330", 0.35), roughness=0.05)
neon = make_material("M_Neon_Cyan", srgb("#000000"), emission=srgb("#00E5FF"), strength=8.0)
tyre = make_material("M_Tyre", srgb("#111111"), roughness=0.9)

# Body: subdivided box (~6k tris so Godot LOD generation has something to reduce)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.55))
body = bpy.context.active_object
body.name = "Roadster_Body"
body.scale = (1.9, 4.4, 0.7)                     # Blender: X right, Y forward, Z up
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
mod = body.modifiers.new("Subd", "SUBSURF")
mod.levels = 3
mod.render_levels = 3
body.data.materials.append(paint)
body.data.materials.append(glass)
for poly in body.data.polygons:                  # top face -> glass slot (index 1)
    if poly.normal.z > 0.9:
        poly.material_index = 1
body["skyrush_type"] = "player_car"              # -> glTF extras -> Godot metadata

for name, x, y in (("Wheel_FL", -0.85, 1.4), ("Wheel_FR", 0.85, 1.4),
                   ("Wheel_RL", -0.85, -1.4), ("Wheel_RR", 0.85, -1.4)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.34, depth=0.28,
                                        location=(x, y, 0.34), rotation=(0, 1.5707963, 0))
    w = bpy.context.active_object
    w.name = name
    w.data.materials.append(tyre)
    w.parent = body
    w.matrix_parent_inverse = body.matrix_world.inverted()

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.25))     # visible barrier + trimesh col
barrier = bpy.context.active_object
barrier.name = "Barrier-col"
barrier.scale = (0.4, 10.0, 0.5)
barrier.location = (6.0, 0, 0.25)
barrier.data.materials.append(make_material("M_Concrete", srgb("#7A7A78"), roughness=0.8))

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))         # invisible ramp collision
ramp = bpy.context.active_object
ramp.name = "Ramp-colonly"
ramp.scale = (6.0, 10.0, 1.0)
ramp.location = (0, 20.0, 0.5)

bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.15, depth=3.0, location=(-6.0, 0, 1.5))
pole = bpy.context.active_object                                       # lamp pole + convex col
pole.name = "LampPole-convcol"
pole.data.materials.append(neon)

bpy.ops.object.select_all(action="DESELECT")
res = bpy.ops.export_scene.gltf(
    filepath=out_path, export_format="GLB", use_selection=False,
    export_apply=True,            # bake modifiers (Subsurf) into the exported mesh
    export_yup=True,              # Blender Z-up -> glTF/Godot Y-up (Blender +Y fwd -> Godot -Z fwd)
    export_extras=True,           # custom properties -> extras -> Godot metadata
    export_cameras=False, export_lights=False)
print("EXPORT_RESULT", res, out_path)
