#!/bin/bash
# Kernel virtio-9p PCI smoke: HolyC NinePVirtioPci queues over virtio-9p-pci.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_virtio_9p_demo.hc"
EXPECT="virtio-9p: read_ok"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-virtio-9p-pci smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-virtio-9p-pci smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-virtio-9p-pci smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/share"
printf 'hello from 9p' >"$T/share/test.txt"

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-virtio-9p-pci smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -30 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-virtio-9p-pci smoke — link error" >&2; exit 1; }

# PCI-only attach (no virtio-9p-device) so BindAny takes the PCI queue path.
out="$($TIMEOUT 30 "$QEMU" -M virt -m 256M -bios none -kernel "$T/kp.elf" -nographic \
        -fsdev local,id=fsdev0,path="$T/share",security_model=none \
        -device virtio-9p-pci,fsdev=fsdev0,mount_tag=hostshare </dev/null 2>&1 | tr -d '\r')"
if ! printf '%s\n' "$out" | grep -qF "$EXPECT"; then
  echo "FAIL kernel-virtio-9p-pci smoke — expected line not found:" >&2
  echo "  want: $EXPECT" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -20 | sed 's/^/  got: /' >&2
  exit 1
fi
if [ ! -f "$T/share/export.txt" ]; then
  echo "FAIL kernel-virtio-9p-pci smoke — guest→host export.txt missing on host share" >&2
  exit 1
fi
if ! grep -qF 'overwrite-9p' "$T/share/export.txt"; then
  echo "FAIL kernel-virtio-9p-pci smoke — export.txt overwrite mismatch" >&2
  sed 's/^/  got: /' "$T/share/export.txt" >&2
  exit 1
fi
if [ ! -f "$T/share/Home/nest/out.hc" ] || ! grep -qF 'nested-9p' "$T/share/Home/nest/out.hc"; then
  echo "FAIL kernel-virtio-9p-pci smoke — nested Home/nest/out.hc missing or wrong" >&2
  find "$T/share" -type f 2>/dev/null | sed 's/^/  /' >&2 || true
  exit 1
fi
echo "Kernel-virtio-9p-pci smoke: OK (read + export + overwrite + nested)"
exit 0
