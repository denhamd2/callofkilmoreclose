#!/usr/bin/env python3
"""Procedural concrete interlocking roof tile albedo for Kilmore Close.

    python3 godot/tools/generate_roof_texture.py
    python3 godot/tools/generate_pbr_maps.py

Reference: dark charcoal-grey Marley-style double-Roman courses on 1960s–70s
Dublin semis — matte, weathered, with a clear horizontal lap shadow.
"""

from __future__ import annotations

import math
import os
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


def generate_roof(w: int = SIZE, h: int = SIZE) -> bytearray:
    """Interlocking tile courses — horizontal rows, brick offset, lap shadow."""
    rgb = bytearray(w * h * 3)
    row_h = 28
    tile_w = 52
    base = 72

    for y in range(h):
        row = y // row_h
        row_off = (tile_w // 2) if row % 2 else 0
        lap_y = y % row_h
        for x in range(w):
            tx = (x + row_off) % tile_w
            ty = lap_y

            # Per-tile weathering
            tile_id_x = (x + row_off) // tile_w
            tile_id_y = row
            grain = (_noise(tile_id_x * 1.7, tile_id_y * 2.3, 1) - 0.5) * 18.0
            grain += (_noise(x * 0.35, y * 0.22, 2) - 0.5) * 8.0

            # Bottom lap shadow (tile above overhangs)
            lap = 0.0
            if ty < 5:
                lap = -16.0 + ty * 2.2
            elif ty < 8:
                lap = -4.0

            # Vertical joint between tiles
            joint = 0.0
            if tx < 2:
                joint = -12.0
            elif tx > tile_w - 3:
                joint = -8.0

            # Row joint / course line
            course = -10.0 if ty < 2 else 0.0

            # Occasional lichen / damp patch
            lichen = 0.0
            if _noise(tile_id_x * 0.8, tile_id_y * 0.6, 4) > 0.88:
                lichen = 6.0

            v = int(max(0, min(255, base + grain + lap + joint + course + lichen)))
            # Slight cool charcoal bias
            i = (y * w + x) * 3
            rgb[i] = v
            rgb[i + 1] = int(v * 0.98)
            rgb[i + 2] = int(v * 0.94)

    # Soften tile edges for seamless repeat
    for y in range(h):
        for x in range(w):
            edge = min(x, y, w - 1 - x, h - 1 - y)
            if edge < 2:
                i = (y * w + x) * 3
                fade = edge / 2.0
                for c in range(3):
                    rgb[i + c] = int(rgb[i + c] * (0.94 + 0.06 * fade))
    return rgb


def main() -> int:
    os.makedirs(TEX_DIR, exist_ok=True)
    out = os.path.join(TEX_DIR, "roof.png")
    write_png(out, SIZE, SIZE, generate_roof())
    print("wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
