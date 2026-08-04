#!/usr/bin/env python3
"""Procedural brushed-concrete textures for Kilmore Close road and footpath.

    python3 godot/tools/generate_tarmac_texture.py
    python3 godot/tools/generate_pbr_maps.py

Writes:
  assets/textures/tarmac.png  — carriageway with longitudinal brush marks + joints
  assets/textures/path.png    — footpath slabs with combed finish
"""

from __future__ import annotations

import math
import os
import random
import struct
import sys
import zlib

ROOT = os.path.join(os.path.dirname(__file__), "..")
TEX_DIR = os.path.join(ROOT, "assets", "textures")
SIZE = 512


def write_png(path: str, w: int, h: int, rgb: bytearray) -> None:
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body)) + tag + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def _noise(x: float, y: float, seed: int = 0) -> float:
    n = math.sin(x * 12.9898 + y * 78.233 + seed * 43.17) * 43758.5453
    return n - math.floor(n)


def generate_tarmac(w: int = SIZE, h: int = SIZE) -> bytearray:
    """Brushed concrete: fine horizontal grooves + transverse expansion joints."""
    rng = random.Random(42)
    rgb = bytearray(w * h * 3)
    base = 148
    joint_every = 64  # ~4 m at world_scale 0.25

    for y in range(h):
        for x in range(w):
            # Subtle luminance noise
            n = _noise(x * 0.07, y * 0.05, 1) * 14.0 - 7.0
            # Longitudinal brush striations (along street when mapped on horizontal face)
            brush = math.sin(y * 0.85 + _noise(x * 0.2, y * 0.1, 2) * 2.5) * 6.0
            brush += math.sin(y * 2.1) * 2.0
            # Transverse expansion joints
            joint = 0.0
            if y % joint_every < 2:
                joint = -22.0
            elif y % joint_every < 4:
                joint = -10.0
            # Occasional wear patches
            wear = 0.0
            if _noise(x * 0.03, y * 0.03, 3) > 0.82:
                wear = -6.0

            v = int(max(0, min(255, base + n + brush + joint + wear)))
            i = (y * w + x) * 3
            rgb[i] = v
            rgb[i + 1] = v
            rgb[i + 2] = int(min(255, v + 2))

    # Slight vignette wear at tile edges for tiling softness
    for y in range(h):
        for x in range(w):
            edge = min(x, y, w - 1 - x, h - 1 - y)
            if edge < 3:
                i = (y * w + x) * 3
                fade = edge / 3.0
                for c in range(3):
                    rgb[i + c] = int(rgb[i + c] * (0.92 + 0.08 * fade))
    return rgb


def generate_path(w: int = SIZE, h: int = SIZE) -> bytearray:
    """Combed concrete footpath with slab joints."""
    rgb = bytearray(w * h * 3)
    base = 168
    slab = 96

    for y in range(h):
        for x in range(w):
            n = _noise(x * 0.09, y * 0.07, 5) * 10.0 - 5.0
            comb = math.sin(y * 1.15 + _noise(x * 0.15, 0, 6) * 1.8) * 5.0
            joint_x = 0.0
            if x % slab < 2:
                joint_x = -18.0
            joint_y = 0.0
            if y % slab < 2:
                joint_y = -14.0
            v = int(max(0, min(255, base + n + comb + joint_x + joint_y)))
            i = (y * w + x) * 3
            rgb[i] = v
            rgb[i + 1] = v
            rgb[i + 2] = int(min(255, v + 1))
    return rgb


def main() -> int:
    os.makedirs(TEX_DIR, exist_ok=True)
    tarmac_path = os.path.join(TEX_DIR, "tarmac.png")
    path_path = os.path.join(TEX_DIR, "path.png")
    write_png(tarmac_path, SIZE, SIZE, generate_tarmac())
    write_png(path_path, SIZE, SIZE, generate_path())
    print("wrote", tarmac_path)
    print("wrote", path_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
