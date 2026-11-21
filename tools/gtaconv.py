#!/usr/bin/env python3
"""gtaconv - asset converter and optimiser for NEON CITY 6.

The game only needs three formats, so this tool implements exactly those,
with the Python standard library and no third-party packages:

  * PNG  -> box-filtered, metadata-stripped PNG (+ optional mip chain)
  * WAV  -> mono, resampled 16-bit WAV (loop-safe)
  * OBJ  -> binary glTF 2.0 (.glb) with vertex-cluster LOD and welded normals

Commands
--------
  optimize FILE [-o OUT] [options]   convert one file
  pack SRC -o OUT [options]          convert a tree + manifest.json + budget
  verify MANIFEST [--budget-mb N]    re-hash every entry, check the budget
  info FILE                          print what the optimiser sees

Examples
--------
  python3 tools/gtaconv.py pack assets -o build/optimized --budget-mb 25
  python3 tools/gtaconv.py optimize car.obj -o car.glb --ratio 0.5
  python3 tools/gtaconv.py optimize sign.png --max-texture 256 --mips
  python3 tools/gtaconv.py verify build/optimized/manifest.json --budget-mb 25
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import struct
import sys
import tempfile
import wave
import zlib

VERSION = "1.0.0"
PNG_SIG = b"\x89PNG\r\n\x1a\n"
GLB_MAGIC = 0x46546C67


# ---------------------------------------------------------------------------
# PNG
# ---------------------------------------------------------------------------
class PngError(ValueError):
    pass


def png_decode(data: bytes):
    """Return (width, height, RGBA bytearray). 8/16-bit, non-interlaced."""
    if not data.startswith(PNG_SIG):
        raise PngError("not a PNG")
    pos = 8
    w = h = depth = ctype = interlace = 0
    palette = b""
    trns = b""
    idat = bytearray()
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            w, h, depth, ctype, _comp, _filt, interlace = struct.unpack(">IIBBBBB", body)
        elif tag == b"PLTE":
            palette = body
        elif tag == b"tRNS":
            trns = body
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    if w <= 0 or h <= 0:
        raise PngError("missing IHDR")
    if interlace:
        raise PngError("interlaced PNG is not supported; re-save it non-interlaced")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if channels is None:
        raise PngError("unsupported colour type %d" % ctype)
    if depth not in (8, 16) and not (ctype == 3 and depth in (1, 2, 4, 8)):
        raise PngError("unsupported bit depth %d" % depth)
    if ctype == 3 and not palette:
        raise PngError("palette PNG without PLTE")

    bpp = max(1, (channels * depth) // 8)
    stride = (w * channels * depth + 7) // 8
    raw = zlib.decompress(bytes(idat))
    lines = _png_unfilter(raw, w, h, bpp, stride)
    out = bytearray(w * h * 4)

    def sample(line, i, channel, maxv):
        if depth == 8:
            return line[i * channels + channel]
        if depth == 16:
            j = (i * channels + channel) * 2
            return line[j]
        # sub-byte palette indices
        bit = i * depth
        byte = line[bit // 8]
        shift = 8 - depth - (bit % 8)
        return (byte >> shift) & ((1 << depth) - 1)

    maxv = (1 << depth) - 1
    for y in range(h):
        line = lines[y]
        for x in range(w):
            o = (y * w + x) * 4
            if ctype == 3:
                idx = sample(line, x, 0, maxv)
                if idx * 3 + 2 >= len(palette):
                    raise PngError("palette index out of range")
                out[o] = palette[idx * 3]
                out[o + 1] = palette[idx * 3 + 1]
                out[o + 2] = palette[idx * 3 + 2]
                out[o + 3] = trns[idx] if idx < len(trns) else 255
            elif ctype == 0:
                g = sample(line, x, 0, maxv)
                out[o] = out[o + 1] = out[o + 2] = g
                out[o + 3] = 255
            elif ctype == 4:
                g = sample(line, x, 0, maxv)
                a = sample(line, x, 1, maxv)
                out[o] = out[o + 1] = out[o + 2] = g
                out[o + 3] = a
            elif ctype == 2:
                out[o] = sample(line, x, 0, maxv)
                out[o + 1] = sample(line, x, 1, maxv)
                out[o + 2] = sample(line, x, 2, maxv)
                out[o + 3] = 255
            else:
                out[o] = sample(line, x, 0, maxv)
                out[o + 1] = sample(line, x, 1, maxv)
                out[o + 2] = sample(line, x, 2, maxv)
                out[o + 3] = sample(line, x, 3, maxv)
    return w, h, out


def _png_unfilter(raw, w, h, bpp, stride):
    if len(raw) < (stride + 1) * h:
        raise PngError("truncated image data")
    lines = []
    prev = bytearray(stride)
    pos = 0
    for _y in range(h):
        ft = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ft == 0:
            pass
        elif ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        else:
            raise PngError("bad filter type %d" % ft)
        lines.append(line)
        prev = line
    return lines


def png_encode(w: int, h: int, rgba: bytes) -> bytes:
    def chunk(tag: bytes, body: bytes) -> bytes:
        return (struct.pack(">I", len(body)) + tag + body +
                struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]
    return (PNG_SIG +
            chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
            chunk(b"IEND", b""))


def png_resize(w, h, rgba, nw, nh):
    if (nw, nh) == (w, h):
        return bytearray(rgba)
    out = bytearray(nw * nh * 4)
    for y in range(nh):
        y0 = y * h // nh
        y1 = max(y0 + 1, (y + 1) * h // nh)
        for x in range(nw):
            x0 = x * w // nw
            x1 = max(x0 + 1, (x + 1) * w // nw)
            r = g = b = a = 0
            n = 0
            for yy in range(y0, y1):
                base = (yy * w + x0) * 4
                for _xx in range(x0, x1):
                    r += rgba[base]
                    g += rgba[base + 1]
                    b += rgba[base + 2]
                    a += rgba[base + 3]
                    base += 4
                    n += 1
            o = (y * nw + x) * 4
            out[o] = r // n
            out[o + 1] = g // n
            out[o + 2] = b // n
            out[o + 3] = a // n
    return out


def optimize_png(src: str, dst: str, max_texture: int, mips: bool):
    with open(src, "rb") as f:
        w, h, rgba = png_decode(f.read())
    scale = min(1.0, max_texture / float(max(w, h)))
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    rgba = png_resize(w, h, rgba, nw, nh)
    with open(dst, "wb") as f:
        f.write(png_encode(nw, nh, rgba))
    outputs = [dst]
    if mips:
        pw, ph, cur = nw, nh, rgba
        level = 1
        stem, _ext = os.path.splitext(dst)
        while pw > 1 or ph > 1:
            cw, ch = max(1, pw // 2), max(1, ph // 2)
            cur = png_resize(pw, ph, cur, cw, ch)
            path = "%s_mip%d.png" % (stem, level)
            with open(path, "wb") as f:
                f.write(png_encode(cw, ch, cur))
            outputs.append(path)
            pw, ph = cw, ch
            level += 1
    return {"kind": "texture", "width": nw, "height": nh,
            "source_width": w, "source_height": h, "outputs": outputs}


# ---------------------------------------------------------------------------
# WAV
# ---------------------------------------------------------------------------
def wav_read(path: str):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")
    pos = 12
    fmt = None
    raw = b""
    while pos + 8 <= len(data):
        tag = data[pos:pos + 4]
        (size,) = struct.unpack("<I", data[pos + 4:pos + 8])
        body = data[pos + 8:pos + 8 + size]
        pos += 8 + size + (size & 1)
        if tag == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
            if fmt[0] == 0xFFFE and len(body) >= 26:
                # WAVE_FORMAT_EXTENSIBLE: the real format is the first two
                # bytes of the SubFormat GUID.
                fmt = (struct.unpack("<H", body[24:26])[0],) + fmt[1:]
        elif tag == b"data":
            raw = body
    if fmt is None:
        raise ValueError("missing fmt chunk")
    tag, channels, rate, _byterate, _align, bits = fmt
    if tag not in (1, 3):
        raise ValueError("unsupported WAV format %d" % tag)
    samples = []
    if tag == 3:
        n = len(raw) // 4
        for i in range(n):
            samples.append(struct.unpack("<f", raw[i * 4:i * 4 + 4])[0])
    elif bits == 8:
        samples = [(b - 128) / 128.0 for b in raw]
    elif bits == 16:
        n = len(raw) // 2
        samples = [struct.unpack("<h", raw[i * 2:i * 2 + 2])[0] / 32768.0 for i in range(n)]
    elif bits == 24:
        for i in range(0, len(raw) - 2, 3):
            v = raw[i] | (raw[i + 1] << 8) | (raw[i + 2] << 16)
            if v & 0x800000:
                v -= 0x1000000
            samples.append(v / 8388608.0)
    elif bits == 32:
        n = len(raw) // 4
        samples = [struct.unpack("<i", raw[i * 4:i * 4 + 4])[0] / 2147483648.0 for i in range(n)]
    else:
        raise ValueError("unsupported bit depth %d" % bits)
    if channels < 1:
        raise ValueError("bad channel count")
    if channels > 1:
        mixed = []
        frames = len(samples) // channels
        for i in range(frames):
            mixed.append(sum(samples[i * channels:(i + 1) * channels]) / channels)
        samples = mixed
    return rate, samples


def wav_write(path: str, rate: int, samples):
    peak = max([abs(s) for s in samples] + [1e-9])
    gain = 0.89 / peak if peak > 0.89 else 1.0
    data = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s * gain)) * 32767)
        data += struct.pack("<h", v)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(bytes(data))


def optimize_wav(src: str, dst: str, rate: int):
    old_rate, samples = wav_read(src)
    if rate and rate != old_rate and samples:
        ratio = rate / float(old_rate)
        n = max(1, int(len(samples) * ratio))
        out = []
        last = len(samples) - 1
        for i in range(n):
            x = i / ratio
            i0 = int(x)
            frac = x - i0
            s0 = samples[min(i0, last)]
            s1 = samples[min(i0 + 1, last)]
            out.append(s0 + (s1 - s0) * frac)
        samples = out
        old_rate = rate
    wav_write(dst, old_rate, samples)
    return {"kind": "audio", "rate": old_rate, "seconds": round(len(samples) / old_rate, 3)}


# ---------------------------------------------------------------------------
# OBJ -> GLB
# ---------------------------------------------------------------------------
def obj_load(path: str):
    verts, uvs, normals = [], [], []
    tris = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "v" and len(parts) >= 4:
                verts.append((float(parts[1]), float(parts[2]), float(parts[3])))
            elif parts[0] == "vt" and len(parts) >= 3:
                uvs.append((float(parts[1]), float(parts[2])))
            elif parts[0] == "vn" and len(parts) >= 4:
                normals.append((float(parts[1]), float(parts[2]), float(parts[3])))
            elif parts[0] == "f" and len(parts) >= 4:
                face = []
                for token in parts[1:]:
                    bits = token.split("/")
                    vi = int(bits[0])
                    ti = int(bits[1]) if len(bits) > 1 and bits[1] else 0
                    ni = int(bits[2]) if len(bits) > 2 and bits[2] else 0
                    vi = vi - 1 if vi > 0 else len(verts) + vi
                    ti = ti - 1 if ti > 0 else (len(uvs) + ti if ti else -1)
                    ni = ni - 1 if ni > 0 else (len(normals) + ni if ni else -1)
                    if not (0 <= vi < len(verts)):
                        raise ValueError("OBJ face references missing vertex")
                    face.append((vi, ti, ni))
                for k in range(1, len(face) - 1):
                    tris.append((face[0], face[k], face[k + 1]))
    if not verts or not tris:
        raise ValueError("OBJ contains no geometry")
    return verts, uvs, normals, tris


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _norm(v):
    ln = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if ln < 1e-12:
        return (0.0, 0.0, 0.0)
    return (v[0] / ln, v[1] / ln, v[2] / ln)


def obj_to_mesh(verts, uvs, normals, tris, ratio=1.0):
    """Vertex-cluster LOD + index build. Returns positions, uvs, normals, indices."""
    has_uv = any(t[0][1] >= 0 for t in tris) and bool(uvs)
    has_n = any(t[0][2] >= 0 for t in tris) and bool(normals)

    # Attribute references per source vertex (a vertex can be used with
    # several UVs/normals on a seam).
    vuv = {}
    vn = {}
    for tri in tris:
        for vi, ti, ni in tri:
            if has_uv and ti >= 0:
                vuv.setdefault(vi, []).append(ti)
            if has_n and ni >= 0:
                vn.setdefault(vi, []).append(ni)

    if ratio < 1.0:
        # Cluster vertices in a regular grid and average the attributes inside
        # every cell. Deterministic, dependency-free LOD generation.
        xs = [v[0] for v in verts]
        ys = [v[1] for v in verts]
        zs = [v[2] for v in verts]
        diag = math.sqrt((max(xs) - min(xs)) ** 2 + (max(ys) - min(ys)) ** 2 +
                         (max(zs) - min(zs)) ** 2)
        cell = max(1e-6, diag * (1.0 - max(0.02, min(0.98, ratio))) * 0.55)
        key_to_idx = {}
        cluster_of = [0] * len(verts)
        sums = []
        for i, v in enumerate(verts):
            key = (int(math.floor(v[0] / cell)), int(math.floor(v[1] / cell)),
                   int(math.floor(v[2] / cell)))
            ci = key_to_idx.get(key)
            if ci is None:
                ci = len(sums)
                key_to_idx[key] = ci
                sums.append([0.0, 0.0, 0.0, 0])
            cluster_of[i] = ci
            s = sums[ci]
            s[0] += v[0]
            s[1] += v[1]
            s[2] += v[2]
            s[3] += 1
        positions = [(s[0] / s[3], s[1] / s[3], s[2] / s[3]) for s in sums]

        texcoords = []
        if has_uv:
            uv_acc = [[0.0, 0.0, 0] for _ in positions]
            for vi, refs in vuv.items():
                ci = cluster_of[vi]
                for ti in refs:
                    if 0 <= ti < len(uvs):
                        uv_acc[ci][0] += uvs[ti][0]
                        uv_acc[ci][1] += uvs[ti][1]
                        uv_acc[ci][2] += 1
            texcoords = [(s[0] / s[2], s[1] / s[2]) if s[2] else (0.0, 0.0)
                         for s in uv_acc]

        norms = []
        if has_n:
            n_acc = [[0.0, 0.0, 0.0, 0] for _ in positions]
            for vi, refs in vn.items():
                ci = cluster_of[vi]
                for ni in refs:
                    if 0 <= ni < len(normals):
                        n_acc[ci][0] += normals[ni][0]
                        n_acc[ci][1] += normals[ni][1]
                        n_acc[ci][2] += normals[ni][2]
                        n_acc[ci][3] += 1
            norms = [_norm((s[0], s[1], s[2])) if s[3] else (0.0, 1.0, 0.0)
                     for s in n_acc]

        indices = []
        seen = set()
        for a, b, c in tris:
            ia, ib, ic = cluster_of[a[0]], cluster_of[b[0]], cluster_of[c[0]]
            if ia == ib or ib == ic or ia == ic:
                continue
            key = tuple(sorted((ia, ib, ic)))
            if key in seen:
                continue
            seen.add(key)
            indices.extend((ia, ib, ic))

        if not has_n:
            norms = _vertex_normals(positions, indices)
        return positions, (texcoords if has_uv else []), norms, indices

    keymap = {}
    positions, texcoords, norms, indices = [], [], [], []

    def vidx(vi, ti, ni):
        key = (vi, ti if has_uv else -1, ni if has_n else -1)
        if key in keymap:
            return keymap[key]
        idx = len(positions)
        keymap[key] = idx
        positions.append(verts[vi])
        if has_uv:
            texcoords.append(uvs[ti] if 0 <= ti < len(uvs) else (0.0, 0.0))
        if has_n:
            norms.append(normals[ni] if 0 <= ni < len(normals) else (0.0, 1.0, 0.0))
        return idx

    seen = set()
    for a, b, c in tris:
        ia, ib, ic = vidx(*a), vidx(*b), vidx(*c)
        if ia == ib or ib == ic or ia == ic:
            continue
        key = tuple(sorted((ia, ib, ic)))
        if key in seen:
            continue
        seen.add(key)
        indices.extend((ia, ib, ic))

    if not has_n:
        norms = _vertex_normals(positions, indices)
    return positions, (texcoords if has_uv else []), norms, indices


def _vertex_normals(positions, indices):
    acc = [[0.0, 0.0, 0.0] for _ in positions]
    for k in range(0, len(indices), 3):
        ia, ib, ic = indices[k:k + 3]
        n = _cross(_sub(positions[ib], positions[ia]),
                   _sub(positions[ic], positions[ia]))
        for idx in (ia, ib, ic):
            acc[idx][0] += n[0]
            acc[idx][1] += n[1]
            acc[idx][2] += n[2]
    return [_norm(tuple(v)) for v in acc]


def _align4(n: int) -> int:
    return (n + 3) & ~3


def glb_write(path: str, positions, uvs, normals, indices, name="mesh"):
    pos_bytes = b"".join(struct.pack("<3f", *p) for p in positions)
    nrm_bytes = b"".join(struct.pack("<3f", *n) for n in normals)
    uv_bytes = b"".join(struct.pack("<2f", *t) for t in uvs)
    idx_bytes = b"".join(struct.pack("<I", i) for i in indices)

    views = []
    bin_parts = []
    offset = 0

    def add_view(data: bytes, target=None):
        nonlocal offset
        while offset % 4:
            bin_parts.append(b"\x00")
            offset += 1
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        views.append(view)
        bin_parts.append(data)
        offset += len(data)
        return len(views) - 1

    v_pos = add_view(pos_bytes, 34962)
    v_nrm = add_view(nrm_bytes, 34962)
    v_uv = add_view(uv_bytes, 34962) if uvs else None
    v_idx = add_view(idx_bytes, 34963)
    while offset % 4:
        bin_parts.append(b"\x00")
        offset += 1
    bin_blob = b"".join(bin_parts)

    mins = [min(p[i] for p in positions) for i in range(3)]
    maxs = [max(p[i] for p in positions) for i in range(3)]
    accessors = [
        {"bufferView": v_pos, "componentType": 5126, "count": len(positions),
         "type": "VEC3", "min": mins, "max": maxs},
        {"bufferView": v_nrm, "componentType": 5126, "count": len(normals),
         "type": "VEC3"},
    ]
    attrs = {"POSITION": 0, "NORMAL": 1}
    if v_uv is not None:
        accessors.append({"bufferView": v_uv, "componentType": 5126,
                          "count": len(uvs), "type": "VEC2"})
        attrs["TEXCOORD_0"] = 2
    idx_accessor = len(accessors)
    accessors.append({"bufferView": v_idx, "componentType": 5125,
                      "count": len(indices), "type": "SCALAR"})

    doc = {
        "asset": {"version": "2.0", "generator": "gtaconv %s" % VERSION},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": attrs, "indices": idx_accessor, "mode": 4,
            "material": 0}]}],
        "materials": [{"name": "default", "pbrMetallicRoughness": {
            "baseColorFactor": [0.8, 0.8, 0.8, 1.0],
            "metallicFactor": 0.05, "roughnessFactor": 0.85}}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_blob)}],
    }
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(bin_blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(bin_blob), 0x004E4942))
        f.write(bin_blob)
    return len(positions), len(indices) // 3


def glb_read(path: str):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack("<III", data[:12])
    if magic != GLB_MAGIC or version != 2:
        raise ValueError("not a glTF 2.0 binary")
    pos = 12
    doc = None
    blob = b""
    while pos + 8 <= len(data):
        size, kind = struct.unpack("<II", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + size]
        pos += 8 + size
        if kind == 0x4E4F534A:
            doc = json.loads(body.decode("utf-8"))
        elif kind == 0x004E4942:
            blob = body
    if doc is None:
        raise ValueError("GLB has no JSON chunk")
    return doc, blob


def optimize_obj(src: str, dst: str, ratio: float):
    verts, uvs, normals, tris = obj_load(src)
    positions, texcoords, norms, indices = obj_to_mesh(verts, uvs, normals, tris, ratio)
    name = os.path.splitext(os.path.basename(dst))[0]
    nv, nt = glb_write(dst, positions, texcoords, norms, indices, name)
    return {"kind": "model", "vertices": nv, "triangles": nt,
            "source_vertices": len(verts), "source_triangles": len(tris)}


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
def optimize_file(src: str, dst: str, args) -> dict:
    ext = os.path.splitext(src)[1].lower()
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    if ext == ".png":
        return optimize_png(src, dst, args.max_texture, args.mips)
    if ext == ".wav":
        return optimize_wav(src, dst, args.rate)
    if ext == ".obj":
        return optimize_obj(src, dst, args.ratio)
    raise ValueError("unsupported input %s (PNG, WAV and OBJ are supported)" % ext)


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 16), b""):
            h.update(block)
    return h.hexdigest()


def cmd_optimize(args) -> int:
    dst = args.output
    if dst is None:
        base = os.path.splitext(args.input)[0]
        dst = base + ".glb" if args.input.lower().endswith(".obj") else base + ".opt" + os.path.splitext(args.input)[1]
    info = optimize_file(args.input, dst, args)
    info["source"] = args.input
    info["output"] = dst
    info["bytes_before"] = os.path.getsize(args.input)
    info["bytes_after"] = sum(os.path.getsize(p) for p in info.get("outputs", [dst]))
    info["sha256"] = _sha256(dst)
    print(json.dumps(info, indent=2))
    return 0


def cmd_pack(args) -> int:
    src = args.input
    out = args.output
    if not os.path.isdir(src):
        print("error: %s is not a directory" % src, file=sys.stderr)
        return 2
    os.makedirs(out, exist_ok=True)
    entries = []
    total_before = total_after = 0
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for name in sorted(files):
            if name == "manifest.json":
                continue
            full = os.path.join(root, name)
            rel = os.path.relpath(full, src)
            ext = os.path.splitext(name)[1].lower()
            before = os.path.getsize(full)
            total_before += before
            if ext in (".png", ".wav", ".obj"):
                rel_out = os.path.splitext(rel)[0] + (".glb" if ext == ".obj" else ext)
                dst = os.path.join(out, rel_out)
                try:
                    info = optimize_file(full, dst, args)
                except (ValueError, PngError) as exc:
                    print("error: %s: %s" % (rel, exc), file=sys.stderr)
                    return 2
                after = sum(os.path.getsize(p) for p in info.get("outputs", [dst]))
                entries.append({"source": rel, "output": rel_out,
                                "kind": info["kind"], "bytes_before": before,
                                "bytes_after": after, "sha256": _sha256(dst)})
            else:
                dst = os.path.join(out, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(full, dst)
                after = os.path.getsize(dst)
                entries.append({"source": rel, "output": rel, "kind": "copy",
                                "bytes_before": before, "bytes_after": after,
                                "sha256": _sha256(dst)})
            total_after += after
    manifest = {
        "generator": "gtaconv %s" % VERSION,
        "source": os.path.abspath(src),
        "budget_mb": args.budget_mb,
        "total_bytes_before": total_before,
        "total_bytes_after": total_after,
        "saved_percent": round(100.0 * (1 - total_after / max(1, total_before)), 2),
        "entries": entries,
    }
    path = os.path.join(out, "manifest.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("packed %d files: %.1f KiB -> %.1f KiB (%.1f%% saved)"
          % (len(entries), total_before / 1024.0, total_after / 1024.0,
             manifest["saved_percent"]))
    print("manifest:", path)
    if args.budget_mb and total_after > args.budget_mb * 1024 * 1024:
        print("error: %.2f MiB exceeds the %.2f MiB budget"
              % (total_after / 1048576.0, args.budget_mb), file=sys.stderr)
        return 3
    return 0


def cmd_verify(args) -> int:
    with open(args.manifest, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    base = os.path.dirname(os.path.abspath(args.manifest))
    total = 0
    bad = 0
    for e in manifest.get("entries", []):
        path = os.path.join(base, e["output"])
        if not os.path.exists(path):
            print("MISSING", e["output"])
            bad += 1
            continue
        size = os.path.getsize(path)
        total += size
        digest = _sha256(path)
        if digest != e["sha256"]:
            print("HASH MISMATCH", e["output"])
            bad += 1
        elif size != e["bytes_after"]:
            print("SIZE MISMATCH", e["output"])
            bad += 1
    budget = args.budget_mb if args.budget_mb is not None else manifest.get("budget_mb")
    over = budget is not None and total > budget * 1024 * 1024
    print("verified %d entries, %d bad, %.2f MiB%s"
          % (len(manifest.get("entries", [])), bad, total / 1048576.0,
             "" if budget is None else " (budget %.2f MiB%s)"
             % (budget, ", OVER" if over else "")))
    if bad or over:
        return 1
    return 0


def cmd_info(args) -> int:
    ext = os.path.splitext(args.input)[1].lower()
    if ext == ".png":
        with open(args.input, "rb") as f:
            w, h, rgba = png_decode(f.read())
        print(json.dumps({"kind": "texture", "width": w, "height": h,
                          "bytes": os.path.getsize(args.input)}))
    elif ext == ".wav":
        rate, samples = wav_read(args.input)
        print(json.dumps({"kind": "audio", "rate": rate,
                          "seconds": round(len(samples) / rate, 3),
                          "bytes": os.path.getsize(args.input)}))
    elif ext == ".obj":
        verts, uvs, normals, tris = obj_load(args.input)
        print(json.dumps({"kind": "obj", "vertices": len(verts),
                          "uvs": len(uvs), "normals": len(normals),
                          "triangles": len(tris)}))
    elif ext == ".glb":
        doc, blob = glb_read(args.input)
        tris = 0
        for mesh in doc.get("meshes", []):
            for prim in mesh.get("primitives", []):
                acc = doc["accessors"][prim["indices"]]
                tris += acc["count"] // 3
        print(json.dumps({"kind": "glb", "triangles": tris,
                          "bin_bytes": len(blob)}))
    else:
        print(json.dumps({"kind": "unknown", "bytes": os.path.getsize(args.input)}))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gtaconv",
        description="Asset converter/optimiser for NEON CITY 6 (PNG, WAV, OBJ).")
    p.add_argument("--version", action="version", version=VERSION)
    sub = p.add_subparsers(dest="command", required=True)

    def common(sp):
        sp.add_argument("--max-texture", type=int, default=1024,
                        help="longest texture side in pixels (default 1024)")
        sp.add_argument("--mips", action="store_true", help="write a PNG mip chain")
        sp.add_argument("--rate", type=int, default=22050, help="WAV sample rate")
        sp.add_argument("--ratio", type=float, default=0.6,
                        help="target vertex ratio for OBJ LOD (0..1)")

    o = sub.add_parser("optimize", help="convert one file")
    o.add_argument("input")
    o.add_argument("-o", "--output")
    common(o)
    o.set_defaults(func=cmd_optimize)

    pk = sub.add_parser("pack", help="convert a directory and write manifest.json")
    pk.add_argument("input")
    pk.add_argument("-o", "--output", required=True)
    pk.add_argument("--budget-mb", type=float, default=25.0)
    common(pk)
    pk.set_defaults(func=cmd_pack)

    v = sub.add_parser("verify", help="verify a manifest and its files")
    v.add_argument("manifest")
    v.add_argument("--budget-mb", type=float, default=None)
    v.set_defaults(func=cmd_verify)

    i = sub.add_parser("info", help="inspect a file")
    i.add_argument("input")
    i.set_defaults(func=cmd_info)
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (OSError, ValueError, PngError, struct.error) as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
