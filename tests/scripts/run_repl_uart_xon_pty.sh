#!/bin/bash
# Software XON/XOFF: host Ctrl-S must pause bulk UART TX until Ctrl-Q.
# Markers are raw UartPut bytes (SOH/EOT) so the echoed command line cannot
# false-trigger. Host PTY IXON/IXOFF cleared — only injected XOFF pauses.
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
for fd in (master, slave):
    attrs = termios.tcgetattr(fd)
    attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.IXANY)
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
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

def wait_prompt(timeout=90.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        read_more(0.3)
        if buf.endswith(b"> "):
            t_end = time.time() + 0.5
            while time.time() < t_end:
                if read_more(0.05):
                    t_end = time.time() + 0.25
            if buf.endswith(b"> "):
                return True
    return False

ok = wait_prompt()
if not ok:
    sys.stderr.write("FAIL repl-uart-xon-pty — no prompt\n")
    sys.stderr.write(repr(buf[-500:]) + "\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)

# SOH (1) … 800× 'x' … EOT (4) — markers are not in the typed source text.
cmd = (
    b"I64 i;"
    b"UartXonXoff(1);"
    b"UartPut(1);"
    b"for(i=0;i<800;i++)UartPut(120);"
    b"UartPut(4);\r"
)
mark = len(buf)
os.write(master, cmd)

deadline = time.time() + 25
saw_start = False
while time.time() < deadline:
    read_more(0.05)
    if b"\x01" in buf[mark:]:
        saw_start = True
        time.sleep(0.03)
        os.write(master, b"\x13")  # XOFF
        break

if not saw_start:
    sys.stderr.write("FAIL repl-uart-xon-pty — never saw SOH start marker\n")
    sys.stderr.write(repr(buf[mark:][:400]) + "\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)

time.sleep(0.12)
read_more(0.1)
paused_at = len(buf)
time.sleep(0.4)
read_more(0.1)
grew = len(buf) - paused_at
seg = buf[mark:]
if b"\x04" in seg:
    sys.stderr.write("FAIL repl-uart-xon-pty — EOT arrived while XOFF held\n")
    sys.stderr.write(f"  grew={grew} x_count={seg.count(b'x')}\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)
if grew > 128:
    sys.stderr.write(f"FAIL repl-uart-xon-pty — TX kept growing under XOFF (+{grew} B)\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)

os.write(master, b"\x11")  # XON
deadline = time.time() + 30
while time.time() < deadline:
    read_more(0.2)
    if b"\x04" in buf[mark:] and buf.endswith(b"> "):
        break

if b"\x04" not in buf[mark:]:
    sys.stderr.write("FAIL repl-uart-xon-pty — EOT missing after XON\n")
    sys.stderr.write(repr(buf[mark:][-400:]) + "\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)

i0 = buf.find(b"\x01", mark) + 1
i1 = buf.find(b"\x04", mark)
nx = buf[i0:i1].count(b"x")
if nx < 700:
    sys.stderr.write(f"FAIL repl-uart-xon-pty — short payload count={nx}\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)

proc.send_signal(signal.SIGKILL)
try:
    proc.wait(timeout=2)
except Exception:
    pass

print("OK   REPL uart-xon-pty: XOFF pauses bulk TX; XON resumes")
PY
