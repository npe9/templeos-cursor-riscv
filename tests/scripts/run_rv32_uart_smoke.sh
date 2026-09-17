#!/bin/bash
# RV32 P0 smoke: compile an import-free HolyC UART hello with --target rv32, link it behind a
# minimal rv32 crt0, boot it on qemu-system-riscv32 -M virt, and check the printed line plus
# the crt0's ORACLE return-value report. First end-to-end proof that the host compiler emits RV32.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/rv32/uart_hello.hc"
EXPECT="TempleOS/RISC-V rv32 hello"
EXPECT2_RE="^ORACLE [0-9a-f]{8}00000000$"   # low word of main()'s 0 (high word is P1)

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM_RV32:-qemu-system-riscv32}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP rv32-uart smoke — missing $t" >&2; exit 0; }
done

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

"$GCC" -march=rv32ima_zicsr -mabi=ilp32 -nostdlib -ffreestanding -c "$HARNESS/crt0_rv32.S" -o "$T/crt0.o" \
  || { echo "FAIL rv32-uart smoke — crt0" >&2; exit 1; }
if ! "$COMPILER" --target rv32 "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL rv32-uart smoke — compile error" >&2; exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf32-littleriscv blob.bin blob_in.o && \
  "$LD" -m elf32lriscv -T "$HARNESS/link_rv32.ld" -nostdlib --no-warn-mismatch -o p0.elf crt0.o blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL rv32-uart smoke — link error" >&2; exit 1; }

out="$($TIMEOUT 20 "$QEMU" -M virt -bios none -kernel "$T/p0.elf" -nographic </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "$EXPECT" && printf '%s\n' "$out" | grep -qE "$EXPECT2_RE"; then
  echo "RV32 uart smoke: OK"
  exit 0
fi
echo "FAIL rv32-uart smoke — expected lines not found:" >&2
printf '%s\n' "$out" | head -5 | sed 's/^/  got: /' >&2
exit 1
