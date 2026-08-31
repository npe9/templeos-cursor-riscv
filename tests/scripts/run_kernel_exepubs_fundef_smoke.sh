#!/usr/bin/env bash
# Guest ExePutS of a function def — P0 gate (Compiler_RV / ExePutS, not jit.hc).
# Expects: ExePutS("I64 MakeOSProbe(){return 42;}") then MakeOSProbe → 42.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_exepubs_fundef.hc"
EXPECT="ExePutS smoke: OK"
EXPECT_FUN="ExePutS fun=42"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-exepubs-fundef smoke — missing $t" >&2; exit 0; }
done

make -C "$ROOT" holyc-riscv >/dev/null
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-exepubs-fundef — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-exepubs-fundef — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-exepubs-fundef — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly \
    blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
    -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-exepubs-fundef — link error" >&2; exit 1; }

cp "$T/kp.elf" "$OUTDIR/exepubs_fundef.elf"
out="$(LC_ALL=C $TIMEOUT 120 "$QEMU" -M virt -m 128M -bios none -kernel "$T/kp.elf" -nographic </dev/null 2>&1 | LC_ALL=C tr -cd '\11\12\15\40-\176')"
if printf '%s\n' "$out" | grep -qF "$EXPECT" && printf '%s\n' "$out" | grep -qF "$EXPECT_FUN"; then
  echo "Kernel-ExePutS-fundef smoke: OK"
  exit 0
fi
echo "FAIL kernel-exepubs-fundef — expected line not found:" >&2
echo "  want: $EXPECT and $EXPECT_FUN" >&2
printf '%s\n' "$out" | grep -E 'ExePutS|COC:|Except|Error|FAIL|OK|IB!' | head -40 | sed 's/^/  /' >&2
printf '%s\n' "$out" | tail -20 | sed 's/^/  /' >&2
exit 1
