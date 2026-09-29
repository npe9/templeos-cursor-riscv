#!/bin/bash
# The simulated spacecraft: bus, apps and the fault-detection loop (Kernel/Cfs).
#
# Asserts the FDIR chain end to end, not that messages merely flow. Because the scheduler runs on
# SIMULATED time (a tick advances a fixed step), the execution counts are exact and deterministic on
# any host -- so this gate can require 200 IMU runs and 100 NAV runs rather than "more than zero",
# which is what makes a scheduler regression visible instead of silent.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_cfs_demo.hc"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL cfs smoke — missing $t" >&2; exit 1; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL cfs smoke — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL cfs smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL cfs smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -30 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf \
    "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL cfs smoke — link error" >&2; exit 1; }

out="$($TIMEOUT 180 "$QEMU" -M virt -m 256M -bios none -kernel "$T/kp.elf" -nographic \
        </dev/null 2>&1 | tr -d '\r')"

rc=0
# The FDIR chain, each stage named so a failure says which link broke.
for n in "cfs-sim: nominal_ok" \
         "cfs-sim: capture_chain_ok" \
         "cfs-sim: load_shed_ok" \
         "cfs-sim: hs_detect_ok" \
         "cfs-sim: safe_mode_ok" \
         "cfs-sim: cs_detect_ok" \
         "cfs-sim: queue_drop_ok" \
         "cfs-sim: done"; do
  printf '%s\n' "$out" | grep -qF "$n" || { echo "FAIL cfs smoke — missing: $n" >&2; rc=1; }
done
# Exact execution counts. Simulated time makes these deterministic: 2 s of mission time at a 10 ms
# IMU period is 200 runs and nothing else. A drifting scheduler changes these before it breaks
# anything a boolean needle would notice.
for n in "cfs-sim: imu_runs=200" "cfs-sim: nav_runs=100"; do
  printf '%s\n' "$out" | grep -qF "$n" || { echo "FAIL cfs smoke — timing changed, expected: $n" >&2; rc=1; }
done
if printf '%s\n' "$out" | grep -q '_FAIL'; then
  echo "FAIL cfs smoke — a phase reported _FAIL" >&2
  printf '%s\n' "$out" | grep '_FAIL' | sed 's/^/  /' >&2
  rc=1
fi
if [ "$rc" != 0 ]; then
  printf '%s\n' "$out" | grep -vE 'import unresolved' | tail -25 | sed 's/^/  /' >&2
  exit 1
fi
printf '%s\n' "$out" | grep -E 'cfs-sim: (imu_runs|nav_runs|ds_records|sb_sent|nav_dropped|evs_crit|hs_deaths|cs_faults)' | sed 's/^/  /'
echo "cfs smoke: OK"
