#!/bin/bash
# virtio-blk storage smoke: attach a raw disk image as a virtio-blk device, write a marker sector and
# read it back (round trip), then confirm the marker actually landed in the disk file (persistence).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"; OUTDIR="$ROOT/build/exec"; COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_blk_demo.hc"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"; OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"; QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do command -v "$t" >/dev/null 2>&1 || { echo "SKIP blk smoke — missing $t" >&2; exit 0; }; done
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL blk smoke — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL blk smoke — crt0" >&2; exit 1; }
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then echo "FAIL blk smoke — compile" >&2; exit 1; fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o b.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 || { echo "FAIL blk smoke — link" >&2; exit 1; }
# fresh zeroed disk image
python3 -c "open('$T/disk.img','wb').write(b'\x00'*(512*64))"
out="$($TIMEOUT 20 "$QEMU" -M virt -bios none -kernel "$T/b.elf" -nographic -drive file=$T/disk.img,format=raw,if=none,id=hd0 -device virtio-blk-device,drive=hd0 </dev/null 2>&1 | tr -d '\r')"
persisted="$(dd if=$T/disk.img bs=512 skip=5 count=1 2>/dev/null | head -c 14)"
if printf '%s\n' "$out" | grep -qF "verified=1" && [ "$persisted" = "RISCV-BLOCK-OK" ]; then
  echo "Kernel-blk smoke: OK"; exit 0
fi
echo "FAIL blk smoke — round trip or persistence failed:" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -4 | sed 's/^/  got: /' >&2
echo "  disk sector5: '$persisted'" >&2
exit 1
