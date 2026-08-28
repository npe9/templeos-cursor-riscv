#!/bin/bash
# Kernel-virtio smoke: compile a program that #includes the real TempleOS kernel (Kernel_RV.PRJ) and
# uses the kernel's OWN native virtio-blk driver (Kernel/BlkDev/DskVirtioRV.HC) to read and write a
# real disk over legacy virtio-mmio. QEMU virt is launched with a raw disk image (sector 5 pre-filled
# with 0xCC) attached as a virtio-blk-device. This proves the kernel drives real hardware on RISC-V,
# the translation of the x86 ATA driver.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_virtio_demo.hc"
EXPECT="virtio-blk read-write OK"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-virtio smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-virtio smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-virtio smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Disk image: 256 sectors; sector 5 pre-filled with 0xCC so the read path has a known value to check.
python3 -c "
d=bytearray(256*512)
for i in range(512): d[5*512+i]=0xCC
open('$T/disk.img','wb').write(d)" || { echo "FAIL kernel-virtio smoke — mkdisk" >&2; exit 1; }

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-virtio smoke — compile error" >&2; exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-virtio smoke — link error" >&2; exit 1; }

out="$($TIMEOUT 30 "$QEMU" -M virt -m 256M -bios none -kernel "$T/kp.elf" -nographic \
        -drive file="$T/disk.img",if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "$EXPECT"; then
  echo "Kernel-virtio smoke: OK"
  exit 0
fi
echo "FAIL kernel-virtio smoke — expected line not found:" >&2
echo "  want: $EXPECT" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -8 | sed 's/^/  got: /' >&2
exit 1
