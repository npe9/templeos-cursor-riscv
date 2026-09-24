#!/bin/bash
# Kernel framebuffer smoke (Phase 0–1): compile RVFb demo, run under QEMU virt with ramfb.
# CI uses -display none + UART hash; no host window required.
#
# Interactive display (host window — macOS cocoa; omit -nographic / -display none):
#   qemu-system-riscv64 -M virt -m 128M -bios none -kernel build/exec/fb.elf \
#     -device ramfb -display cocoa -serial stdio
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_fb_demo.hc"
EXPECT_PREFIX="RVFb smoke hash="
# Word-wise FNV-1a for tests/exec/cases/kernel_fb_demo.hc (800×600). Override with RVFB_EXPECT_HASH.
PINNED_HASH="0x28921CB5"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-fb smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ] || [ "$ROOT/bootstrap/holy_rt_names.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-fb smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-fb smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_NO_TIER2="${HOLYC_NO_TIER2:-1}" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-fb smoke — compile error" >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o fb.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-fb smoke — link error" >&2; exit 1; }

cp "$T/fb.elf" "$OUTDIR/fb.elf"

# -m 128M: FB at 0x86100000. ramfb needs fw_cfg DMA (virt provides it).
# Background QEMU with a QMP socket, so the SCANOUT can be captured while the guest is still
# up. Everything in this tree until now hashed rv_fb.pixels -- the guest's own COMPOSE buffer
# -- which proves the guest drew the right picture but not that any of it reached a display
# surface. See tools/fb_scanout_hash.py.
ser="$T/ser.txt"
: > "$ser"
"$QEMU" -M virt -m 128M -bios none -kernel "$T/fb.elf" \
  -device ramfb -display none -serial "file:$ser" \
  -qmp "unix:$T/qmp.sock,server,nowait" </dev/null >"$T/qemu.err" 2>&1 &
qpid=$!
waited=0
while [ "$waited" -lt 40 ]; do
  kill -0 "$qpid" 2>/dev/null || break
  grep -qF "$EXPECT_PREFIX" "$ser" 2>/dev/null && break
  sleep 1
  waited=$((waited + 1))
done
# Capture the scanout BEFORE killing QEMU; a failure here must not fail the smoke on its own
# (old QEMU may lack screendump over QMP), so it is reported and checked only when present.
scanout=""
if kill -0 "$qpid" 2>/dev/null && [ -S "$T/qmp.sock" ]; then
  scanout="$(python3 "$ROOT/tools/fb_scanout_hash.py" "$T/qmp.sock" "$T/scanout.ppm" 2>"$T/scanout.err" \
    | sed -n 's/^scanout_hash=//p')"
fi
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
out="$(tr -d '\r' < "$ser")"

if ! printf '%s\n' "$out" | grep -qF "$EXPECT_PREFIX"; then
  echo "FAIL kernel-fb smoke — no hash line:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -20 | sed 's/^/  got: /' >&2
  exit 1
fi

line="$(printf '%s\n' "$out" | grep -F "$EXPECT_PREFIX" | tail -1)"
hash="$(printf '%s\n' "$line" | sed -n 's/.*hash=\(0x[0-9A-Fa-f]\{1,8\}\).*/\1/p')"
# Normalize to uppercase for comparison
hash="$(printf '%s' "$hash" | tr 'abcdef' 'ABCDEF')"
if [ -z "$hash" ] || [ "$hash" = "0x00000000" ]; then
  echo "FAIL kernel-fb smoke — bad hash: $line" >&2
  exit 1
fi

want="${RVFB_EXPECT_HASH:-$PINNED_HASH}"
want="$(printf '%s' "$want" | tr 'abcdef' 'ABCDEF')"
if [ "$want" = "0x00000000" ]; then
  # Calibrate mode: accept any non-zero hash and print it for pinning.
  echo "Kernel-fb smoke: OK (calibrate: pin PINNED_HASH=$hash) ($line)"
  echo "$hash" > "$OUTDIR/fb_expect_hash.txt"
  exit 0
fi

if [ "$hash" != "$want" ]; then
  echo "FAIL kernel-fb smoke — hash mismatch:" >&2
  echo "  want: $want" >&2
  echo "  got:  $line" >&2
  exit 1
fi

# SCANOUT check: the display surface must carry the very bytes the guest hashed. This is the
# only assertion in the tree that distinguishes "drew the right picture" from "the picture
# reached the screen"; the compose-buffer hash above cannot tell those apart.
if [ -n "$scanout" ]; then
  scanout="$(printf '%s' "$scanout" | tr 'abcdef' 'ABCDEF')"
  if [ "$scanout" != "$hash" ]; then
    echo "FAIL kernel-fb smoke — scanout does not match the guest's framebuffer:" >&2
    echo "  guest compose: $hash" >&2
    echo "  host scanout:  $scanout   ($T/scanout.ppm)" >&2
    exit 1
  fi
else
  echo "kernel-fb smoke: scanout capture unavailable, compose hash only" >&2
  [ -s "$T/scanout.err" ] && sed 's/^/  /' "$T/scanout.err" >&2
fi

# Prefer present=1 (ramfb configured); still pass on soft-only if hash matches (old QEMU).
if ! printf '%s\n' "$out" | grep -qF "RVFb simplefb OK"; then
  echo "FAIL kernel-fb smoke — simplefb bind/present missing:" >&2
  printf '%s\n' "$out" | grep -i simplefb | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
echo "Kernel-fb smoke: OK ($line; scanout=${scanout:-unavailable})"
exit 0
