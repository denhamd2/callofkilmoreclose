#!/usr/bin/env python3
"""Headless Blender export: Jay-Artist Golf MK4 blend -> Godot-ready GLB.

Source blend (CC-BY 3.0):
  Volkswagen VW Golf MK4 - Cycles / GolfMK4-Cycles-Jay-Hardy-2011.blend

Reorients Blender +X forward to Godot -Z forward (matches legacy car.glb),
grounds the mesh on Y=0, and strips studio backdrop geometry.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = Path.home() / (
    "Downloads/Volkswagen VW Golf MK4 - Cycles/GolfMK4-Cycles-Jay-Hardy-2011.blend"
)
OUT_DIR = ROOT / "assets" / "models" / "golf_mk4"
OUT_GLB = OUT_DIR / "golf_mk4.glb"
ATTRIBUTION = OUT_DIR / "ATTRIBUTION.txt"

BLENDER_PY = r'''
import bpy
import math
import mathutils
from pathlib import Path

blend = Path(r"""__BLEND__""")
out_glb = Path(r"""__OUT_GLB__""")

bpy.ops.wm.open_mainfile(filepath=str(blend))

# Remove studio / camera clutter.
remove_names = {"Studio-Floor-Bckgrnd", "Camera.001"}
for obj in list(bpy.data.objects):
    if obj.name in remove_names or obj.name.startswith("Plane."):
        bpy.data.objects.remove(obj, do_unlink=True)

# Curves (rear badge) -> mesh so glTF carries geometry.
for obj in list(bpy.data.objects):
    if obj.type == "CURVE":
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")
        obj.select_set(False)

car_objs = [o for o in bpy.data.objects if o.type == "MESH"]
if not car_objs:
    raise RuntimeError("no car meshes found after cleanup")

# Rotate -90 deg around Y: Blender +X (nose) -> Godot -Z forward.
rot = mathutils.Matrix.Rotation(-math.pi / 2.0, 4, "Y")
for obj in car_objs:
    obj.matrix_world = rot @ obj.matrix_world

# Ground on Y=0 (wheel bottoms sit near the lowest Y).
mins = [1e9, 1e9, 1e9]
maxs = [-1e9, -1e9, -1e9]
for obj in car_objs:
    for c in obj.bound_box:
        v = obj.matrix_world @ mathutils.Vector(c)
        for i in range(3):
            mins[i] = min(mins[i], v[i])
            maxs[i] = max(maxs[i], v[i])
lift = -mins[1]
for obj in car_objs:
    obj.matrix_world = mathutils.Matrix.Translation((0.0, lift, 0.0)) @ obj.matrix_world

# Bake world alignment into mesh vertices so glTF nodes stay upright (no per-part spins).
bpy.ops.object.select_all(action="DESELECT")
for obj in car_objs:
    obj.select_set(True)
bpy.context.view_layer.objects.active = car_objs[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Re-ground after apply — some parts had negative local origins.
mins = [1e9, 1e9, 1e9]
maxs = [-1e9, -1e9, -1e9]
for obj in car_objs:
    for c in obj.bound_box:
        v = obj.matrix_world @ mathutils.Vector(c)
        for i in range(3):
            mins[i] = min(mins[i], v[i])
            maxs[i] = max(maxs[i], v[i])
lift2 = -mins[1]
if abs(lift2) > 0.0001:
    for obj in car_objs:
        obj.matrix_world = mathutils.Matrix.Translation((0.0, lift2, 0.0)) @ obj.matrix_world
    bpy.ops.object.select_all(action="DESELECT")
    for obj in car_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = car_objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

root = bpy.data.objects.new("GolfMK4", None)
bpy.context.collection.objects.link(root)
for obj in car_objs:
    obj.parent = root
    obj.matrix_parent_inverse = root.matrix_world.inverted()

def _iter_mesh_objects(parent):
    for child in parent.children:
        if child.type == "MESH":
            yield child
        for sub in _iter_mesh_objects(child):
            yield sub

def _world_vertex_bounds(parent):
    mins = [1e9, 1e9, 1e9]
    maxs = [-1e9, -1e9, -1e9]
    for obj in _iter_mesh_objects(parent):
        for v in obj.data.vertices:
            w = obj.matrix_world @ v.co
            for i in range(3):
                mins[i] = min(mins[i], w[i])
                maxs[i] = max(maxs[i], w[i])
    return mins, maxs

mins, maxs = _world_vertex_bounds(root)
dx = -(mins[0] + maxs[0]) * 0.5
dy = -mins[1]
dz = -(mins[2] + maxs[2]) * 0.5

bpy.ops.object.select_all(action="DESELECT")
mesh_list = list(_iter_mesh_objects(root))
for obj in mesh_list:
    obj.select_set(True)
bpy.context.view_layer.objects.active = mesh_list[0]
bpy.ops.transform.translate(value=(dx, dy, dz))
for obj in mesh_list:
    obj.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

mins, maxs = _world_vertex_bounds(root)

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for obj in mesh_list:
    obj.select_set(True)

out_glb.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(out_glb),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_texcoords=True,
    export_normals=True,
    export_materials="NONE",
)

size = [maxs[i] - mins[i] for i in range(3)]
print("EXPORT_OK", out_glb, "SIZE", size, "MIN", mins, "MAX", maxs, "LIFT", lift, "LIFT2", lift2)
'''

ATTRIBUTION_TEXT = """Volkswagen VW Golf MK4 - Cycles
Author: Jay-Artist (Blendswap)
License: Creative Commons Attribution 3.0
Source: http://www.blendswap.com/blends/view/22152
Imported for Call of Kilmore Close (offline static asset).
"""


def find_blender() -> str:
    candidates = [
        "/Applications/Blender.app/Contents/MacOS/Blender",
        "blender",
    ]
    for c in candidates:
        try:
            subprocess.run([c, "--version"], capture_output=True, check=True)
            return c
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue
    raise FileNotFoundError("Blender not found — install Blender or set PATH")


def main() -> int:
    blend = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_BLEND
    if not blend.is_file():
        print(f"blend not found: {blend}", file=sys.stderr)
        return 1

    blender = find_blender()
    script = (
        BLENDER_PY.replace("__BLEND__", str(blend))
        .replace("__OUT_GLB__", str(OUT_GLB))
    )
    cmd = [blender, "--background", str(blend), "--python-expr", script]
    print("running:", blender, "--background", blend)
    proc = subprocess.run(cmd, text=True)
    if proc.returncode != 0:
        return proc.returncode

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ATTRIBUTION.write_text(ATTRIBUTION_TEXT, encoding="utf-8")
    if not OUT_GLB.is_file():
        print(f"export missing: {OUT_GLB}", file=sys.stderr)
        return 1
    print(f"written {OUT_GLB} ({OUT_GLB.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
