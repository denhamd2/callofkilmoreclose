#!/usr/bin/env python3
"""Headless Blender export: Painkiller5555 Trees & Bushes -> Godot GLBs.

Source blend (CC-BY 3.0):
  Trees & Bushes.blend

Exports mid-size street trees (tree .. tree.004) and bush (leaves).
Skips backdrop planes and large trees (tree.005+).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = Path.home() / "Downloads/Trees  Bushes pack/Trees & Bushes.blend"
OUT_DIR = ROOT / "assets" / "models" / "trees_bushes"
ATTRIBUTION = OUT_DIR / "ATTRIBUTION.txt"

# Blender object name -> output stem (glb + visual scene)
EXPORTS: dict[str, str] = {
    "tree": "tree_a",
    "tree.001": "tree_b",
    "tree.002": "tree_c",
    "tree.003": "tree_d",
    "tree.004": "tree_e",
    "leaves": "bush_a",
}

BLENDER_PY = r'''
import bpy
import mathutils
from pathlib import Path

blend = Path(r"""__BLEND__""")
out_dir = Path(r"""__OUT_DIR__""")
exports = __EXPORTS__

bpy.ops.wm.open_mainfile(filepath=str(blend))

for obj in list(bpy.data.objects):
    if obj.name in {"Plane", "Plane.001"} or obj.name.startswith("Plane."):
        bpy.data.objects.remove(obj, do_unlink=True)

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

out_dir.mkdir(parents=True, exist_ok=True)

for src_name, stem in exports.items():
  src = bpy.data.objects.get(src_name)
  if src is None or src.type != "MESH":
    print("SKIP_MISSING", src_name)
    continue

  # Hide everything except this mesh for a clean export.
  for obj in bpy.data.objects:
    obj.hide_viewport = obj.type == "MESH" and obj.name != src_name
    obj.hide_render = obj.hide_viewport

  bpy.ops.object.select_all(action="DESELECT")
  src.select_set(True)
  bpy.context.view_layer.objects.active = src
  bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

  root = bpy.data.objects.new(stem, None)
  bpy.context.collection.objects.link(root)
  src.parent = root
  src.matrix_parent_inverse = root.matrix_world.inverted()

  mins, maxs = _world_vertex_bounds(root)
  dx = -(mins[0] + maxs[0]) * 0.5
  dy = -mins[1]
  dz = -(mins[2] + maxs[2]) * 0.5
  mesh_list = list(_iter_mesh_objects(root))
  bpy.ops.object.select_all(action="DESELECT")
  for obj in mesh_list:
    obj.select_set(True)
  bpy.context.view_layer.objects.active = mesh_list[0]
  bpy.ops.transform.translate(value=(dx, dy, dz))
  bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
  mins, maxs = _world_vertex_bounds(root)

  out_glb = out_dir / f"{stem}.glb"
  bpy.ops.object.select_all(action="DESELECT")
  root.select_set(True)
  for obj in mesh_list:
    obj.select_set(True)
  bpy.ops.export_scene.gltf(
    filepath=str(out_glb),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_texcoords=True,
    export_normals=True,
    export_materials="NONE",
  )
  height = maxs[1] - mins[1]
  print("EXPORT_OK", stem, out_glb, "HEIGHT", round(height, 2))

  # Unparent and restore for next export pass.
  src.parent = None
  bpy.data.objects.remove(root, do_unlink=True)
  for obj in bpy.data.objects:
    if obj.type == "MESH":
      obj.hide_viewport = False
      obj.hide_render = False
'''

ATTRIBUTION_TEXT = """Trees & Bushes pack
Author: Painkiller5555
License: Creative Commons Attribution 3.0
Source: https://opengameart.org (asset 78071)
Imported for Call of Kilmore Close (offline static assets).
"""

VISUAL_SCENE = """[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/models/trees_bushes/{stem}.glb" id="1_mesh"]

[node name="{stem}Visual" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_mesh")]
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
    exports_repr = repr(EXPORTS)
    script = (
        BLENDER_PY.replace("__BLEND__", str(blend))
        .replace("__OUT_DIR__", str(OUT_DIR))
        .replace("__EXPORTS__", exports_repr)
    )
    cmd = [blender, "--background", str(blend), "--python-expr", script]
    print("running:", blender, "--background", blend)
    proc = subprocess.run(cmd, text=True)
    if proc.returncode != 0:
        return proc.returncode

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ATTRIBUTION.write_text(ATTRIBUTION_TEXT, encoding="utf-8")

    for stem in EXPORTS.values():
        glb = OUT_DIR / f"{stem}.glb"
        if not glb.is_file():
            print(f"export missing: {glb}", file=sys.stderr)
            return 1
        visual = OUT_DIR / f"{stem}_visual.tscn"
        visual.write_text(
            VISUAL_SCENE.format(stem=stem),
            encoding="utf-8",
        )
        print(f"written {glb} ({glb.stat().st_size} bytes) + {visual.name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
