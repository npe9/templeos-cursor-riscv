#!/usr/bin/env python3
"""Pack host files into a TempleOS RedSea image for phase3 QEMU virtio-blk.

Layout matches Kernel/BlkDev/FileSysRedSea.HC (clus == LBA, bitmap @ LBA1..):
  boot LBA0, bitmap_sects = ceil(sects/4096), data_area = bitmap_sects,
  first data clus at data_area (overlaps last bitmap sector — marked used),
  root at data_area+1.

Example:
  tools/mk_redsea_seed_img.py build/phase3_redsea.img \\
      Compiler/Compiler.BIN=build/Compiler.BIN \\
      Kernel/Kernel.BIN=build/Kernel.BIN
"""
from __future__ import annotations

import argparse
import os
import struct
import sys

BLKSZ = 512
MBR_PT_REDSEA = 0x88
RS_ATTR_DIR = 0x10
RS_ATTR_CONTIGUOUS = 0x800
CDIR_SIZE = 64
NAME_MAX = 37  # CDIR_FILENAME_LEN 38 incl NUL


def le16(x: int) -> bytes:
    return struct.pack("<H", x & 0xFFFF)


def le64(x: int) -> bytes:
    return struct.pack("<Q", x & 0xFFFFFFFFFFFFFFFF)


def cdir(attr: int, name: str, clus: int, size: int, dt: int = 0) -> bytes:
    e = bytearray(CDIR_SIZE)
    e[0:2] = le16(attr)
    b = name.encode("ascii", errors="replace")[:NAME_MAX]
    e[2 : 2 + len(b)] = b
    e[40:48] = le64(clus)
    e[48:56] = le64(size)
    e[56:64] = le64(dt)
    return bytes(e)


def bitmap_sects_for(sects: int) -> int:
    # TempleOS: ceil(sects / (BLK_SIZE*8))
    return (sects + (BLKSZ * 8) - 1) // (BLKSZ * 8)


def mark_clus(bitmap: bytearray, data_area: int, clus: int) -> None:
    bit = clus - data_area
    if bit < 0:
        return
    bitmap[bit >> 3] |= 1 << (bit & 7)


def parse_mapping(s: str) -> tuple[str, str]:
    if "=" not in s:
        raise argparse.ArgumentTypeError(f"expected GUEST_PATH=HOST_FILE, got {s!r}")
    guest, host = s.split("=", 1)
    guest = guest.replace("\\", "/").lstrip("/")
    if not guest or not host:
        raise argparse.ArgumentTypeError(f"bad mapping {s!r}")
    return guest, host


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("out_img", help="output raw RedSea image path")
    ap.add_argument(
        "files",
        nargs="+",
        type=parse_mapping,
        help="GUEST_PATH=HOST_FILE (e.g. Compiler/Compiler.BIN=build/Compiler.BIN)",
    )
    ap.add_argument(
        "--sects",
        type=int,
        default=16384,
        help="image size in 512-byte sectors (default 16384 = 8MiB, phase3 RAM size)",
    )
    args = ap.parse_args()
    if args.sects < 64:
        print("sects too small", file=sys.stderr)
        return 1

    # Group files by parent directory (one level under root for now).
    # guest path "Compiler/Compiler.BIN" → dir Compiler, file Compiler.BIN
    dirs: dict[str, list[tuple[str, bytes]]] = {}
    for guest, host in args.files:
        parts = [p for p in guest.split("/") if p]
        if len(parts) == 1:
            dname, fname = "", parts[0]
        elif len(parts) == 2:
            dname, fname = parts[0], parts[1]
        else:
            print(f"only root or one subdir supported: {guest}", file=sys.stderr)
            return 1
        with open(host, "rb") as f:
            body = f.read()
        dirs.setdefault(dname, []).append((fname, body))

    bm_sects = bitmap_sects_for(args.sects)
    data_area = bm_sects
    img = bytearray(args.sects * BLKSZ)
    bitmap = bytearray(bm_sects * BLKSZ)

    # Reserve clus data_area (last bitmap sector overlap) like RedSeaFmt Alloc#1.
    next_clus = data_area
    mark_clus(bitmap, data_area, next_clus)
    next_clus += 1

    root_clus = next_clus
    mark_clus(bitmap, data_area, root_clus)
    next_clus += 1

    # Allocate subdirectory clusters + file extents.
    dir_clus: dict[str, int] = {}
    file_meta: list[tuple[str, str, int, int, bytes]] = []  # dname, fname, clus, size, body
    for dname, entries in dirs.items():
        if dname:
            dc = next_clus
            mark_clus(bitmap, data_area, dc)
            next_clus += 1
            dir_clus[dname] = dc
        for fname, body in entries:
            nblk = max(1, (len(body) + BLKSZ - 1) // BLKSZ)
            if next_clus + nblk > args.sects:
                print("image full — raise --sects", file=sys.stderr)
                return 1
            fc = next_clus
            for i in range(nblk):
                mark_clus(bitmap, data_area, fc + i)
            next_clus += nblk
            file_meta.append((dname, fname, fc, len(body), body))

    # Boot sector
    boot = bytearray(BLKSZ)
    boot[3] = MBR_PT_REDSEA
    boot[8:16] = le64(0)  # drv_offset
    boot[16:24] = le64(args.sects)
    boot[24:32] = le64(root_clus)
    boot[32:40] = le64(bm_sects)
    boot[40:48] = le64(0xC0FFEE)
    boot[510:512] = le16(0xAA55)
    img[0:BLKSZ] = boot
    img[BLKSZ : BLKSZ + len(bitmap)] = bitmap

    # Root directory
    root = bytearray(BLKSZ)
    root[0:64] = cdir(RS_ATTR_DIR | RS_ATTR_CONTIGUOUS, ".", root_clus, BLKSZ)
    root[64:128] = cdir(RS_ATTR_DIR | RS_ATTR_CONTIGUOUS, "..", root_clus, 0)
    slot = 2
    for dname, dc in dir_clus.items():
        if slot >= BLKSZ // CDIR_SIZE:
            print("root dir full", file=sys.stderr)
            return 1
        root[slot * CDIR_SIZE : (slot + 1) * CDIR_SIZE] = cdir(
            RS_ATTR_DIR | RS_ATTR_CONTIGUOUS, dname, dc, BLKSZ
        )
        slot += 1
    for dname, fname, fc, sz, body in file_meta:
        if dname:
            continue
        if slot >= BLKSZ // CDIR_SIZE:
            print("root dir full", file=sys.stderr)
            return 1
        root[slot * CDIR_SIZE : (slot + 1) * CDIR_SIZE] = cdir(
            RS_ATTR_CONTIGUOUS, fname, fc, sz
        )
        slot += 1
    img[root_clus * BLKSZ : root_clus * BLKSZ + BLKSZ] = root

    # Subdirectories
    for dname, dc in dir_clus.items():
        sub = bytearray(BLKSZ)
        sub[0:64] = cdir(RS_ATTR_DIR | RS_ATTR_CONTIGUOUS, ".", dc, BLKSZ)
        sub[64:128] = cdir(RS_ATTR_DIR | RS_ATTR_CONTIGUOUS, "..", root_clus, 0)
        slot = 2
        for dn, fname, fc, sz, body in file_meta:
            if dn != dname:
                continue
            if slot >= BLKSZ // CDIR_SIZE:
                print(f"dir {dname} full", file=sys.stderr)
                return 1
            sub[slot * CDIR_SIZE : (slot + 1) * CDIR_SIZE] = cdir(
                RS_ATTR_CONTIGUOUS, fname, fc, sz
            )
            slot += 1
        img[dc * BLKSZ : dc * BLKSZ + BLKSZ] = sub

    # File payloads
    for dname, fname, fc, sz, body in file_meta:
        off = fc * BLKSZ
        img[off : off + len(body)] = body

    os.makedirs(os.path.dirname(os.path.abspath(args.out_img)) or ".", exist_ok=True)
    with open(args.out_img, "wb") as f:
        f.write(img)
    nfiles = len(file_meta)
    print(
        f"wrote {args.out_img} ({len(img)} bytes, {args.sects} sects, "
        f"bitmap={bm_sects}, root={root_clus}, files={nfiles})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
