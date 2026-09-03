#!/usr/bin/env python3
"""Receive native trzsz (tsz-compatible) from the HolyC REPL UART.

Guest: TrzszSend("file");  TrzszSendDir("Tutorials");  TrzszSendChanges;
TX is raw 16550 THR bytes (UartPut) — native #ACT/#CFG JSON + zlib+base64 + MD5
(not ZMODEM; use uart_recv_zmodem.py / rz / trzsz --zmodem for that).

Host, QEMU PTY (wait for prompt, then bidirectional protocol — same as
uart_recv_zmodem.py). Do **not** use PIPE stdio: QEMU only delivers the
boot-time preload; post-trigger host #ACT never reaches the guest RX FIFO.

  python3 tools/uart_recv_trzsz.py --qemu bootstrap/repl.elf -o /tmp/out \\
      --cmd 'TrzszSend("boot.hc");'

Self-test (no QEMU): python3 tools/uart_recv_trzsz.py --selftest

Stock trzsz: wrap a dedicated serial PTY session; guest TrzszSend emits
::TRZSZ:TRANSFER:S:… so the client auto-confirms and receives.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import time
import zlib
from pathlib import Path

TRIGGER_RE = re.compile(
    # Require the full trigger line before #ACT — matching the bare
    # `TRANSFER:S:` prefix races guest mid-TzTrigger and drops #CFG.
    # PTY ONLCR can turn guest `\r\n` into `\r\r\n` — allow any CR run.
    rb"::TRZSZ:TRANSFER:S:(\d+\.\d+\.\d+):(\d+)(?::(\d+))?\r*\n"
)
PROTOCOL_VERSION = 1
CLIENT_VERSION = "1.0.0"


def encode_buffer(buf: bytes) -> str:
    return base64.b64encode(zlib.compress(buf)).decode("ascii")


def decode_buffer(buf: str) -> bytes:
    return zlib.decompress(base64.b64decode(buf))


def send_line(write, typ: str, body: str) -> None:
    write(f"#{typ}:{body}\n".encode("latin1"))


def send_string(write, typ: str, s: str) -> None:
    send_line(write, typ, encode_buffer(s.encode("utf8")))


def send_binary(write, typ: str, data: bytes) -> None:
    send_line(write, typ, encode_buffer(data))


def send_integer(write, typ: str, value: int) -> None:
    send_line(write, typ, str(value))


def send_action(write) -> None:
    action = {
        "lang": "py",
        "confirm": True,
        "version": CLIENT_VERSION,
        "support_dir": True,
        "protocol": PROTOCOL_VERSION,
    }
    send_string(write, "ACT", json.dumps(action))


class ByteSrc:
    def __init__(self) -> None:
        self.buf = bytearray()
        self.read_fn = None

    def push(self, data: bytes) -> None:
        self.buf.extend(data)

    def _fill(self, want: float = 0.2) -> None:
        if not self.read_fn:
            return
        deadline = time.time() + want
        while time.time() < deadline:
            chunk = self.read_fn()
            if chunk:
                self.buf.extend(chunk)
                return
            time.sleep(0.01)

    def read_line(self, timeout: float = 30.0) -> str | None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            nl = self.buf.find(b"\n")
            if nl >= 0:
                raw = bytes(self.buf[:nl])
                del self.buf[: nl + 1]
                if raw.endswith(b"\r"):
                    raw = raw[:-1]
                return raw.decode("latin1", errors="surrogateescape")
            self._fill(0.2)
        return None

    def find_trigger(self, timeout: float = 60.0) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            m = TRIGGER_RE.search(self.buf)
            if m:
                del self.buf[: m.end()]
                return True
            self._fill(0.2)
        return False


def parse_typed_line(line: str) -> tuple[str, str]:
    if not line.startswith("#") or ":" not in line:
        raise ValueError(f"bad trzsz line: {line[:80]!r}")
    typ, body = line[1:].split(":", 1)
    return typ, body


def recv_expect(src: ByteSrc, expect: str, timeout: float = 30.0) -> str:
    while True:
        line = src.read_line(timeout=timeout)
        if line is None:
            raise TimeoutError(f"timeout waiting for #{expect}")
        # Ignore non-protocol chatter (REPL echo / boot)
        if not line.startswith("#"):
            continue
        typ, body = parse_typed_line(line)
        if typ in ("fail", "FAIL", "EXIT") and expect != typ:
            raise RuntimeError(f"remote {typ}: {body[:120]}")
        if typ != expect:
            # keep scanning (may have junk prefixes)
            idx = line.rfind("#" + expect + ":")
            if idx < 0:
                continue
            typ, body = parse_typed_line(line[idx:])
        if typ != expect:
            continue
        return body


def recv_string(src: ByteSrc, expect: str) -> str:
    return decode_buffer(recv_expect(src, expect)).decode("utf8")


def recv_binary(src: ByteSrc, expect: str) -> bytes:
    return decode_buffer(recv_expect(src, expect))


def recv_integer(src: ByteSrc, expect: str) -> int:
    return int(recv_expect(src, expect))


def recv_config(src: ByteSrc) -> dict:
    cfg = json.loads(recv_string(src, "CFG"))
    return cfg


def recv_files(src: ByteSrc, write, out_dir: Path) -> list[str]:
    num = recv_integer(src, "NUM")
    send_integer(write, "SUCC", num)
    saved: list[str] = []
    for _ in range(num):
        name = recv_string(src, "NAME")
        # basename only (guest non-directory mode)
        local = name.replace("\\", "/").split("/")[-1] or "unnamed"
        path = out_dir / local
        send_string(write, "SUCC", local)

        size = recv_integer(src, "SIZE")
        send_integer(write, "SUCC", size)

        md5 = hashlib.md5()
        step = 0
        with open(path, "wb") as f:
            while step < size:
                data = recv_binary(src, "DATA")
                f.write(data)
                md5.update(data)
                step += len(data)
                send_integer(write, "SUCC", len(data))

        digest = recv_binary(src, "MD5")
        if digest != md5.digest():
            raise RuntimeError(f"MD5 mismatch for {local}")
        send_binary(write, "SUCC", digest)
        saved.append(local)
    return saved


class TrzszSession:
    def __init__(self, write, out_dir: Path) -> None:
        self.write = write
        self.out_dir = out_dir

    def run(self, src: ByteSrc) -> int:
        if not src.find_trigger(timeout=45.0):
            print("FAIL trzsz: no TRANSFER:S trigger", file=sys.stderr)
            return 1
        try:
            # XON in case guest/boot left the host chardev paused (IXOFF).
            self.write(b"\x11")
            send_action(self.write)
            recv_config(src)
            names = recv_files(src, self.write, self.out_dir)
            msg = f"Saved {len(names)} file" + ("s" if len(names) != 1 else "")
            send_string(self.write, "EXIT", msg)
            print(f"OK   trzsz recv: {', '.join(names)}", file=sys.stderr)
            return 0
        except Exception as ex:
            print(f"FAIL trzsz: {ex}", file=sys.stderr)
            try:
                send_string(self.write, "fail", str(ex))
            except Exception:
                pass
            return 1


def zlib_store(data: bytes) -> bytes:
    """Match guest TzZlibStore (stored deflate block)."""
    out = bytearray([0x78, 0x01, 0x01])
    ln = len(data)
    nln = (~ln) & 0xFFFF
    out.append(ln & 255)
    out.append((ln >> 8) & 255)
    out.append(nln & 255)
    out.append((nln >> 8) & 255)
    out.extend(data)
    a, b = 1, 0
    for x in data:
        a = (a + x) % 65521
        b = (b + a) % 65521
    adler = (b << 16) | a
    out.append((adler >> 24) & 255)
    out.append((adler >> 16) & 255)
    out.append((adler >> 8) & 255)
    out.append(adler & 255)
    return bytes(out)


def selftest() -> int:
    # Guest-style encode must decompress
    for sample in [b"", b"hello", b"x" * 1000, json.dumps({"a": 1}).encode()]:
        z = zlib_store(sample)
        assert zlib.decompress(z) == sample
        assert zlib.decompress(base64.b64decode(base64.b64encode(z))) == sample

    payload = b"hello-trzsz\n"
    digest = hashlib.md5(payload).digest()

    # Full duplex: synthetic guest (tsz) ↔ this client (trz)
    out_dir = Path(os.environ.get("TMPDIR", "/tmp")) / "trzsz-selftest-out"
    if out_dir.exists():
        for p in out_dir.iterdir():
            p.unlink()
    out_dir.mkdir(parents=True, exist_ok=True)

    guest_q: list[bytes] = []
    host_q: list[bytes] = []

    def guest_write(b: bytes) -> None:
        guest_q.append(b)

    def host_write(b: bytes) -> None:
        host_q.append(b)

    # Guest trigger + wait; host finds trigger and sends ACT
    guest_write(b"\x1b7::TRZSZ:TRANSFER:S:1.0.0:0000000000001:0\r\n")

    src = ByteSrc()
    src.push(b"".join(guest_q))
    guest_q.clear()
    assert src.find_trigger(timeout=1.0)

    send_action(host_write)
    # Guest consumes ACT (ignore body), sends CFG/NUM/NAME/SIZE/DATA/MD5
    act = b"".join(host_q)
    host_q.clear()
    assert act.startswith(b"#ACT:")

    def enc_line(typ: str, raw: bytes) -> bytes:
        body = base64.b64encode(zlib_store(raw)).decode("ascii")
        return f"#{typ}:{body}\n".encode("ascii")

    guest_write(enc_line("CFG", b'{"lang":"hc","quiet":true,"protocol":1}'))
    guest_write(b"#NUM:1\n")

    # Drive client state machine manually interleaved with guest
    src.push(b"".join(guest_q))
    guest_q.clear()
    cfg = recv_config(src)
    assert cfg.get("quiet") is True

    # NUM
    num = recv_integer(src, "NUM")
    assert num == 1
    send_integer(host_write, "SUCC", 1)

    guest_write(enc_line("NAME", b"t.txt"))
    guest_write(b"#SIZE:%d\n" % len(payload))
    guest_write(enc_line("DATA", payload))
    guest_write(enc_line("MD5", digest))
    src.push(b"".join(guest_q))
    guest_q.clear()

    # Drain host SUCC for NUM already sent; feed remaining
    name = recv_string(src, "NAME")
    assert name == "t.txt"
    send_string(host_write, "SUCC", name)

    size = recv_integer(src, "SIZE")
    assert size == len(payload)
    send_integer(host_write, "SUCC", size)

    data = recv_binary(src, "DATA")
    assert data == payload
    send_integer(host_write, "SUCC", len(data))

    got_md5 = recv_binary(src, "MD5")
    assert got_md5 == digest
    send_binary(host_write, "SUCC", got_md5)

    path = out_dir / name
    path.write_bytes(payload)
    assert path.read_bytes() == payload

    send_string(host_write, "EXIT", "Saved 1 file")
    assert any(b.startswith(b"#EXIT:") for b in host_q)

    print("OK   uart_recv_trzsz selftest", file=sys.stderr)
    return 0


def _pty_raw_no_ixon(fd: int) -> None:
    """Raw PTY: no IXON/IXOFF, no echo, no ONLCR (guest already emits CR/LF)."""
    attrs = termios.tcgetattr(fd)
    attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.IXANY)  # iflag
    attrs[1] &= ~(termios.OPOST | termios.ONLCR)  # oflag — keep `\n` as `\n`
    attrs[3] &= ~(termios.ECHO | termios.ICANON)  # lflag
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def wait_prompt(src: ByteSrc, master: int, timeout: float = 90.0) -> bool:
    """Wait for REPL `> ` after boot seal (same needles as uart_recv_zmodem)."""
    deadline = time.time() + timeout
    buf = bytearray()

    def read_more() -> bytes:
        r, _, _ = select.select([master], [], [], 0.3)
        if master in r:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                return b""
            return chunk or b""
        return b""

    while time.time() < deadline:
        chunk = read_more()
        if chunk:
            buf.extend(chunk)
            src.push(bytes(chunk))
        if buf.endswith(b"> ") and (
            b'Man("' in buf
            or b"boot aborted" in buf
            or b"[boot]" in buf
            or b"HolyC primitives" in buf
            or b"fs epoch" in buf
        ):
            t_end = time.time() + 0.4
            while time.time() < t_end:
                chunk = read_more()
                if chunk:
                    buf.extend(chunk)
                    src.push(bytes(chunk))
                    t_end = time.time() + 0.2
            return buf.endswith(b"> ")
    return False


def qemu_cmd(elf: Path, qemu: str, cmd: str, out_dir: Path) -> int:
    """Speak trzsz on a QEMU PTY (not PIPE).

    PIPE stdio only delivers boot-preload bytes: UartPut during boot drains the
    16550 FIFO into the RX ring, so a preloaded HolyC line runs — but later
    host writes (#ACT) never appear in LSR.DR. PTY chardev delivers both
    directions after the prompt. find_trigger still waits for the full
    TRANSFER:S line (trailing newline) before #ACT.
    """
    master, slave = pty.openpty()
    _pty_raw_no_ixon(master)
    proc = subprocess.Popen(
        [qemu, "-M", "virt", "-bios", "none", "-kernel", str(elf), "-nographic", "-m", "128M"],
        stdin=slave,
        stdout=slave,
        stderr=subprocess.DEVNULL,
        close_fds=True,
    )
    os.close(slave)
    src = ByteSrc()

    def read_fn() -> bytes:
        r, _, _ = select.select([master], [], [], 0.2)
        if master not in r:
            return b""
        try:
            return os.read(master, 65536)
        except OSError:
            return b""

    src.read_fn = read_fn

    def write_fn(b: bytes) -> None:
        os.write(master, b)

    try:
        if not wait_prompt(src, master):
            print("FAIL trzsz: no REPL prompt", file=sys.stderr)
            return 1
        write_fn(cmd.encode("utf-8") + b"\r")
        sess = TrzszSession(write_fn, out_dir)
        return sess.run(src)
    finally:
        proc.send_signal(signal.SIGKILL)
        try:
            proc.wait(timeout=2)
        except Exception:
            pass
        os.close(master)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--qemu", type=Path, help="Path to repl.elf; spawn QEMU on a PTY")
    p.add_argument("--cmd", default="", help="HolyC statement after prompt (needs --qemu)")
    p.add_argument("-o", "--out-dir", type=Path, default=Path("."))
    p.add_argument("--qemu-bin", default=os.environ.get("QEMU_SYSTEM_RISCV", "qemu-system-riscv64"))
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if args.selftest:
        return selftest()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    if args.qemu:
        if not args.cmd:
            print("error: --qemu needs --cmd 'TrzszSend(\"file\");'", file=sys.stderr)
            return 2
        return qemu_cmd(args.qemu, args.qemu_bin, args.cmd, args.out_dir)
    print("error: use --selftest or --qemu ELF --cmd '...'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
