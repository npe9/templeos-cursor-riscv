#!/bin/bash
# Interactive TermProbe geometry: open a PTY, answer DSR CPR, prove TermRows/TermCols
# leave the 80x24 default. Piped QEMU smoke cannot exercise this path (no emulator
# reply — TermProbe times out / skips and keeps 80x24).
#
# Product guest: HolyC AOT REPL (build/hc_repl.elf). Same ESC[6n (+ ESC[18t]) protocol
# as deleted worry_dream C TermProbe; Vi/EditHoly call TermProbe then TermRows/Cols.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/hc_repl.elf"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"

make -C "$ROOT" holyc-riscv >/dev/null
make -C "$ROOT/bootstrap/hc_repl" all >/dev/null

python3 - "$ELF" "$QEMU" <<'PY'
import fcntl, os, pty, re, select, struct, subprocess, sys, termios, time

elf, qemu = sys.argv[1], sys.argv[2]
rows, cols = 37, 119
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
# Guest software XON/XOFF: host IXON during boot floods can freeze UartPut.
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
        chunk = os.read(master, 4096)
    except OSError:
        return False
    if not chunk:
        return False
    buf += chunk
    return True

def wait_ans(pred, timeout=8.0):
    """Wait until pred(list_of_int_ans) is true; return matching ans list or None."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        read_more(0.15)
        vals = [int(m.group(1), 16) for m in re.finditer(br"ans=0x([0-9a-fA-F]+)", buf)]
        if pred(vals):
            return vals
    return None

def wait_prompt(timeout=8.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        read_more(0.15)
        if buf.rstrip().endswith(b">") or buf.endswith(b"> "):
            return True
    return False

deadline = time.time() + 40
while time.time() < deadline:
    read_more(0.3)
    if b"> " in buf or buf.rstrip().endswith(b">"):
        break
while read_more(0.1):
    pass

# Separate TermRows/TermCols — guest JIT expression TermRows()*1000+TermCols() is unreliable.
n0 = len(re.findall(br"ans=0x", buf))
os.write(master, b"TermRows();\n")
vals = wait_ans(lambda v: len(v) > n0 and v[-1] == 24)
pre_rows = vals[-1] if vals else None
n0 = len(re.findall(br"ans=0x", buf))
os.write(master, b"TermCols();\n")
vals = wait_ans(lambda v: len(v) > n0 and v[-1] == 80)
pre_cols = vals[-1] if vals else None
wait_prompt()

mark = len(buf)
os.write(master, b"TermProbe();\n")
answered_cpr = False
t0 = time.time()
probe_ans = None
while time.time() - t0 < 5.0:
    read_more(0.05)
    # Answer DSR CPR only. Do NOT also inject ESC[8;r;c t — TermProbe returns on the
    # first reply and a late window-size CSI pollutes the next REPL line.
    chunk = buf[mark:]
    if not answered_cpr and b"\x1b[6n" in chunk:
        os.write(master, f"\x1b[{rows};{cols}R".encode())
        answered_cpr = True
    if answered_cpr:
        ms = list(re.finditer(br"ans=0x([0-9a-fA-F]+)", chunk))
        if ms:
            probe_ans = int(ms[-1].group(1), 16)
            if probe_ans == 1:
                break

wait_prompt()
# Brief settle so any in-flight ESC bytes are not glued to the next command.
time.sleep(0.15)
while read_more(0.05):
    pass

n0 = len(re.findall(br"ans=0x", buf))
os.write(master, b"TermRows();\n")
vals = wait_ans(lambda v: len(v) > n0 and v[-1] == rows)
post_rows = vals[-1] if vals else None
n0 = len(re.findall(br"ans=0x", buf))
os.write(master, b"TermCols();\n")
vals = wait_ans(lambda v: len(v) > n0 and v[-1] == cols)
post_cols = vals[-1] if vals else None
n0 = len(re.findall(br"ans=0x", buf))
os.write(master, b"TermFlags();\n")
vals = wait_ans(lambda v: len(v) > n0 and (v[-1] & 2) != 0)
post_flags = vals[-1] if vals else None

os.write(master, b"4919;\n")
wait_ans(lambda v: v and v[-1] == 0x1337, timeout=8.0)

proc.terminate()
try:
    proc.wait(timeout=3)
except subprocess.TimeoutExpired:
    proc.kill()
os.close(master)

text = buf.decode("utf-8", "replace")
ok = (
    pre_rows == 24
    and pre_cols == 80
    and answered_cpr
    and probe_ans == 1
    and post_rows == rows
    and post_cols == cols
    and post_flags is not None
    and (post_flags & 2) != 0
)
if not ok:
    sys.stderr.write("FAIL term-probe-pty\n")
    sys.stderr.write(
        f"  pre={pre_rows}x{pre_cols} answered_cpr={answered_cpr} probe_ans={probe_ans}\n"
    )
    sys.stderr.write(f"  post={post_rows}x{post_cols} flags={post_flags}\n")
    sys.stderr.write("--- transcript tail ---\n")
    sys.stderr.write(text[-2500:] + "\n")
    raise SystemExit(1)
print(f"OK   term-probe-pty: TermProbe CPR → {rows}x{cols} (was 24x80)")
PY
