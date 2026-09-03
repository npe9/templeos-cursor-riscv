#!/usr/bin/env python3
"""Host-prepatch HolyC import slots in an XIP-resident FE310 ELF.

XIP/QSPI is ROM at runtime — do not rely on guest resolve_imports writes.
After link, poke Yield/Call/Print slots in .user_blob with absolute addresses
of fe310_rt_* symbols from the same ELF.

Uses binutils only (no pyelftools).
"""
from __future__ import annotations

import argparse
import struct
import subprocess
import sys

HOLY_IMPORT_MAGIC = 0x31504D4959464F48  # "HOFYIMP1" little-endian u64
SYM_MAP = {
    b"Yield": "fe310_rt_yield",
    b"Call": "fe310_rt_call",
    b"Print": "fe310_rt_print",
}
NM = "riscv64-unknown-elf-nm"
OBJDUMP = "riscv64-unknown-elf-objdump"


def read_symbols(path: str) -> dict[str, int]:
    out = subprocess.check_output([NM, "-n", path], text=True)
    syms: dict[str, int] = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and all(c in "0123456789abcdefABCDEF" for c in parts[0]):
            syms[parts[-1]] = int(parts[0], 16)
    return syms


def find_user_blob(path: str) -> tuple[int, int, int]:
    """Return (file_offset, size, vma) for .user_blob via objdump -h."""
    out = subprocess.check_output([OBJDUMP, "-h", path], text=True)
    for line in out.splitlines():
        # "  3 .user_blob    00002580  0000000020400xxx  0000000020400xxx  000012c0  2**0"
        if ".user_blob" not in line:
            continue
        cols = line.split()
        try:
            idx = cols.index(".user_blob")
        except ValueError:
            continue
        size = int(cols[idx + 1], 16)
        vma = int(cols[idx + 2], 16)
        # File off is 4th numeric after name (Idx Name Size VMA LMA File-off)
        file_off = int(cols[idx + 4], 16)
        return file_off, size, vma
    raise SystemExit("missing section .user_blob")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("elf", help="kernel-fe310.elf (modified in place)")
    args = ap.parse_args()
    path = args.elf

    syms = read_symbols(path)
    for n in SYM_MAP.values():
        if n not in syms:
            print(f"FAIL patch_fe310_xip_imports: missing symbol {n}", file=sys.stderr)
            return 1

    off, size, vma = find_user_blob(path)
    with open(path, "r+b") as f:
        f.seek(off)
        blob = bytearray(f.read(size))
        if len(blob) < 16:
            print("FAIL patch_fe310_xip_imports: blob too small", file=sys.stderr)
            return 1
        magic = struct.unpack_from("<Q", blob, len(blob) - 8)[0]
        count = struct.unpack_from("<Q", blob, len(blob) - 16)[0]
        if magic != HOLY_IMPORT_MAGIC:
            print(f"FAIL patch_fe310_xip_imports: bad magic {magic:#x}", file=sys.stderr)
            return 1
        if count > 64:
            print(f"FAIL patch_fe310_xip_imports: crazy import count {count}", file=sys.stderr)
            return 1
        ent = len(blob) - 16 - int(count) * 32
        patched = 0
        for k in range(int(count)):
            e = ent + k * 32
            slot = struct.unpack_from("<Q", blob, e)[0]
            name = bytes(blob[e + 8 : e + 32]).split(b"\0", 1)[0]
            sym = SYM_MAP.get(name)
            if sym is None:
                print(f"WARN unresolved import {name!r} — left as-is", file=sys.stderr)
                continue
            fn = syms[sym]
            if slot + 8 > len(blob):
                print(f"FAIL bad slot {slot} for {name!r}", file=sys.stderr)
                return 1
            struct.pack_into("<Q", blob, int(slot), fn)
            patched += 1
        f.seek(off)
        f.write(blob)

    print(f"Patched {patched} XIP import slot(s) in {path} (.user_blob vma={vma:#x} size={size})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
