#!/usr/bin/env python3
"""Pack host files into a TempleOS RedSea image for phase3 QEMU virtio-blk.

Layout matches Kernel/BlkDev/FileSysRedSea.HC (clus == LBA, bitmap @ LBA1..):
  boot LBA0, bitmap_sects = ceil(sects/4096), data_area = bitmap_sects,
  first data clus at data_area (overlaps last bitmap sector — marked used),
  root at data_area+1 (contiguous multi-blk when root slots need it).

Supports nested guest paths (e.g. Adam/DolDoc/MakeDoc_RV.HC) via multi-blk
contiguous dirs at each level. Name2DirClus walks parent/name on RedSea.

Example:
  tools/mk_redsea_seed_img.py build/phase3_redsea.img \\
      Compiler/Compiler.BIN=build/Compiler.BIN \\
      Adam/DolDoc/MakeDoc_RV.HC=tests/exec/seeds/phase3_MakeDoc_RV_Nest.HC \\
      MakeOS/Tiny.PRJ=tests/exec/seeds/phase3_MakeOS.HC \\
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
SLOTS_PER_BLK = BLKSZ // CDIR_SIZE  # 8


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


def nblks_for_slots(nslots: int) -> int:
    return max(1, (nslots * CDIR_SIZE + BLKSZ - 1) // BLKSZ)


def parent_path(dpath: str) -> str:
    if not dpath:
        return ""
    if "/" not in dpath:
        return ""
    return dpath.rsplit("/", 1)[0]


def basename(path: str) -> str:
    return path.rsplit("/", 1)[-1] if path else ""


def spare_slots_for(dpath: str) -> int:
    # Spare blks: guest Cmp FileWrite *.BIN + Adam P6 Lite* staging without
    # relocating a tight dir (Runtime was 6 files → 8 slots full). Nested
    # Adam/DolDoc keeps one spare blk for Soft nest BIN growth.
    top = dpath.split("/", 1)[0] if dpath else ""
    if dpath in ("Adam", "Runtime", "MakeOS") or top in ("Adam", "Runtime", "MakeOS"):
        return SLOTS_PER_BLK * 2
    if dpath.endswith("/DolDoc") or dpath == "DolDoc" or "/DolDoc/" in (dpath + "/"):
        return SLOTS_PER_BLK
    return SLOTS_PER_BLK


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("out_img", help="output raw RedSea image path")
    ap.add_argument(
        "files",
        nargs="+",
        type=parse_mapping,
        help="GUEST_PATH=HOST_FILE (e.g. Adam/DolDoc/MakeDoc_RV.HC=…)",
    )
    ap.add_argument(
        "--sects",
        type=int,
        default=16384,
        help="image size in 512-byte sectors (default 16384 = 8MiB, phase3 RAM size)",
    )
    ap.add_argument(
        "--min-root-blks",
        type=int,
        default=0,
        help="minimum contiguous root directory blocks (0 = auto: ≥2 when ≥3 root dirs)",
    )
    args = ap.parse_args()
    if args.sects < 64:
        print("sects too small", file=sys.stderr)
        return 1

    # Nested tree: every intermediate dir path + files keyed by full guest path.
    # guest "Adam/DolDoc/MakeDoc_RV.HC" → dirs Adam, Adam/DolDoc; file under Adam/DolDoc.
    all_dirs: set[str] = set()
    files: dict[str, bytes] = {}  # full guest path → body
    for guest, host in args.files:
        parts = [p for p in guest.split("/") if p]
        if not parts:
            print(f"empty guest path: {guest}", file=sys.stderr)
            return 1
        for i in range(len(parts) - 1):
            all_dirs.add("/".join(parts[: i + 1]))
        with open(host, "rb") as f:
            body = f.read()
        if guest in files:
            print(f"duplicate guest path: {guest}", file=sys.stderr)
            return 1
        files[guest] = body

    def child_dirs(dpath: str) -> list[str]:
        out = []
        prefix = f"{dpath}/" if dpath else ""
        for d in all_dirs:
            if dpath:
                if d.startswith(prefix) and "/" not in d[len(prefix) :]:
                    out.append(d)
            elif "/" not in d:
                out.append(d)
        return sorted(out)

    def child_files(dpath: str) -> list[str]:
        out = []
        for fpath in files:
            parent = parent_path(fpath)
            if parent == dpath:
                out.append(fpath)
        return sorted(out)

    bm_sects = bitmap_sects_for(args.sects)
    data_area = bm_sects
    img = bytearray(args.sects * BLKSZ)
    bitmap = bytearray(bm_sects * BLKSZ)

    # Reserve clus data_area (last bitmap sector overlap) like RedSeaFmt Alloc#1.
    next_clus = data_area
    mark_clus(bitmap, data_area, next_clus)
    next_clus += 1

    def alloc_blks(n: int) -> int:
        nonlocal next_clus
        if next_clus + n > args.sects:
            raise RuntimeError("image full — raise --sects")
        base = next_clus
        for i in range(n):
            mark_clus(bitmap, data_area, base + i)
        next_clus += n
        return base

    # Root: multi-blk contiguous (. size drives RedSeaFileFind BlkRead count).
    root_child_dirs = child_dirs("")
    root_child_files = child_files("")
    root_nslots = 2 + len(root_child_dirs) + len(root_child_files)
    root_nblk = nblks_for_slots(root_nslots)
    min_root = args.min_root_blks
    if min_root <= 0:
        # Product phase3: Compiler+Kernel+Adam (+MakeOS/Runtime) → keep spare blk
        # for Adam lean expand / guest DirMk without relocating root mid-smoke.
        min_root = 2 if len(root_child_dirs) >= 3 else 1
    root_nblk = max(root_nblk, min_root)
    try:
        root_clus = alloc_blks(root_nblk)
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        return 1
    root_sz = root_nblk * BLKSZ

    # Allocate dirs depth-first parents-before-children so parent_clus is known.
    dir_clus: dict[str, int] = {"": root_clus}
    dir_nblk: dict[str, int] = {"": root_nblk}
    # Depth-sorted so Adam before Adam/DolDoc.
    for dpath in sorted(all_dirs, key=lambda p: (p.count("/"), p)):
        nslots = 2 + len(child_dirs(dpath)) + len(child_files(dpath))
        spare = spare_slots_for(dpath)
        dnblk = nblks_for_slots(nslots + spare)
        try:
            dc = alloc_blks(dnblk)
        except RuntimeError as e:
            print(str(e), file=sys.stderr)
            return 1
        dir_clus[dpath] = dc
        dir_nblk[dpath] = dnblk

    # File extents
    file_meta: list[tuple[str, int, int, bytes]] = []  # fpath, clus, size, body
    for fpath, body in sorted(files.items()):
        nblk = max(1, (len(body) + BLKSZ - 1) // BLKSZ)
        try:
            fc = alloc_blks(nblk)
        except RuntimeError as e:
            print(str(e), file=sys.stderr)
            return 1
        file_meta.append((fpath, fc, len(body), body))

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

    def write_dir(dpath: str) -> int:
        dc = dir_clus[dpath]
        dnblk = dir_nblk[dpath]
        dsz = dnblk * BLKSZ
        parent = parent_path(dpath) if dpath else ""
        parent_c = dir_clus[parent] if dpath else root_clus
        buf = bytearray(dsz)
        buf[0:64] = cdir(RS_ATTR_DIR | RS_ATTR_CONTIGUOUS, ".", dc, dsz)
        # Root .. points at root; nested .. points at parent clus.
        buf[64:128] = cdir(
            RS_ATTR_DIR | RS_ATTR_CONTIGUOUS, "..", parent_c if dpath else root_clus, 0
        )
        slot = 2
        max_slots = dsz // CDIR_SIZE
        for cd in child_dirs(dpath):
            if slot >= max_slots:
                print(f"dir {dpath or '/'} full", file=sys.stderr)
                return 1
            cdc = dir_clus[cd]
            cdsz = dir_nblk[cd] * BLKSZ
            buf[slot * CDIR_SIZE : (slot + 1) * CDIR_SIZE] = cdir(
                RS_ATTR_DIR | RS_ATTR_CONTIGUOUS, basename(cd), cdc, cdsz
            )
            slot += 1
        for fpath in child_files(dpath):
            if slot >= max_slots:
                print(f"dir {dpath or '/'} full", file=sys.stderr)
                return 1
            # look up meta
            fc = sz = None
            body = None
            for fp, fclus, fsz, fbody in file_meta:
                if fp == fpath:
                    fc, sz, body = fclus, fsz, fbody
                    break
            assert fc is not None and sz is not None
            buf[slot * CDIR_SIZE : (slot + 1) * CDIR_SIZE] = cdir(
                RS_ATTR_CONTIGUOUS, basename(fpath), fc, sz
            )
            slot += 1
        img[dc * BLKSZ : dc * BLKSZ + dsz] = buf
        return 0

    if write_dir("") != 0:
        return 1
    for dpath in sorted(all_dirs, key=lambda p: (p.count("/"), p)):
        if write_dir(dpath) != 0:
            return 1

    # File payloads
    for fpath, fc, sz, body in file_meta:
        off = fc * BLKSZ
        img[off : off + len(body)] = body

    os.makedirs(os.path.dirname(os.path.abspath(args.out_img)) or ".", exist_ok=True)
    with open(args.out_img, "wb") as f:
        f.write(img)
    nfiles = len(file_meta)
    ndirs = len(all_dirs)
    print(
        f"wrote {args.out_img} ({len(img)} bytes, {args.sects} sects, "
        f"bitmap={bm_sects}, root={root_clus}/{root_nblk}blk, "
        f"dirs={ndirs}, files={nfiles})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
