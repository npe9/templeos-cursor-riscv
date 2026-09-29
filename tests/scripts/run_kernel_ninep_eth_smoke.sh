#!/bin/bash
# 9P over raw Ethernet: HolyC NinePEth.HC talks to tools/ninep/eth9p.py through QEMU's socket
# netdev. Proves the third NinePTransport carries a real mount -- version, attach, walk, open,
# read, and a write that lands on the host filesystem.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_ninep_eth_demo.hc"
PORT="${NINEP_ETH_PORT:-9199}"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU" python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL ninep-eth smoke — missing $t" >&2; exit 1; }
done

# shellcheck source=tests/scripts/kconfig_snapshot.sh
. "$SCRIPT_DIR/kconfig_snapshot.sh"
kconfig_snapshot_begin

# GEM Yes + SiFive UART are selected only under the sifive_u defconfig.
make -C "$ROOT/templeos-riscv" defconfig-sifive_u >/dev/null || {
  echo "FAIL ninep-eth smoke — defconfig-sifive_u" >&2; exit 1; }

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL ninep-eth smoke — harness" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL ninep-eth smoke — crt0" >&2; exit 1; }
fi

# Hart 1, and this is the part that cost the most time. On -M sifive_u hart 0 is the E51: no F/D,
# so it cannot execute an image built from Kernel_RV.PRJ, and with a BOOT_HARTID=0 crt0 it is hart
# 0 that runs and faults before a single character reaches the UART -- silence, not a message.
# `-kernel` sets the reset vector for BOTH harts, so a BOOT_HARTID=1 crt0 makes hart 0 halt at the
# gate and hart 1 run. That is exactly how build_kernel_plat.sh builds sifive_u, and why its plat
# smoke passes with plain `-kernel`. The loader form is for images linked at a board address.
# The C half needs the SiFive UART too, and this is the failure that cost the most time here.
# oracle_out.o in $OUTDIR is built with the DEFAULT console: a 16550 at 0x10000000, which is
# virt's UART and sifive_u's PRCI. A full-Kernel_RV.PRJ blob has unresolved imports, the C runtime
# announces them with rt_puts, and that store faults at 0x10000000 -- in a loop, before one
# character reaches the real UART. Output: absolutely nothing, on a case that runs fine on -M virt.
# `-d int` named it in one run: cause 7 store fault, tval 0x10000000. Exactly the board-only class
# docs/UNMATCHED_JTAG.md records. Build a SiFive-flavoured oracle instead of reusing the shared one.
ORACLE1="$OUTDIR/oracle_out-sifive-ninep.o"
if [ ! -f "$ORACLE1" ] || [ "$HARNESS/oracle_out.c" -nt "$ORACLE1" ] || \
   [ "$ROOT/bootstrap/holy_rt.h" -nt "$ORACLE1" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -DHOLY_UART_SIFIVE=1 -DUART_BASE=0x10010000UL -DHOLY_UART_BASE=0x10010000ULL \
    -DHOLY_UART_IRQ=4 -DHOLY_CLINT_MTIMECMP_OFF=0x4008ULL \
    -DHOLY_PLIC_ENABLE_OFF=0x2080 -DHOLY_PLIC_THRESHOLD_OFF=0x201000 \
    -DHOLY_PLIC_CLAIM_OFF=0x201004 \
    -c "$HARNESS/oracle_out.c" -o "$ORACLE1" \
    || { echo "FAIL ninep-eth smoke — sifive oracle" >&2; exit 1; }
fi
CRT1="$OUTDIR/crt0-hart1-ninep.o"
if [ ! -f "$CRT1" ] || [ "$HARNESS/crt0.S" -nt "$CRT1" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -DBOOT_HARTID=1 -c "$HARNESS/crt0.S" -o "$CRT1" \
    || { echo "FAIL ninep-eth smoke — crt0 hart1" >&2; exit 1; }
fi

T="$(mktemp -d)"
SRVPID=""
trap 'rm -rf "$T"; kill $SRVPID 2>/dev/null; make -C "$ROOT/templeos-riscv" defconfig-virt >/dev/null; kconfig_snapshot_end' EXIT

mkdir -p "$T/share"
printf 'hello-over-ethernet' >"$T/share/test.txt"

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL ninep-eth smoke — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" 2>&1 | tail -30 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o kp.elf \
    "$CRT1" "$ORACLE1" blob_in.o ) \
  >/dev/null 2>&1 || { echo "FAIL ninep-eth smoke — link error" >&2; exit 1; }

# Server first: QEMU connects out to it. Listening before QEMU starts removes the race entirely.
python3 "$ROOT/tools/ninep/eth9p.py" --root "$T/share" --mode qemu --port "$PORT" \
  --seconds 45 >"$T/srv.log" 2>&1 &
SRVPID=$!
for i in $(seq 1 50); do
  grep -q 'listening on' "$T/srv.log" 2>/dev/null && break
  sleep 0.1
done
grep -q 'listening on' "$T/srv.log" || { echo "FAIL ninep-eth smoke — server did not listen" >&2; sed 's/^/  /' "$T/srv.log" >&2; exit 1; }

# Exactly the invocation run_kernel_sifive_gem_smoke.sh uses and passes with, with the socket
# backend in place of `-nic user` so there is a real peer on the other end of the GEM.
out="$($TIMEOUT 60 "$QEMU" -M sifive_u -m 256M -bios none -smp 2 -kernel "$T/kp.elf" -nographic \
        -nic socket,connect=127.0.0.1:"$PORT" </dev/null 2>&1 | tr -d '\r')"
wait $SRVPID 2>/dev/null

rc=0
for n in "ninep-eth: connect_ok" "ninep-eth: read_ok data=hello-over-ethernet" "ninep-eth: write_ok"; do
  printf '%s\n' "$out" | grep -qF "$n" || { echo "FAIL ninep-eth smoke — missing: $n" >&2; rc=1; }
done
# The write must have landed on the HOST, not merely been acknowledged on the guest side.
if [ ! -f "$T/share/out.txt" ] || ! grep -qF 'eth9p-wrote-this' "$T/share/out.txt"; then
  echo "FAIL ninep-eth smoke — out.txt did not reach the host share" >&2
  rc=1
fi
if [ "$rc" != 0 ]; then
  echo "--- guest:" >&2; printf '%s\n' "$out" | grep -v 'import unresolved' | tail -20 | sed 's/^/  /' >&2
  echo "--- server:" >&2; tail -12 "$T/srv.log" | sed 's/^/  /' >&2
  exit 1
fi
printf '%s\n' "$out" | grep -E 'ninep-eth: (msize|txns|retries)' | sed 's/^/  /'
echo "ninep-eth smoke: OK"
