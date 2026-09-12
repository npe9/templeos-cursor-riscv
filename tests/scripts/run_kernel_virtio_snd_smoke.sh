#!/bin/bash
# Kernel virtio-sound smoke: HolyC VirtioSnd.HC PCM TX over legacy virtio-mmio.
# Proves TX progress (tx_ok) with -audiodev none (CI-safe; no host speaker).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_virtio_snd_demo.hc"
EXPECT="virtio-snd: ok"
EXPECT_TX="virtio-snd: tx_ok="

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-virtio-snd smoke — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-virtio-snd smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-virtio-snd smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-virtio-snd smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -40 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-virtio-snd smoke — link error" >&2; exit 1; }

out="$($TIMEOUT 60 "$QEMU" -M virt -m 256M -bios none -kernel "$T/kp.elf" -nographic \
        -audiodev none,id=snd0 -device virtio-sound-device,audiodev=snd0 \
        </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "$EXPECT" && printf '%s\n' "$out" | grep -qE 'virtio-snd: tx_ok=[1-9]'; then
  if ! printf '%s\n' "$out" | grep -qE 'virtio-snd: timing_ms=[0-9]+'; then
    echo "FAIL kernel-virtio-snd smoke — missing wall-clock timing needle:" >&2
    printf '%s\n' "$out" | grep -E 'virtio-snd: timing' | head -5 | sed 's/^/  got: /' >&2
    exit 1
  fi
  if printf '%s\n' "$out" | grep -qE 'virtio-snd: timing FAIL'; then
    echo "FAIL kernel-virtio-snd smoke — timing out of range:" >&2
    printf '%s\n' "$out" | grep -E 'virtio-snd: timing' | head -5 | sed 's/^/  got: /' >&2
    exit 1
  fi
  line="$(printf '%s\n' "$out" | grep -F "$EXPECT_TX" | tail -1)"
  timing="$(printf '%s\n' "$out" | grep -E 'virtio-snd: timing_ms=' | tail -1)"
  echo "Kernel-virtio-snd smoke: OK ($line | $timing)"
  exit 0
fi
echo "FAIL kernel-virtio-snd smoke — expected TX progress:" >&2
echo "  want: $EXPECT and tx_ok>=1" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -20 | sed 's/^/  got: /' >&2
exit 1
