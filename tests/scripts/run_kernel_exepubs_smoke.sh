#!/usr/bin/env bash
# Guest ExePutS smoke: Kernel_RV + Compiler_RV_Body → ExePutS("Add(40,2)") under QEMU.
# TempleOS-shaped path (not jit.hc). See templeos-riscv/COMPILER_RV.md.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_exepubs_demo.hc"
EXPECT="ExePutS smoke: OK"
EXPECT2="ExePutS 40+2=42"
EXPECT2b="ExePutS Add(40,2)=42"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-exepubs smoke — missing $t" >&2; exit 0; }
done

make -C "$ROOT" holyc-riscv >/dev/null
mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-exepubs smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-exepubs smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Also refresh standalone Compiler_RV blob into the Phase-B slot path (layout / future Load).
mkdir -p "$ROOT/build"
if HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$ROOT/Compiler/Compiler_RV.PRJ" \
     -o "$ROOT/build/compiler_rv.blob.bin" >/dev/null 2>&1; then
  # COMP magic + blob (C kernel slot expects magic at 0x80200000; HolyC smoke uses in-image Body).
  {
    printf 'COMP'
    # pad to 8 then append — keep raw blob for RedSea/install docs
    cat "$ROOT/build/compiler_rv.blob.bin"
  } > "$ROOT/build/compiler_slot.bin" 2>/dev/null || true
  ls -la "$ROOT/build/compiler_rv.blob.bin" "$ROOT/build/compiler_slot.bin" 2>/dev/null | sed 's/^/  /'
fi

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-exepubs smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly \
    blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch \
    -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-exepubs smoke — link error" >&2; exit 1; }

cp "$T/kp.elf" "$OUTDIR/exepubs.elf"
# 2MB HolyC image; allow longer QEMU window for JIT
out="$(LC_ALL=C $TIMEOUT 120 "$QEMU" -M virt -m 128M -bios none -kernel "$T/kp.elf" -nographic </dev/null 2>&1 | LC_ALL=C tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "$EXPECT" && \
   { printf '%s\n' "$out" | grep -qF "$EXPECT2" || printf '%s\n' "$out" | grep -qF "$EXPECT2b"; }; then
  echo "Kernel-ExePutS smoke: OK"
  exit 0
fi
echo "FAIL kernel-exepubs smoke — expected line not found:" >&2
echo "  want: $EXPECT and ($EXPECT2 or $EXPECT2b)" >&2
printf '%s\n' "$out" | grep -E 'ExePutS|Except|Error|JIT|ans=|FAIL|OK' | head -40 | sed 's/^/  /' >&2
printf '%s\n' "$out" | tail -30 | sed 's/^/  /' >&2
exit 1
