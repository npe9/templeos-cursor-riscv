#!/bin/bash
# Stock Apps/Psalmody Load + Draw $IB imgs/DrawIt/PopUpDuration + WinMgr GetMsg live
# (SHIFT_ESC exit, record 'z', right-click→PopUpDuration needles).
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
if ! printf '%s\n' "$line" | grep -qE 'ona_hits=[1-9]'; then
  echo "FAIL kernel-psalmody smoke — expected ona_hits>=1 (RV Snd):" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'pcm=[1-9]'; then
  echo "FAIL kernel-psalmody smoke — expected pcm>=1 (soft square ring):" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'notes=[1-9]'; then
  echo "FAIL kernel-psalmody smoke — expected notes>=1 (Play parse):" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVPsalmody UI ok imgs=12 first=10 draw=1 dur=6'; then
  echo "FAIL kernel-psalmody smoke — expected UI ok (imgs/DrawIt/PopUpDuration):" >&2
  printf '%s\n' "$out" | grep -E 'RVPsalmody UI' | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVPsalmody UI ok imgs=12 first=10 draw=1 dur=6 sprite=1'; then
  echo "FAIL kernel-psalmody smoke — expected UI SpriteIns (play/record LM=):" >&2
  printf '%s\n' "$out" | grep -E 'RVPsalmody UI' | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVPsalmody live ok live=[1-9]'; then
  echo "FAIL kernel-psalmody smoke — expected live ok:" >&2
  printf '%s\n' "$out" | grep -E 'RVPsalmody live' | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVPsalmody needles ok esc=1 rec=1 dur=6'; then
  echo "FAIL kernel-psalmody smoke — expected needles ok (SHIFT_ESC/record/PopUpDuration):" >&2
  printf '%s\n' "$out" | grep -E 'RVPsalmody needles' | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVPsalmody stock needles ok esc=1 rec=1 dur=6 notes=[1-9]'; then
  echo "FAIL kernel-psalmody smoke — expected stock Psalmody() needles:" >&2
  printf '%s\n' "$out" | grep -E 'RVPsalmody stock' | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi

ui="$(printf '%s\n' "$out" | grep -E 'RVPsalmody UI ok' | tail -1)"
live="$(printf '%s\n' "$out" | grep -E 'RVPsalmody live ok' | tail -1)"
needles="$(printf '%s\n' "$out" | grep -E 'RVPsalmody needles ok' | tail -1)"
stock="$(printf '%s\n' "$out" | grep -E 'RVPsalmody stock needles ok' | tail -1)"
echo "Kernel-psalmody smoke: OK ($line | $ui | $live | $needles | $stock)"
exit 0
