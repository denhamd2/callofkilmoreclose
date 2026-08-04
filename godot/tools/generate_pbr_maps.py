#!/usr/bin/env python3
"""Derive normal and packed-ORM maps for the street textures.

    python3 godot/tools/generate_pbr_maps.py

Why derived rather than authored: only four of the fifteen street albedos have a
generator (`generate_phase7_assets.py` makes pebbledash, path, block_wall and
brick_red). The rest are committed PNGs with no source, so the maps have to come
out of the albedo itself. That is a real limitation — a derived normal map invents
detail from luminance and cannot know that mortar is recessed rather than merely
darker — but at street distance it reads correctly, and it is the difference
between "flat coloured box" and "a rendered wall".

Two outputs per texture, both written next to the albedo:

  <name>_normal.png   tangent-space normal, from a Sobel gradient of a blurred
                      luminance heightfield
  <name>_orm.png      R = ambient occlusion, G = roughness, B = metallic
                      (Godot's ORMMaterial3D layout — one fetch, not three)

`.import` files are written alongside so Godot treats normals as normal maps
(`compress/normal_map=1`) and compresses them at high quality. The project-wide
default is `high_quality=false`, which visibly blockifies a pebbledash normal.

No third-party imaging dependency: the project's rule is `three`-only on the web
side and no new packages here either, so the convolutions are done by hand on
Python's own `array`. These are 256-512px textures; it takes a moment and runs
offline, once.
"""

import os
import struct
import sys
import zlib
from array import array

TEX_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")

# Per-texture tuning. `bump` is how pronounced the surface relief is, `blur` how
# much the heightfield is smoothed first (high for noisy stone, low for flat
# render), and the roughness pair is the range the albedo luminance maps into.
# Rougher surfaces get a *narrower* range: tarmac is uniformly matte, whereas
# brick alternates between damp mortar and fired face.
PROFILES = {
    "pebbledash":  dict(bump=3.2, blur=1, rough=(0.72, 0.94), ao=0.55, metal=0.0),
    "band":        dict(bump=0.8, blur=2, rough=(0.78, 0.90), ao=0.30, metal=0.0),
    "band_mid":    dict(bump=0.9, blur=2, rough=(0.74, 0.88), ao=0.30, metal=0.0),
    "brick_red":   dict(bump=2.6, blur=1, rough=(0.62, 0.86), ao=0.65, metal=0.0),
    "block_wall":  dict(bump=2.4, blur=1, rough=(0.68, 0.90), ao=0.60, metal=0.0),
    "chimney":     dict(bump=2.2, blur=1, rough=(0.70, 0.90), ao=0.55, metal=0.0),
    "roof":        dict(bump=2.8, blur=1, rough=(0.60, 0.82), ao=0.70, metal=0.0),
    "tarmac":      dict(bump=1.4, blur=1, rough=(0.58, 0.76), ao=0.35, metal=0.0),
    "path":        dict(bump=1.6, blur=1, rough=(0.66, 0.86), ao=0.45, metal=0.0),
    "drive":       dict(bump=1.8, blur=1, rough=(0.64, 0.84), ao=0.50, metal=0.0),
    "kerb":        dict(bump=1.6, blur=1, rough=(0.62, 0.82), ao=0.45, metal=0.0),
    "garage_door": dict(bump=1.2, blur=1, rough=(0.42, 0.66), ao=0.30, metal=0.05),
    "grass":       dict(bump=1.8, blur=1, rough=(0.82, 0.96), ao=0.55, metal=0.0),
    "grass_lawn":  dict(bump=1.8, blur=1, rough=(0.82, 0.96), ao=0.55, metal=0.0),
    "hedge":       dict(bump=2.4, blur=1, rough=(0.84, 0.97), ao=0.70, metal=0.0),
}


# ----------------------------------------------------------------- PNG codec

def read_png(path):
    """Minimal PNG reader: 8-bit RGB/RGBA/grey, non-interlaced. Returns
    (w, h, channels, bytes) with the filters undone."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos, w, h, depth, ctype = 8, 0, 0, 0, 0
    idat = bytearray()
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctag == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            interlace = body[12]
            if depth != 8 or interlace != 0:
                raise ValueError(f"{path}: need 8-bit non-interlaced, got depth={depth}")
        elif ctag == b"IDAT":
            idat += body
        elif ctag == b"IEND":
            break
        pos += 12 + length

    nch = {0: 1, 2: 3, 4: 2, 6: 4}.get(ctype)
    if nch is None:
        raise ValueError(f"{path}: unsupported colour type {ctype} (palette?)")

    raw = zlib.decompress(bytes(idat))
    stride = w * nch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    src = 0
    for y in range(h):
        ftype = raw[src]
        src += 1
        line = bytearray(raw[src:src + stride])
        src += stride
        if ftype == 1:      # Sub
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif ftype == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:    # Average
            for i in range(stride):
                left = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:    # Paeth
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError(f"{path}: bad filter {ftype}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, nch, out


def write_png(path, w, h, rgb):
    """Write 8-bit RGB with no filtering — these are small and load once."""
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


# ------------------------------------------------------------- image helpers

def luminance(w, h, nch, pix):
    lum = array("f", bytes(4 * w * h))
    for i in range(w * h):
        p = i * nch
        if nch >= 3:
            lum[i] = (0.2126 * pix[p] + 0.7152 * pix[p + 1] + 0.0722 * pix[p + 2]) / 255.0
        else:
            lum[i] = pix[p] / 255.0
    return lum


def box_blur_wrap(src, w, h, passes):
    """Separable 3-tap box blur, wrapping at the edges — these textures tile, so
    clamping would seam the normal map down the join."""
    cur = src
    for _ in range(passes):
        tmp = array("f", bytes(4 * w * h))
        for y in range(h):
            row = y * w
            for x in range(w):
                tmp[row + x] = (cur[row + (x - 1) % w] + cur[row + x]
                                + cur[row + (x + 1) % w]) / 3.0
        nxt = array("f", bytes(4 * w * h))
        for y in range(h):
            up, dn = ((y - 1) % h) * w, ((y + 1) % h) * w
            row = y * w
            for x in range(w):
                nxt[row + x] = (tmp[up + x] + tmp[row + x] + tmp[dn + x]) / 3.0
        cur = nxt
    return cur


def normal_map(height, w, h, bump):
    """Sobel gradient -> tangent-space normal, +Y up (Godot's convention)."""
    out = bytearray(w * h * 3)
    for y in range(h):
        y0, y1 = ((y - 1) % h) * w, ((y + 1) % h) * w
        row = y * w
        for x in range(w):
            xm, xp = (x - 1) % w, (x + 1) % w
            tl, tc, tr = height[y0 + xm], height[y0 + x], height[y0 + xp]
            ml, mr = height[row + xm], height[row + xp]
            bl, bc, br = height[y1 + xm], height[y1 + x], height[y1 + xp]
            dx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl)
            dy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr)
            nx, ny, nz = -dx * bump, -dy * bump, 1.0
            inv = 1.0 / max((nx * nx + ny * ny + nz * nz) ** 0.5, 1e-6)
            i = (row + x) * 3
            out[i] = int(max(0.0, min(255.0, (nx * inv * 0.5 + 0.5) * 255.0)))
            out[i + 1] = int(max(0.0, min(255.0, (ny * inv * 0.5 + 0.5) * 255.0)))
            out[i + 2] = int(max(0.0, min(255.0, (nz * inv * 0.5 + 0.5) * 255.0)))
    return out


def orm_map(lum, w, h, rough_lo, rough_hi, ao_strength, metal):
    """R=AO, G=roughness, B=metallic. Darker albedo reads as more occluded and
    slightly rougher — crude, but it is the correlation real surfaces have."""
    out = bytearray(w * h * 3)
    mb = int(max(0.0, min(1.0, metal)) * 255.0)
    for i in range(w * h):
        l = lum[i]
        ao = 1.0 - (1.0 - l) * ao_strength
        rough = rough_hi - (rough_hi - rough_lo) * l
        p = i * 3
        out[p] = int(max(0.0, min(255.0, ao * 255.0)))
        out[p + 1] = int(max(0.0, min(255.0, rough * 255.0)))
        out[p + 2] = mb
    return out


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path="res://.godot/imported/{base}-{md5}.ctex"
metadata={{
"vram_texture": true
}}

[deps]

source_file="res://assets/textures/{base}"
dest_files=["res://.godot/imported/{base}-{md5}.ctex"]

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
svg/scale=1.0
editor/scale_with_editor_scale=false
editor/convert_colors_with_editor_theme=false
"""


def write_import(png_path, is_normal):
    """Emit a .import so the map is treated correctly. Normals must be flagged or
    Godot compresses them as colour and the lighting goes blotchy; both get
    high_quality, unlike the project default."""
    import hashlib
    base = os.path.basename(png_path)
    md5 = hashlib.md5(("res://assets/textures/" + base).encode()).hexdigest()
    uid = hashlib.md5((base + "pbr").encode()).hexdigest()[:16]
    with open(png_path + ".import", "w") as fh:
        fh.write(IMPORT_TEMPLATE.format(
            base=base, md5=md5, uid=uid, normal=1 if is_normal else 0))


def main():
    tex_dir = os.path.normpath(TEX_DIR)
    made = 0
    for name, prof in sorted(PROFILES.items()):
        src = os.path.join(tex_dir, name + ".png")
        if not os.path.exists(src):
            print(f"  skip {name}: no albedo at {src}")
            continue
        w, h, nch, pix = read_png(src)
        lum = luminance(w, h, nch, pix)
        height = box_blur_wrap(lum, w, h, prof["blur"])

        n_path = os.path.join(tex_dir, f"{name}_normal.png")
        write_png(n_path, w, h, normal_map(height, w, h, prof["bump"]))
        write_import(n_path, True)

        o_path = os.path.join(tex_dir, f"{name}_orm.png")
        lo, hi = prof["rough"]
        write_png(o_path, w, h, orm_map(lum, w, h, lo, hi, prof["ao"], prof["metal"]))
        write_import(o_path, False)

        print(f"  {name}: {w}x{h} -> _normal.png + _orm.png")
        made += 1
    print(f"generated {made} texture pairs in {tex_dir}")
    return 0 if made else 1


if __name__ == "__main__":
    sys.exit(main())
