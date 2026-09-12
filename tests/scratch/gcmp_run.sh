#!/usr/bin/env bash
# Scratch runner: build+run a guest-Cmp probe case under QEMU (UART only).
# usage: tests/scratch/gcmp_run.sh tests/scratch/gcmp_arrpp_probe.hc
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="${1:-$ROOT/tests/scratch/gcmp_arrpp_probe.hc}"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

make -C "$ROOT" holyc-riscv >/dev/null || exit 1
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || exit 1
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || exit 1
fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "COMPILE FAIL" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -25 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
    -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 || { echo "LINK FAIL" >&2; exit 1; }
LC_ALL=C $TIMEOUT "${GCMP_TIMEOUT:-180}" "$QEMU" -M virt -m 128M -bios none -kernel "$T/kp.elf" -nographic \
  </dev/null 2>&1 | LC_ALL=C tr -cd '\11\12\15\40-\176' | awk '{print} /GCMP: done/{exit 0}'
