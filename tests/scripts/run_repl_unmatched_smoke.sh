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
# TOS_REPL_DIRTY_DDR=1 pre-fills the heap-control window with 0xff before the image runs.
# QEMU hands out ZEROED RAM, so every gate in this tree has been testing against pristine
# memory that no real board provides -- and Kernel/KBootRV.HC puts `CHeapCtrl *the_heap` at a
# fixed 0x82000000 that nothing ever zeroes. This mode is the model of a board's DDR, and it
# reproduced the exact failure a HiFive Unmatched showed (blob+0x115f20, MAlloc+0x168,
# `ld a0,32(s1)` with s1 = -1) before crt0 started zeroing that window. Run it this way and the
# image must STILL reach the prompt.
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
DIRTY="${TOS_REPL_DIRTY_DDR:-}"
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
#
# *** DO NOT RUN THIS CONCURRENTLY WITH ANY OTHER KERNEL COMPILE. ***
# The lock below only excludes scripts that TAKE the lock. Between defconfig-hifive_unmatched
# and the restoring trap, Kernel/RVAutoConf.HH and Kernel/Drv/*Selected.HH describe an FU740 for
# the WHOLE TREE, so any kernel compile from another process in that window silently inherits
# the SiFive UART at 0x10010000. Observed: kernel-fsshell-smoke store-faulted at 0x10010008 on
# -M virt during a concurrent qemu-integration, and passed on its own. The symptom looks like a
# kernel bug in whatever else was building, not like a problem here, which is what makes it
# expensive.
#
# The real fix is to stop mutating the shared tree at all: compile the variant against a private
# HOLYC_INCLUDE_ROOT copy with its own generated headers, so nothing outside this script can see
# the board's config. Deliberately not done yet — it wants its own change and its own gate, and
# it must not be started while a full qemu-integration is in flight.
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
  echo "FAIL repl-unmatched -- CONFIG_UART_SIFIVE not set" >&2; exit 1; }
# ...and now assert the same thing about the file the HolyC COMPILER actually reads.
# .config is an INPUT to the generator; Kernel/RVAutoConf.HH is what #include pulls in, and the
# two can disagree -- the kconfig snapshot machinery exists precisely to pin those headers.
# Checking only .config is how a REPL image got built against virt's 0x10000000 while this
# script cheerfully reported the base as correct. It cost a debugging cycle: the image ran,
# reached the register pane, and died on `sb a0,0(t0)` with t0=0x10000000, which on this board
# is the PRCI, not a UART.
AUTOCONF="$ROOT/Kernel/RVAutoConf.HH"
hh_base="$(sed -n 's/^#define CONFIG_UART_BASE //p' "$AUTOCONF" | tail -1)"
if [ -z "$hh_base" ] || [ "$((hh_base))" -ne "$((UART_BASE))" ]; then
  echo "FAIL repl-unmatched -- Kernel/RVAutoConf.HH has CONFIG_UART_BASE '$hh_base', expected $UART_BASE" >&2
  echo "  (.config said $got_base; the generated header did not follow it)" >&2
  exit 1
fi
grep -q '^#define CONFIG_UART_SIFIVE 1' "$AUTOCONF" || {
  echo "FAIL repl-unmatched -- Kernel/RVAutoConf.HH does not select the SiFive UART" >&2; exit 1; }
echo "repl-unmatched: RVAutoConf.HH CONFIG_UART_BASE=$hh_base UART_SIFIVE=1 (the header the compiler reads)"
# And the DRIVER selection, which is a third artifact that can disagree with both of the
# above. Kernel/Drv/*Selected.HH is what actually decides whether RVUartPutS is the SiFive
# 32-bit TXDATA writer or the 16550 one -- a board can have the right base in RVAutoConf.HH
# and still compile the wrong driver against it.
for pair in "RVUartSelected.HH:RVUartSifive.HC" "RVSifiveSelected.HH:RVSifiveYes.HC"; do
  hdr="${pair%%:*}"; want="${pair##*:}"
  got="$(sed -n 's/.*#include "\(.*\)".*/\1/p' "$ROOT/Kernel/Drv/$hdr" | tail -1)"
  if [ "$got" != "$want" ]; then
    echo "FAIL repl-unmatched -- Kernel/Drv/$hdr selects '$got', expected '$want'" >&2
    exit 1
  fi
  echo "repl-unmatched: Kernel/Drv/$hdr -> $got"
done

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
# Kernel/KBootRV.HC puts `CHeapCtrl *the_heap` at a FIXED 0x82000000 with heap_next at
# 0x82000400 -- a 1 KiB control block that no section covers and nothing ever zeroes. MAlloc's
# first act is to read the_heap->malloc_free_lst: 0 means "empty free list" and takes the bump
# path, 0xff means a list head of -1 and `f->size` then loads through -1. QEMU hands out zeroed
# RAM so this was invisible for the whole port; the board's DDR held 0xff and the image died at
# MAlloc+0x168 with s1 = -1. crt0 now zeroes it.
HEAPCTL_BASE=0x82000000
HEAPCTL_LEN=0x400
CRT_OBJ="$OUTDIR/crt0-hart1-zero${HEAPCTL_BASE}.o"
# shellcheck disable=SC2086
"$GCC" $CFLAGS -DBOOT_HARTID=1 -DZERO_BASE=${HEAPCTL_BASE} -DZERO_LEN=${HEAPCTL_LEN} \
  -c "$HARNESS/crt0.S" -o "$CRT_OBJ" \
  || { echo "FAIL repl-unmatched -- crt0" >&2; exit 1; }

# --- the HolyC half -----------------------------------------------------------------
# --- the case's own console is virt-hardwired; build a board variant of it --------------
# tests/exec/cases/kernel_repl_exepubs_demo.hc contains:
#     #define MEM_UART 0x10000000
#     U0 UartPutC(I64 ch) { U8 *uart = MEM_UART; *uart = ch; }
# i.e. it overrides the Kconfig-generated MEM_UART with virt's 16550 base and byte-stores to
# it. On an FU740 that address is the PRCI, so every banner the demo prints -- including
# "A2 ExePutS REPL" -- was a byte store into the clock controller. Measured: store access
# fault, mepc=0x806CB344, mtval=0x10000000, resolved through a board-config HOLYC_MAP to
# UartPutC+0x60. It is invisible on -M virt, where that address really is the UART, which is
# why `make repl-cmp-smoke` passes there.
#
# The case is shared and owned elsewhere, so this does not edit it. It builds a variant whose
# UartPutC delegates to the kernel's own selected UART driver -- which is SiFive-correct,
# CRLF-correct, and right on every board -- and ASSERTS the substitution happened, because a
# silent no-op here would put the fault straight back.
CASE_SRC="$SRC"
SRC="$T/kernel_repl_unmatched_demo.hc"
python3 - "$CASE_SRC" "$SRC" <<'PYEOF' || { echo "FAIL repl-unmatched -- case rewrite" >&2; exit 1; }
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
old_def = "#define MEM_UART 0x10000000\n"
old_fn = ("U0 UartPutC(I64 ch)\n"
          "{\n"
          "  U8 *uart = MEM_UART;\n"
          "  *uart = ch;\n"
          "}\n")
missing = [n for n, x in (("MEM_UART define", old_def), ("UartPutC body", old_fn)) if t.count(x) != 1]
if missing:
    sys.exit("expected exactly one of each, missing/duplicated: " + ", ".join(missing))
t = t.replace(old_def, "// MEM_UART override removed for this board (see run_repl_unmatched_smoke.sh)\n")
t = t.replace(old_fn,
              "U0 UartPutC(I64 ch)\n"
              "{\n"
              "  // Through the Kconfig-selected driver, not a hardcoded base: on this board the\n"
              "  // UART is a SiFive one (32-bit TXDATA at +0, FULL in bit 31) and the address\n"
              "  // the case hardcoded is this SoC's clock controller.\n"
              "  U8 e[2];\n"
              "  e[0] = ch;\n"
              "  e[1] = 0;\n"
              "  RVUartPutS(e);\n"
              "}\n")
open(dst, "w").write(t)
print("repl-unmatched: case variant written (UartPutC -> RVUartPutS, MEM_UART override dropped)")
PYEOF
grep -q "RVUartPutS(e);" "$SRC" || { echo "FAIL repl-unmatched -- variant missing the driver call" >&2; exit 1; }
grep -q "0x10000000" "$SRC" && { echo "FAIL repl-unmatched -- variant still contains 0x10000000" >&2; exit 1; }

MAPFILE="$OUTDIR/repl_unmatched.map"
rm -f "$MAPFILE"
if ! HOLYC_MAP="$MAPFILE" HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$SRC" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL repl-unmatched — HolyC compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$SRC" -o /dev/null 2>&1 \
    | tail -25 >"$T/errs.txt"
  cat "$T/errs.txt" >&2
  if grep -q "MEM_VIRTIO\|BDT_VIRTIO" "$T/errs.txt"; then
    cat >&2 <<'EOF'

  ^ This is the KNOWN blocker, not a regression in this script. See
    docs/HIFIVE_UNMATCHED.md §9a. The REPL pulls in Kernel_RV.PRJ, whose virtio block
    driver body is compiled unconditionally while its constants are Kconfig-gated:
      MEM_VIRTIO  kconfig.py mem_aliases emits nothing when CONFIG_VIRTIO_MMIO_BASE is
                  absent (it depends on HAS_VIRTIO_MMIO), though the SIBLING generated
                  header already emits MEM_VIRTIO 0 -- the two disagree.
      BDT_VIRTIO  #ifdef RISCV_VIRT in Kernel/KernelA.HH, as are all six consumers, but
                  DskVirtioRV.HC's body is not, and wrapping a HolyC body in #ifdef turns
                  it into an unresolved import.
    Measured: defining both unconditionally is enough to compile. It is a two-line change
    to SHARED code (KernelA.HH is the stock x86 distro's too, and BDT_TYPES_NUM 6->7 sizes
    arrays there), so it needs its own change and its own 12-board matrix gate.
    Past that lies §9b: GetTSC's `rdtime` is illegal on SiFive cores.
EOF
  fi
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
  # The console's push-back path must be real: a stubbed RVUartSoftEnqueue silently eats the first
  # keystroke after the banner (RVDocVT's ESC[6n probe pushes non-reply bytes back through it).
  grep -q 'RVUartSoftEnqueue' "$T/imports.txt" && { echo "FAIL repl-unmatched -- RVUartSoftEnqueue is an unresolved import (SiFive driver has no soft RX ring)" >&2; exit 1; }
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
# Poison the heap-control window first, so the payload loader that follows wins everywhere
# the two overlap and only the window the image treats as pristine is left dirty.
DIRTY_ARGS=""
if [ -n "$DIRTY" ]; then
  python3 -c "open('$R/ff.bin','wb').write(b'\xff' * 0x10000)"
  DIRTY_ARGS="-device loader,file=$R/ff.bin,addr=0x82000000"
  echo "repl-unmatched: DIRTY DDR -- 0xff at 0x82000000 +0x10000 (the_heap's control block)"
fi
# shellcheck disable=SC2086
feed | $TIMEOUT 75 "$QEMU" -M sifive_u -smp 2 -bios none $DIRTY_ARGS \
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
# The guest's own debugger pane reports faults as "mepc=<hex>", the C harness as
# "TRAP mcause=... mepc=...". Catch both, and name the function -- an address alone is not
# actionable, and the blob carries no ELF symbols (it is objcopy -I binary'd in).
FAULT_ADDRS="$( { grep -oE 'mepc=0*[0-9A-Fa-f]{6,16}' "$R/out.txt" || true; } | sed 's/mepc=//' | sort -u | head -4)"
if [ -n "$FAULT_ADDRS" ]; then
  echo "FAIL repl-unmatched -- the image faulted:" >&2
  { grep -oE 'store access fault|load access fault|illegal instruction|TRAP mcause=[^ ]*' "$R/out.txt" || true; } \
    | sort -u | sed 's/^/  /' >&2
  for fa in $FAULT_ADDRS; do
    printf '  mepc=0x%s' "$fa" >&2
    if [ -f "$MAPFILE" ]; then
      BLOB_VMA=0x80300000 python3 - "$MAPFILE" "$fa" >&2 <<'PYEOF' || true
import bisect, os, sys
mapfile, fa = sys.argv[1], int(sys.argv[2], 16)
blob = int(os.environ.get("BLOB_VMA", "0x80300000"), 16)
rows = []
for ln in open(mapfile):
    p = ln.split()
    if len(p) < 2:
        continue
    try:
        rows.append((int(p[0], 16), p[1]))
    except ValueError:
        pass
rows.sort()
off = fa - blob
if off < 0 or not rows:
    print("  (not inside the blob at 0x%x)" % blob)
    sys.exit(0)
i = bisect.bisect_right([r[0] for r in rows], off) - 1
if i < 0:
    print("  (before the first mapped function)")
else:
    print("  = blob+0x%x = %s+0x%x" % (off, rows[i][1], off - rows[i][0]))
PYEOF
    else
      echo "  (no map: $MAPFILE missing)" >&2
    fi
  done
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  if [ -n "$DIRTY" ]; then
    echo "repl-unmatched: OK (dirty DDR) -- evaluated 2+3 to 5 with 0xff in the heap window"
  else
    echo "repl-unmatched: OK -- FU740 REPL image evaluated 2+3 to 5 over the SiFive UART"
  fi
else
  echo "repl-unmatched: FAIL" >&2
fi
exit "$rc"
