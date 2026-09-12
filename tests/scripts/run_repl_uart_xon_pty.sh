#!/bin/bash
# Software XON/XOFF: host Ctrl-S must pause bulk UART TX until Ctrl-Q.
# Markers are raw UartPut bytes (SOH/EOT) so the echoed command line cannot
# false-trigger. Host PTY IXON/IXOFF cleared — only injected XOFF pauses.
#
# Product guest: HolyC AOT REPL (build/hc_repl.elf). The legacy C bootstrap/repl.elf
# this used to build was deleted with worry_dream; UartPut / UartXonXoff are JIT-
# registered from repl.hc so the typed command line below is real prompt surface.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/hc_repl.elf"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"

make -C "$ROOT" holyc-riscv >/dev/null
make -C "$ROOT/bootstrap/hc_repl" all >/dev/null

python3 - "$ELF" "$QEMU" <<'PY'
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

# SOH (1) … 800× 'x' … EOT (4) — markers are the bytes UartPut writes, not text
# in the typed source, so the echoed command line cannot false-trigger.
# The thin JitTry has no toplevel `for` (that is a fun-body form only), so the
# blast is a prompt-defined function — still real prompt surface, no new JIT.
def send_line(payload: bytes, timeout=20.0):
    global buf
    n0 = len(buf)
    os.write(master, payload + b"\r")
    deadline = time.time() + timeout
    while time.time() < deadline:
        read_more(0.1)
        if buf.endswith(b"> ") and len(buf) > n0 + len(payload):
            return True
    return False

if not send_line(b"UartXonXoff(1);"):
    sys.stderr.write("FAIL repl-uart-xon-pty — UartXonXoff(1) did not return to prompt\n")
    sys.stderr.write(repr(buf[-400:]) + "\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)

# The inner j-loop paces the payload to ~3 s of guest time: with a bare
# UartPut loop QEMU pushes all 800 bytes in ~3 ms, so the host XOFF always
# lost the race and the test proved nothing. Slower hosts only widen the
# window, so pacing is safe to over-estimate.
blast = (
    b"U0 XonBlast(){I64 i,j;UartPut(1);"
    b"for(i=0;i<800;i++){for(j=0;j<1000000;j++){}UartPut(120);}"
    b"UartPut(4);}"
)
if not send_line(blast):
    sys.stderr.write("FAIL repl-uart-xon-pty — XonBlast definition did not return to prompt\n")
    sys.stderr.write(repr(buf[-400:]) + "\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)
if b"JIT:" in buf[-len(blast) - 200:]:
    sys.stderr.write("FAIL repl-uart-xon-pty — JIT rejected XonBlast\n")
    sys.stderr.write(repr(buf[-400:]) + "\n")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    sys.exit(1)

mark = len(buf)
os.write(master, b"XonBlast();\r")

# Hold off the XOFF until the payload is demonstrably flowing (SOH + a few x),
# rather than a fixed sleep — that adapts to whatever rate this host runs at.
deadline = time.time() + 25
saw_start = False
while time.time() < deadline:
    read_more(0.05)
    seg = buf[mark:]
    i0 = seg.find(b"\x01")
    if i0 >= 0 and seg[i0:].count(b"x") >= 8:
        saw_start = True
        os.write(master, b"\x13")  # XOFF
        break

if not saw_start:
    sys.stderr.write("FAIL repl-uart-xon-pty — never saw SOH + payload start\n")
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
    sys.stderr.write(f"  grew={grew} x_count={seg.count(b'x')} (payload too fast to pause?)\n")
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
