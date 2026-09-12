#!/bin/bash
# Interactive TempleOS DolDoc/WinMgr REPL presented to YOUR terminal as ANSI.
#
# Unlike run_kernel_vt_demo.sh (which paints a static frame and holds), this takes
# input: keystrokes go to RVWinTermPutChar, so they echo into the focused window's
# DolDoc body and Enter runs RVWinSerialDispatch with output captured into that same
# body. RVVtPresent is the only writer on the wire, so what you see is the grid.
#
#   make kernel-vt-repl                   # 80x24 ASCII + colour
#   RV_VT_ROWS=25 make kernel-vt-repl
#   RV_VT_UTF8=1 make kernel-vt-repl
#
# Commands: help, regs, bt, md ADDR [N], mw ADDR VAL, max, tileh, tilev, user,
# fault, crash, q. Type `q` to quit (or Ctrl-A then X).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC="$ROOT/tests/exec/cases/kernel_vt_repl.hc"
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
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-vt repl — missing $t" >&2; exit 0; }
done

mkdir -p "$OUTDIR"
if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
   [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ]; then
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-vt repl — harness compile" >&2; exit 1; }
  "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
    -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-vt repl — crt0" >&2; exit 1; }
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Geometry and capability flags are baked in as #defines so the guest needs no runtime
# config channel. RVVtInit takes utf8/color as flags — it does not probe — so these are
# the knobs that decide what the terminal is asked to render.
sed -e "s/^#define RV_VT_REPL_ROWS .*/#define RV_VT_REPL_ROWS $ROWS/" \
    -e "s/^#define RV_VT_REPL_COLS .*/#define RV_VT_REPL_COLS $COLS/" \
    -e "s/^#define RV_VT_REPL_UTF8 .*/#define RV_VT_REPL_UTF8 $UTF8/" \
    -e "s/^#define RV_VT_REPL_COLOR .*/#define RV_VT_REPL_COLOR $COLOR/" \
    "$SRC" > "$T/case.hc"
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$T/case.hc" -o "$T/blob.bin" >/dev/null 2>&1; then
  echo "FAIL kernel-vt repl — compile error" >&2
  HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1 "$COMPILER" "$T/case.hc" -o /dev/null 2>&1 | tail -20 >&2
  exit 1
fi
( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv blob.bin blob_in.o && \
  "$LD" -T "$HARNESS/link_exec.ld" -nostdlib --no-warn-mismatch -o vtrepl.elf \
        "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) >/dev/null 2>&1 \
  || { echo "FAIL kernel-vt repl — link error" >&2; exit 1; }
cp "$T/vtrepl.elf" "$OUTDIR/vtrepl.elf"

cat >&2 <<EOF
Interactive DolDoc REPL — ${COLS}x${ROWS} (utf8=$UTF8 color=$COLOR), matched to this terminal.
  This IS interactive: there is a block cursor after the "> " prompt.
  Type a command and press Enter:  help   regs   bt   md ADDR   q
  Commands come from RVWinSerialDispatch; this image has no HolyC eval wired.
  Quit: type q  (or Ctrl-A then X)
EOF
sleep 2
exec "$QEMU" -M virt -m 128M -bios none -kernel "$OUTDIR/vtrepl.elf" -nographic
