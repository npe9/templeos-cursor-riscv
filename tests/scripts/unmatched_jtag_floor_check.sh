#!/bin/bash
# Pre-flight for the HiFive Unmatched JTAG link: measure the per-scan DMI corruption floor
# BEFORE trying to load anything, because the way this link fails is uniquely misleading.
#
# WHY THIS EXISTS. Measured on the board over 300+ alternating dmstatus/abstractcs/dmcontrol
# scans per setting, in one held OpenOCD session, with the on-board FT2232H:
#
#     10 MHz, tdo_sample_edge falling   9 stray values
#      8 MHz, falling                   6
#      8 MHz, rising                    8  (+1 hard error)
#      6 MHz, falling                   7
#      3 MHz                            OpenOCD asserts (riscv-013.c:499)
#    1-2 MHz                            collapse: 0/30 reads parse
#
# That is a ~2-3% per-scan corruption floor that NO setting reaches zero on. Below ~4 MHz it
# is not a floor at all, it is a collapse, so "turn the speed down to be safe" is exactly
# the wrong move on this board.
#
# The reason this needs a dedicated check is that small probes LIE. Raw dmi_write/dmi_read
# pairs come back 0/30 bad, and a 60-operation probe looks perfect — which is how "24/24
# clean IDCODE reads" and "found 5 harts" were both true and both misleading. OpenOCD's
# target examine and halt each issue HUNDREDS of DMI operations, so at a 2-3% floor they
# hit a bad one essentially every time, and OpenOCD treats a single bad DMI status as
# FATAL with no retry. So the observable is not "does one read work" but "how many out of
# three hundred".
#
# Usage, against an already-running OpenOCD with its TCL RPC port open (default 6666):
#   openocd -f tests/openocd/hifive_unmatched_hart1.cfg &
#   tests/scripts/unmatched_jtag_floor_check.sh [scans] [max_bad]
# Defaults: 300 scans, and a threshold of 0 bad, because anything above 0 means an examine
# or a halt will probably fail. It prints the count either way so a non-zero floor is
# information rather than just a refusal.
#
# NOT VERIFIED BY THE AUTHOR OF THIS FILE: no board was attached when it was written. The
# numbers above were measured by someone who had one; the script that reproduces them is
# this. Treat a clean run as "worth trying `load`", not as proof.
set -u
HOST="${OPENOCD_TCL_HOST:-127.0.0.1}"
PORT="${OPENOCD_TCL_PORT:-6666}"
SCANS="${1:-300}"
MAX_BAD="${2:-0}"

command -v python3 >/dev/null 2>&1 || { echo "FAIL floor-check — need python3" >&2; exit 1; }

python3 - "$HOST" "$PORT" "$SCANS" "$MAX_BAD" <<'PY'
import socket, sys

host, port, scans, max_bad = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])

# OpenOCD's TCL RPC: each command and each reply is terminated by 0x1a.
TERM = b"\x1a"

def cmd(sock, text):
    sock.sendall(text.encode() + TERM)
    buf = b""
    while not buf.endswith(TERM):
        chunk = sock.recv(4096)
        if not chunk:
            raise EOFError("openocd closed the connection")
        buf += chunk
    return buf[:-1].decode(errors="replace").strip()

try:
    s = socket.create_connection((host, port), timeout=10)
except OSError as e:
    print(f"FAIL floor-check — cannot reach OpenOCD TCL RPC at {host}:{port} ({e})",
          file=sys.stderr)
    print("  start it first:  openocd -f tests/openocd/hifive_unmatched_hart1.cfg &",
          file=sys.stderr)
    sys.exit(1)

# dmstatus is DMI register 0x11. It is read-only and its value is stable while the hart is
# not changing state, which is what makes it usable as a corruption detector: every reply
# that is not the modal value is a bad scan, not a state change.
vals, errors = {}, 0
try:
    for _ in range(scans):
        try:
            r = cmd(s, "riscv dmi_read 0x11")
        except (EOFError, OSError) as e:
            print(f"FAIL floor-check — link died after {sum(vals.values())} scans: {e}",
                  file=sys.stderr)
            sys.exit(1)
        r = r.split()[-1] if r.split() else ""
        try:
            v = int(r, 16) if r.startswith("0x") else int(r)
        except ValueError:
            errors += 1
            continue
        vals[v] = vals.get(v, 0) + 1
finally:
    try:
        s.close()
    except OSError:
        pass

total = sum(vals.values()) + errors
if not vals:
    print(f"FAIL floor-check — no parseable dmstatus in {total} scans "
          f"({errors} unparseable). Below ~4 MHz this link collapses entirely.",
          file=sys.stderr)
    sys.exit(1)

modal = max(vals, key=lambda k: vals[k])
bad = total - vals[modal]
print(f"floor-check: {total} dmstatus scans, modal 0x{modal:x} x{vals[modal]}, "
      f"{bad} stray ({100.0*bad/total:.1f}%), {errors} unparseable")
for v, n in sorted(vals.items(), key=lambda kv: -kv[1]):
    if v != modal:
        print(f"  stray 0x{v:x} x{n}")
# dmstatus 0x30382 = allhalted|anyhalted|resumeack — a halted hart. Worth naming, because
# a hart left halted by an earlier session that never resumed looks like a dead board.
if modal == 0x30382:
    print("  note: modal value says the hart is ALREADY HALTED (allhalted|resumeack).")
elif modal & 0x300:
    print("  note: hart appears running (allrunning/anyrunning).")

if bad > max_bad:
    print(f"FAIL floor-check — {bad} stray > threshold {max_bad}.", file=sys.stderr)
    print("  An OpenOCD examine or halt issues HUNDREDS of DMI ops and treats ONE bad", file=sys.stderr)
    print("  status as fatal, so at this rate it will not reliably complete. Do not", file=sys.stderr)
    print("  lower the adapter speed: below ~4 MHz this link collapses. Try", file=sys.stderr)
    print("  tdo_sample_edge falling at 8-10 MHz, a different cable, or the external", file=sys.stderr)
    print("  Olimex ARM-USB-TINY-H on header J18 as an independent JTAG path.", file=sys.stderr)
    sys.exit(1)
print("floor-check: OK — worth trying an examine/halt (this is not proof it will work)")
PY
