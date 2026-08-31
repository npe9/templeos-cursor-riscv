#!/usr/bin/env python3
"""Tiny RedSea-shaped image for Phase E kernel probe (tos/Doc/RedSea.DD, Kernel/KernelA.HH)."""
import struct
import sys

SECTS = 16
BLKSZ = 512
RS_DIR = 0x10 | 0x800  # RS_ATTR_DIR | RS_ATTR_CONTIGUOUS
RS_FILE = 0x800  # RS_ATTR_CONTIGUOUS (regular file)


def le64(x: int) -> bytes:
    return struct.pack("<Q", x & 0xFFFFFFFFFFFFFFFF)


def le16(x: int) -> bytes:
    return struct.pack("<H", x & 0xFFFF)


def cdir(attr: int, name: str, clus: int, size: int, dt: int) -> bytes:
    e = bytearray(64)
    e[0:2] = le16(attr)
    b = name.encode("ascii", errors="replace")[:37]
    e[2 : 2 + len(b)] = b
    e[40:48] = le64(clus)
    e[48:56] = le64(size)
    e[56:64] = le64(dt)
    return bytes(e)


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else "build/redsea_smoke.img"
    img = bytearray(SECTS * BLKSZ)

    root_clus = 2
    readme_clus = 3
    boot_txt_clus = 5
    boot = bytearray(BLKSZ)
    boot[3] = 0x88  # MBR_PT_REDSEA
    boot[8:16] = le64(0)
    boot[16:24] = le64(SECTS)
    boot[24:32] = le64(root_clus)
    boot[32:40] = le64(1)
    boot[40:48] = le64(0xC0FFEE)
    boot[510:512] = b"\x55\xaa"
    img[0:BLKSZ] = boot

    # Bitmap LBA 1: clus 0..5 allocated (README uses 3–4, BOOT.TXT uses 5)
    img[BLKSZ] = 0x3F

    base = root_clus * BLKSZ
    img[base : base + 64] = cdir(RS_DIR, ".", root_clus, BLKSZ, 0)
    img[base + 64 : base + 128] = cdir(RS_DIR, "..", root_clus, BLKSZ, 0)
    # 640 bytes across clus 3 and 4 (tests multi-sector contiguous read)
    readme_body = (b"abcdefghij" * 64)[:640]
    img[base + 128 : base + 192] = cdir(RS_FILE, "README", readme_clus, len(readme_body), 0)
    boot_txt_body = b"REDSEA_BOOT\n"
    img[base + 192 : base + 256] = cdir(RS_FILE, "BOOT.TXT", boot_txt_clus, len(boot_txt_body), 0)

    off = readme_clus * BLKSZ
    img[off : off + len(readme_body)] = readme_body
    off_bt = boot_txt_clus * BLKSZ
    img[off_bt : off_bt + len(boot_txt_body)] = boot_txt_body

    with open(out, "wb") as f:
        f.write(img)
    print(f"wrote {out} ({len(img)} bytes)", file=sys.stderr)


if __name__ == "__main__":
    main()
