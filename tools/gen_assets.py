#!/usr/bin/env python3
"""Generate every texture and sound NEON CITY 6 ships with.

Nothing here is sampled from another game: facades, roads, the icon and all
music/SFX are synthesised from maths with the Python standard library only.

    python3 tools/gen_assets.py [--force]

Outputs:
    assets/textures/*.png
    assets/audio/*.wav
"""
from __future__ import annotations

import argparse
import math
import os
import random
import struct
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "textures")
AUD = os.path.join(ROOT, "assets", "audio")
RATE = 22050


# ---------------------------------------------------------------------------
# PNG writer (RGBA8, no external dependencies)
# ---------------------------------------------------------------------------
def write_png(path: str, w: int, h: int, rgba: bytes | bytearray) -> None:
    assert len(rgba) == w * h * 4, (len(rgba), w, h)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def blank(w: int, h: int, col=(0, 0, 0, 255)) -> bytearray:
    return bytearray(bytes(col) * (w * h))


def put(buf: bytearray, w: int, h: int, x: int, y: int, col) -> None:
    if 0 <= x < w and 0 <= y < h:
        i = (y * w + x) * 4
        buf[i:i + 4] = bytes(col)


def rect(buf, w, h, x0, y0, x1, y1, col) -> None:
    for y in range(max(0, y0), min(h, y1)):
        i = (y * w + max(0, x0)) * 4
        for _ in range(max(0, x1) - max(0, x0)):
            buf[i:i + 4] = bytes(col)
            i += 4


def blend(dst, src, a: float):
    return (int(dst[0] * (1 - a) + src[0] * a),
            int(dst[1] * (1 - a) + src[1] * a),
            int(dst[2] * (1 - a) + src[2] * a),
            255)


def circle(buf, w, h, cx, cy, r, col) -> None:
    for y in range(max(0, int(cy - r)), min(h, int(cy + r) + 1)):
        for x in range(max(0, int(cx - r)), min(w, int(cx + r) + 1)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                put(buf, w, h, x, y, col)


# ---------------------------------------------------------------------------
# Textures
# ---------------------------------------------------------------------------
def tex_asphalt() -> None:
    w = h = 256
    rng = random.Random(101)
    buf = blank(w, h)
    for y in range(h):
        for x in range(w):
            n = rng.randint(-12, 12)
            v = 46 + n
            i = (y * w + x) * 4
            buf[i:i + 4] = bytes((v, v, v + 4, 255))
    for _ in range(18):  # cracks
        x, y = rng.randrange(w), rng.randrange(h)
        for _ in range(rng.randint(10, 40)):
            put(buf, w, h, x, y, (26, 26, 30, 255))
            x += rng.choice((-1, 0, 1))
            y += rng.choice((-1, 0, 1))
    write_png(os.path.join(TEX, "asphalt.png"), w, h, buf)


def tex_road() -> None:
    w, h = 128, 512
    rng = random.Random(202)
    buf = blank(w, h)
    for y in range(h):
        for x in range(w):
            v = 42 + rng.randint(-8, 8)
            i = (y * w + x) * 4
            buf[i:i + 4] = bytes((v, v, v + 3, 255))
    for x0, col in ((5, (225, 225, 215, 255)), (119, (225, 225, 215, 255))):
        rect(buf, w, h, x0, 0, x0 + 4, h, col)
    for y in range(0, h, 120):
        rect(buf, w, h, 61, y, 67, y + 62, (230, 200, 70, 255))
    write_png(os.path.join(TEX, "road.png"), w, h, buf)


def tex_sidewalk() -> None:
    w = h = 128
    rng = random.Random(303)
    buf = blank(w, h)
    for y in range(h):
        for x in range(w):
            v = 118 + rng.randint(-6, 6)
            i = (y * w + x) * 4
            buf[i:i + 4] = bytes((v, v, v + 6, 255))
    for k in range(0, w, 32):
        rect(buf, w, h, k, 0, k + 2, h, (78, 78, 88, 255))
        rect(buf, w, h, 0, k, w, k + 2, (78, 78, 88, 255))
    write_png(os.path.join(TEX, "sidewalk.png"), w, h, buf)


def tex_grass() -> None:
    w = h = 128
    rng = random.Random(404)
    buf = blank(w, h)
    for y in range(h):
        for x in range(w):
            v = rng.randint(0, 20)
            i = (y * w + x) * 4
            buf[i:i + 4] = bytes((24 + v // 2, 62 + v, 32 + v // 2, 255))
    write_png(os.path.join(TEX, "grass.png"), w, h, buf)


def tex_roof() -> None:
    w = h = 128
    rng = random.Random(505)
    buf = blank(w, h)
    for y in range(h):
        for x in range(w):
            v = 54 + rng.randint(-10, 10)
            i = (y * w + x) * 4
            buf[i:i + 4] = bytes((v, v, v + 2, 255))
    for _ in range(40):
        x, y = rng.randrange(w), rng.randrange(h)
        rect(buf, w, h, x, y, x + 3, y + 3, (34, 34, 38, 255))
    write_png(os.path.join(TEX, "roof.png"), w, h, buf)


FACADE_WALLS = [
    ((26, 30, 52), (40, 44, 74)),
    ((44, 26, 38), (66, 38, 54)),
    ((22, 40, 46), (34, 58, 66)),
    ((40, 36, 24), (58, 52, 34)),
]
LIT = [
    (255, 206, 128), (255, 232, 190), (150, 230, 255), (255, 160, 210),
    (190, 255, 200), (255, 245, 160),
]


def tex_facade(idx: int) -> None:
    w = h = 256
    rng = random.Random(700 + idx)
    wall_a, wall_b = FACADE_WALLS[idx]
    albedo = blank(w, h)
    emit = blank(w, h, (0, 0, 0, 255))
    for y in range(h):
        for x in range(w):
            k = (x + y) / (w + h)
            c = tuple(int(wall_a[i] + (wall_b[i] - wall_a[i]) * k) for i in range(3))
            c = tuple(max(0, min(255, v + rng.randint(-4, 4))) for v in c)
            i = (y * w + x) * 4
            albedo[i:i + 4] = bytes(c + (255,))
    cols, rows = 4, 4
    cw, ch = w // cols, h // rows
    for cy in range(rows):
        for cx in range(cols):
            x0 = cx * cw + 12
            y0 = cy * ch + 10
            x1 = x0 + cw - 24
            y1 = y0 + ch - 22
            lit = rng.random() < 0.42
            if lit:
                col = rng.choice(LIT)
                glass = tuple(int(v * 0.55) for v in col) + (255,)
            else:
                glass = (18, 24, 36, 255)
            rect(albedo, w, h, x0, y0, x1, y1, glass)
            rect(albedo, w, h, x0, y0, x1, y0 + 3, (70, 74, 90, 255))
            if lit:
                rect(emit, w, h, x0, y0, x1, y1, col + (255,))
    write_png(os.path.join(TEX, "facade_%d.png" % idx), w, h, albedo)
    write_png(os.path.join(TEX, "facade_%d_emit.png" % idx), w, h, emit)


# ---------------------------------------------------------------------------
# Icon (bitmap lettering, no font files)
# ---------------------------------------------------------------------------
FONT = {
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    " ": ["00000"] * 7,
}


def draw_glyph(buf, w, h, ch, x, y, scale, col) -> None:
    for gy, row in enumerate(FONT[ch]):
        for gx, bit in enumerate(row):
            if bit == "1":
                rect(buf, w, h, x + gx * scale, y + gy * scale,
                     x + (gx + 1) * scale, y + (gy + 1) * scale, col)


def draw_icon(size: int, foreground_only=False, background_only=False) -> bytearray:
    w = h = size
    rng = random.Random(666)
    buf = blank(w, h, (0, 0, 0, 0) if foreground_only else (6, 4, 14, 255))
    if not foreground_only:
        for y in range(h):
            k = y / h
            col = (int(8 + 22 * k), int(4 + 6 * k), int(22 + 34 * k), 255)
            rect(buf, w, h, 0, y, w, y + 1, col)
        # horizon glow
        for y in range(int(h * 0.42), int(h * 0.72)):
            a = 0.35 * (1 - abs(y - h * 0.57) / (h * 0.15))
            for x in range(w):
                i = (y * w + x) * 4
                buf[i:i + 4] = bytes(blend(tuple(buf[i:i + 4]),
                                           (120, 20, 90), max(0.0, a)))
        # grid
        horizon = int(h * 0.60)
        for i in range(9):
            x = int(w * 0.5 + (i - 4) * w * 0.22)
            for y in range(horizon, h):
                t = (y - horizon) / max(1, h - horizon)
                xx = int(w * 0.5 + (x - w * 0.5) * (0.35 + t * 2.2))
                if 0 <= xx < w:
                    put(buf, w, h, xx, y, (110, 30, 95, 255))
        for i in range(6):
            y = horizon + int((h - horizon) * (i / 5.0) ** 2)
            rect(buf, w, h, 0, y, w, y + 1, (110, 30, 95, 255))
        # skyline
        x = 0
        while x < w:
            bw = rng.randint(int(w * 0.05), int(w * 0.11))
            bh = rng.randint(int(h * 0.08), int(h * 0.24))
            rect(buf, w, h, x, horizon - bh, x + bw, horizon, (10, 8, 26, 255))
            for _ in range(rng.randint(1, 3)):
                wx = x + rng.randint(2, max(3, bw - 4))
                wy = horizon - rng.randint(4, max(5, bh - 4))
                put(buf, w, h, wx, wy, (120, 220, 255, 255))
            x += bw + rng.randint(2, 6)

    # Neon letters NC and a big 6.
    scale = max(3, size // 30)
    if background_only:
        return buf
    if foreground_only:
        gw = 5 * scale * 3 + scale * 2 * 2
        gx = (w - gw) // 2
        gy = (h - 7 * scale) // 2
        for ch in "NC6":
            for dx in range(-scale, scale + 1):
                for dy in range(-scale, scale + 1):
                    if dx * dx + dy * dy <= scale * scale:
                        draw_glyph(buf, w, h, ch, gx + dx, gy + dy, scale,
                                   (255, 40, 140, 70))
            draw_glyph(buf, w, h, ch, gx, gy, scale, (255, 40, 150, 255))
            gx += 5 * scale + 2 * scale
        return buf

    total_w = 5 * scale * 3 + 2 * scale * 2
    gx = (w - total_w) // 2
    gy = int(h * 0.52)
    for ch in "NC6":
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                if dx * dx + dy * dy <= 9:
                    draw_glyph(buf, w, h, ch, gx + dx, gy + dy, scale,
                               (255, 30, 120, 45))
        draw_glyph(buf, w, h, ch, gx, gy, scale, (255, 40, 150, 255))
        draw_glyph(buf, w, h, ch, gx - scale // 3, gy - scale // 3, scale,
                   (120, 240, 255, 90))
        gx += 5 * scale + 2 * scale
    for y in range(0, h, 3):
        rect(buf, w, h, 0, y, w, y + 1, (0, 0, 0, 30))
    return buf


def tex_icons() -> None:
    write_png(os.path.join(TEX, "icon_512.png"), 512, 512, draw_icon(512))
    write_png(os.path.join(TEX, "icon_192.png"), 192, 192, draw_icon(192))
    write_png(os.path.join(TEX, "icon_432_fg.png"), 432, 432,
              draw_icon(432, foreground_only=True))
    write_png(os.path.join(TEX, "icon_432_bg.png"), 432, 432,
              draw_icon(432, background_only=True))


# ---------------------------------------------------------------------------
# Audio synthesis
# ---------------------------------------------------------------------------
def wav_write(path: str, samples, rate=RATE) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.86 / peak
    data = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s * gain)) * 32767)
        data += struct.pack("<h", v)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(bytes(data))


def env(t: float, dur: float, a=0.01, d=0.1, s=0.7, r=0.2) -> float:
    if t < 0 or t > dur:
        return 0.0
    if t < a:
        return t / a
    if t < a + d:
        return 1.0 - (1.0 - s) * (t - a) / d
    if t < dur - r:
        return s
    return max(0.0, s * (dur - t) / max(1e-6, r))


def note(freq: float, t: float, kind="sine") -> float:
    ph = 2.0 * math.pi * freq * t
    if kind == "sine":
        return math.sin(ph)
    if kind == "saw":
        return 2.0 * ((freq * t) % 1.0) - 1.0
    if kind == "square":
        return 1.0 if math.sin(ph) >= 0 else -1.0
    if kind == "tri":
        return 2.0 * abs(2.0 * ((freq * t) % 1.0) - 1.0) - 1.0
    return math.sin(ph)


NOTE = {
    "A2": 110.00, "C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61,
    "G3": 196.00, "A3": 220.00, "B3": 246.94, "C4": 261.63, "D4": 293.66,
    "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00, "B4": 493.88,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99,
    "A5": 880.00,
}

PROGRESSIONS = {
    "synth": [("A2", ["A3", "C4", "E4"]), ("F3", ["F3", "A3", "C4"]),
              ("C3", ["C4", "E4", "G4"]), ("G3", ["G3", "B3", "D4"])],
    "beat": [("A2", ["A3", "C4", "E4"]), ("G3", ["G3", "B3", "D4"]),
             ("F3", ["F3", "A3", "C4"]), ("E3", ["E3", "G3", "B3"])],
    "electro": [("D3", ["D4", "F4", "A4"]), ("C3", ["C4", "E4", "G4"]),
                ("A2", ["A3", "C4", "E4"]), ("G3", ["G3", "B3", "D4"])],
}


def make_track(style: str, seconds: float, bpm: float, seed: int) -> list:
    rng = random.Random(seed)
    n = int(seconds * RATE)
    out = [0.0] * n
    beat = 60.0 / bpm
    bar = beat * 4.0
    prog = PROGRESSIONS[style]
    bars = int(seconds / bar) + 1
    for b in range(bars):
        root_name, chord = prog[b % len(prog)]
        root = NOTE[root_name]
        t0 = b * bar
        # pad
        for cn in chord:
            f = NOTE[cn]
            for i in range(int(t0 * RATE), min(n, int((t0 + bar) * RATE))):
                t = i / RATE - t0
                e = env(t, bar, 0.18, 0.5, 0.55, 0.5)
                out[i] += 0.09 * e * note(f, i / RATE, "saw")
        # bass, eighth notes
        for k in range(8):
            st = t0 + k * beat * 0.5
            dur = beat * 0.42
            for i in range(int(st * RATE), min(n, int((st + dur) * RATE))):
                t = i / RATE - st
                out[i] += 0.16 * env(t, dur, 0.005, 0.08, 0.6, 0.06) * \
                    note(root, i / RATE, "square")
        # arpeggio, sixteenths
        if style != "beat" or b % 2 == 0:
            for k in range(16):
                st = t0 + k * beat * 0.25
                f = NOTE[chord[k % len(chord)]] * (2 if (k % 8) >= 4 else 1)
                dur = beat * 0.22
                for i in range(int(st * RATE), min(n, int((st + dur) * RATE))):
                    t = i / RATE - st
                    out[i] += 0.055 * env(t, dur, 0.003, 0.05, 0.25, 0.05) * \
                        note(f, i / RATE, "tri")
        # drums
        for k in range(4):
            st = t0 + k * beat
            if k in (0, 2):
                dur = 0.20
                for i in range(int(st * RATE), min(n, int((st + dur) * RATE))):
                    t = i / RATE - st
                    f = 110.0 * math.exp(-t * 18.0) + 42.0
                    out[i] += 0.30 * math.exp(-t * 16.0) * math.sin(2 * math.pi * f * t)
            if k in (1, 3):
                dur = 0.16
                for i in range(int(st * RATE), min(n, int((st + dur) * RATE))):
                    t = i / RATE - st
                    out[i] += 0.13 * math.exp(-t * 24.0) * rng.uniform(-1, 1)
            for h in (0, 2):
                st2 = t0 + k * beat + h * beat * 0.5
                dur = 0.05
                for i in range(int(st2 * RATE), min(n, int((st2 + dur) * RATE))):
                    t = i / RATE - st2
                    out[i] += 0.05 * math.exp(-t * 70.0) * rng.uniform(-1, 1)
    return out


def make_intro() -> list:
    seconds = 18.0
    n = int(seconds * RATE)
    out = [0.0] * n
    rng = random.Random(11)
    chords = [("A2", ["A3", "C4", "E4"]), ("F3", ["F3", "A3", "C4"]),
              ("C3", ["C4", "E4", "G4"]), ("G3", ["G3", "B3", "D4"])]
    bar = 3.0
    for b in range(6):
        root_name, chord = chords[b % len(chords)]
        t0 = b * bar
        for cn in chord:
            f = NOTE[cn]
            for i in range(int(t0 * RATE), min(n, int((t0 + bar) * RATE))):
                t = i / RATE - t0
                e = env(t, bar, 0.5, 0.6, 0.7, 0.7)
                out[i] += 0.10 * e * (note(f, i / RATE, "saw") +
                                      note(f * 2.0, i / RATE, "sine") * 0.4)
        for k in range(8):
            st = t0 + k * bar / 8.0
            f = NOTE[chord[k % len(chord)]]
            dur = bar / 8.0
            for i in range(int(st * RATE), min(n, int((st + dur) * RATE))):
                t = i / RATE - st
                out[i] += 0.06 * env(t, dur, 0.005, 0.08, 0.3, 0.08) * \
                    note(f, i / RATE, "tri")
    # riser + impact
    for i in range(n):
        t = i / RATE
        if 8.0 < t < 11.5:
            k = (t - 8.0) / 3.5
            out[i] += 0.10 * k * math.sin(2 * math.pi * (200 + 900 * k * k) * t)
        if 11.5 < t < 14.0:
            out[i] += 0.20 * math.exp(-(t - 11.5) * 2.2) * \
                math.sin(2 * math.pi * 55 * (t - 11.5))
    return out


def make_engine() -> list:
    seconds = 2.0
    n = int(seconds * RATE)
    out = []
    rng = random.Random(21)
    for i in range(n):
        t = i / RATE
        base = 52.0
        s = 0.45 * (2.0 * ((base * t) % 1.0) - 1.0)
        s += 0.25 * (2.0 * ((base * 2.0 * t) % 1.0) - 1.0)
        s += 0.12 * rng.uniform(-1, 1)
        s *= 0.65 + 0.35 * math.sin(2 * math.pi * 8 * t)
        out.append(s)
    return out


def make_siren() -> list:
    seconds = 2.0
    n = int(seconds * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        f = 760.0 + 420.0 * math.sin(2 * math.pi * t / seconds * 2.0)
        out.append(0.5 * math.sin(2 * math.pi * f * t))
    return out


def make_sfx(name: str) -> list:
    if name == "ui_click":
        n = int(0.07 * RATE)
        return [0.5 * math.exp(-i / RATE * 60) * math.sin(2 * math.pi * 900 * i / RATE)
                for i in range(n)]
    if name == "pickup":
        n = int(0.28 * RATE)
        return [0.5 * env(i / RATE, 0.28, 0.005, 0.05, 0.5, 0.1) *
                math.sin(2 * math.pi * (660 + 660 * i / n) * i / RATE) for i in range(n)]
    if name == "crash":
        n = int(0.45 * RATE)
        rng = random.Random(31)
        return [0.9 * math.exp(-i / RATE * 9) * rng.uniform(-1, 1) for i in range(n)]
    if name == "mission_complete":
        notes = [523.25, 659.25, 783.99, 1046.5]
        n = int(1.1 * RATE)
        out = [0.0] * n
        for k, f in enumerate(notes):
            st = k * 0.12
            for i in range(int(st * RATE), n):
                t = i / RATE - st
                out[i] += 0.3 * env(t, 0.6, 0.005, 0.06, 0.4, 0.2) * math.sin(2 * math.pi * f * t)
        return out
    if name == "jump":
        n = int(0.22 * RATE)
        return [0.4 * math.exp(-i / RATE * 12) *
                math.sin(2 * math.pi * (300 + 900 * i / n) * i / RATE) for i in range(n)]
    if name == "enter_car":
        n = int(0.3 * RATE)
        return [0.5 * math.exp(-i / RATE * 18) *
                (math.sin(2 * math.pi * 70 * i / RATE) + 0.4 * math.sin(2 * math.pi * 140 * i / RATE))
                for i in range(n)]
    if name == "mission_fail":
        n = int(0.8 * RATE)
        return [0.4 * math.exp(-i / RATE * 3) *
                math.sin(2 * math.pi * (400 - 250 * i / n) * i / RATE) for i in range(n)]
    if name == "radio_switch":
        n = int(0.12 * RATE)
        rng = random.Random(41)
        return [0.4 * math.exp(-i / RATE * 30) * rng.uniform(-1, 1) for i in range(n)]
    return [0.0] * 16


def gen_audio(force: bool) -> None:
    os.makedirs(AUD, exist_ok=True)
    jobs = {
        "intro_theme": make_intro,
        "menu_theme": lambda: make_track("synth", 16.0, 100.0, 61),
        "radio_synth": lambda: make_track("synth", 24.0, 108.0, 62),
        "radio_beat": lambda: make_track("beat", 24.0, 96.0, 63),
        "radio_electro": lambda: make_track("electro", 24.0, 124.0, 64),
        "engine_loop": make_engine,
        "siren_loop": make_siren,
    }
    for name, fn in jobs.items():
        path = os.path.join(AUD, name + ".wav")
        if os.path.exists(path) and not force:
            continue
        print("  audio:", name)
        wav_write(path, fn())
    for name in ("ui_click", "pickup", "crash", "mission_complete", "jump",
                 "enter_car", "mission_fail", "radio_switch"):
        path = os.path.join(AUD, name + ".wav")
        if os.path.exists(path) and not force:
            continue
        print("  sfx:", name)
        wav_write(path, make_sfx(name))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="regenerate existing files")
    args = ap.parse_args()
    os.makedirs(TEX, exist_ok=True)
    print("generating textures")
    for fn in (tex_asphalt, tex_road, tex_sidewalk, tex_grass, tex_roof):
        fn()
    for i in range(4):
        tex_facade(i)
    tex_icons()
    print("generating audio")
    gen_audio(args.force)
    print("done")


if __name__ == "__main__":
    main()
