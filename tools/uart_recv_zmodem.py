#!/usr/bin/env python3
"""Receive ZMODEM (sz subset) from the HolyC REPL UART.

Guest: ZmodemSend("file");  ZmodemSendDir("Tutorials");  ZmodemSendChanges;
TX is raw 16550 THR bytes (UartPut) — no CRLF translation.

Host, QEMU PTY (wait for prompt, then bidirectional handshake — same as
uart_recv_trzsz.py). Do **not** use PIPE stdio for the session. Raw termios
(no IXON/ONLCR). Hex headers match via ZHEX_HDR_RE (full `**\\x18B`+CRC+NL);
post-header XON may arrive in a later read — read_data skips leading FC bytes.

  python3 tools/uart_recv_zmodem.py --qemu bootstrap/repl.elf -o /tmp/out \\
      --cmd 'ZmodemSend("boot.hc");'

Host, lrzsz / trzsz (same PTY as the REPL — typical split serial):

  qemu-system-riscv64 -M virt -bios none -kernel bootstrap/repl.elf \\
      -display none -serial pty
  # QEMU prints: char device redirected to /dev/pts/N
  rz -yee < /dev/pts/N > /dev/pts/N     # lrzsz receive
  # or, if trzsz is wrapping the session with ZMODEM enabled:
  #   trzsz --zmodem …
  # Native `trz`/`tsz` is a different protocol (JSON+zlib+MD5). The guest
  # speaks ZMODEM; use `trzsz --zmodem` (needs lrzsz) or this script / rz.

Self-test (no QEMU): python3 tools/uart_recv_zmodem.py --selftest
"""
from __future__ import annotations

import argparse
import os
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import time
from pathlib import Path

# Complete hex header before parsing — PTY ONLCR can widen `\r\n`; guest may
# split frames across reads so byte-at-a-time scan mis-syncs on `**\x18B`.
ZHEX_HDR_RE = re.compile(rb"\*\*\x18B([0-9a-fA-F]{14})\r*\n")

ZPAD, ZDLE = 0x2A, 0x18
ZBIN, ZHEX = 0x41, 0x42
ZCRCE, ZCRCG, ZCRCQ, ZCRCW = 0x68, 0x69, 0x6A, 0x6B
ZRQINIT, ZRINIT, ZACK, ZFILE, ZSKIP, ZFIN, ZRPOS, ZDATA, ZEOF = (
    0,
    1,
    3,
    4,
    5,
    8,
    9,
    10,
    11,
)
CANFDX, CANOVIO = 0x01, 0x02


def _crc_tab() -> list[int]:
    tab = []
    for i in range(256):
        crc = i << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
        tab.append(crc)
    return tab


CRCTAB = _crc_tab()


def updcrc(cp: int, crc: int) -> int:
    return (CRCTAB[(crc >> 8) & 255] ^ ((crc << 8) & 0xFFFF) ^ (cp & 255)) & 0xFFFF


def crc16(data: bytes) -> int:
    crc = 0
    for b in data:
        crc = updcrc(b, crc)
    return updcrc(0, updcrc(0, crc))


def hex_header(typ: int, p0: int, p1: int, p2: int, p3: int, xon: bool = True) -> bytes:
    payload = bytes([typ & 255, p0 & 255, p1 & 255, p2 & 255, p3 & 255])
    c = crc16(payload)
    body = "".join(f"{b:02x}" for b in payload + bytes([c >> 8, c & 255]))
    out = b"**\x18B" + body.encode("ascii") + b"\r\n"
    if xon:
        out += b"\x11"
    return out


def zrinit() -> bytes:
    return hex_header(ZRINIT, 0, 0, 0, CANFDX | CANOVIO)


def zrpos(pos: int = 0) -> bytes:
    return hex_header(ZRPOS, pos & 255, (pos >> 8) & 255, (pos >> 16) & 255, (pos >> 24) & 255)


def zfin() -> bytes:
    return hex_header(ZFIN, 0, 0, 0, 0, xon=False)


def escape_byte(c: int) -> bytes:
    c &= 255
    if c < 32 or c == 0x7F or 0x80 <= c < 0xA0:
        return bytes([ZDLE, c ^ 0x40])
    return bytes([c])


def encode_data(data: bytes, frameend: int) -> bytes:
    out = bytearray()
    crc = 0
    for b in data:
        out.extend(escape_byte(b))
        crc = updcrc(b, crc)
    out.append(ZDLE)
    out.append(frameend)
    crc = updcrc(frameend, crc)
    crc = updcrc(0, updcrc(0, crc))
    out.extend(escape_byte(crc >> 8))
    out.extend(escape_byte(crc & 255))
    return bytes(out)


def encode_bin_hdr(typ: int, pos: int) -> bytes:
    p = bytes(
        [typ & 255, pos & 255, (pos >> 8) & 255, (pos >> 16) & 255, (pos >> 24) & 255]
    )
    c = crc16(p)
    out = bytearray(b"*\x18A")
    for b in p + bytes([c >> 8, c & 255]):
        out.extend(escape_byte(b))
    return bytes(out)


def encode_file_tx(name: str, data: bytes) -> bytes:
    """Guest TX bytes for one file (no handshake waits)."""
    n = len(data)
    info = name.encode("ascii", "replace") + b"\0" + str(n).encode("ascii") + b"\0"
    out = bytearray()
    out += hex_header(ZRQINIT, 0, 0, 0, 0)
    out += hex_header(ZFILE, 0, 0, 0, 1)
    out += encode_data(info, ZCRCW)
    out += encode_bin_hdr(ZDATA, 0)
    out += encode_data(data, ZCRCE)
    out += hex_header(ZEOF, n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255)
    out += hex_header(ZFIN, 0, 0, 0, 0, xon=False)
    out += b"OO"
    return bytes(out)


class ByteSrc:
    def __init__(self, data: bytes | None = None):
        self.buf = bytearray(data or b"")
        self.read_fn = None
        self.timeout = 30.0

    def push(self, chunk: bytes) -> None:
        self.buf.extend(chunk)

    def unget(self, c: int) -> None:
        self.buf.insert(0, c & 255)

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

    def find_zhex_hdr(self, timeout: float = 60.0) -> bool:
        """Wait for a full `**\\x18B` hex header (e.g. guest ZRQINIT)."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            m = ZHEX_HDR_RE.search(self.buf)
            if m:
                del self.buf[: m.end()]
                while self.buf and self.buf[0] in (0x0D, 0x0A, 0x11, 0x13):
                    self.buf.pop(0)
                return True
            self._fill(0.2)
        return False

    def get_buffered(self) -> int | None:
        """Pop one buffered byte only — never block (optional trailer drain)."""
        if self.buf:
            return self.buf.pop(0)
        return None

    def get(self) -> int | None:
        if self.buf:
            return self.buf.pop(0)
        if not self.read_fn:
            return None
        deadline = time.time() + self.timeout
        while time.time() < deadline:
            chunk = self.read_fn()
            if chunk:
                self.buf.extend(chunk)
                if self.buf:
                    return self.buf.pop(0)
            time.sleep(0.01)
        return None


def unescape_one(src: ByteSrc) -> int | None:
    c = src.get()
    if c is None:
        return None
    if c != ZDLE:
        return c
    n = src.get()
    if n is None:
        return None
    if n in (ZCRCE, ZCRCG, ZCRCQ, ZCRCW):
        return 0x100 | n
    return (n ^ 0x40) & 255


def parse_hex_hdr(src: ByteSrc) -> tuple[int, bytes] | None:
    hx = bytearray()
    while len(hx) < 14:
        c = src.get()
        if c is None:
            return None
        if c in (0x0D, 0x0A, 0x11, 0x13):
            if hx:
                break
            continue
        if 48 <= c <= 57 or 97 <= c <= 102 or 65 <= c <= 70:
            hx.append(c)
        elif hx:
            break
    if len(hx) < 14:
        return None
    raw = bytes.fromhex(hx[:14].decode("ascii"))
    typ, rest, got = raw[0], raw[1:5], (raw[5] << 8) | raw[6]
    if crc16(bytes([typ]) + rest) != got:
        return None
    # Optional CR/LF/XON trailer — buffered only. A blocking get() here used to
    # wait the full ByteSrc timeout (~8s) for a 4th byte after `\r\n\x11`, so
    # ZRINIT was sent after the guest's ~4s ZmGetHdr deadline ("no rz").
    for _ in range(4):
        c = src.get_buffered()
        if c is None:
            break
        if c not in (0x0D, 0x0A, 0x11, 0x13):
            src.unget(c)
            break
    return typ, rest


def parse_bin_hdr(src: ByteSrc) -> tuple[int, bytes] | None:
    vals = []
    for _ in range(7):
        v = unescape_one(src)
        if v is None or v > 255:
            return None
        vals.append(v)
    typ = vals[0]
    rest = bytes(vals[1:5])
    got = (vals[5] << 8) | vals[6]
    if crc16(bytes([typ]) + rest) != got:
        return None
    return typ, rest


def _skip_fc_bytes(src: ByteSrc) -> None:
    """Drop CR/LF/XON/XOFF that may trail a hex header across a PTY read split."""
    while True:
        c = src.get_buffered()
        if c is None:
            return
        if c not in (0x0D, 0x0A, 0x11, 0x13):
            src.unget(c)
            return


def read_data(src: ByteSrc) -> tuple[bytes, int] | None:
    # Guest ZmShhdr appends XON after most hex headers. If the header's `\r\n`
    # arrives in one PTY read and `\x11` in the next, ZHEX_HDR_RE matches
    # before XON is buffered — without this skip, XON is CRC'd as payload.
    _skip_fc_bytes(src)
    if src.read_fn and not src.buf:
        src._fill(0.05)
        _skip_fc_bytes(src)
    data = bytearray()
    crc = 0
    while True:
        v = unescape_one(src)
        if v is None:
            return None
        if v > 255:
            end = v & 0xFF
            crc = updcrc(end, crc)
            crc = updcrc(0, updcrc(0, crc))
            b0 = unescape_one(src)
            b1 = unescape_one(src)
            if b0 is None or b1 is None or b0 > 255 or b1 > 255:
                return None
            got = ((b0 & 255) << 8) | (b1 & 255)
            if got != crc:
                return None
            return bytes(data), end
        data.append(v)
        crc = updcrc(v, crc)


def _parse_hex_match(src: ByteSrc, m: re.Match[bytes]) -> tuple[int, bytes] | None:
    raw = bytes.fromhex(m.group(1).decode("ascii"))
    typ, rest, got = raw[0], raw[1:5], (raw[5] << 8) | raw[6]
    if crc16(bytes([typ]) + rest) != got:
        del src.buf[: m.start() + 1]
        return None
    del src.buf[: m.end()]
    while src.buf and src.buf[0] in (0x0D, 0x0A, 0x11, 0x13):
        src.buf.pop(0)
    return typ, rest


def _scan_header_once(src: ByteSrc) -> tuple[int, bytes] | None:
    while True:
        c = src.get()
        if c is None:
            return None
        if c != ZPAD:
            continue
        while True:
            c = src.get()
            if c is None:
                return None
            if c != ZPAD:
                break
        if c != ZDLE:
            continue
        kind = src.get()
        if kind is None:
            return None
        if kind == ZHEX:
            return parse_hex_hdr(src)
        if kind == ZBIN:
            return parse_bin_hdr(src)


def scan_header(src: ByteSrc) -> tuple[int, bytes] | None:
    deadline = time.time() + src.timeout
    while time.time() < deadline:
        if src.read_fn:
            src._fill(0.05)
        while src.buf and src.buf[0] in (0x0D, 0x0A, 0x11, 0x13):
            src.buf.pop(0)
        m = ZHEX_HDR_RE.match(src.buf)
        if m:
            hdr = _parse_hex_match(src, m)
            if hdr is not None:
                return hdr
            continue
        if src.buf.startswith(b"**\x18B"):
            src._fill(0.2)
            continue
        if not src.buf:
            if src.read_fn:
                src._fill(0.2)
                continue
            return None
        hdr = _scan_header_once(src)
        if hdr is not None:
            return hdr
        if src.read_fn:
            src._fill(0.2)
    return None


def parse_sender_stream(buf: bytes) -> list[tuple[str, bytes]]:
    """Parse a unidirectional guest TX capture (ignores missing ACKs)."""
    src = ByteSrc(buf)
    files: list[tuple[str, bytes]] = []
    name, acc = None, bytearray()
    while True:
        hdr = scan_header(src)
        if hdr is None:
            break
        typ, rest = hdr
        if typ == ZFILE:
            pkt = read_data(src)
            if not pkt:
                break
            blob, _ = pkt
            z = blob.find(b"\0")
            name = blob[:z].decode("ascii", "replace") if z >= 0 else "file"
            acc = bytearray()
        elif typ == ZDATA:
            while True:
                pkt = read_data(src)
                if not pkt:
                    break
                chunk, end = pkt
                acc.extend(chunk)
                if end in (ZCRCE, ZCRCW):
                    break
        elif typ == ZEOF and name is not None:
            files.append((name, bytes(acc)))
            name, acc = None, bytearray()
        elif typ == ZFIN:
            break
    return files


class ZmodemSession:
    def __init__(self, write_fn, out_dir: Path):
        self.write_fn = write_fn
        self.out_dir = out_dir
        self.files: list[tuple[str, int]] = []
        self._name: str | None = None
        self._acc = bytearray()

    def send(self, data: bytes) -> None:
        self.write_fn(data)

    def _save(self) -> None:
        if not self._name:
            return
        rel = Path(self._name)
        if rel.is_absolute() or ".." in rel.parts:
            rel = Path(rel.name)
        dest = self.out_dir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(bytes(self._acc))
        self.files.append((str(rel), len(self._acc)))
        print(f"OK   {dest} ({len(self._acc)} bytes)", file=sys.stderr)
        self._name, self._acc = None, bytearray()

    def run(self, src: ByteSrc) -> int:
        if not src.find_zhex_hdr(timeout=45.0):
            print("FAIL zmodem: no ZRQINIT", file=sys.stderr)
            return 1
        # XON in case guest/boot left the host chardev paused (IXOFF).
        self.send(b"\x11")
        self.send(zrinit())
        saw = True
        idle_deadline = time.time() + src.timeout
        while True:
            hdr = scan_header(src)
            if hdr is None:
                if self.files:
                    return 0
                if saw and time.time() < idle_deadline:
                    if src.read_fn:
                        src._fill(0.2)
                        idle_deadline = time.time() + src.timeout
                        continue
                return 0 if self.files else 1
            idle_deadline = time.time() + src.timeout
            typ, rest = hdr
            if typ == ZRQINIT:
                self.send(zrinit())
            elif typ == ZFILE:
                pkt = read_data(src)
                if not pkt:
                    return 1
                blob, _ = pkt
                z = blob.find(b"\0")
                self._name = blob[:z].decode("ascii", "replace") if z >= 0 else "file"
                self._acc = bytearray()
                self.send(zrpos(0))
            elif typ == ZDATA:
                while True:
                    pkt = read_data(src)
                    if not pkt:
                        return 1
                    chunk, end = pkt
                    self._acc.extend(chunk)
                    if end in (ZCRCE, ZCRCW):
                        break
            elif typ == ZEOF:
                self._save()
                self.send(zrinit())
            elif typ == ZFIN:
                self.send(zfin())
                return 0 if self.files or saw else 1
            elif typ == ZSKIP:
                self._name, self._acc = None, bytearray()
                self.send(zrinit())
        return 1


def selftest() -> int:
    assert crc16(b"123456789") == 0x31C3, hex(crc16(b"123456789"))
    assert crc16(bytes(5)) == 0
    payload = bytes([0, 1, 2, 0x18, 0x11, 0x13, 0x7F, 255])
    tx = encode_file_tx("Tmp/hi.bin", payload)
    got = parse_sender_stream(tx)
    assert len(got) == 1, got
    assert got[0][0] == "Tmp/hi.bin"
    assert got[0][1] == payload

    # Offline PTY-split replay: hex ZFILE header ends at `\n`, XON arrives as
    # the first byte of the next read (common under raw PTY byte timing).
    info = b"zm_c.txt\x004\x00"
    zfile = hex_header(ZFILE, 0, 0, 0, 1)  # includes trailing `\r\n\x11`
    # Split after `\n`, before `\x11` — same race as live QEMU.
    assert zfile.endswith(b"\r\n\x11"), zfile
    part1, part2 = zfile[:-1], zfile[-1:] + encode_data(info, ZCRCW)
    src = ByteSrc(part1)
    hdr = scan_header(src)
    assert hdr and hdr[0] == ZFILE, hdr
    src.push(part2)
    pkt = read_data(src)
    assert pkt and pkt[0] == info, pkt

    print("OK   uart_recv_zmodem selftest", file=sys.stderr)
    return 0


def _pty_raw_no_ixon(fd: int) -> None:
    """Raw PTY: no IXON/IXOFF, no echo, no ONLCR (guest already emits CR/LF)."""
    attrs = termios.tcgetattr(fd)
    attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.IXANY)  # iflag
    attrs[1] &= ~(termios.OPOST | termios.ONLCR)  # oflag — keep `\n` as `\n`
    attrs[3] &= ~(termios.ECHO | termios.ICANON)  # lflag
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def wait_prompt(src: ByteSrc, master: int, timeout: float = 90.0) -> bool:
    """Wait for REPL `> ` after boot seal (same needles as uart_recv_trzsz)."""
    deadline = time.time() + timeout
    buf = bytearray()

    def read_more():
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
    """Speak ZMODEM on a QEMU PTY (not PIPE) — same recipe as uart_recv_trzsz.

    Wait for prompt, send HolyC, wait for ZRQINIT, then bidirectional session.
    Raw termios on both PTY ends: no IXON/ONLCR.
    """
    master, slave = pty.openpty()
    _pty_raw_no_ixon(master)
    _pty_raw_no_ixon(slave)
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
            print("FAIL zmodem: no REPL prompt", file=sys.stderr)
            return 1
        # Drop boot chatter; XON in case guest software FC paused TX.
        src.buf.clear()
        write_fn(b"\x11")
        write_fn(cmd.encode("utf-8") + b"\r")
        sess = ZmodemSession(write_fn, out_dir)
        rc = sess.run(src)
        if rc != 0:
            print("FAIL zmodem receive", file=sys.stderr)
        return rc
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
    p.add_argument(
        "--cmd",
        default="",
        help="HolyC statement to send after boot (needs --qemu)",
    )
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
            print("error: --qemu needs --cmd 'ZmodemSend(\"file\");'", file=sys.stderr)
            return 2
        return qemu_cmd(args.qemu, args.qemu_bin, args.cmd, args.out_dir)
    print("error: use --selftest or --qemu ELF --cmd '...'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
