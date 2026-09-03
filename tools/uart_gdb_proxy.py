#!/usr/bin/env python3
"""Host proxy / smoke client for guest GDB RSP over UART (GdbStub).

Guest (HolyC), post-seal:
  Run("Boot/gdbstub.hc");  GdbStub;
emits $HC_GDB$ then speaks RSP until detach ($HC_GDB_END$).

Default transport: raw UART (dedicated make gdb-uart-smoke). Optional mux ch2
TX via GdbUseMux(1) + FrameDbgSend after Run("Lib/frame.hc") — RX still raw;
prefer raw attach until uart_mux.py round-trips dbg both ways.

Modes:
  --selftest     Packet codec + fake stub (no QEMU)
  --qemu ELF     Boot REPL, enter GdbStub, exercise ?, g, m, Z0/z0, c/s, D
  --listen PORT  TCP listen for gdb; bridge RSP ↔ UART/PTY

Attach recipe (interactive):
  # terminal A — QEMU (-nographic or -serial pty)
  # after seal:
  Run("Boot/gdbstub.hc");
  GdbStub;
  # terminal B
  python3 tools/uart_gdb_proxy.py --uart /dev/pts/N --listen 3334
  riscv64-elf-gdb bootstrap/repl.elf -ex 'set architecture riscv:rv64' \\
    -ex 'target remote :3334' -ex 'info registers' -ex 'x/4xb 0x80000000'

Or one-shot smoke: make gdb-uart-smoke

Scratch for Z0/s smoke: 0x86f00000 (DRAM; two nops via M, then Z0 / soft-step).
"""
from __future__ import annotations

import argparse
import os
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

ENTER_MARK = b"GDB_STUB_ENTER"
END_MARK = b"GDB_STUB_LEAVE"
WIRE_ENTER = b"$HC_GDB$"
WIRE_END = b"$HC_GDB_END$"
SEAL_MARK = b"sealed"


def checksum(body: bytes) -> int:
    return sum(body) & 0xFF


def pack_packet(body: bytes | str) -> bytes:
    if isinstance(body, str):
        body = body.encode("ascii")
    return b"$" + body + b"#%02x" % checksum(body)


def parse_packet_from(buf: bytearray) -> tuple[bytes | None, bytes | None]:
    """Return (payload, rest) or (None, buf) if incomplete. Raises on bad checksum."""
    while True:
        i = buf.find(b"$")
        if i < 0:
            buf.clear()
            return None, buf
        if i > 0:
            del buf[:i]
        hash_i = buf.find(b"#", 1)
        if hash_i < 0 or len(buf) < hash_i + 3:
            return None, buf
        body = bytes(buf[1:hash_i])
        try:
            cs = int(buf[hash_i + 1 : hash_i + 3], 16)
        except ValueError:
            del buf[: hash_i + 3]
            continue
        if cs != checksum(body):
            del buf[: hash_i + 3]
            raise ValueError(f"bad checksum for {body!r}")
        rest = bytearray(buf[hash_i + 3 :])
        return body, rest


def hex_le_u64(v: int) -> str:
    return "".join(f"{b:02x}" for b in struct.pack("<Q", v & ((1 << 64) - 1)))


def decode_le_u64_hex(h: str) -> int:
    raw = bytes.fromhex(h)
    if len(raw) < 8:
        raw = raw + b"\x00" * (8 - len(raw))
    return struct.unpack("<Q", raw[:8])[0]


class UartBridge:
    def __init__(self, read_fn, write_fn):
        self.read_fn = read_fn
        self.write_fn = write_fn
        self.buf = bytearray()

    def read_more(self, timeout: float = 0.2) -> bytes:
        chunk = self.read_fn(timeout)
        if chunk:
            self.buf.extend(chunk)
        return chunk

    def wait_mark(self, mark: bytes, timeout: float = 60.0) -> bool:
        t0 = time.time()
        while time.time() - t0 < timeout:
            if mark in self.buf:
                i = self.buf.find(mark)
                del self.buf[: i + len(mark)]
                # swallow trailing newline if present
                if self.buf[:1] in (b"\n", b"\r"):
                    del self.buf[:1]
                if self.buf[:1] == b"\n":
                    del self.buf[:1]
                return True
            self.read_more(0.2)
        return False

    def drain_acks(self) -> None:
        while True:
            self.read_more(0.05)
            if not self.buf:
                return
            if self.buf[0:1] == b"+":
                del self.buf[:1]
                continue
            if self.buf[0:1] == b"-":
                del self.buf[:1]
                continue
            return

    def transact(self, body: bytes | str, timeout: float = 10.0) -> bytes:
        pkt = pack_packet(body)
        self.write_fn(pkt)
        t0 = time.time()
        while time.time() - t0 < timeout:
            self.read_more(0.2)
            # skip acks
            while self.buf[:1] == b"+":
                del self.buf[:1]
            while self.buf[:1] == b"-":
                del self.buf[:1]
            try:
                payload, rest = parse_packet_from(self.buf)
            except ValueError:
                continue
            if payload is None:
                continue
            self.buf = rest
            return payload
        raise TimeoutError(f"no reply for {body!r}; buf={bytes(self.buf)[:80]!r}")


def selftest() -> int:
    assert pack_packet("?") == b"$?#3f"
    assert checksum(b"g") == ord("g")
    body = b"S05"
    assert pack_packet(body) == b"$S05#" + f"{checksum(body):02x}".encode()
    buf = bytearray(b"noise$S05#a8more")
    # fix checksum
    buf = bytearray(b"noise" + pack_packet(b"S05") + b"more")
    payload, rest = parse_packet_from(buf)
    assert payload == b"S05"
    assert rest == b"more"
    # fake stub: g returns zeros + pc
    g = ("00" * 8) * 32 + hex_le_u64(0x80000000)
    assert len(g) == 33 * 16
    assert decode_le_u64_hex(g[-16:]) == 0x80000000
    print("OK   uart_gdb_proxy selftest")
    return 0


def smoke_qemu(elf: Path, qemu: str) -> int:
    """Drive GdbStub over QEMU stdio.

    Feed HolyC + RSP into stdin up-front (dbg-smoke style). Delayed writes after
    the stub owns the UART often never reach the 16550 RX on this host.
    """
    import threading

    proc = subprocess.Popen(
        [qemu, "-M", "virt", "-bios", "none", "-kernel", str(elf), "-nographic", "-m", "128M"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )
    assert proc.stdin and proc.stdout
    buf = bytearray()
    lock = threading.Lock()
    done_read = threading.Event()

    def reader() -> None:
        try:
            while True:
                chunk = proc.stdout.read(4096)
                if not chunk:
                    break
                with lock:
                    buf.extend(chunk)
        finally:
            done_read.set()

    threading.Thread(target=reader, daemon=True).start()

    def snapshot() -> bytes:
        with lock:
            return bytes(buf)

    def wait_for(mark: bytes, timeout: float) -> bool:
        t0 = time.time()
        while time.time() - t0 < timeout:
            if mark in snapshot():
                return True
            time.sleep(0.15)
        return False

    # Build G packet body: zeros + a0 magic + pc zero / scratch pc
    a0 = hex_le_u64(0x1122334455667788)
    g_body = ("00" * 8) * 10 + a0 + ("00" * 8) * 22  # x0..x9, a0, x11..x31, pc=0
    assert len(g_body) == 33 * 16
    # Inside free heap bump (base 0x86000000 .. end 0x86F00000); avoid heap end edge.
    scratch = 0x86E00000
    g_pc_scratch = ("00" * 8) * 32 + hex_le_u64(scratch)
    assert len(g_pc_scratch) == 33 * 16
    # addi x0,x0,0 twice (LE) at scratch for Z0 + soft-step target
    nop4 = "13000000"
    ebreak4 = "73001000"

    # Preload: help, enter stub, then RSP queue (FIFO) before/while stub listens.
    preload = (
        b"GdbHelp;\nGdbStub;\n"
        + pack_packet("?")
        + pack_packet("g")
        + pack_packet("G" + g_body)
        + pack_packet("g")
        + pack_packet("m80000000,10")
        + pack_packet(f"M{scratch:x},8:{nop4}{nop4}")
        + pack_packet(f"Z0,{scratch:x},4")
        + pack_packet(f"m{scratch:x},4")
        + pack_packet(f"z0,{scratch:x},4")
        + pack_packet(f"m{scratch:x},4")
        + pack_packet("Z0,1,4")
        + pack_packet("G" + g_pc_scratch)
        + pack_packet("c")
        + pack_packet("s")
        + pack_packet(f"z0,{scratch + 4:x},4")
        + pack_packet("qSupported:multiprocess+")
        + pack_packet("D")
    )
    fail = 0
    try:
        proc.stdin.write(preload)
        proc.stdin.flush()

        if not wait_for(b"GDB_HELP_OK", 100):
            print("FAIL gdb-uart: GdbHelp missing GDB_HELP_OK", file=sys.stderr)
            print(snapshot()[-800:].decode("utf-8", "replace"), file=sys.stderr)
            fail = 1
        if not wait_for(ENTER_MARK, 90):
            print("FAIL gdb-uart: no $HC_GDB$ enter marker", file=sys.stderr)
            print(snapshot()[-800:].decode("utf-8", "replace"), file=sys.stderr)
            return 1

        # Parse RSP replies after enter mark (ignore '+' acks).
        t0 = time.time()
        replies: list[bytes] = []
        parse_buf = bytearray()
        while time.time() - t0 < 90 and len(replies) < 18:
            snap = snapshot()
            i = snap.find(ENTER_MARK)
            if i < 0:
                time.sleep(0.1)
                continue
            parse_buf = bytearray(snap[i + len(ENTER_MARK) :])
            # strip CR/LF after marker
            while parse_buf[:1] in (b"\n", b"\r"):
                del parse_buf[:1]
            replies = []
            tmp = bytearray(parse_buf)
            while True:
                while tmp[:1] == b"+":
                    del tmp[:1]
                while tmp[:1] == b"-":
                    del tmp[:1]
                try:
                    payload, rest = parse_packet_from(tmp)
                except ValueError:
                    break
                if payload is None:
                    break
                replies.append(payload)
                tmp = rest
            if END_MARK in snap:
                break
            time.sleep(0.2)

        def need(idx: int, pred, label: str) -> None:
            nonlocal fail
            if idx >= len(replies):
                print(f"FAIL gdb-uart: missing reply {label} (got {len(replies)})", file=sys.stderr)
                fail = 1
                return
            ok, msg = pred(replies[idx])
            if not ok:
                print(f"FAIL gdb-uart: {label}: {msg}", file=sys.stderr)
                fail = 1
            else:
                print(f"OK   gdb-uart: {label}")

        # Expected reply order matches preload packet order.
        expected = [
            ("? → S05", lambda r: (r == b"S05", repr(r))),
            (
                "g (x0=0)",
                lambda r: (
                    len(r) == 33 * 16 and r[:16] == b"00" * 8,
                    f"len={len(r)}",
                ),
            ),
            ("G → OK", lambda r: (r == b"OK", repr(r))),
            (
                "g after G a0",
                lambda r: (
                    len(r) == 33 * 16
                    and decode_le_u64_hex(r[10 * 16 : 11 * 16].decode())
                    == 0x1122334455667788,
                    f"a0={r[10*16:11*16]!r}",
                ),
            ),
            (
                "m80000000,10",
                lambda r: (
                    len(r) == 32 and all(c in b"0123456789abcdefABCDEF" for c in r),
                    repr(r),
                ),
            ),
            ("M scratch nop", lambda r: (r == b"OK", repr(r))),
            ("Z0 → OK", lambda r: (r == b"OK", repr(r))),
            (
                "m after Z0 = ebreak",
                lambda r: (r.lower() == ebreak4.encode(), repr(r)),
            ),
            ("z0 → OK", lambda r: (r == b"OK", repr(r))),
            (
                "m after z0 = nop",
                lambda r: (r.lower() == nop4.encode(), repr(r)),
            ),
            ("Z0 bad addr → E01", lambda r: (r == b"E01", repr(r))),
            ("G pc scratch → OK", lambda r: (r == b"OK", repr(r))),
            ("c → S05", lambda r: (r == b"S05", repr(r))),
            ("s soft-step → S05", lambda r: (r == b"S05", repr(r))),
            ("z0 clear step → OK", lambda r: (r == b"OK", repr(r))),
            (
                "qSupported swbreak+",
                lambda r: (b"PacketSize" in r and b"swbreak+" in r, repr(r)),
            ),
            ("D → OK", lambda r: (r == b"OK", repr(r))),
        ]
        for i, (label, pred) in enumerate(expected):
            need(i, pred, label)

        if not wait_for(END_MARK, 20):
            print("FAIL gdb-uart: no $HC_GDB_END$", file=sys.stderr)
            fail = 1
        else:
            print("OK   gdb-uart: $HC_GDB_END$")
        if fail:
            print("---- replies ----", file=sys.stderr)
            for i, r in enumerate(replies):
                print(f"  [{i}] {r[:80]!r}", file=sys.stderr)
        return fail
    finally:
        try:
            proc.send_signal(signal.SIGKILL)
            proc.wait(timeout=2)
        except Exception:
            pass
        done_read.wait(timeout=1)



def listen_bridge(uart_path: str, port: int) -> int:
    fd = os.open(uart_path, os.O_RDWR | os.O_NOCTTY)
    try:
        def read_fn(timeout: float) -> bytes:
            r, _, _ = select.select([fd], [], [], timeout)
            if fd not in r:
                return b""
            try:
                return os.read(fd, 65536)
            except OSError:
                return b""

        def write_fn(data: bytes) -> None:
            os.write(fd, data)

        bridge = UartBridge(read_fn, write_fn)
        print(f"waiting for {ENTER_MARK.decode()} on {uart_path}…", flush=True)
        if not bridge.wait_mark(ENTER_MARK, timeout=300):
            print("error: enter marker timeout", file=sys.stderr)
            return 1
        print(f"listening gdb on 0.0.0.0:{port}", flush=True)
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", port))
        srv.listen(1)
        conn, _ = srv.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        uart_to_tcp = bytearray()
        tcp_buf = bytearray()
        try:
            while True:
                r, _, _ = select.select([fd, conn], [], [], 0.5)
                if fd in r:
                    chunk = os.read(fd, 65536)
                    if not chunk:
                        break
                    # strip end marker noise
                    if END_MARK in chunk:
                        break
                    # forward + and $ packets
                    conn.sendall(chunk)
                if conn in r:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    os.write(fd, chunk)
        finally:
            conn.close()
            srv.close()
        return 0
    finally:
        os.close(fd)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--qemu", type=Path, help="Path to repl.elf; smoke GdbStub over PTY")
    p.add_argument("--qemu-bin", default=os.environ.get("QEMU_SYSTEM_RISCV", "qemu-system-riscv64"))
    p.add_argument("--uart", help="UART/PTY device for --listen")
    p.add_argument("--listen", type=int, metavar="PORT", help="TCP port for gdb (needs --uart)")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if args.selftest:
        return selftest()
    if args.qemu:
        return smoke_qemu(args.qemu, args.qemu_bin)
    if args.listen is not None:
        if not args.uart:
            print("error: --listen needs --uart /dev/pts/N", file=sys.stderr)
            return 2
        return listen_bridge(args.uart, args.listen)
    print("error: use --selftest, --qemu ELF, or --uart DEV --listen PORT", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
