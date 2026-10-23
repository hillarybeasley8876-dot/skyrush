"""Stage 1 of the hero car: import the Khronos CarConcept, bake it into the game's frame.

The game frame (Blender side of CONTRACTS.md 6): the car faces +Y, X is its right, Z is up, the
origin is on the ground at the middle of the wheelbase, the wheel centres are one tyre radius
above the ground. The concept faces -Y, its wheels are posed (steered and spun) and its origin
is somewhere else, so every part is baked into world space first and then moved.
"""
import math

import bpy
from mathutils import Matrix, Vector

import meshkit

WHEEL_KEYS = {"FL": "WheelFrontL", "FR": "WheelFrontR", "RL": "WheelRearL", "RR": "WheelRearR"}


class Concept:
    """The imported concept: world-space copies of every mesh, the wheels measured."""

    def __init__(self, path):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        self.parts = {}
        self.wheels = {}
        sources = {o.name: o for o in bpy.data.objects}
        for name, ob in sources.items():
            if ob.type == "MESH":
                self.parts[name] = meshkit.world_copy(ob, name + "__w")
        for key, empty_name in WHEEL_KEYS.items():
            empty = sources[empty_name]
            axle = empty.matrix_world.to_quaternion() @ Vector((1.0, 0.0, 0.0))
            if axle.x < 0.0:
                axle = -axle
            self.wheels[key] = {
                "centre": empty.matrix_world.translation.copy(),
                "steer": math.atan2(axle.y, axle.x),
                "children": [o.name for o in empty.children],
            }
        for ob in list(bpy.data.objects):
            if ob.name not in {p.name for p in self.parts.values()}:
                bpy.data.objects.remove(ob, do_unlink=True)
        for name, ob in self.parts.items():
            ob.name = name

    def release(self, *objects):
        """Forgets objects that were turned into finished parts (so the clean-up leaves them alone)."""
        for name, ob in list(self.parts.items()):
            if any(ob is o for o in objects):
                del self.parts[name]

    def wheel_parts(self, key):
        """The world-space objects of one wheel: tyre, rim, disc, pad."""
        out = {}
        for child in self.wheels[key]["children"]:
            low = child.lower()
            if "rim" in low:
                out["rim"] = self.parts[child]
            elif "disc" in low:
                out["disc"] = self.parts[child]
            elif "pad" in low:
                out["pad"] = self.parts[child]
            else:
                out["tyre"] = self.parts[child]
        return out

    def straighten_wheels(self):
        """Turns every steered wheel back to straight, about its own centre (import frame)."""
        for key, info in self.wheels.items():
            if abs(info["steer"]) < 1e-4:
                continue
            c = info["centre"]
            m = Matrix.Translation(c) @ Matrix.Rotation(-info["steer"], 4, "Z") @ Matrix.Translation(-c)
            for ob in self.wheel_parts(key).values():
                meshkit.transform(ob, m)
            info["steer"] = 0.0

    def to_game_frame(self):
        """Faces the car +Y, puts the middle of the wheelbase on the origin and the tyres on the ground."""
        flip = Matrix.Rotation(math.pi, 4, "Z")
        centres = {k: flip @ i["centre"] for k, i in self.wheels.items()}
        mid_y = 0.5 * (centres["FL"].y + centres["RL"].y)
        tyre_low = min(meshkit.bounds(self.wheel_parts(k)["tyre"])[0].z for k in self.wheels)
        move = Matrix.Translation(Vector((0.0, -mid_y, -tyre_low)))
        full = move @ flip
        for ob in self.parts.values():
            meshkit.transform(ob, full)
        for info in self.wheels.values():
            info["centre"] = full @ info["centre"]
        return full
