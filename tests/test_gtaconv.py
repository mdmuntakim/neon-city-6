#!/usr/bin/env python3
"""Tests for tools/gtaconv.py and the generated asset pipeline.

    python3 -m unittest discover -s tests -p 'test_*.py' -v
"""
from __future__ import annotations

import math
import os
import struct
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "tools"))

import gtaconv  # noqa: E402


def make_rgba(w, h):
    out = bytearray()
    for y in range(h):
        for x in range(w):
            out += bytes((x * 255 // max(1, w - 1), y * 255 // max(1, h - 1),
                          128, 255))
    return out


def write_grid_obj(path, n=12):
    lines = []
    for y in range(n + 1):
        for x in range(n + 1):
            lines.append("v %.4f %.4f %.4f" % (x / n, 0.0, y / n))
    for y in range(n + 1):
        for x in range(n + 1):
            lines.append("vt %.4f %.4f" % (x / n, y / n))
    for y in range(n):
        for x in range(n):
            a = y * (n + 1) + x + 1
            b = a + 1
            c = a + (n + 1)
            d = c + 1
            lines.append("f %d/%d %d/%d %d/%d %d/%d" % (a, a, b, b, d, d, c, c))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


class PngTests(unittest.TestCase):
    def test_roundtrip(self):
        w, h = 17, 9
        rgba = make_rgba(w, h)
        data = gtaconv.png_encode(w, h, rgba)
        w2, h2, out = gtaconv.png_decode(data)
        self.assertEqual((w2, h2), (w, h))
        self.assertEqual(out, rgba)
        self.assertTrue(data.startswith(gtaconv.PNG_SIG))

    def test_resize_box_filter(self):
        rgba = make_rgba(8, 8)
        small = gtaconv.png_resize(8, 8, rgba, 4, 4)
        self.assertEqual(len(small), 4 * 4 * 4)
        self.assertLess(small[0], 40)  # left edge stays dark
        self.assertGreater(small[(3 * 4 + 3) * 4], 180)

    def test_optimize_png_and_mips(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "sign.png")
            with open(src, "wb") as f:
                f.write(gtaconv.png_encode(64, 32, make_rgba(64, 32)))
            dst = os.path.join(tmp, "out.png")
            args = type("A", (), {"max_texture": 16, "mips": True})()
            info = gtaconv.optimize_file(src, dst, args)
            self.assertEqual((info["width"], info["height"]), (16, 8))
            with open(dst, "rb") as f:
                w, h, _ = gtaconv.png_decode(f.read())
            self.assertEqual((w, h), (16, 8))
            self.assertTrue(os.path.exists(os.path.join(tmp, "out_mip1.png")))
            self.assertTrue(os.path.exists(os.path.join(tmp, "out_mip2.png")))


class WavTests(unittest.TestCase):
    def test_roundtrip_and_resample(self):
        rate = 22050
        samples = [math.sin(2 * math.pi * 440 * i / rate) for i in range(rate)]
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "tone.wav")
            gtaconv.wav_write(src, rate, samples)
            got_rate, got = gtaconv.wav_read(src)
            self.assertEqual(got_rate, rate)
            self.assertEqual(len(got), rate)
            self.assertGreater(max(abs(s) for s in got), 0.8)
            dst = os.path.join(tmp, "tone_lo.wav")
            args = type("A", (), {"rate": 11025})()
            info = gtaconv.optimize_file(src, dst, args)
            self.assertEqual(info["rate"], 11025)
            r2, got2 = gtaconv.wav_read(dst)
            self.assertEqual(r2, 11025)
            self.assertAlmostEqual(len(got2), 11025, delta=4)

    def test_float_wav(self):
        rate = 8000
        samples = [0.5, -0.5, 0.25, -0.25]
        raw = b"".join(struct.pack("<f", s) for s in samples)
        fmt = struct.pack("<HHIIHH", 3, 1, rate, rate * 4, 4, 32)
        data = (b"RIFF" + struct.pack("<I", 36 + len(raw)) + b"WAVE" +
                b"fmt " + struct.pack("<I", len(fmt)) + fmt +
                b"data" + struct.pack("<I", len(raw)) + raw)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "f.wav")
            with open(path, "wb") as f:
                f.write(data)
            r, got = gtaconv.wav_read(path)
            self.assertEqual(r, rate)
            self.assertEqual(len(got), 4)
            self.assertAlmostEqual(got[0], 0.5, places=5)


class ObjTests(unittest.TestCase):
    def test_obj_to_glb_lod(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "grid.obj")
            write_grid_obj(src, 12)
            verts, uvs, normals, tris = gtaconv.obj_load(src)
            self.assertEqual(len(verts), 13 * 13)
            self.assertEqual(len(tris), 12 * 12 * 2)

            full = gtaconv.obj_to_mesh(verts, uvs, normals, tris, 1.0)
            self.assertEqual(len(full[3]) // 3, 288)
            self.assertEqual(len(full[0]), len(full[2]))
            self.assertEqual(len(full[0]), len(full[1]))

            lod = gtaconv.obj_to_mesh(verts, uvs, normals, tris, 0.25)
            self.assertLess(len(lod[3]) // 3, 288)
            self.assertGreater(len(lod[3]) // 3, 0)

            dst = os.path.join(tmp, "grid.glb")
            nv, nt = gtaconv.glb_write(dst, *lod)
            self.assertEqual(nv, len(lod[0]))
            self.assertEqual(nt, len(lod[3]) // 3)
            doc, blob = gtaconv.glb_read(dst)
            self.assertEqual(doc["asset"]["version"], "2.0")
            prim = doc["meshes"][0]["primitives"][0]
            acc = doc["accessors"][prim["indices"]]
            self.assertEqual(acc["count"], len(lod[3]))
            self.assertEqual(acc["componentType"], 5125)
            self.assertEqual(prim["attributes"]["POSITION"], 0)
            self.assertEqual(len(blob), doc["buffers"][0]["byteLength"])

    def test_obj_without_uvs(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "tri.obj")
            with open(src, "w", encoding="utf-8") as f:
                f.write("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
            verts, uvs, normals, tris = gtaconv.obj_load(src)
            mesh = gtaconv.obj_to_mesh(verts, uvs, normals, tris, 1.0)
            dst = os.path.join(tmp, "tri.glb")
            gtaconv.glb_write(dst, *mesh)
            doc, _ = gtaconv.glb_read(dst)
            prim = doc["meshes"][0]["primitives"][0]
            self.assertNotIn("TEXCOORD_0", prim["attributes"])
            # indices must point at the last accessor, not a hard-coded index
            self.assertEqual(prim["indices"], 2)
            self.assertEqual(doc["accessors"][2]["type"], "SCALAR")


class PackTests(unittest.TestCase):
    def _fixture(self, tmp):
        src = os.path.join(tmp, "src")
        os.makedirs(src)
        with open(os.path.join(src, "sign.png"), "wb") as f:
            f.write(gtaconv.png_encode(32, 32, make_rgba(32, 32)))
        gtaconv.wav_write(os.path.join(src, "blip.wav"), 22050,
                          [math.sin(i / 10.0) for i in range(2205)])
        write_grid_obj(os.path.join(src, "road.obj"), 8)
        with open(os.path.join(src, "readme.txt"), "w") as f:
            f.write("copied verbatim\n")
        return src

    def test_pack_verify_and_tamper(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = self._fixture(tmp)
            out = os.path.join(tmp, "out")
            rc = gtaconv.main(["pack", src, "-o", out, "--budget-mb", "10",
                               "--max-texture", "16", "--rate", "8000",
                               "--ratio", "0.3"])
            self.assertEqual(rc, 0)
            manifest_path = os.path.join(out, "manifest.json")
            self.assertTrue(os.path.exists(manifest_path))
            self.assertTrue(os.path.exists(os.path.join(out, "road.glb")))
            self.assertTrue(os.path.exists(os.path.join(out, "readme.txt")))
            rc = gtaconv.main(["verify", manifest_path, "--budget-mb", "10"])
            self.assertEqual(rc, 0)

            with open(os.path.join(out, "sign.png"), "ab") as f:
                f.write(b"tamper")
            rc = gtaconv.main(["verify", manifest_path])
            self.assertEqual(rc, 1)

    def test_budget_is_enforced(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = self._fixture(tmp)
            out = os.path.join(tmp, "out")
            rc = gtaconv.main(["pack", src, "-o", out, "--budget-mb", "0.0001",
                               "--max-texture", "32"])
            self.assertEqual(rc, 3)

    def test_info(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "a.png")
            with open(src, "wb") as f:
                f.write(gtaconv.png_encode(4, 4, make_rgba(4, 4)))
            self.assertEqual(gtaconv.main(["info", src]), 0)


if __name__ == "__main__":
    unittest.main()
