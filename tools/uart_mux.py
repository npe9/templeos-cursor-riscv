#!/usr/bin/env python3
"""Demux framed multi-channel UART (CONSOLE.md / G22) from guest FrameSend.

Guest wire format (bootstrap/seed/frame.hc):
  SYNC=0x7E, then byte-stuffed: CH | LEN16le | PAYLOAD | CRC8
  Escape: 0x7D then (b^0x20) for 0x7E and 0x7D.
  CRC8 poly 0x07 init 0 over CH||LEN||PAYLOAD (unstuffed).

Channels:
  0 console  1 FS/9P  2 debugger  3 log  4 RPC stub

Raw (non-frame) bytes pass through as console (compat with mux-off REPL).

Soft VT (console.hc / CONSOLE.md #4): guest Vt(n) prints banners
  --- VT N (title) ---
and, when UartMuxOn, FrameSend(ch0, b"V\\tN"). Use --vt-split with -o DIR
to write vt0..vt3 session files. --vt-follow streams the active VT live;
--vt N filters follow/stdout to one session. VtPane(a,b) records layout
(framed P\\ta\\tb); --vt-panes renders a side-by-side dump (no guest TTY split).

Usage:
  qemu-system-riscv64 … -nographic 2>&1 | python3 tools/uart_mux.py -o /tmp/mux
  qemu-system-riscv64 … -nographic 2>&1 | python3 tools/uart_mux.py -o /tmp/mux --vt-split
  qemu-system-riscv64 … -nographic 2>&1 | python3 tools/uart_mux.py -o /tmp/mux --vt-panes
  qemu-system-riscv64 … -nographic 2>&1 | python3 tools/uart_mux.py --vt-follow
  python3 tools/uart_mux.py --selftest

At the guest prompt:
  UartMuxOn;  Print("hi\\n");  LogInfo("mux","ch3");  UartMuxOff;
  Vt(1); VtPutStr("side"); VtDetach;
  VtCapture(1); Print("cap\\n"); VtCapture(0);
  VtPane(0,1);  // host --vt-panes; VtPaneOff;
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SYNC = 0x7E
ESC = 0x7D
CH_NAMES = {
    0: "console",
    1: "fs",
    2: "dbg",
    3: "log",
    4: "rpc",
}
VT_N = 4
VT_BANNER_RE = re.compile(rb"--- VT ([0-3]) \(")
# Longest prefix of a banner that can straddle a read: "\r\n--- VT 0 (" -> hold back
# this many bytes so a banner split across chunks is still matched.
VT_BANNER_HOLD = 16


def crc8(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ 0x07) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc & 0xFF


def stuff(data: bytes) -> bytes:
    out = bytearray()
    for b in data:
        if b in (SYNC, ESC):
            out.append(ESC)
            out.append(b ^ 0x20)
        else:
            out.append(b)
    return bytes(out)


def encode_frame(ch: int, payload: bytes) -> bytes:
    if len(payload) > 256:
        raise ValueError("payload > FRAME_MAX")
    hdr = bytes([ch & 0xFF, len(payload) & 0xFF, (len(payload) >> 8) & 0xFF]) + payload
    body = stuff(hdr + bytes([crc8(hdr)]))
    return bytes([SYNC]) + body


class Demux:
    def __init__(self) -> None:
        self._esc = False
        self._in_frame = False
        self._buf = bytearray()
        self.raw_console = bytearray()
        self.channels: dict[int, bytearray] = {i: bytearray() for i in range(5)}
        self.frames = 0
        self.bad_crc = 0
        self._rawbuf = bytearray()
        self._cons_pending = bytearray()
        self.bad_len = 0
        self.vt_cur = 0
        self.vt: dict[int, bytearray] = {i: bytearray() for i in range(VT_N)}
        self.vt_switches = 0
        self.vt_pane: tuple[int, int] | None = None
        self._vt_follow_cb = None  # optional Callable[[int, bytes], None]

    def _vt_switch(self, n: int) -> None:
        # Idempotent: with framing on, a Vt(n) produces BOTH a framed "V\tN" notify and
        # the soft banner, so counting every notify double-reports every switch.
        if 0 <= n < VT_N and n != self.vt_cur:
            self.vt_cur = n
            self.vt_switches += 1

    def _vt_pane_set(self, a: int, b: int) -> None:
        if 0 <= a < VT_N and 0 <= b < VT_N:
            self.vt_pane = (a, b)

    def _vt_pane_clear(self) -> None:
        self.vt_pane = None

    def _vt_emit(self, chunk: bytes) -> None:
        if not chunk:
            return
        self.vt[self.vt_cur].extend(chunk)
        if self._vt_follow_cb:
            self._vt_follow_cb(self.vt_cur, chunk)

    def _note_console_bytes(self, data: bytes) -> None:
        """Track soft VT banners + append bytes to active vtN buffer.

        Callers hand this data in arbitrary sizes — the raw path feeds a single byte
        at a time — so the multi-byte banner pattern can only be found by carrying a
        pending buffer across calls. Scanning each call's data in isolation meant
        `--- VT N (title) ---` never matched and soft-banner splitting silently did
        nothing (the selftest missed it: its switches come from framed V\tN).
        """
        if not data:
            return
        self._cons_pending.extend(data)
        buf = bytes(self._cons_pending)
        last = 0
        for m in VT_BANNER_RE.finditer(buf):
            self._vt_emit(buf[last : m.start()])
            self._vt_switch(int(m.group(1)))
            # The banner text belongs to the VT it announces — emit it there, and
            # consume it so a retained tail cannot re-match it on the next call.
            self._vt_emit(buf[m.start() : m.end()])
            last = m.end()
        rest = buf[last:]
        if len(rest) > VT_BANNER_HOLD:
            cut = len(rest) - VT_BANNER_HOLD
            self._vt_emit(rest[:cut])
            rest = rest[cut:]
        self._cons_pending = bytearray(rest)

    def _flush_console_pending(self) -> None:
        if self._cons_pending:
            self._vt_emit(bytes(self._cons_pending))
            self._cons_pending.clear()

    def _recover_raw(self) -> None:
        """Not a frame after all — emit the candidate bytes as console.

        A literal 0x7E in console text is indistinguishable from SYNC, and the REPL
        boot banner contains one ('~10000000 Hz' in Uptime). Dropping the buffer on a
        failed frame silently truncated everything after that byte. Re-emit the
        original, still-stuffed bytes (SYNC included) so console text survives.
        """
        raw = bytes(self._rawbuf)
        self._rawbuf.clear()
        if not raw:
            return
        self.raw_console.extend(raw)
        self.channels[0].extend(raw)
        self._note_console_bytes(raw)

    def _finish_frame(self) -> None:
        raw = bytes(self._buf)
        self._buf.clear()
        self._in_frame = False
        self._esc = False
        if len(raw) < 4:
            self.bad_len += 1
            self._recover_raw()
            return
        body, csum = raw[:-1], raw[-1]
        if crc8(body) != csum:
            self.bad_crc += 1
            self._recover_raw()
            return
        ch = body[0]
        ln = body[1] | (body[2] << 8)
        if ln > 256 or 3 + ln != len(body):
            self.bad_len += 1
            self._recover_raw()
            return
        self._rawbuf.clear()
        payload = body[3 : 3 + ln]
        if ch not in self.channels:
            self.channels[ch] = bytearray()
        self.channels[ch].extend(payload)
        self.frames += 1
        # Soft VT framed notify on ch0: "V\tN" or pane "P\ta\tb" / "P\t-"
        if ch == 0 and len(payload) >= 3 and payload[1] == ord("\t"):
            if payload[0] == ord("V"):
                dig = payload[2] - ord("0")
                if 0 <= dig < VT_N:
                    # Raw console bytes still held for banner matching belong to the
                    # VT we are leaving — a framed switch is out-of-band and would
                    # otherwise misattribute them to the new one.
                    self._flush_console_pending()
                    self._vt_switch(dig)
                    return
            if payload[0] == ord("P"):
                if payload[2] == ord("-"):
                    self._vt_pane_clear()
                    return
                if (
                    len(payload) >= 5
                    and payload[3] == ord("\t")
                    and ord("0") <= payload[2] <= ord("3")
                    and ord("0") <= payload[4] <= ord("3")
                ):
                    self._vt_pane_set(payload[2] - ord("0"), payload[4] - ord("0"))
                    return
        if ch == 0:
            self._note_console_bytes(payload)

    def feed(self, data: bytes) -> None:
        for b in data:
            if not self._in_frame:
                if b == SYNC:
                    self._in_frame = True
                    self._esc = False
                    self._buf.clear()
                    self._rawbuf.clear()
                    self._rawbuf.append(b)
                else:
                    self.raw_console.append(b)
                    self.channels[0].append(b)
                    self._note_console_bytes(bytes([b]))
                continue
            self._rawbuf.append(b)
            if self._esc:
                self._buf.append(b ^ 0x20)
                self._esc = False
                continue
            if b == ESC:
                self._esc = True
                continue
            if b == SYNC:
                if self._buf:
                    # Drop the trailing SYNC from the candidate; it starts the next one.
                    self._rawbuf.pop()
                    self._finish_frame()
                self._in_frame = True
                self._esc = False
                self._buf.clear()
                self._rawbuf.clear()
                self._rawbuf.append(b)
                continue
            self._buf.append(b)
            if len(self._buf) >= 3:
                ln = self._buf[1] | (self._buf[2] << 8)
                # A real frame is at most FRAME_MAX (64); >256 cannot become valid, so
                # give up now rather than swallowing the rest of the stream to EOF.
                if ln > 256:
                    self.bad_len += 1
                    self._buf.clear()
                    self._in_frame = False
                    self._esc = False
                    self._recover_raw()
                    continue
                if len(self._buf) >= 4 and len(self._buf) == 3 + ln + 1:
                    self._finish_frame()

    def feed_eof(self) -> None:
        if self._in_frame and self._buf:
            self._finish_frame()
        self._flush_console_pending()

    def vt_status_line(self) -> str:
        parts = [
            f"vt{i}={len(self.vt.get(i, b''))}B"
            + ("*" if i == self.vt_cur else "")
            for i in range(VT_N)
        ]
        pane = (
            f" pane={self.vt_pane[0]}|{self.vt_pane[1]}"
            if self.vt_pane is not None
            else " pane=off"
        )
        return (
            f"vt_cur={self.vt_cur} switches={self.vt_switches} "
            + " ".join(parts)
            + pane
        )

    def render_panes(self, width: int = 36, max_lines: int = 12) -> str:
        """Side-by-side dump of two VT buffers (host-side; no guest TTY split)."""
        if self.vt_pane is not None:
            a, b = self.vt_pane
        else:
            a, b = 0, 1
        w = max(8, min(width, 72))

        def lines_of(n: int) -> list[str]:
            raw = bytes(self.vt.get(n, b"")).decode("utf-8", errors="replace")
            raw = raw.replace("\r\n", "\n").replace("\r", "\n")
            out = [ln.replace("\t", " ") for ln in raw.split("\n") if ln != ""]
            if len(out) > max_lines:
                out = out[-max_lines:]
            return out

        left, right = lines_of(a), lines_of(b)
        nrows = max(len(left), len(right), 1)
        hdr = f"===== VT panes: {a} | {b} ====="
        col_a = f"vt{a}".ljust(w)
        col_b = f"vt{b}".ljust(w)
        rows = [hdr, f"{col_a} | {col_b}", ("-" * w) + "-+-" + ("-" * w)]
        for i in range(nrows):
            la = (left[i] if i < len(left) else "")[:w].ljust(w)
            lb = (right[i] if i < len(right) else "")[:w].ljust(w)
            rows.append(f"{la} | {lb}")
        rows.append(f"===== panes end ({a}|{b}) =====")
        return "\n".join(rows) + "\n"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "-o",
        "--out-dir",
        type=Path,
        default=None,
        help="Write chN streams to OUT/console, OUT/log, …",
    )
    p.add_argument(
        "--console-stdout",
        action="store_true",
        help="Also print demuxed console (ch0 + raw) to stdout",
    )
    p.add_argument(
        "--vt-split",
        action="store_true",
        help="With -o, also write vt0..vt3 from soft banners / framed V\\tN",
    )
    p.add_argument(
        "--vt-follow",
        action="store_true",
        help="Stream active VT bytes to stdout (live follow)",
    )
    p.add_argument(
        "--vt",
        type=int,
        default=-1,
        metavar="N",
        help="With --vt-follow, only emit VT N (0..3); default = active",
    )
    p.add_argument(
        "--vt-status",
        action="store_true",
        help="Print VT size/cur summary on stderr at EOF",
    )
    p.add_argument(
        "--vt-panes",
        action="store_true",
        help="Render side-by-side VT panes at EOF (stdout; or OUT/vt_panes.txt with -o)",
    )
    p.add_argument(
        "--vt-pane-left",
        type=int,
        default=-1,
        metavar="A",
        help="With --vt-panes, left VT (default: guest VtPane or 0)",
    )
    p.add_argument(
        "--vt-pane-right",
        type=int,
        default=-1,
        metavar="B",
        help="With --vt-panes, right VT (default: guest VtPane or 1)",
    )
    p.add_argument(
        "--selftest",
        action="store_true",
        help="Encode/decode round-trip (no QEMU)",
    )
    return p.parse_args()


def selftest() -> int:
    d = Demux()
    followed: list[tuple[int, bytes]] = []

    def _follow(n: int, chunk: bytes) -> None:
        followed.append((n, chunk))

    d._vt_follow_cb = _follow
    stream = bytearray(b"boot>")
    stream += encode_frame(0, b"hello\n")
    stream += encode_frame(3, b"I\tsmoke\tmux-ok")
    stream += encode_frame(1, bytes([SYNC, ESC, 0x00, 0x7E]))
    stream += encode_frame(2, b"+")
    stream += encode_frame(4, b"rpc-stub")
    stream += b" raw-tail"
    bad = encode_frame(0, b"x")
    bad = bad[:-1] + bytes([(bad[-1] ^ 0xFF) & 0xFF])
    stream += bad
    stream += encode_frame(0, b"V\t1")
    stream += b"\r\n--- VT 1 (vt1) ---\r\nside-session\n"
    stream += encode_frame(0, b"P\t0\t1")
    stream += encode_frame(0, b"V\t0")
    stream += b"\r\n--- VT 0 (repl) ---\r\n"
    d.feed(bytes(stream))
    d.feed_eof()
    assert d.channels[0].startswith(b"boot>") or b"hello\n" in d.channels[0]
    assert b"hello\n" in d.channels[0]
    assert b"I\tsmoke\tmux-ok" in d.channels[3]
    assert bytes([SYNC, ESC, 0x00, 0x7E]) in d.channels[1]
    assert d.channels[2] == b"+"
    assert d.channels[4] == b"rpc-stub"
    assert b" raw-tail" in d.channels[0]
    assert d.frames >= 5
    assert d.bad_crc >= 1
    assert d.vt_switches >= 2
    assert b"side-session" in d.vt[1]
    assert d.vt_pane == (0, 1)
    # Soft banners alone (no framing) must drive VT switching, fed one byte at a
    # time the way the raw console path does. This is the regression that hid behind
    # the framed assertions above.
    d2 = Demux()
    soft = b"boot ~ tilde\r\n--- VT 1 (vt1) ---\r\nalpha\n--- VT 2 (vt2) ---\nbeta\n"
    for byte in soft:
        d2.feed(bytes([byte]))
    d2.feed_eof()
    assert d2.vt_switches == 2, d2.vt_switches
    assert b"alpha" in d2.vt[1], bytes(d2.vt[1])
    assert b"beta" in d2.vt[2], bytes(d2.vt[2])
    assert b"boot ~ tilde" in d2.vt[0], bytes(d2.vt[0])
    panes = d.render_panes()
    assert "VT panes: 0 | 1" in panes
    assert "side-session" in panes
    assert "panes end" in panes
    joined1 = b"".join(c for n, c in followed if n == 1)
    assert b"side-session" in joined1
    assert "vt_cur=" in d.vt_status_line()
    assert "pane=0|1" in d.vt_status_line()
    d._vt_pane_clear()
    assert d.vt_pane is None
    assert "pane=off" in d.vt_status_line()
    assert crc8(b"") == 0
    assert crc8(bytes([0, 0, 0])) == 0
    print("uart_mux selftest OK", file=sys.stderr)
    return 0


def main() -> int:
    args = parse_args()
    if args.selftest:
        return selftest()

    demux = Demux()
    filter_vt = args.vt if 0 <= args.vt < VT_N else None

    def follow_cb(n: int, chunk: bytes) -> None:
        if filter_vt is not None and n != filter_vt:
            return
        if args.vt_follow:
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()

    if args.vt_follow:
        demux._vt_follow_cb = follow_cb

    try:
        while True:
            chunk = sys.stdin.buffer.read(4096)
            if not chunk:
                break
            before = len(demux.channels[0])
            demux.feed(chunk)
            if args.console_stdout and not args.vt_follow:
                sys.stdout.buffer.write(demux.channels[0][before:])
                sys.stdout.buffer.flush()
    except KeyboardInterrupt:
        pass
    demux.feed_eof()

    if 0 <= args.vt_pane_left < VT_N and 0 <= args.vt_pane_right < VT_N:
        demux._vt_pane_set(args.vt_pane_left, args.vt_pane_right)

    if args.vt_status or args.vt_split or args.vt_follow or args.vt_panes:
        print(f"uart_mux: {demux.vt_status_line()}", file=sys.stderr)

    panes_txt = demux.render_panes() if args.vt_panes else None

    if args.out_dir:
        args.out_dir.mkdir(parents=True, exist_ok=True)
        for ch, name in CH_NAMES.items():
            path = args.out_dir / name
            path.write_bytes(bytes(demux.channels.get(ch, b"")))
        (args.out_dir / "raw_console").write_bytes(bytes(demux.raw_console))
        if args.vt_split:
            for i in range(VT_N):
                (args.out_dir / f"vt{i}").write_bytes(bytes(demux.vt.get(i, b"")))
            (args.out_dir / "vt_status.txt").write_text(demux.vt_status_line() + "\n")
        if panes_txt is not None:
            (args.out_dir / "vt_panes.txt").write_text(panes_txt)
        print(
            f"uart_mux: frames={demux.frames} bad_crc={demux.bad_crc} "
            f"bad_len={demux.bad_len} vt_sw={demux.vt_switches} → {args.out_dir}",
            file=sys.stderr,
        )
    elif not args.console_stdout and not args.vt_follow:
        if panes_txt is not None:
            sys.stdout.write(panes_txt)
        else:
            sys.stdout.buffer.write(bytes(demux.channels[0]))
        for ch, name in CH_NAMES.items():
            n = len(demux.channels.get(ch, b""))
            if n:
                print(f"ch{ch}/{name}: {n} bytes", file=sys.stderr)
        if demux.vt_switches:
            print(f"vt_switches={demux.vt_switches}", file=sys.stderr)
        print(
            f"frames={demux.frames} bad_crc={demux.bad_crc} bad_len={demux.bad_len}",
            file=sys.stderr,
        )
    elif panes_txt is not None:
        # --vt-follow / --console-stdout already used stdout; panes → stderr
        print(panes_txt, end="", file=sys.stderr)
    return 0 if demux.bad_crc == 0 or demux.frames > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
