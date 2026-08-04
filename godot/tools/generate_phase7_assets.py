#!/usr/bin/env python3
"""Offline generator for phase-7 textures and glTF hero assets."""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEX_DIR = ROOT / "assets" / "textures"
MODEL_DIR = ROOT / "assets" / "models"


def _rng(seed: int):
    state = seed & 0xFFFFFFFF

    def nextf() -> float:
        nonlocal state
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        return state / 4294967296.0

    return nextf


def _save_png(path: Path, w: int, h: int, pixels: list[tuple[int, int, int]]) -> None:
    import struct as st

    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            i = y * w + x
            r, g, b = pixels[i]
            raw.extend((r, g, b))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            st.pack(">I", len(data))
            + tag
            + data
            + st.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = st.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    comp = zlib.compress(bytes(raw), 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", comp) + chunk(b"IEND", b"")
    path.write_bytes(png)


def _tex_import(path: Path) -> None:
    imp = path.with_suffix(path.suffix + ".import")
    name = path.name
    imp.write_text(
        f"""[remap]

importer="texture"
type="CompressedTexture2D"
path="res://.godot/imported/{name}-phase7.s3tc.ctex"
metadata={{
"vram_texture": true
}}

[deps]

source_file="res://assets/textures/{name}"

[params]

compress/mode=2
mipmaps/generate=true
detect_3d/compress_to=1
"""
    )


def gen_pebbledash() -> None:
    w, h = 256, 256
    rng = _rng(7)
    px = []
    for y in range(h):
        for x in range(w):
            n = rng()
            base = 210 + int((n - 0.5) * 55)
            speck = 1 if n > 0.72 else (-18 if n < 0.28 else 0)
            v = max(0, min(255, base + speck))
            px.append((v, v - 4, v - 8))
    _save_png(TEX_DIR / "pebbledash.png", w, h, px)


def gen_path() -> None:
    w, h = 256, 256
    px = []
    for y in range(h):
        for x in range(w):
            slab_x = x % 64
            slab_y = y % 64
            joint = slab_x < 3 or slab_y < 3 or slab_x > 60 or slab_y > 60
            speck = ((x * 11 + y * 17) % 7) - 3
            if joint:
                v = 128 + speck
            else:
                v = 168 + speck
            px.append((v, v - 1, v - 3))
    _save_png(TEX_DIR / "path.png", w, h, px)


def gen_block_wall() -> None:
    w, h = 256, 256
    px = []
    for y in range(h):
        for x in range(w):
            bx, by = x // 32, y // 16
            ox = (by % 2) * 16
            cx = (x + ox) % 32
            mortar = cx < 2 or y % 16 < 2
            shade = ((bx + by) % 2) * 8
            v = 150 if mortar else 168 + shade
            px.append((v, v - 2, v - 4))
    _save_png(TEX_DIR / "block_wall.png", w, h, px)


def gen_brick_red() -> None:
    w, h = 256, 256
    px = []
    for y in range(h):
        for x in range(w):
            bx, by = x // 40, y // 18
            ox = (by % 2) * 20
            cx = (x + ox) % 40
            mortar = cx < 2 or y % 18 < 2
            shade = ((bx * 3 + by) % 4) * 6
            if mortar:
                px.append((145, 140, 135))
            else:
                r, g, b = 155 + shade, 72 + shade // 2, 52 + shade // 3
                px.append((r, g, b))
    _save_png(TEX_DIR / "brick_red.png", w, h, px)


def _box(min_v, max_v, color):
    x0, y0, z0 = min_v
    x1, y1, z1 = max_v
    r, g, b = color
    verts = [
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    ]
    faces = [
        (0, 1, 2, 0, 2, 3), (5, 4, 7, 5, 7, 6), (4, 0, 3, 4, 3, 7),
        (1, 5, 6, 1, 6, 2), (3, 2, 6, 3, 6, 7), (4, 5, 1, 4, 1, 0),
    ]
    positions, normals, colors = [], [], []
    for f in faces:
        v0, v1, v2 = verts[f[0]], verts[f[1]], verts[f[2]]
        e1 = (v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2])
        e2 = (v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2])
        nx = e1[1] * e2[2] - e1[2] * e2[1]
        ny = e1[2] * e2[0] - e1[0] * e2[2]
        nz = e1[0] * e2[1] - e1[1] * e2[0]
        ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        nx, ny, nz = nx / ln, ny / ln, nz / ln
        for idx in f:
            vx, vy, vz = verts[idx]
            positions.extend((vx, vy, vz))
            normals.extend((nx, ny, nz))
            colors.extend((r, g, b, 1.0))
    return positions, normals, colors


def _write_glb(path: Path, meshes: list[dict], nodes: list[dict]) -> None:
  """Write a minimal GLB with named mesh nodes."""
  buffer_views, accessors, gltf_meshes, gltf_nodes, children = [], [], [], [], []
  bin_blob = bytearray()
  mesh_index = 0

  for node in nodes:
    if "mesh" not in node:
      gltf_nodes.append({"name": node["name"]})
      continue
    mdef = meshes[node["mesh"]]
    pos, nrm, col = mdef["data"]
    pos_b = struct.pack(f"<{len(pos)}f", *pos)
    nrm_b = struct.pack(f"<{len(nrm)}f", *nrm)
    col_b = struct.pack(f"<{len(col)}f", *col)
    pos_off = len(bin_blob)
    bin_blob.extend(pos_b)
    nrm_off = len(bin_blob)
    bin_blob.extend(nrm_b)
    col_off = len(bin_blob)
    bin_blob.extend(col_b)
    stride = 12
    n_verts = len(pos) // 3
    buffer_views.extend([
      {"buffer": 0, "byteOffset": pos_off, "byteLength": len(pos_b), "target": 34962},
      {"buffer": 0, "byteOffset": nrm_off, "byteLength": len(nrm_b), "target": 34962},
      {"buffer": 0, "byteOffset": col_off, "byteLength": len(col_b), "target": 34962},
    ])
    base = len(accessors)
    accessors.extend([
      {"bufferView": base, "componentType": 5126, "count": n_verts, "type": "VEC3"},
      {"bufferView": base + 1, "componentType": 5126, "count": n_verts, "type": "VEC3"},
      {"bufferView": base + 2, "componentType": 5126, "count": n_verts, "type": "VEC4"},
    ])
    gltf_meshes.append({
      "name": node["name"],
      "primitives": [{
        "attributes": {"POSITION": base, "NORMAL": base + 1, "COLOR_0": base + 2},
        "mode": 4,
      }],
    })
    gltf_nodes.append({"name": node["name"], "mesh": mesh_index})
    mesh_index += 1

  root_children = list(range(len(gltf_nodes)))
  gltf_nodes.append({"name": "Root", "children": root_children})

  gltf = {
    "asset": {"version": "2.0", "generator": "phase7"},
    "scene": 0,
    "scenes": [{"nodes": [len(gltf_nodes) - 1]}],
    "nodes": gltf_nodes,
    "meshes": gltf_meshes,
    "buffers": [{"byteLength": len(bin_blob)}],
    "bufferViews": buffer_views,
    "accessors": accessors,
  }
  json_chunk = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
  json_chunk += b" " * ((4 - len(json_chunk) % 4) % 4)
  bin_chunk = bytes(bin_blob)
  bin_chunk += b"\x00" * ((4 - len(bin_chunk) % 4) % 4)
  total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
  out = bytearray()
  out.extend(struct.pack("<4sII", b"glTF", 2, total))
  out.extend(struct.pack("<I4s", len(json_chunk), b"JSON"))
  out.extend(json_chunk)
  out.extend(struct.pack("<I4s", len(bin_chunk), b"BIN\x00"))
  out.extend(bin_chunk)
  path.write_bytes(bytes(out))


def gen_person() -> None:
    parts = [
        ("Head", (-0.14, 1.55, -0.14), (0.14, 1.78, 0.14), (0.86, 0.72, 0.62)),
        ("Torso", (-0.22, 0.95, -0.12), (0.22, 1.52, 0.12), (0.22, 0.28, 0.38)),
        ("LegL", (-0.20, 0.0, -0.10), (-0.04, 0.95, 0.10), (0.18, 0.20, 0.28)),
        ("LegR", (0.04, 0.0, -0.10), (0.20, 0.95, 0.10), (0.18, 0.20, 0.28)),
        ("ArmL", (-0.38, 1.02, -0.08), (-0.22, 1.48, 0.08), (0.86, 0.72, 0.62)),
        ("ArmR", (0.22, 1.02, -0.08), (0.38, 1.48, 0.08), (0.86, 0.72, 0.62)),
        ("FootL", (-0.22, -0.04, -0.14), (-0.02, 0.06, 0.18), (0.12, 0.12, 0.14)),
        ("FootR", (0.02, -0.04, -0.14), (0.22, 0.06, 0.18), (0.12, 0.12, 0.14)),
    ]
    meshes, nodes = [], []
    for i, (name, mn, mx, col) in enumerate(parts):
        meshes.append({"data": _box(mn, mx, col)})
        nodes.append({"name": name, "mesh": i})
    _write_glb(MODEL_DIR / "person.glb", meshes, nodes)


def gen_car() -> None:
    parts = [
        ("Body", (-0.90, 0.35, -2.05), (0.90, 1.05, 2.05), (0.82, 0.84, 0.88)),
        ("Roof", (-0.78, 1.05, -0.55), (0.78, 1.32, 1.05), (0.75, 0.77, 0.80)),
        ("Hood", (-0.85, 0.88, 0.85), (0.85, 1.08, 2.00), (0.80, 0.82, 0.86)),
        ("GlassF", (-0.72, 0.92, -1.85), (0.72, 1.18, -1.55), (0.12, 0.16, 0.20)),
        ("GlassR", (-0.68, 0.95, -0.45), (0.68, 1.15, 0.95), (0.12, 0.16, 0.20)),
        ("BumperF", (-0.92, 0.30, -2.12), (0.92, 0.48, -1.88), (0.15, 0.15, 0.16)),
        ("BumperR", (-0.92, 0.30, 1.88), (0.92, 0.48, 2.12), (0.15, 0.15, 0.16)),
        ("WheelFL", (-0.92, 0.0, -1.35), (-0.62, 0.38, -1.05), (0.08, 0.08, 0.09)),
        ("WheelFR", (0.62, 0.0, -1.35), (0.92, 0.38, -1.05), (0.08, 0.08, 0.09)),
        ("WheelRL", (-0.92, 0.0, 1.05), (-0.62, 0.38, 1.35), (0.08, 0.08, 0.09)),
        ("WheelRR", (0.62, 0.0, 1.05), (0.92, 0.38, 1.35), (0.08, 0.08, 0.09)),
        ("MirrorL", (-1.02, 0.98, -0.55), (-0.88, 1.12, -0.35), (0.10, 0.10, 0.11)),
        ("MirrorR", (0.88, 0.98, -0.55), (1.02, 1.12, -0.35), (0.10, 0.10, 0.11)),
    ]
    meshes, nodes = [], []
    for i, (name, mn, mx, col) in enumerate(parts):
        meshes.append({"data": _box(mn, mx, col)})
        nodes.append({"name": name, "mesh": i})
    _write_glb(MODEL_DIR / "car.glb", meshes, nodes)


def gen_tree() -> None:
    parts = [
        ("Trunk", (-0.12, 0.0, -0.12), (0.12, 2.8, 0.12), (0.35, 0.22, 0.14)),
        ("CanopyA", (-1.1, 2.2, -0.9), (0.5, 3.8, 1.0), (0.22, 0.48, 0.24)),
        ("CanopyB", (-0.4, 2.5, -1.2), (1.2, 4.0, 0.4), (0.18, 0.42, 0.20)),
        ("CanopyC", (-0.8, 2.0, 0.2), (0.9, 3.5, 1.3), (0.20, 0.45, 0.22)),
    ]
    meshes, nodes = [], []
    for i, (name, mn, mx, col) in enumerate(parts):
        meshes.append({"data": _box(mn, mx, col)})
        nodes.append({"name": name, "mesh": i})
    _write_glb(MODEL_DIR / "tree.glb", meshes, nodes)


def main() -> None:
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    gen_pebbledash()
    gen_path()
    gen_block_wall()
    gen_brick_red()
    for name in ("pebbledash", "path", "block_wall", "brick_red"):
        _tex_import(TEX_DIR / f"{name}.png")
    gen_person()
    gen_car()
    gen_tree()
    print("phase-7 assets generated")


if __name__ == "__main__":
    main()
