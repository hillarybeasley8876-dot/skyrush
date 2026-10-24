"""glTF export with the project settings (core-owned). See CONTRACTS.md §2."""
import os
import shutil

import bpy


def export_glb(path, objects=None, collection=None, jpeg_quality=90, extras=True, shared_texture_dir=None):
    """Export `objects` (list) or everything in `collection` (name or Collection) or the whole scene
    to a .glb at `path` (absolute, or relative to ~/m/skyrush/game). Modifiers are applied, Y-up,
    tangents on, images embedded (JPEG unless the image needs alpha). Returns the absolute path.

    shared_texture_dir: for big tiled sets (city tiles) pass a folder name relative to the output file
    (e.g. "../_tex"): the asset is written as .gltf + .bin with its images in that shared folder, so
    tiles that use the same textures share ONE imported copy in Godot instead of embedding duplicates.
    `path` may still end in .glb — it is rewritten to .gltf."""
    if not os.path.isabs(path):
        path = os.path.join(os.path.expanduser("~/m/skyrush/game"), path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if collection is not None and objects is None:
        col = bpy.data.collections[collection] if isinstance(collection, str) else collection
        objects = list(col.all_objects)
    bpy.ops.object.select_all(action="DESELECT")
    use_sel = objects is not None
    if use_sel:
        for obj in objects:
            obj.hide_set(False)
            obj.select_set(True)
    common_args = dict(use_selection=use_sel, export_apply=True, export_yup=True, export_tangents=True,
                       export_cameras=False, export_lights=False, export_extras=extras,
                       export_image_format="AUTO", export_jpeg_quality=jpeg_quality, export_texcoords=True,
                       export_normals=True, export_materials="EXPORT")
    if shared_texture_dir:
        path = os.path.splitext(path)[0] + ".gltf"
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE",
                                  export_texture_dir=shared_texture_dir, **common_args)
    else:
        # Write outside the Godot project, then rename into place (same volume -> atomic): Godot never
        # scans a half-written file and no `*.tmp.glb.import` orphans appear.
        tmp_dir = os.path.expanduser("~/m/skyrush/tmp/export")
        os.makedirs(tmp_dir, exist_ok=True)
        tmp = os.path.join(tmp_dir, "%d_%s" % (os.getpid(), os.path.basename(path)))
        bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLB", **common_args)
        try:
            os.replace(tmp, path)
        except OSError:
            # The scratch folder is on another volume than the project (the tmp folder is a junction to a bigger disk): a rename
            # cannot cross volumes, so the file is copied next to its target and renamed there.
            staging = path + ".part"
            shutil.copyfile(tmp, staging)
            os.replace(staging, path)
            os.remove(tmp)
    print("EXPORT %s (%d objects)" % (path, len(objects) if use_sel else len(bpy.data.objects)))
    return path
