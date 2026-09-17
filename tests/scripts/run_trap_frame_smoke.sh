#!/bin/bash
# Trap-frame width smoke: the fault freeze must carry EVERY GPR, not just the caller-saved set.
# Plants known constants in s1-s11 / gp / tp, faults, resumes with `go`, then reads them back
# through DbgX (canonical x0..x31 view at TRAP_SNAP_X). The older DbgReg slots have no room for
# these registers, so trap-smoke / dbg-smoke stay green whether they are saved or garbage —
# this is the test that can actually see the widening.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/hc_repl.elf"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "error: need timeout or gtimeout" >&2
  exit 2
fi

make -C "$ROOT" holyc-riscv >/dev/null
make -C "$ROOT/bootstrap/hc_repl" all >/dev/null

input=""
add() { input+="$1"$'\n'; }

# TrapFrameProbe (bootstrap/seed/debug.hc) plants markers in s1/s2/s5/s11/gp/tp and faults;
# the automatic CrashDump prints them. The REPL's thin evaluator takes a bare call like this,
# but not asm blocks mixed with statements — hence a function in the image, not a typed-in one.
add 'TrapFrameProbe;'
add 'go'
add 'TrapFrameCheck;'
# Phase 2: a handler that edits the frozen s1 and RESUMES (the default fault path aborts the
# evaluation instead). TrapSnapApply must copy the edit into the real register before mret,
# so the probe's post-fault store sees 0x77, not the planted 0x51.
add 'TrapFrameArmEdit;'
add 'TrapFrameProbe;'
add 'TrapFrameCheck;'
add 'Print("after-probe\n");'
add 'q'

log="$(mktemp)"
fifo="$(mktemp -u)"
cleanup() { rm -f "$log" "$fifo"; }
trap cleanup EXIT
mkfifo "$fifo"
$TIMEOUT_CMD 300s "$QEMU" -M virt -m 128M -bios none -kernel "$ELF" -nographic \
  <"$fifo" >"$log" 2>&1 &
qpid=$!
(
  for _ in $(seq 1 240); do
    if grep -qE '^> $' "$log" 2>/dev/null || grep -qF '=== VT end ===' "$log" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  sleep 2
  printf '%s' "$input"
  while kill -0 "$qpid" 2>/dev/null; do
    sleep 0.05
  done
) >"$fifo" &
feeder=$!
wait "$qpid" 2>/dev/null || true
kill "$feeder" 2>/dev/null || true
wait "$feeder" 2>/dev/null || true

fail=0
need() {
  if ! grep -qF -- "$1" "$log"; then
    echo "FAIL trap-frame-smoke -- missing: $1" >&2
    fail=1
  fi
}

need 's1=0x51 s2=0x52'          # callee-saved registers survived into the freeze
need 's5=0x55'
need 's11=0x5B'
need 'gp=0x63 tp=0x64'          # gp/tp too — neither has a legacy slot
need '*** FAULT'                # the fault really happened
need 'TRAP_SNAP_X (x0..x31)'    # the raw dump covers the canonical array too
need 'TFCHK x0z=1 x1ra=1 s1=0x51'  # a live Bt does not clobber the array
need 'TFPOST s1=0x77'          # phase 2: the edited register went live on resume (TrapSnapApply)

if [[ "$fail" -ne 0 ]]; then
  echo "---- uart (tail) ----" >&2
  tail -n 120 "$log" >&2
  exit 1
fi

echo "OK   trap-frame-smoke: all 32 GPRs + mstatus in the fault freeze (DbgX / TRAP_SNAP_X)"
