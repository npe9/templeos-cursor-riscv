#!/bin/bash
# VT presenter smoke: run the WinMgr/DolDoc stack headless (RVWinMgrLiteInit, no FB)
# and ship its text grid to the UART as ANSI via Kernel/RVDocVT.HC.
#
# The interesting assertion is not "it drew something" — it is the bandwidth property
# the whole design rests on. 80x25 is 2000 cells; a full repaint with a colour escape
# per cell is ~24 KiB, which at 115200 baud is over two seconds per frame. So the
# presenter diffs against a shadow of what the terminal already shows, and this smoke
# gates that: an idle present must cost EXACTLY zero bytes, and a one-line edit must
# cost strictly less than the first full paint. Without those two checks the design
# silently decays back to full repaints and nobody notices until a real serial line.
#
# Interactive (watch it paint a real terminal):
#   qemu-system-riscv64 -M virt -m 128M -bios none -kernel build/exec/vt.elf -nographic
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_vt_present.hc"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-vt smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-vt smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-vt smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-vt smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o vt.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-vt smoke — link error" >&2; exit 1; }

cp "$T/vt.elf" "$OUTDIR/vt.elf"

out="$($TIMEOUT 60 "$QEMU" -M virt -m 128M -bios none -kernel "$T/vt.elf" -nographic </dev/null 2>&1 | tr -d '\r')"
clean="$(printf '%s\n' "$out" | grep -v 'import unresolved')"

fail=0
need() {
  printf '%s\n' "$clean" | grep -qF -- "$1" || { echo "FAIL kernel-vt smoke — missing: $1" >&2; fail=1; }
}

need "VT: WinMgr lite up"
need "VT: OK"

# The guest already asserts the two cost properties and prints its own FAIL lines;
# surface them here rather than only relying on the absence of "VT: OK".
if printf '%s\n' "$clean" | grep -qF "VT: FAIL idle present was not free"; then
  echo "FAIL kernel-vt smoke — idle present emitted bytes (shadow diff broken)" >&2
  fail=1
fi
if printf '%s\n' "$clean" | grep -qF "VT: FAIL incremental present not cheaper"; then
  echo "FAIL kernel-vt smoke — incremental present not cheaper than full paint" >&2
  fail=1
fi

# Border glyphs must have been translated out of the 0x02..0x0D font range into the
# ASCII fallback: a raw control byte here would mean RVVtPutGlyph let one through.
# Via `cat -v` so this is portable (macOS grep has no -P, and a silently-skipped
# check is worse than none). ^A-^H = 0x01-0x08, ^K/^L = 0x0b/0x0c, ^N-^Z = 0x0e-0x1a.
# Deliberately excluded: ^I/^J/^M (tab, LF, CR) and ^[ (ESC), which every ANSI
# sequence this presenter emits begins with.
if printf '%s\n' "$clean" | LC_ALL=C cat -v | grep -q '\^[A-HKLN-Z]'; then
  echo "FAIL kernel-vt smoke — raw control byte in output (glyph translation leaked)" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "---- output ----" >&2
  printf '%s\n' "$clean" | head -30 | cat -v | sed 's/^/  /' >&2
  exit 1
fi

printf '%s\n' "$clean" | grep -F 'VT: first=' | sed 's/^/  /'
echo "Kernel-VT smoke: OK (headless grid → ANSI; idle present free, incremental < full)"
exit 0
