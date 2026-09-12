#!/bin/bash
# Real HolyC ExePutS REPL + real DolDoc, presented to this terminal as ANSI.
#
# This is the same image kernel-win-interactive builds — same Adam boot, same CInit,
# same compiler unit, same DolDoc — differing only in the link-time flag unit
# (tests/exec/aot/win_flag_tos.hc), which selects a VT present loop instead of pushing
# pixels at ramfb. The monolithic shortcut does NOT work here: Compiler/RVExePubs.HC
# declares `extern U8 doldoc` for cross-unit resolution, which collides with
# Kernel/RVDoc.HC's real `CDolDocGlbls doldoc` when both land in one translation unit
# and leaves DocInit dereferencing address 0. See tests/scratch/vt_holyc_doldoc_note.md.
#
# Type HolyC at the prompt:  2+3;   "hi\n";   or the dig-down built-ins (help/regs/bt).
# Quit: q  (or Ctrl-A then X)
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLAG_SRC="$ROOT/tests/exec/aot/win_flag_tos.hc"
ELF="$ROOT/build/exec/win_tos.elf"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"

command -v "$QEMU" >/dev/null 2>&1 || { echo "SKIP kernel-tos — missing $QEMU" >&2; exit 0; }

# Geometry lives in the flag unit (the Kernel unit sizes the framebuffer from it, so
# RVWinMgrInit derives exactly these text cols/rows). Match the caller's terminal.
DEF_COLS=80
DEF_ROWS=24
if [ -t 2 ] && command -v tput >/dev/null 2>&1; then
  t_cols="$(tput cols 2>/dev/null || echo '')"
  t_rows="$(tput lines 2>/dev/null || echo '')"
  case "$t_cols" in ''|*[!0-9]*) ;; *) [ "$t_cols" -ge 40 ] && DEF_COLS="$t_cols" ;; esac
  case "$t_rows" in ''|*[!0-9]*) ;; *) [ "$t_rows" -ge 10 ] && DEF_ROWS="$t_rows" ;; esac
fi
COLS="${RV_VT_COLS:-$DEF_COLS}"
ROWS="${RV_VT_ROWS:-$DEF_ROWS}"
# RV_VT_CELLS_MAX (Kernel/RVDocVT.HC) is 8192 cells.
while [ $((COLS * ROWS)) -gt 8192 ]; do
  ROWS=$((ROWS - 1))
  [ "$ROWS" -lt 10 ] && { COLS=80; ROWS=24; break; }
done

# Rewrite the flag unit only when the geometry actually changes — an unconditional
# write would re-trigger the ~30s AOT unit rebuild on every launch.
cur_c="$(sed -n 's/^#define RV_VT_COLS \([0-9]*\).*/\1/p' "$FLAG_SRC")"
cur_r="$(sed -n 's/^#define RV_VT_ROWS \([0-9]*\).*/\1/p' "$FLAG_SRC")"
if [ "$cur_c" != "$COLS" ] || [ "$cur_r" != "$ROWS" ]; then
  sed -e "s/^#define RV_VT_COLS .*/#define RV_VT_COLS $COLS/" \
      -e "s/^#define RV_VT_ROWS .*/#define RV_VT_ROWS $ROWS/" \
      "$FLAG_SRC" > "$FLAG_SRC.tmp" && mv "$FLAG_SRC.tmp" "$FLAG_SRC"
fi

make -C "$ROOT" "$ELF" >&2 || { echo "FAIL kernel-tos — build" >&2; exit 1; }

cat >&2 <<EOF
TempleOS/RISC-V - clean interactive boot at ${COLS}x${ROWS}.
  HolyC:   2+3;   "hi\\n";   I64 i=7; i*6;   F64 f=2.0; Sqrt(f);
  DolDoc:  Cat("A:/Doc/VtDemo.DD");
  Files:   Dir;
  Quit:    q   (or Ctrl-A then X)
EOF
sleep 2
exec "$QEMU" -M virt -m 256M -bios none -kernel "$ELF" -nographic
