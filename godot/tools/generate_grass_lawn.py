#!/usr/bin/env python3
"""Generate a patchier lawn albedo for the grass/verges phase (P0)."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures" / "grass_lawn.png"


def _rng(seed: int):
    state = seed & 0xFFFFFFFF

    def nextf() -> float:
        nonlocal state
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        return state / 4294967296.0

    return nextf


def _save_png(path: Path, w: int, h: int, pixels: list[tuple[int, int, int]]) -> None:
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b = pixels[y * w + x]
            raw.extend((r, g, b))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    w, h = 256, 256
    rng = _rng(91)
    px = []
    for y in range(h):
        for x in range(w):
            n = rng()
            # Muted Irish lawn: green with yellow-brown wear patches.
            patch = 1.0 if ((x * 17 + y * 29) % 97) > 78 else 0.0
            g = int(95 + n * 55 - patch * 28)
            r = int(48 + n * 35 + patch * 22)
            b = int(32 + n * 22 - patch * 8)
            px.append((max(20, min(200, r)), max(30, min(210, g)), max(15, min(160, b))))
    _save_png(OUT, w, h, px)
    imp = OUT.with_suffix(OUT.suffix + ".import")
    imp.write_text(
        f"""[remap]

importer="texture"
type="CompressedTexture2D"
path="res://.godot/imported/{OUT.name}-grass.s3tc.ctex"
metadata={{
"vram_texture": true
}}

[deps]

source_file="res://assets/textures/{OUT.name}"

[params]

compress/mode=2
mipmaps/generate=true
detect_3d/compress_to=1
"""
    )
    print("wrote", OUT)


if __name__ == "__main__":
    main()
