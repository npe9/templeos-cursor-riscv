#!/bin/bash
# The HolyC REPL, built for the HiFive Unmatched and evaluated under emulation.
#
# This is the eventual point of the whole exercise: hc_repl on an FU740 over serial. It is
# the same guest-compiler REPL as `make repl-cmp` (tests/exec/cases/kernel_repl_exepubs_demo.hc,
# Kernel_RV + Compiler_RV_Body ExePutS loop), with three board-specific changes and nothing else:
#
#   1. the FU740 Kconfig applied, so the HolyC side's CONFIG_UART_BASE is 0x10010000
#   2. the C harness compiled for the SiFive UART layout at that base (-DHOLY_UART_SIFIVE=1),
#      not the 16550 at 0x10000000 that 0x10010000's neighbour PRCI would have swallowed
#   3. linked at 0x80200000 and entered on hart 1 (-DBOOT_HARTID=1), because firmware owns
#      the first 2 MiB of DDR and hart 0 is the S7 (rv64imac, no F/D — it cannot execute
#      this rv64imafdc/lp64d image at all)
#
# It then feeds `2+3;` in and requires `ans=5` out — the REPL COMPILING AND EVALUATING, not
# merely printing a prompt.
#
# Usage: run_repl_unmatched_smoke.sh
# Artifacts: build/exec/repl_unmatched.elf / .bin
#
# NEGATIVE CONTROL: TOS_REPL_BREAK=dflt16550 links the same blob against the default 16550
# harness. The REPL's own output goes through the C runtime's HOLY_RT_PUTC, so unlike the
# plat demo it should go completely silent — which is the difference between this board's C
# harness mattering a little and mattering entirely.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOS="$ROOT/templeos-riscv"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_repl_exepubs_demo.hc"
GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
READELF="${RISCV_READELF:-riscv64-unknown-elf-readelf}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"
BREAK="${TOS_REPL_BREAK:-}"
ENTRY=0x80200000
UART_BASE=0x10010000
UART_IRQ=39

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL repl-unmatched — missing $t" >&2; exit 1; }
done
make -C "$ROOT" holyc-riscv >/dev/null 2>&1 || { echo "FAIL repl-unmatched — holyc-riscv" >&2; exit 1; }
mkdir -p "$OUTDIR"

# --- apply the FU740 Kconfig, and put back exactly what was there -------------------
# Same discipline as build_kernel_plat.sh: this rewrites global generated headers, so it
# is serialised against concurrent plat builds and restores content AND mtime.
LOCKDIR="$ROOT/build/.kernel-plat.lock"
mkdir -p "$ROOT/build"
while ! mkdir "$LOCKDIR" 2>/dev/null; do sleep 0.1; done
SAVE_CFG="$(mktemp)"
SAVE_HAD_CFG=0
[ -f "$TOS/.config" ] && { cp "$TOS/.config" "$SAVE_CFG"; SAVE_HAD_CFG=1; }
# shellcheck source=tests/scripts/kconfig_snapshot.sh
. "$SCRIPT_DIR/kconfig_snapshot.sh"
kconfig_snapshot_begin
T="$(mktemp -d)"
restore_all() {
  if [ "$SAVE_HAD_CFG" -eq 1 ]; then
    cmp -s "$SAVE_CFG" "$TOS/.config" || cp "$SAVE_CFG" "$TOS/.config"
    make -C "$TOS" syncconfig >/dev/null 2>&1
  else
    make -C "$TOS" defconfig-virt >/dev/null 2>&1
  fi
  kconfig_snapshot_end
  rm -f "$SAVE_CFG"
  rm -rf "$T"
  rmdir "$LOCKDIR" 2>/dev/null || true
}
trap restore_all EXIT

make -C "$TOS" defconfig-hifive_unmatched >/dev/null || {
  echo "FAIL repl-unmatched — defconfig-hifive_unmatched" >&2; exit 1; }
# The applied config is what the HolyC half compiles against; assert the one value the
# whole board port turns on rather than assuming the defconfig did its job.
got_base="$(sed -n 's/^CONFIG_UART_BASE=//p' "$TOS/.config" | tail -1)"
if [ "$((got_base))" -ne "$((UART_BASE))" ]; then
  echo "FAIL repl-unmatched — CONFIG_UART_BASE is $got_base, expected $UART_BASE" >&2
  exit 1
fi
grep -q '^CONFIG_UART_SIFIVE=y' "$TOS/.config" || {
  echo "FAIL repl-unmatched — CONFIG_UART_SIFIVE not set" >&2; exit 1; }

# --- the C half, for the SiFive UART at the board's base ----------------------------
# Distinct object paths: the shared oracle_out.o / crt0.o are mtime-cached and would
# otherwise be served to (or taken from) a virt build with the wrong flags baked in.
ORACLE_DEFS="-DHOLY_UART_SIFIVE=1 -DUART_BASE=${UART_BASE}UL -DHOLY_UART_BASE=${UART_BASE}ULL -DHOLY_UART_IRQ=${UART_IRQ}"
ORACLE_OBJ="$OUTDIR/oracle_out-sfu-${UART_BASE}-irq${UART_IRQ}.o"
CRT_OBJ="$OUTDIR/crt0-hart1.o"
CFLAGS="-march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin"
LINK_LD="$HARNESS/link_exepubs_hifive_unmatched.ld"

if [ "$BREAK" = dflt16550 ]; then
  ORACLE_DEFS=""
  ORACLE_OBJ="$T/oracle_dflt.o"
  echo "repl-unmatched: NEGATIVE CONTROL — default 16550 harness at 0x10000000 (the PRCI)"
fi

# shellcheck disable=SC2086
"$GCC" $CFLAGS $ORACLE_DEFS -c "$HARNESS/oracle_out.c" -o "$ORACLE_OBJ" \
  || { echo "FAIL repl-unmatched — harness compile" >&2; exit 1; }
# shellcheck disable=SC2086
"$GCC" $CFLAGS -DBOOT_HARTID=1 -c "$HARNESS/crt0.S" -o "$CRT_OBJ" \
  || { echo "FAIL repl-unmatched — crt0" >&2; exit 1; }

# --- the HolyC half -----------------------------------------------------------------
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL repl-unmatched — HolyC compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 | tail -25 >&2
  exit 1
fi

# "It compiles" is not "it works": an asm{} block the assembler cannot handle is dropped
# SILENTLY, and a symbol the image calls but does not define is stubbed to return 0. Both
# have to be looked at, not assumed.
HOLYC_ASM_SKIPS=1 HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o /dev/null 2>"$T/skips.txt" >/dev/null || true
if [ -s "$T/skips.txt" ] && grep -qi 'skip' "$T/skips.txt"; then
  echo "repl-unmatched: dropped asm constructs (HOLYC_ASM_SKIPS):"
  sed 's/^/  /' "$T/skips.txt" | head -10
fi
if [ -f "$ROOT/tools/blob_imports.py" ]; then
  python3 "$ROOT/tools/blob_imports.py" "$T/blob.bin" >"$T/imports.txt" 2>&1 || true
  n_imp="$(grep -c . "$T/imports.txt" 2>/dev/null || echo 0)"
  echo "repl-unmatched: blob_imports.py reports $n_imp line(s) (C-runtime-resolved symbols)"
fi

( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
    --rename-section .data=.data,alloc,load,code,contents,readonly \
    blob.bin blob_in.o && \
  "$LD" -T "$LINK_LD" -nostdlib --no-warn-mismatch \
    -o repl.elf "$CRT_OBJ" "$ORACLE_OBJ" blob_in.o ) >"$T/link.log" 2>&1 \
  || { echo "FAIL repl-unmatched — link error" >&2; tail -10 "$T/link.log" >&2; exit 1; }

cp "$T/repl.elf" "$OUTDIR/repl_unmatched.elf"
"$OBJCOPY" -O binary "$OUTDIR/repl_unmatched.elf" "$OUTDIR/repl_unmatched.bin" 2>/dev/null || true

# The link address is the whole reason this file exists; assert it structurally. The image
# is position-independent (see docs/HIFIVE_UNMATCHED.md §2), so output cannot tell a right
# load address from a wrong one and only the ELF can.
got_entry="$("$READELF" -h "$OUTDIR/repl_unmatched.elf" | sed -n 's/.*Entry point address: *//p')"
if [ "$((got_entry))" -ne "$((ENTRY))" ]; then
  echo "FAIL repl-unmatched — entry $got_entry != $ENTRY" >&2; exit 1
fi
echo "repl-unmatched: $OUTDIR/repl_unmatched.elf entry $got_entry ($(wc -c <"$OUTDIR/repl_unmatched.bin") bytes flat)"

# Put the tree's Kconfig back before running anything, so a QEMU hang cannot leave the
# checkout on a foreign board's config.
restore_all
trap - EXIT

# --- run it -------------------------------------------------------------------------
# The real board image at its real address, on hart 1. -kernel cannot be used: on sifive_u
# it enters at DRAM base, so a 0x80200000 image would load and never be entered.
R="$(mktemp -d)"
trap 'rm -rf "$R"' EXIT
# Pace the input: the REPL's line editor drops characters on unpaced input, and stdin must
# not arrive while CInit is still running.
feed() {
  perl -e '
    $|=1;
    select(undef,undef,undef,6);
    for my $x ("2+3;", "q") { print $x,"\n"; select(undef,undef,undef,1.2); }
    select(undef,undef,undef,3);
  '
}
feed | $TIMEOUT 75 "$QEMU" -M sifive_u -smp 2 -bios none \
  -device "loader,file=$OUTDIR/repl_unmatched.bin,addr=$ENTRY" \
  -device "loader,addr=$ENTRY,cpu-num=1" -nographic >"$R/out.log" 2>&1
tr -d '\r' <"$R/out.log" >"$R/out.txt"

echo "repl-unmatched: UART, last 25 lines:"
tail -25 "$R/out.txt" | sed 's/^/  uart: /'

rc=0
# "prints a prompt" is not "works". ans=5 is the REPL having COMPILED and EVALUATED 2+3.
for n in "A2 ExePutS REPL" "ans=5"; do
  if ! grep -qF "$n" "$R/out.txt"; then
    echo "FAIL repl-unmatched — missing: $n" >&2
    rc=1
  fi
done
if grep -qF "TRAP mcause" "$R/out.txt"; then
  echo "FAIL repl-unmatched — the image trapped:" >&2
  grep -F "TRAP" "$R/out.txt" | head -4 | sed 's/^/  /' >&2
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  echo "repl-unmatched: OK — FU740 REPL image evaluated 2+3 to 5 over the SiFive UART"
else
  echo "repl-unmatched: FAIL" >&2
fi
exit "$rc"
