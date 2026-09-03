#!/bin/bash
# Paced PTY typing: each keystroke must appear once (not "aa" per key).
# Catches the 16550 LSR/RBR × nested-IRQ stale-RBR race in uart_hw_drain.
# Piped smoke often misses it (bulk RX / different IRQ timing).
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

python3 - "$BOOT/repl.elf" "$QEMU" <<'PY'
import os, pty, select, signal, subprocess, sys, time, termios

elf, qemu = sys.argv[1], sys.argv[2]
master, slave = pty.openpty()
# Guest software XON/XOFF (default on): kernel IXON on the PTY would send
# real XOFF during boot floods and freeze UartPut. Disable host line FC.
attrs = termios.tcgetattr(master)
attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.IXANY)
termios.tcsetattr(master, termios.TCSANOW, attrs)
attrs = termios.tcgetattr(slave)
attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.IXANY)
termios.tcsetattr(slave, termios.TCSANOW, attrs)
proc = subprocess.Popen(
    [qemu, "-M", "virt", "-bios", "none", "-kernel", elf, "-nographic", "-m", "128M"],
    stdin=slave, stdout=slave, stderr=subprocess.DEVNULL, close_fds=True,
)
os.close(slave)
buf = b""

def read_more(timeout=0.2):
    global buf
    r, _, _ = select.select([master], [], [], timeout)
    if master not in r:
        return False
    try:
        chunk = os.read(master, 65536)
    except OSError:
        return False
    if not chunk:
        return False
    buf += chunk
    return True

def wait_prompt(timeout=60.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        read_more(0.3)
        if b'Man("' in buf and buf.endswith(b"> "):
            # drain trailing Help chatter
            t_end = time.time() + 0.4
            while time.time() < t_end:
                if read_more(0.05):
                    t_end = time.time() + 0.2
            if buf.endswith(b"> "):
                return True
    return False

def paced_line(payload: bytes, delay: float) -> bytes:
    global buf
    mark = len(buf)
    for ch in payload:
        os.write(master, bytes([ch]))
        time.sleep(delay)
    os.write(master, b"\r")
    deadline = time.time() + 8
    while time.time() < deadline:
        read_more(0.15)
        if buf.endswith(b"> ") and len(buf) > mark + 4:
            t_end = time.time() + 0.15
            while time.time() < t_end:
                if read_more(0.05):
                    t_end = time.time() + 0.1
            break
    return buf[mark:]

ok = wait_prompt()
if not ok:
    sys.stderr.write("FAIL repl-uart-echo-pty — no prompt\n")
    sys.stderr.write(repr(buf[-400:]) + "\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)

failures = 0
for delay in (0.0, 0.005, 0.01, 0.015, 0.02):
    for _ in range(3):
        seg = paced_line(b"abcdef;", delay)
        # Doubled interactive echo looks like aabbccddeeff;;
        if b"aabbccddeeff" in seg or seg.startswith(b"aa"):
            failures += 1
            sys.stderr.write(f"FAIL double echo delay={delay}: {seg[:48]!r}\n")
        elif b"abcdef;" not in seg[:24] and b"abcdef;" not in seg:
            failures += 1
            sys.stderr.write(f"FAIL missing echo delay={delay}: {seg[:48]!r}\n")

# Ctrl-C must still interrupt a busy eval (MIE restore path).
mark = len(buf)
os.write(master, b"while(1){}\r")
time.sleep(0.4)
os.write(master, b"\x03")
deadline = time.time() + 6
while time.time() < deadline:
    read_more(0.2)
    if b"Interrupted" in buf[mark:]:
        break
if b"Interrupted" not in buf[mark:]:
    failures += 1
    sys.stderr.write("FAIL repl-uart-echo-pty — Ctrl-C did not interrupt\n")
    sys.stderr.write(repr(buf[mark:mark + 120]) + "\n")

proc.send_signal(signal.SIGKILL)
try:
    proc.wait(timeout=2)
except Exception:
    pass

if failures:
    sys.stderr.write(f"FAIL repl-uart-echo-pty — {failures} check(s)\n")
    sys.exit(1)
print("OK   REPL uart-echo-pty: paced keys single-echo; Ctrl-C interrupts")
PY
