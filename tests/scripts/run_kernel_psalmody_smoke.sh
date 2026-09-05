#!/bin/bash
# Stock Apps/Psalmody Load + WinMgr GetMsg live (Note2Ona/Menu/Tempo + $IB staff + live notes).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_psalmody_demo.hc"
EXPECT_PREFIX="RVPsalmody smoke ona="

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-psalmody smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-psalmody smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-psalmody smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-psalmody smoke — compile error" >&2
  HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >&2 || true
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o psalmody.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-psalmody smoke — link error" >&2; exit 1; }

cp "$T/psalmody.elf" "$OUTDIR/psalmody.elf"

out="$($TIMEOUT 120 "$QEMU" -M virt -m 128M -bios none -kernel "$T/psalmody.elf" \
  -device ramfb -display none -serial stdio </dev/null 2>&1 | tr -d '\r')"

if ! printf '%s\n' "$out" | grep -qF "$EXPECT_PREFIX"; then
  echo "FAIL kernel-psalmody smoke — no smoke line:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -40 | sed 's/^/  got: /' >&2
  exit 1
fi

line="$(printf '%s\n' "$out" | grep -F "$EXPECT_PREFIX" | tail -1)"
if printf '%s\n' "$out" | grep -qE 'RVPsalmody .* FAIL'; then
  echo "FAIL kernel-psalmody smoke — guest FAIL:" >&2
  echo "  got: $line" >&2
  printf '%s\n' "$out" | grep -E 'RVPsalmody' | head -10 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'ona=51'; then
  echo "FAIL kernel-psalmody smoke — expected ona=51:" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'ib=3'; then
  echo "FAIL kernel-psalmody smoke — expected host \$IB staff first=3:" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVPsalmody live ok live=[1-9]'; then
  echo "FAIL kernel-psalmody smoke — expected live ok:" >&2
  printf '%s\n' "$out" | grep -E 'RVPsalmody live' | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi

live="$(printf '%s\n' "$out" | grep -E 'RVPsalmody live ok' | tail -1)"
echo "Kernel-psalmody smoke: OK ($line | $live)"
exit 0
