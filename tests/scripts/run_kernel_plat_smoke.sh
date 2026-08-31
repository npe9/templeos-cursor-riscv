#!/bin/bash
# HolyC platform smoke: Kernel/Drv UART+CLINT via Kconfig (RVAutoConf.HH).
# Usage: run_kernel_plat_smoke.sh [virt|sifive_u]
# Compiles tests/exec/cases/kernel_plat_demo.hc after switching defconfig; restores virt after.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOS="$ROOT/templeos-riscv"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_plat_demo.hc"
MACHINE="${1:-virt}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP plat smoke — missing $t" >&2; exit 0; }
done
[ -f "$COMPILER" ] || [ -x "$COMPILER" ] || make -C "$ROOT" holyc-riscv >/dev/null

restore_virt() {
  if [ "$MACHINE" != "virt" ]; then
    make -C "$TOS" defconfig-virt >/dev/null
  fi
}
trap restore_virt EXIT

case "$MACHINE" in
  virt) make -C "$TOS" defconfig-virt >/dev/null ;;
  sifive_u) make -C "$TOS" defconfig-sifive_u >/dev/null ;;
  *) echo "usage: $0 [virt|sifive_u]" >&2; exit 2 ;;
esac

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL plat smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL plat smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"; restore_virt' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL plat smoke — HolyC compile error ($MACHINE)" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -20 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o plat.elf \
    "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL plat smoke — link error" >&2; exit 1; }

cp "$T/plat.elf" "$OUTDIR/plat-$MACHINE.elf"
out="$($TIMEOUT 20 "$QEMU" -M "$MACHINE" -bios none -kernel "$T/plat.elf" -nographic </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "plat-smoke: PASS"; then
  echo "Plat smoke ($MACHINE): OK"
  exit 0
fi
echo "FAIL plat smoke ($MACHINE) — expected plat-smoke: PASS" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
exit 1
