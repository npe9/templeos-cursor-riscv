#!/bin/bash
# Multi-hart smoke: HolyC + crt0_smp on QEMU virt -smp 2.
# Optional (not in default qemu-integration): make kernel-smp-smoke
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_smp_demo.hc"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP smp smoke — missing $t" >&2; exit 0; }
done
[ -f "$COMPILER" ] || [ -x "$COMPILER" ] || make -C "$ROOT" holyc-riscv >/dev/null

mkdir -p "$OUTDIR"
"$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
  -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL smp smoke — harness compile" >&2; exit 1; }
"$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
  -c "$HARNESS/crt0_smp.S" -o "$OUTDIR/crt0_smp.o" || { echo "FAIL smp smoke — crt0_smp" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL smp smoke — HolyC compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -30 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o smp.elf \
    "$OUTDIR/crt0_smp.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL smp smoke — link error" >&2; exit 1; }

cp "$T/smp.elf" "$OUTDIR/smp.elf"
out="$($TIMEOUT 20 "$QEMU" -M virt -smp 2 -bios none -kernel "$T/smp.elf" -nographic </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "smp-smoke: hart1_count=42 PASS"; then
  echo "SMP smoke: OK"
  exit 0
fi
echo "FAIL smp smoke — expected smp-smoke: hart1_count=42 PASS" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -30 | sed 's/^/  got: /' >&2
exit 1
