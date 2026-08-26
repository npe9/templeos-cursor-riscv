#!/bin/bash
# Interrupt-driven UART input smoke: feed a line over the UART; the program receives it via the PLIC
# external interrupt (main reads only the interrupt-filled ring buffer, never the device) and echoes.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"; OUTDIR="$ROOT/build/exec"; COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_uartirq_demo.hc"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"; OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"; QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do command -v "$t" >/dev/null 2>&1 || { echo "SKIP uartirq smoke — missing $t" >&2; exit 0; }; done
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL uartirq smoke — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL uartirq smoke — crt0" >&2; exit 1; }
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then echo "FAIL uartirq smoke — compile" >&2; exit 1; fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o u.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 || { echo "FAIL uartirq smoke — link" >&2; exit 1; }
out="$(printf 'hello\n' | $TIMEOUT 20 "$QEMU" -M virt -bios none -kernel "$T/u.elf" -nographic 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "got: 'hello' len=5"; then echo "Kernel-uartirq smoke: OK"; exit 0; fi
echo "FAIL uartirq smoke — expected input not received:" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -6 | sed 's/^/  got: /' >&2
exit 1
