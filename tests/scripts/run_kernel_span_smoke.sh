#!/bin/bash
# Stock Apps/Span Load on RV (Cd(__DIR__) + Bridge/DrawIt + GetMsg under WinMgr).
# CI: -display none + UART needles; GetMsg PlaceMass + win_getmsg + FilesFind PopUpPickFile
# (not infinite Span() / stock FileMgr GetMsg).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_span_demo.hc"
EXPECT_PREFIX="RVSpan smoke masses="

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-span smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-span smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-span smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-span smoke — compile error" >&2
  HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >&2 || true
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o span.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-span smoke — link error" >&2; exit 1; }

cp "$T/span.elf" "$OUTDIR/span.elf"

out="$($TIMEOUT 90 "$QEMU" -M virt -m 128M -bios none -kernel "$T/span.elf" \
  -device ramfb -display none -serial stdio </dev/null 2>&1 | tr -d '\r')"

if ! printf '%s\n' "$out" | grep -qF "$EXPECT_PREFIX"; then
  echo "FAIL kernel-span smoke — no smoke line:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -40 | sed 's/^/  got: /' >&2
  exit 1
fi

line="$(printf '%s\n' "$out" | grep -F "$EXPECT_PREFIX" | tail -1)"
if printf '%s\n' "$out" | grep -qF 'RVSpan smoke FAIL'; then
  echo "FAIL kernel-span smoke — guest FAIL:" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'masses=1[5-9]|masses=[2-9][0-9]'; then
  echo "FAIL kernel-span smoke — expected masses>=15:" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'flood=[1-9]'; then
  echo "FAIL kernel-span smoke — expected flood>0:" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'getmsg=[1-9]|win_getmsg=[1-9]'; then
  echo "FAIL kernel-span smoke — expected getmsg/win_getmsg:" >&2
  echo "  got: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'pick=1'; then
  echo "FAIL kernel-span smoke — expected pick=1:" >&2
  echo "  got: $line" >&2
  exit 1
fi

echo "Kernel-span smoke: OK ($line)"
exit 0
