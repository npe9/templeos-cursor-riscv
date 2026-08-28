#!/bin/bash
# Kernel-print smoke: compile a program that #includes the real TempleOS kernel (Kernel_RV.PRJ),
# formats a string with the kernel's own StrPrintJoin, and writes it to the QEMU virt UART. Then
# run it under qemu-system-riscv64 and check the expected line appears. This proves real kernel
# code (not just the front end) executes and produces output on RISC-V.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_fsshell_demo.hc"
EXPECT="inside docs"
EXPECT2="now in /DOCS"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-fsshell smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-fsshell smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-fsshell smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-fsshell smoke — compile error" >&2; exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-fsshell smoke — link error" >&2; exit 1; }

out="$(printf 'mkdir DOCS\nwrite HELLO.TXT hello world\ndir\ncat HELLO.TXT\ncd DOCS\nwrite NOTE.TXT inside docs\ncat NOTE.TXT\nexit\n' | $TIMEOUT 30 "$QEMU" -M virt -bios none -kernel "$T/kp.elf" -nographic 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "$EXPECT" && printf '%s\n' "$out" | grep -qF "$EXPECT2"; then
  echo "Kernel-fsshell smoke: OK"
  exit 0
fi
echo "FAIL kernel-fsshell smoke — expected line not found:" >&2
echo "  want: $EXPECT" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -5 | sed 's/^/  got: /' >&2
exit 1
