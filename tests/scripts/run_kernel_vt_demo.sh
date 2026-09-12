#!/bin/bash
# Build + run the DolDoc VT presenter on YOUR terminal and hold the frame.
#
# This is NOT a gate — it never exits on its own and asserts nothing. It exists because
# the gated smoke (run_kernel_vt_smoke.sh) paints, measures and exits in milliseconds,
# which cannot answer the question docs/DOLDOC_VT.md leaves open: what this looks like
# on a real 80x24 terminal rather than QEMU's pipe.
#
#   make kernel-vt-demo                  # 80x24 ASCII + colour
#   RV_VT_ROWS=25 make kernel-vt-demo    # 80x25 (what RVWinMgrLiteInit hardcodes)
#   RV_VT_UTF8=1 make kernel-vt-demo     # UTF-8 box drawing instead of ASCII fallback
#   RV_VT_COLOR=0 make kernel-vt-demo    # monochrome (no SGR colour runs)
#   RV_VT_COLS=100 RV_VT_ROWS=30 make kernel-vt-demo
#
# Quit with Ctrl-A then X.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_vt_demo.hc"
# The guest cannot ask the terminal how big it is: RVVtInit takes flags, not a query,
# and term.hc's TermQuery lives in the REPL image while the grid lives in the kernel
# image (docs/DOLDOC_VT.md "Image layering"). The host can ask, so do it here — this is
# what makes the frame fit instead of scrolling. RV_VT_ROWS/RV_VT_COLS still override.
DEF_ROWS=24
DEF_COLS=80
if [ -t 2 ] && command -v tput >/dev/null 2>&1; then
  t_rows="$(tput lines 2>/dev/null || echo '')"
  t_cols="$(tput cols 2>/dev/null || echo '')"
  case "$t_rows" in ''|*[!0-9]*) ;; *) [ "$t_rows" -ge 10 ] && DEF_ROWS="$t_rows" ;; esac
  case "$t_cols" in ''|*[!0-9]*) ;; *) [ "$t_cols" -ge 40 ] && DEF_COLS="$t_cols" ;; esac
fi
ROWS="${RV_VT_ROWS:-$DEF_ROWS}"
COLS="${RV_VT_COLS:-$DEF_COLS}"
# RV_VT_CELLS_MAX in Kernel/RVDocVT.HC is 8192 cells; clamp rather than paint nothing.
while [ $((ROWS * COLS)) -gt 8192 ]; do
  ROWS=$((ROWS - 1))
  [ "$ROWS" -lt 10 ] && { COLS=80; ROWS=24; break; }
done
UTF8="${RV_VT_UTF8:-0}"
COLOR="${RV_VT_COLOR:-1}"

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"

for t in "$GCC" "$OBJCOPY" "$LD" "$QEMU"; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-vt demo — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-vt demo — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-vt demo — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Geometry and capability flags are baked in as #defines so the guest needs no runtime
# config channel. RVVtInit takes utf8/color as flags — it does not probe — so these are
# the knobs that decide what the terminal is asked to render.
sed -e "s/^#define RV_VT_DEMO_ROWS .*/#define RV_VT_DEMO_ROWS $ROWS/" \
    -e "s/^#define RV_VT_DEMO_COLS .*/#define RV_VT_DEMO_COLS $COLS/" \
    -e "s/^#define RV_VT_DEMO_UTF8 .*/#define RV_VT_DEMO_UTF8 $UTF8/" \
    -e "s/^#define RV_VT_DEMO_COLOR .*/#define RV_VT_DEMO_COLOR $COLOR/" \
    "$SRC" > "$T/case.hc"
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$T/case.hc" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-vt demo — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$T/case.hc" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o vtdemo.elf \
        "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 \
  || { echo "FAIL kernel-vt demo — link error" >&2; exit 1; }
cp "$T/vtdemo.elf" "$OUTDIR/vtdemo.elf"

cat >&2 <<EOF
Running the DolDoc VT presenter at ${COLS}x${ROWS} (utf8=$UTF8 color=$COLOR).
  * the green column ruler (top) and the bottom border must BOTH be visible
  * the last interior row ($((ROWS - 2))) must be on screen above the border
  * if the ruler scrolled away, the grid is taller than your terminal
Quit: Ctrl-A then X
EOF
sleep 2
exec "$QEMU" -M virt -m 128M -bios none -kernel "$OUTDIR/vtdemo.elf" -nographic
