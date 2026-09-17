#!/bin/bash
# Kernel-image fault-freeze smoke: the C runtime's trap vector (bootstrap/holy_rt.h
# HolyTrapVector) must save every GPR and publish the same two views as the seed image —
# legacy slots at 0x87000100 and the canonical x0..x31 array at 0x87000400 — so one debugger
# core can read either image. The demo plants markers in s1/s2/s5/s11/gp/tp, faults, recovers
# via RVTrapRecoverArm, and checks each register came back.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_trapframe_demo.hc"
EXPECT="trapframe: PASS"
EXPECT2="s11=000000000000005b ok"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-trapframe smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-trapframe smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-trapframe smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-trapframe smoke — compile error" >&2; exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-trapframe smoke — link error" >&2; exit 1; }

out="$($TIMEOUT 30 "$QEMU" -M virt -bios none -kernel "$T/kp.elf" -nographic </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "$EXPECT" && printf '%s\n' "$out" | grep -qF "$EXPECT2"; then
  echo "Kernel-trapframe smoke: OK (all 32 GPRs + mstatus frozen by the C trap vector)"
  exit 0
fi
echo "FAIL kernel-trapframe smoke — expected line not found:" >&2
echo "  want: $EXPECT" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -5 | sed 's/^/  got: /' >&2
exit 1
