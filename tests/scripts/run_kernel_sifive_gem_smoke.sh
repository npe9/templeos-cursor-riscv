#!/bin/bash
# Kernel SiFive GEM smoke: HolyC RVSifiveGem TX + local-loopback RX on -M sifive_u.
# Policy: missing toolchain/QEMU → FAIL (not SKIP); board must stay matrix-green separately.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_sifive_gem_demo.hc"
EXPECT_TX="sifive-gem: tx_ok"
EXPECT_RX="sifive-gem: rx_ok"
EXPECT_PASS="sifive-gem: PASS"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU" "$COMPILER"; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL kernel-sifive-gem smoke — missing $t" >&2; exit 1; }
done

# Snapshot the generated headers so this sifive_u→virt round trip leaves them with
# their original mtime — they sit in AOT include graphs (build/aot/win/kernel.d).
# shellcheck source=tests/scripts/kconfig_snapshot.sh
. "$SCRIPT_DIR/kconfig_snapshot.sh"
kconfig_snapshot_begin

# GEM Yes selected only after sifive_u defconfig (writes RVSifiveGemSelected.HH).
make -C "$ROOT/templeos-riscv" defconfig-sifive_u >/dev/null || {
  echo "FAIL kernel-sifive-gem smoke — defconfig-sifive_u" >&2
  exit 1
}

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-sifive-gem smoke — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-sifive-gem smoke — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"; make -C "$ROOT/templeos-riscv" defconfig-virt >/dev/null; kconfig_snapshot_end' EXIT

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-sifive-gem smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -40 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL kernel-sifive-gem smoke — link error" >&2; exit 1; }

# Onboard cadence_gem; user netdev optional (TX works without peers; RX uses LBL).
out="$($TIMEOUT 30 "$QEMU" -M sifive_u -m 256M -bios none -kernel "$T/kp.elf" -nographic \
        -nic user </dev/null 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -qF "$EXPECT_TX" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_RX" && \
   printf '%s\n' "$out" | grep -qF "$EXPECT_PASS"; then
  echo "Kernel-sifive-gem smoke: OK"
  exit 0
fi
echo "FAIL kernel-sifive-gem smoke — expected lines not found:" >&2
echo "  want: $EXPECT_TX" >&2
echo "  want: $EXPECT_RX" >&2
echo "  want: $EXPECT_PASS" >&2
printf '%s\n' "$out" | grep -v 'import unresolved' | head -20 | sed 's/^/  got: /' >&2
exit 1
