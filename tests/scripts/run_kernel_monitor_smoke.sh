#!/bin/bash
# Capstone smoke: an interactive preemptive-multitasking monitor over the UART. A background worker
# counts (lock-protected) while commands arrive by RX interrupt. Feed 'c' a few times (with pauses so
# the worker advances) then 'q'; check the counter is reported and the session ends cleanly.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"; OUTDIR="$ROOT/build/exec"; COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_monitor_demo.hc"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"; OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"; QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do command -v "$t" >/dev/null 2>&1 || { echo "SKIP monitor smoke — missing $t" >&2; exit 0; }; done
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL monitor smoke — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL monitor smoke — crt0" >&2; exit 1; }
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then echo "FAIL monitor smoke — compile" >&2; exit 1; fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o m.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 || { echo "FAIL monitor smoke — link" >&2; exit 1; }
out="$( { printf 'c'; sleep 0.5; printf 'c'; sleep 0.5; printf 'q'; } | $TIMEOUT 20 "$QEMU" -M virt -bios none -kernel "$T/m.elf" -nographic 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qE 'c counter=[0-9]+' && printf '%s\n' "$out" | grep -qF "bye final=1"; then echo "Kernel-monitor smoke: OK"; exit 0; fi
echo "FAIL monitor smoke — expected monitor output not found:" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -8 | sed 's/^/  got: /' >&2
exit 1
