#!/usr/bin/env python3
"""Decode framed base64 UART dumps from the HolyC REPL (DumpFile / DumpMem / DumpChanges).

Guest emits (Print collapses $$ to $ in format strings):
  $HC_DUMP name=foo size=1234 [addr=0x...]$
  <base64 lines>
  $HC_END$

DumpChanges adds a manifest, then N DumpFile frames (same $HC_DUMP$):
  $HC_CHANGES epoch=0..1 count=2 dumps=1$
  W Home/foo.hc
  $HC_END$
  $HC_DUMP name=Home/foo.hc size=…$
  …

Usage (interactive QEMU):
  qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \\
    2>&1 | python3 tools/uart_recv_dump.py -o /tmp/out

Then at the REPL prompt:
  DumpFile("boot.hc");
  DumpChanges;

One-shot (pipe the command after boot chatter):
  ( sleep 8; printf 'DumpFile("boot.hc");\\n' ) | \\
    qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf -nographic \\
    2>&1 | python3 tools/uart_recv_dump.py --once -o /tmp/dumps

  python3 tools/uart_recv_dump.py --selftest
"""
from __future__ import annotations

import argparse
import base64
import io
import re
import sys
from pathlib import Path

BEGIN_RE = re.compile(
    rb"\$HC_DUMP name=([^\s]+) size=(\d+)(?: addr=0x([0-9A-Fa-f]+))?\$"
)
CHANGES_RE = re.compile(
    rb"\$HC_CHANGES epoch=(-?\d+)\.\.(-?\d+) count=(\d+)(?: dumps=(\d+))?\$"
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
        help="Exit after first DumpFile, or after a DumpChanges session "
        "(manifest + dumps=N bodies)",
    )
    p.add_argument(
        "--keep-path",
        action="store_true",
        help="Write memfs-relative paths (Home/foo.hc). Default: basename only.",
    )
    p.add_argument(
        "--selftest",
        action="store_true",
        help="Decode a synthetic DumpChanges stream (no QEMU)",
    )
    return p.parse_args()


def safe_out_path(out_dir: Path, name: str, keep_path: bool) -> Path:
    raw = name.replace("\\", "/").lstrip("/")
    parts: list[str] = []
    for p in Path(raw).parts:
        if p in ("", ".", ".."):
            continue
        parts.append(p)
    if not parts:
        return out_dir / "dump.bin"
    if keep_path and len(parts) > 1:
        dest = out_dir.joinpath(*parts)
        dest.resolve().relative_to(out_dir.resolve())
        return dest
    return out_dir / parts[-1]


def write_bytes(path: Path, data: bytes, list_only: bool) -> None:
    if list_only:
        print(f"dump {path.name} {len(data)} bytes", file=sys.stderr)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"OK   {path} ({len(data)} bytes)", file=sys.stderr)


def decode_stream(
    inp: io.BufferedReader,
    out_dir: Path,
    *,
    list_only: bool = False,
    once: bool = False,
    keep_path: bool = False,
) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)

    buf = b""
    state = "scan"  # scan | payload | changes
    name: str | None = None
    size: int = 0
    b64_parts: list[bytes] = []
    wrote = 0
    pending_dumps: int | None = None
    saw_changes = False

    def finish_ok() -> int:
        return 0 if (wrote or saw_changes) else 1

    while True:
        chunk = inp.read(4096)
        if not chunk:
            break
        buf += chunk

        while True:
            if state == "scan":
                m_d = BEGIN_RE.search(buf)
                m_c = CHANGES_RE.search(buf)
                pick = None
                kind = ""
                if m_d and m_c:
                    if m_d.start() <= m_c.start():
                        pick, kind = m_d, "dump"
                    else:
                        pick, kind = m_c, "changes"
                elif m_d:
                    pick, kind = m_d, "dump"
                elif m_c:
                    pick, kind = m_c, "changes"
                else:
                    if len(buf) > 256:
                        buf = buf[-256:]
                    break

                buf = buf[pick.end() :]
                if buf.startswith(b"\n"):
                    buf = buf[1:]
                if kind == "dump":
                    name = pick.group(1).decode("ascii", errors="replace")
                    size = int(pick.group(2))
                    b64_parts = []
                    state = "payload"
                else:
                    pending_dumps = (
                        int(pick.group(4)) if pick.group(4) is not None else None
                    )
                    saw_changes = True
                    state = "changes"
                continue

            if state == "changes":
                end = buf.find(END_MARK)
                if end < 0:
                    break
                body = buf[:end]
                buf = buf[end + len(END_MARK) :]
                if buf.startswith(b"\n"):
                    buf = buf[1:]
                text = body.decode("utf-8", errors="replace")
                man = out_dir / "CHANGES"
                if list_only:
                    print("changes manifest", file=sys.stderr)
                    print(text, file=sys.stderr)
                else:
                    man.write_text(text, encoding="utf-8")
                    print(f"OK   {man} (manifest)", file=sys.stderr)
                state = "scan"
                if once and pending_dumps == 0:
                    return 0
                continue

            if state == "payload":
                end = buf.find(END_MARK)
                if end < 0:
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
                dest = safe_out_path(out_dir, name or "dump.bin", keep_path)
                write_bytes(dest, data, list_only)
                wrote += 1
                state = "scan"
                name = None
                if pending_dumps is not None and pending_dumps > 0:
                    pending_dumps -= 1
                    if once and pending_dumps == 0:
                        return 0
                    continue
                if once and pending_dumps is None:
                    return 0
                continue

    if state == "payload":
        print("WARN truncated dump (no $HC_END$ before EOF)", file=sys.stderr)
        return 1
    if state == "changes":
        print("WARN truncated changes (no $HC_END$ before EOF)", file=sys.stderr)
        return 1
    return finish_ok()


def selftest() -> int:
    payload = b"p2body"
    b64 = base64.b64encode(payload).decode("ascii")
    stream = (
        "$HC_CHANGES epoch=0..0 count=1 dumps=1$\n"
        "  W  Home/dc.hc\n"
        "$HC_END$\n"
        f"$HC_DUMP name=Home/dc.hc size={len(payload)}$\n"
        f"{b64}\n"
        "$HC_END$\n"
    ).encode("ascii")
    import tempfile

    with tempfile.TemporaryDirectory() as td:
        out = Path(td)
        rc = decode_stream(
            io.BytesIO(stream), out, once=True, keep_path=True
        )
        got = out / "Home" / "dc.hc"
        man = out / "CHANGES"
        if rc != 0:
            print(f"FAIL selftest rc={rc}", file=sys.stderr)
            return 1
        if not got.is_file() or got.read_bytes() != payload:
            print("FAIL selftest body", file=sys.stderr)
            return 1
        if "W  Home/dc.hc" not in man.read_text(encoding="utf-8"):
            print("FAIL selftest manifest", file=sys.stderr)
            return 1
    print("OK   uart_recv_dump.py --selftest", file=sys.stderr)
    return 0


def main() -> int:
    args = parse_args()
    if args.selftest:
        return selftest()
    return decode_stream(
        sys.stdin.buffer,
        args.out_dir,
        list_only=args.list,
        once=args.once,
        keep_path=args.keep_path,
    )


if __name__ == "__main__":
    raise SystemExit(main())
