#!/bin/bash
# Stock Demo/Graphics/Blot.HC on RV Gr (FloodFill3/brush/GrLine3 + SettingsPush/WinMax/PopUpColor/Refresh).
# CI uses -display none + UART hash; no host window required.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_demo_blot.hc"
EXPECT_PREFIX="RVDemo Blot smoke hash="
# Calibrate on first green: RVDEMO_BLOT_EXPECT_HASH=0x00000000 make kernel-demo-blot-smoke
# Re-recorded 2026-09-19. Every pinned framebuffer hash in tests/scripts was read at HEAD and
# again in a worktree at d207eda, before this session: all six came out identical, so no
# rendering moved and the pins that disagree were simply stale. If one moves again, find the
# commit that moved it before touching this line — a framebuffer hash cannot tell you whether
# the picture got better or worse.
PINNED_HASH="0x43186381"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-demo-blot smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-demo-blot smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-demo-blot smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-demo-blot smoke — compile error" >&2
  HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >&2 || true
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o blot.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-demo-blot smoke — link error" >&2; exit 1; }

cp "$T/blot.elf" "$OUTDIR/blot.elf"

out="$($TIMEOUT 40 "$QEMU" -M virt -m 128M -bios none -kernel "$T/blot.elf" \
  -device ramfb -display none -serial stdio </dev/null 2>&1 | tr -d '\r')"

if ! printf '%s\n' "$out" | grep -qF "$EXPECT_PREFIX"; then
  echo "FAIL kernel-demo-blot smoke — no hash line:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -40 | sed 's/^/  got: /' >&2
  exit 1
fi

line="$(printf '%s\n' "$out" | grep -F "$EXPECT_PREFIX" | tail -1)"
hash="$(printf '%s\n' "$line" | sed -n 's/.*hash=\(0x[0-9A-Fa-f]\{1,8\}\).*/\1/p')"
hash="$(printf '%s' "$hash" | tr 'abcdef' 'ABCDEF')"
if [ -z "$hash" ] || [ "$hash" = "0x00000000" ]; then
  echo "FAIL kernel-demo-blot smoke — bad hash: $line" >&2
  exit 1
fi

want="${RVDEMO_BLOT_EXPECT_HASH:-$PINNED_HASH}"
want="$(printf '%s' "$want" | tr 'abcdef' 'ABCDEF')"
if [ "$want" = "0x00000000" ]; then
  echo "Kernel-demo-blot smoke: OK (calibrate: pin PINNED_HASH=$hash) ($line)"
  echo "$hash" > "$OUTDIR/blot_expect_hash.txt"
  exit 0
fi

if [ "$hash" != "$want" ]; then
  echo "FAIL kernel-demo-blot smoke — hash mismatch:" >&2
  echo "  want: $want" >&2
  echo "  got:  $line" >&2
  exit 1
fi

echo "Kernel-demo-blot smoke: OK ($line)"
exit 0
