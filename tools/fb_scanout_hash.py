#!/usr/bin/env python3
"""Screendump a running QEMU over QMP and hash the SCANOUT the same way the guest hashes its
own framebuffer, so the two can be compared.

Why this exists: every pixel assertion in this tree is `RVFbHash` (Kernel/RVFb.HC), an FNV-1a
over `rv_fb.pixels` — the guest's COMPOSE buffer. Its own comment says "CI oracle without a
host screenshot". That proves the guest drew the right picture; it cannot prove the picture
ever reached a display surface. Nothing in the repo closed that gap. This does: QEMU's
`screendump` writes the display surface as a P6 PPM, and hashing it in the guest's U32 layout
reproduces the guest's number exactly when scanout matches compose.

The X byte matters. RVFbHash hashes 32-bit words; PPM carries only RGB. The kernel writes
XRGB with X=0, so words are rebuilt as 0x00RRGGBB (--xbyte overrides).

    tools/fb_scanout_hash.py <qmp-unix-socket> <out.ppm> [--xbyte 0] [--png]

--png also writes <out>.png beside the PPM, because the point of having the real scanout is
that a person can LOOK at it. A hash says the picture is stable, never that it is right.

Prints, for the caller to grep:
    scanout_geom=<w>x<h>
    scanout_hash=0x........
    scanout_png=<path>        (only with --png)
"""
import argparse
import json
import os
import socket
import struct
import sys
import zlib


def qmp_screendump(sock_path, out_path):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(20)
    s.connect(sock_path)
    f = s.makefile("rwb")
    f.readline()  # greeting

    def cmd(name, **args):
        msg = {"execute": name}
        if args:
            msg["arguments"] = args
        f.write((json.dumps(msg) + "\n").encode())
        f.flush()
        while True:
            line = f.readline()
            if not line:
                raise RuntimeError("QMP closed while waiting for a reply to %s" % name)
            reply = json.loads(line)
            if "return" in reply:
                return reply["return"]
            if "error" in reply:
                raise RuntimeError("QMP %s failed: %s" % (name, reply["error"]))
            # anything else is an async event; keep reading

    cmd("qmp_capabilities")
    cmd("screendump", filename=out_path)
    s.close()


def ppm_hash(path, xbyte):
    """FNV-1a over XRGB U32 words — the same arithmetic as RVFbHash in Kernel/RVFb.HC."""
    with open(path, "rb") as fh:
        data = fh.read()
    if not data.startswith(b"P6"):
        raise RuntimeError("%s is not a P6 PPM (QEMU screendump format)" % path)
    fields, pos = [], 2
    while len(fields) < 3:
        while pos < len(data) and data[pos : pos + 1].isspace():
            pos += 1
        if data[pos : pos + 1] == b"#":
            while pos < len(data) and data[pos] != 0x0A:
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos : pos + 1].isspace():
            pos += 1
        fields.append(int(data[start:pos]))
    pos += 1  # the single whitespace byte after maxval
    w, h, maxval = fields
    px = data[pos:]
    if maxval != 255:
        raise RuntimeError("maxval %d unsupported" % maxval)
    if len(px) < w * h * 3:
        raise RuntimeError("short PPM: %d bytes for %dx%d" % (len(px), w, h))

    acc = 2166136261
    hi = xbyte << 24
    for i in range(0, w * h * 3, 3):
        acc = ((acc ^ (hi | (px[i] << 16) | (px[i + 1] << 8) | px[i + 2])) * 16777619) & 0xFFFFFFFF
    return w, h, acc


def write_png(ppm_path, png_path):
    """Minimal RGB8 PNG (stdlib only — no Pillow in this tree)."""
    with open(ppm_path, "rb") as fh:
        data = fh.read()
    _magic, rest = data.split(b"\n", 1)
    dims, rest = rest.split(b"\n", 1)
    _maxval, px = rest.split(b"\n", 1)
    w, h = (int(v) for v in dims.split())
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0
        raw += px[y * w * 3 : (y + 1) * w * 3]

    def chunk(tag, payload):
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    with open(png_path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        fh.write(chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("qmp_socket")
    ap.add_argument("out_ppm")
    ap.add_argument("--xbyte", type=lambda v: int(v, 0), default=0)
    ap.add_argument("--png", action="store_true", help="also write <out>.png for eyeballing")
    args = ap.parse_args()
    try:
        qmp_screendump(args.qmp_socket, args.out_ppm)
    except Exception as exc:  # noqa: BLE001 - the caller only needs the reason
        print("scanout_error=%s" % exc, file=sys.stderr)
        return 2
    if not os.path.exists(args.out_ppm):
        print("scanout_error=screendump returned OK but wrote no file", file=sys.stderr)
        return 2
    try:
        w, h, acc = ppm_hash(args.out_ppm, args.xbyte)
    except Exception as exc:  # noqa: BLE001
        print("scanout_error=%s" % exc, file=sys.stderr)
        return 2
    if args.png:
        png_path = os.path.splitext(args.out_ppm)[0] + ".png"
        try:
            write_png(args.out_ppm, png_path)
            print("scanout_png=%s" % png_path)
        except Exception as exc:  # noqa: BLE001
            print("scanout_png_error=%s" % exc, file=sys.stderr)
    print("scanout_geom=%dx%d" % (w, h))
    print("scanout_hash=0x%08X" % acc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
