#!/bin/bash
# Interactive TermProbe geometry: open a PTY, answer CPR / window-size reports, prove
# TermRows/TermCols leave the 80x24 default. Piped QEMU smoke cannot exercise this path
# (no emulator reply — TermProbe times out / skips and keeps 80x24).
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

python3 - "$BOOT/repl.elf" "$QEMU" <<'PY'
import fcntl, os, pty, re, select, struct, subprocess, sys, termios, time

elf, qemu = sys.argv[1], sys.argv[2]
rows, cols = 37, 119
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
proc = subprocess.Popen(
    [qemu, "-M", "virt", "-bios", "none", "-kernel", elf, "-nographic"],
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
        chunk = os.read(master, 4096)
    except OSError:
        return False
    if not chunk:
        return False
    buf += chunk
    return True

deadline = time.time() + 25
while time.time() < deadline:
    read_more(0.3)
    if b"> " in buf or buf.rstrip().endswith(b">"):
        break
while read_more(0.1):
    pass

os.write(master, b'"pre %d x %d\\n", TermRows(), TermCols();\n')
t0 = time.time()
while time.time() - t0 < 5:
    read_more(0.2)
    if b"pre " in buf:
        break

os.write(master, b"TermProbe();\n")
answered_cpr = answered_ws = False
t0 = time.time()
while time.time() - t0 < 3.0:
    read_more(0.05)
    if not answered_cpr and b"\x1b[6n" in buf:
        os.write(master, f"\x1b[{rows};{cols}R".encode())
        answered_cpr = True
    if not answered_ws and b"\x1b[18t" in buf:
        os.write(master, f"\x1b[8;{rows};{cols}t".encode())
        answered_ws = True
    if answered_cpr and re.search(br"TermProbe\(\);\r?\n.*?ans=", buf, re.S):
        break

os.write(master, b'"post %d x %d flags=%d\\n", TermRows(), TermCols(), TermFlags();\n')
t0 = time.time()
while time.time() - t0 < 5:
    read_more(0.2)
    if b"post " in buf:
        break
os.write(master, b"4919;\n")
t0 = time.time()
while time.time() - t0 < 5:
    read_more(0.2)
    if b"1337" in buf:
        break

proc.terminate()
try:
    proc.wait(timeout=3)
except subprocess.TimeoutExpired:
    proc.kill()
os.close(master)

text = buf.decode("utf-8", "replace")
m_pre = re.search(r"pre (\d+) x (\d+)", text)
m_post = re.search(r"post (\d+) x (\d+) flags=(\d+)", text)
ok = (
    answered_cpr
    and m_pre
    and m_pre.group(1) == "24"
    and m_pre.group(2) == "80"
    and m_post
    and int(m_post.group(1)) == rows
    and int(m_post.group(2)) == cols
    and (int(m_post.group(3)) & 2) != 0  # TF_CPR
)
if not ok:
    sys.stderr.write("FAIL term-probe-pty\n")
    sys.stderr.write(f"  answered_cpr={answered_cpr} answered_ws={answered_ws}\n")
    sys.stderr.write(f"  pre={m_pre.groups() if m_pre else None}\n")
    sys.stderr.write(f"  post={m_post.groups() if m_post else None}\n")
    sys.stderr.write("--- transcript tail ---\n")
    sys.stderr.write(text[-2000:] + "\n")
    raise SystemExit(1)
print(f"OK   term-probe-pty: TermProbe CPR → {rows}x{cols} (was 24x80)")
PY
