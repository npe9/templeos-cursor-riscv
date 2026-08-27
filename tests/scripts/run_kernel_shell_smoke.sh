#!/bin/bash
# Interactive shell smoke: drive the RISC-V shell over the UART — create a file, list it, read it back,
# and check the background (preemptive) clock advanced — exercising filesystem + scheduler + interrupt
# input together on a fresh virtio-blk image.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"; OUTDIR="$ROOT/build/exec"; COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_shell_demo.hc"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"; OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"; QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do command -v "$t" >/dev/null 2>&1 || { echo "SKIP shell smoke — missing $t" >&2; exit 0; }; done
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL shell smoke — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL shell smoke — crt0" >&2; exit 1; }
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then echo "FAIL shell smoke — compile" >&2; exit 1; fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o s.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 || { echo "FAIL shell smoke — link" >&2; exit 1; }
python3 -c "open('$T/disk.img','wb').write(b'\x00'*(512*128))"
out="$( { printf 'write greet hello-riscv-world\n'; sleep 0.4; printf 'write tmp junk\n'; sleep 0.4; printf 'rm tmp\n'; sleep 0.4; printf 'ls\n'; sleep 0.4; printf 'cat greet\n'; sleep 0.4; printf 'uptime\n'; sleep 0.4; printf 'q\n'; } | $TIMEOUT 25 "$QEMU" -M virt -bios none -kernel "$T/s.elf" -nographic -drive file=$T/disk.img,format=raw,if=none,id=hd0 -device virtio-blk-device,drive=hd0 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "wrote greet" && printf '%s\n' "$out" | grep -qF "removed tmp" && printf '%s\n' "$out" | grep -qF "hello-riscv-world" && printf '%s\n' "$out" | grep -qE "background ticks=[1-9]"; then
  echo "Kernel-shell smoke: OK"; exit 0
fi
echo "FAIL shell smoke — shell session did not behave as expected:" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -12 | sed 's/^/  /' >&2
exit 1
