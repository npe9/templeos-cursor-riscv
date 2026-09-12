#!/bin/bash
# Kernel CDC/Sprite smoke: DCNew/GrBlot/FloodFill/brush + Sprite3 + mesh/ScrnCast libs +
# CompressBuf .GR.Z roundtrip (grzok) + WinMgr ScrnCast compose hook (wmcast/ja) +
# just_audio snd queue + soft AUWrite (auok) +
# optional offscreen 8-bit live body + FloodFill (u8ok/ff8) +
# opt-in GrUpdateVGAGraphics 8-bit expand present (vgaok) +
# opt-in WinMgr text/draw_it into full-screen is_u8 (wm8ok) on 32-bpp CRVDC/FB.
# CI uses -display none + UART hash; no host window required.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_cdc_demo.hc"
EXPECT_PREFIX="RVCDC smoke hash="
# Word-wise FNV-1a for kernel_cdc_demo.hc (800×600). Override with RVCDC_EXPECT_HASH.
# Calibrate: RVCDC_EXPECT_HASH=0x00000000 make kernel-cdc-smoke
# Pin recalibrated 2026-09-05 (WIP FB drift vs 0x53F1F7A6/0xF98D0CE6; wm8/auok/vgaok post-hash).
PINNED_HASH="0xEFB2D715"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-cdc smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-cdc smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-cdc smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-cdc smoke — compile error" >&2
  HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >&2 || true
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o cdc.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-cdc smoke — link error" >&2; exit 1; }

cp "$T/cdc.elf" "$OUTDIR/cdc.elf"

out="$($TIMEOUT 40 "$QEMU" -M virt -m 128M -bios none -kernel "$T/cdc.elf" \
  -device ramfb -display none -serial stdio </dev/null 2>&1 | tr -d '\r')"

if ! printf '%s\n' "$out" | grep -qF "$EXPECT_PREFIX"; then
  echo "FAIL kernel-cdc smoke — no hash line:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -20 | sed 's/^/  got: /' >&2
  exit 1
fi

line="$(printf '%s\n' "$out" | grep -F "$EXPECT_PREFIX" | tail -1)"
hash="$(printf '%s\n' "$line" | sed -n 's/.*hash=\(0x[0-9A-Fa-f]\{1,8\}\).*/\1/p')"
hash="$(printf '%s' "$hash" | tr 'abcdef' 'ABCDEF')"
if [ -z "$hash" ] || [ "$hash" = "0x00000000" ]; then
  echo "FAIL kernel-cdc smoke — bad hash: $line" >&2
  exit 1
fi

want="${RVCDC_EXPECT_HASH:-$PINNED_HASH}"
want="$(printf '%s' "$want" | tr 'abcdef' 'ABCDEF')"
if [ "$want" = "0x00000000" ]; then
  echo "Kernel-cdc smoke: OK (calibrate: pin PINNED_HASH=$hash) ($line)"
  echo "$hash" > "$OUTDIR/cdc_expect_hash.txt"
  exit 0
fi

if [ "$hash" != "$want" ]; then
  echo "FAIL kernel-cdc smoke — hash mismatch:" >&2
  echo "  want: $want" >&2
  echo "  got:  $line" >&2
  exit 1
fi

if ! printf '%s\n' "$line" | grep -qE 'grzok=1'; then
  echo "FAIL kernel-cdc smoke — grzok missing/failed: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'u8ok=1'; then
  echo "FAIL kernel-cdc smoke — u8ok missing/failed: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'ff8=[1-9][0-9]*'; then
  echo "FAIL kernel-cdc smoke — ff8 missing/failed (u8 FloodFill): $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'wmcast=[1-9]'; then
  echo "FAIL kernel-cdc smoke — wmcast missing/failed: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'ja=0'; then
  echo "FAIL kernel-cdc smoke — ja missing/failed: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'vgaok=1'; then
  echo "FAIL kernel-cdc smoke — vgaok missing/failed (8-bit expand present): $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'auok=1'; then
  echo "FAIL kernel-cdc smoke — auok missing/failed (just_audio AUWrite): $line" >&2
  exit 1
fi
if ! printf '%s\n' "$line" | grep -qE 'wm8ok=1'; then
  echo "FAIL kernel-cdc smoke — wm8ok missing/failed (WinMgr draw into is_u8): $line" >&2
  exit 1
fi

echo "Kernel-cdc smoke: OK ($line)"
exit 0
