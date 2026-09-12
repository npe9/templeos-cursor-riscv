#!/usr/bin/env python3
"""Decode the memfs change journal out of a raw memory dump (JTAG / OpenOCD / gdb).

The guest keeps an append-only journal of every memfs mutation. The ring bodies have
always lived in RAM, but the cursor (head/count/seq/epoch) lived only in HolyC
globals -- so a halted-core dump found fixed-size records with no way to tell which
were valid. bootstrap/seed/fs.hc now mirrors that cursor into a self-describing
64-byte header, which is what this tool reads.

Getting the bytes off the board
-------------------------------
OpenOCD (halt first so the ring is not mutating under you):

    > halt
    > dump_image fslog.bin 0x87E19B00 0x20000

gdb / riscv64-elf-gdb against an OpenOCD or QEMU gdbstub:

    (gdb) dump binary memory fslog.bin 0x87E19B00 0x87E39B00

0x87E19B00 is the header on QEMU virt (MEMFS_CWD 0x87E01B00 + FS_LOG_HDR_OFF).
The header names the ring's own address, so dumping header-first and then the ring
is enough; if you would rather dump the whole memfs cwd region, pass --base with the
address the dump starts at and the header is located by magic either way.

Usage
-----
    python3 tools/jtag_recv_fslog.py fslog.bin
    python3 tools/jtag_recv_fslog.py fslog.bin --base 0x87E19B00
    python3 tools/jtag_recv_fslog.py fslog.bin --json
    python3 tools/jtag_recv_fslog.py --selftest

Exit status is 0 when a journal was decoded, 1 when the magic was not found.
"""
from __future__ import annotations

import argparse
import json
import struct
import sys

MAGIC = b"TOSFSLOG"
HDR_SIZE = 64
PATH_LEN = 64

# Mirrors FS_OP_* in bootstrap/seed/fs.hc.
OPS = {
    1: "CREATE",
    2: "WRITE",
    3: "UNLINK",
    4: "RENAME",
    5: "TRUNC",
    6: "DIRMK",
    7: "DIRDEL",
    8: "EPOCH",
    9: "WRAP",
}
# FsChanges-style single letter, for eyeballing next to a git status.
OP_LETTER = {
    1: "A", 2: "W", 3: "D", 4: "R", 5: "T",
    6: "A", 7: "D", 8: "=", 9: "~",
}
FS_FLAG_QUIET = 1


class Header:
    __slots__ = ("version", "hdr_size", "rec_size", "rec_max", "head", "count",
                 "seq", "epoch", "chrono_start", "gen", "ring_addr", "self_addr",
                 "found_at")

    def __init__(self, blob: bytes, off: int):
        f = struct.unpack_from("<11I", blob, off + 8)
        (self.version, self.hdr_size, self.rec_size, self.rec_max, self.head,
         self.count, self.seq, self.epoch, self.chrono_start, self.gen,
         ring_lo) = f
        ring_hi, self_lo, self_hi = struct.unpack_from("<3I", blob, off + 52)
        self.ring_addr = (ring_hi << 32) | ring_lo
        # The block's own address. Lets a magic scan recover the dump's base
        # without assuming the ring and the header are adjacent -- they are not:
        # the collapsed dirty-set tables sit between them.
        self.self_addr = (self_hi << 32) | self_lo
        self.found_at = off

    @property
    def ring_bytes(self) -> int:
        return self.rec_size * self.rec_max

    def sane(self) -> str | None:
        if self.version != 1:
            return f"unsupported header version {self.version}"
        if self.hdr_size != HDR_SIZE:
            return f"unexpected hdr_size {self.hdr_size}"
        if not (0 < self.rec_size <= 4096):
            return f"implausible rec_size {self.rec_size}"
        if not (0 < self.rec_max <= 1 << 20):
            return f"implausible rec_max {self.rec_max}"
        if self.count > self.rec_max:
            return f"count {self.count} exceeds rec_max {self.rec_max}"
        if self.head > self.rec_max:
            return f"head {self.head} exceeds rec_max {self.rec_max}"
        return None


def _cstr(blob: bytes, off: int, n: int) -> str:
    raw = blob[off:off + n]
    end = raw.find(b"\0")
    if end >= 0:
        raw = raw[:end]
    return raw.decode("utf-8", "replace")


def find_header(blob: bytes) -> int:
    """Locate the header by magic. Returns byte offset, or -1."""
    return blob.find(MAGIC)


def decode(blob: bytes, base: int | None = None):
    """Decode a dump into (Header, [record dicts]) in chronological order."""
    off = find_header(blob)
    if off < 0:
        raise LookupError("TOSFSLOG magic not found in dump")
    hdr = Header(blob, off)
    bad = hdr.sane()
    if bad:
        raise ValueError(f"header at +0x{off:X} looks wrong: {bad}")

    # Where do the ring bytes live inside this dump? Either the caller told us the
    # address the dump starts at, or we derive it: the header knows its own address
    # and we know where we found it, so base = self_addr - found_at. Never assume
    # the ring is adjacent to the header -- the dirty-set tables sit between them.
    if base is None and hdr.self_addr:
        base = hdr.self_addr - off
    if base is None:
        raise ValueError(
            "header carries no self address (older guest?); "
            "pass --base <address the dump starts at>")
    ring_off = hdr.ring_addr - base

    recs = []
    if hdr.count == 0:
        return hdr, recs
    if ring_off < 0 or ring_off + hdr.rec_max * hdr.rec_size > len(blob):
        raise ValueError(
            f"ring at 0x{hdr.ring_addr:X} is outside this dump "
            f"(computed offset {ring_off}, dump is {len(blob)} bytes). "
            f"Re-dump starting at the ring, or pass --base <dump start address>."
        )

    for age in range(hdr.count):
        idx = (hdr.chrono_start + age) % hdr.rec_max
        r = ring_off + idx * hdr.rec_size
        seq, epoch, op, flags, size, fhash = struct.unpack_from("<IHBBII", blob, r)
        recs.append({
            "seq": seq,
            "epoch": epoch,
            "op": op,
            "op_name": OPS.get(op, f"OP{op}"),
            "letter": OP_LETTER.get(op, "?"),
            "flags": flags,
            "quiet": bool(flags & FS_FLAG_QUIET),
            "size": size,
            "hash": fhash,
            "path": _cstr(blob, r + 16, PATH_LEN),
            "path2": _cstr(blob, r + 80, PATH_LEN),
        })
    return hdr, recs


def render(hdr: Header, recs, show_quiet: bool) -> str:
    out = []
    out.append(f"fslog v{hdr.version}  ring=0x{hdr.ring_addr:X} "
               f"rec={hdr.rec_size}B x{hdr.rec_max}  epoch={hdr.epoch} "
               f"seq={hdr.seq} head={hdr.head} count={hdr.count} gen={hdr.gen}")
    shown = 0
    for r in recs:
        if r["quiet"] and not show_quiet:
            continue
        shown += 1
        line = f"  {r['letter']} {r['seq']:>6} e{r['epoch']:<3} {r['path']}"
        if r["op"] == 4 and r["path2"]:
            line += f"  <- {r['path2']}"
        if r["op"] in (2, 5) or r["size"]:
            line += f"  ({r['size']} B)"
        if r["quiet"]:
            line += "  [quiet]"
        out.append(line)
    hidden = len(recs) - shown
    if hidden > 0 and not show_quiet:
        out.append(f"  ... {hidden} quiet record(s) hidden; pass --all to show")
    if not recs:
        out.append("  (journal empty -- nothing mutated since the epoch was sealed)")
    return "\n".join(out)


def _selftest() -> int:
    """Build a synthetic dump matching fs.hc's encoding and round-trip it."""
    rec_size, rec_max = 144, 512
    ring_addr = 0x87E03F00
    hdr_addr = 0x87E19B00
    base = ring_addr
    blob = bytearray(hdr_addr - ring_addr + HDR_SIZE)

    entries = [
        (1, 0, 8, 0, 0, 0x00000000, "BOOT", ""),
        (2, 0, 2, 0, 42, 0xDEADBEEF, "Home/a.hc", ""),
        (3, 0, 6, 0, 0, 0x00000000, "Home/st", ""),
        (4, 1, 4, 0, 7, 0x12345678, "Home/b.hc", "Home/a.hc"),
        (5, 1, 2, 1, 9, 0x00C0FFEE, "Home/.dirlist", ""),
    ]
    for i, (seq, epoch, op, flags, size, fhash, p1, p2) in enumerate(entries):
        r = (ring_addr - base) + i * rec_size
        struct.pack_into("<IHBBII", blob, r, seq, epoch, op, flags, size, fhash)
        blob[r + 16:r + 16 + len(p1)] = p1.encode()
        blob[r + 80:r + 80 + len(p2)] = p2.encode()

    h = hdr_addr - base
    blob[h:h + 8] = MAGIC
    struct.pack_into("<11I", blob, h + 8,
                     1, HDR_SIZE, rec_size, rec_max,
                     len(entries), len(entries), len(entries) + 1, 1,
                     0, 0, ring_addr & 0xFFFFFFFF)
    struct.pack_into("<3I", blob, h + 52,
                     ring_addr >> 32, hdr_addr & 0xFFFFFFFF, hdr_addr >> 32)

    hdr, recs = decode(bytes(blob), base=base)
    assert hdr.ring_addr == ring_addr, hdr.ring_addr
    assert hdr.epoch == 1 and hdr.count == 5, (hdr.epoch, hdr.count)
    assert [r["seq"] for r in recs] == [1, 2, 3, 4, 5]
    assert recs[1]["path"] == "Home/a.hc" and recs[1]["size"] == 42
    assert recs[3]["op_name"] == "RENAME" and recs[3]["path2"] == "Home/a.hc"
    assert recs[4]["quiet"] is True
    text = render(hdr, recs, show_quiet=False)
    assert "Home/.dirlist" not in text, "quiet record leaked into default view"
    assert "1 quiet record(s) hidden" in text
    assert "Home/a.hc" in render(hdr, recs, show_quiet=True)
    # The ring and the header are deliberately NOT adjacent here -- the real layout
    # puts ~15 KiB of dirty-set tables between them -- so this catches a decoder that
    # tries to locate the ring by backing up ring_bytes from the header.
    assert hdr_addr - (ring_addr + rec_max * rec_size) > 0, "selftest layout is adjacent"
    hdr2, recs2 = decode(bytes(blob))
    assert hdr2.self_addr == hdr_addr, hex(hdr2.self_addr)
    assert [r["seq"] for r in recs2] == [1, 2, 3, 4, 5], "magic-scan located the wrong ring"
    assert recs2[3]["path2"] == "Home/a.hc"
    print("selftest OK")
    print(text)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Decode the memfs change journal from a raw memory dump.")
    ap.add_argument("dump", nargs="?", help="raw binary memory dump")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=None,
                    help="address the dump starts at (e.g. 0x87E03F00)")
    ap.add_argument("--all", action="store_true",
                    help="include quiet records (spill / .dirlist / .funlist)")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return _selftest()
    if not args.dump:
        ap.error("need a dump file (or --selftest)")

    with open(args.dump, "rb") as fh:
        blob = fh.read()
    try:
        hdr, recs = decode(blob, base=args.base)
    except (LookupError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps({
            "ring_addr": hdr.ring_addr, "rec_size": hdr.rec_size,
            "rec_max": hdr.rec_max, "head": hdr.head, "count": hdr.count,
            "seq": hdr.seq, "epoch": hdr.epoch, "gen": hdr.gen,
            "records": recs,
        }, indent=2))
    else:
        print(render(hdr, recs, show_quiet=args.all))
    return 0


if __name__ == "__main__":
    sys.exit(main())
