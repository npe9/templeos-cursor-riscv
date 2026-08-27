#!/bin/bash
# Filesystem persistence smoke: run the FS demo TWICE on the SAME virtio-blk disk image. The first
# boot formats the disk and creates files; the second boot reads them back — proving a filesystem
# whose contents survive across reboots on RISC-V.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"; OUTDIR="$ROOT/build/exec"; COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_fs_demo.hc"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"; OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"; QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do command -v "$t" >/dev/null 2>&1 || { echo "SKIP fs smoke — missing $t" >&2; exit 0; }; done
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL fs smoke — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL fs smoke — crt0" >&2; exit 1; }
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then echo "FAIL fs smoke — compile" >&2; exit 1; fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o f.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 || { echo "FAIL fs smoke — link" >&2; exit 1; }
python3 -c "open('$T/disk.img','wb').write(b'\x00'*(512*128))"
run(){ $TIMEOUT 20 "$QEMU" -M virt -bios none -kernel "$T/f.elf" -nographic -drive file=$T/disk.img,format=raw,if=none,id=hd0 -device virtio-blk-device,drive=hd0 </dev/null 2>&1 | tr -d '\r'; }
out1="$(run)"; out2="$(run)"
if printf '%s\n' "$out1" | grep -qF "fresh disk: formatted" && printf '%s\n' "$out2" | grep -qF "persisted: 2 files, hello.txt='Hello from the RISC-V filesystem!'"; then
  echo "Kernel-fs smoke: OK"; exit 0
fi
echo "FAIL fs smoke — filesystem did not persist across reboots:" >&2
echo "  run1: $(printf '%s' "$out1" | grep -v 'import unresolved' | grep -iE 'disk|file' | head -1)" >&2
echo "  run2: $(printf '%s' "$out2" | grep -v 'import unresolved' | grep -iE 'disk|persist|file' | head -1)" >&2
exit 1
