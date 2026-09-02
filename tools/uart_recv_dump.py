#!/usr/bin/env python3
"""Decode framed base64 UART dumps from the HolyC REPL (DumpFile / DumpMem).

Guest emits (Print collapses $$ to $ in format strings):
  $HC_DUMP name=foo size=1234 [addr=0x...]$
  <base64 lines>
  $HC_END$

Usage (interactive QEMU):
  qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \\
    2>&1 | python3 tools/uart_recv_dump.py -o /tmp/out

Then at the REPL prompt:
  DumpFile("boot.hc");

One-shot (pipe the command after boot chatter):
  ( sleep 8; printf 'DumpFile("boot.hc");\\n' ) | \\
    qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \\
    2>&1 | python3 tools/uart_recv_dump.py -o boot.hc

Writes one file per dump block (uses name= from the header). Exits 0 when
$$HC_END$$ is seen for the last block, or after stdin closes.
"""
from __future__ import annotations

import argparse
import base64
import re
import sys
from pathlib import Path

BEGIN_RE = re.compile(
    rb"\$HC_DUMP name=([^\s]+) size=(\d+)(?: addr=0x([0-9A-Fa-f]+))?\$"
)
END_MARK = b"$HC_END$"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "-o",
        "--out-dir",
        type=Path,
        default=Path("."),
        help="Directory for decoded files (default: cwd)",
    )
    p.add_argument(
        "--list",
        action="store_true",
        help="Print dump headers to stderr instead of writing files",
    )
    p.add_argument(
        "--once",
        action="store_true",
        help="Exit after the first successful $HC_END$ (for piped QEMU runs)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    buf = b""
    state = "scan"  # scan | payload
    name: str | None = None
    size: int = 0
    b64_parts: list[bytes] = []
    wrote = 0

    while True:
        chunk = sys.stdin.buffer.read(4096)
        if not chunk:
            break
        buf += chunk

        while True:
            if state == "scan":
                m = BEGIN_RE.search(buf)
                if not m:
                    # Keep tail in case marker spans reads
                    if len(buf) > 256:
                        buf = buf[-256:]
                    break
                name = m.group(1).decode("ascii", errors="replace")
                size = int(m.group(2))
                b64_parts = []
                buf = buf[m.end() :]
                if buf.startswith(b"\n"):
                    buf = buf[1:]
                state = "payload"
                continue

            if state == "payload":
                end = buf.find(END_MARK)
                if end < 0:
                    # Accumulate complete lines only; keep partial tail
                    nl = buf.rfind(b"\n")
                    if nl >= 0:
                        b64_parts.append(buf[: nl + 1])
                        buf = buf[nl + 1 :]
                    break
                b64_parts.append(buf[:end])
                buf = buf[end + len(END_MARK) :]
                if buf.startswith(b"\n"):
                    buf = buf[1:]

                raw_b64 = b"".join(b64_parts)
                raw_b64 = re.sub(rb"[^A-Za-z0-9+/=]", b"", raw_b64)
                try:
                    data = base64.b64decode(raw_b64, validate=False)
                except Exception as e:
                    print(f"FAIL decode {name}: {e}", file=sys.stderr)
                    return 1
                if len(data) != size:
                    print(
                        f"WARN {name}: header size={size} decoded={len(data)}",
                        file=sys.stderr,
                    )
                if args.list:
                    print(f"dump {name} {len(data)} bytes", file=sys.stderr)
                else:
                    out = args.out_dir / Path(name).name
                    out.write_bytes(data)
                    print(f"OK   {out} ({len(data)} bytes)", file=sys.stderr)
                    wrote += 1

                state = "scan"
                name = None
                if args.once:
                    return 0
                continue

    if state == "payload":
        print("WARN truncated dump (no $HC_END$ before EOF)", file=sys.stderr)
        return 1
    return 0 if wrote else 1


if __name__ == "__main__":
    raise SystemExit(main())
