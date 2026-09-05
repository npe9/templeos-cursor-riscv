#!/bin/bash
# Interactive WinMgr: build win_i.elf / win_hold.elf, headless UART proof, or cocoa hold.
#
# Modes (env):
#   RVWIN_HOLD=0|1     — which ELF (default 0 → win_i.elf; 1 → win_hold.elf)
#   RVWIN_RUN=0|1      — run QEMU after build (default 1)
#   RVWIN_BUILD_ONLY=1 — link ELF only; no QEMU (Makefile ELF rules)
#   RVWIN_SKIP_BUILD=1 — reuse existing ELF and launch (kernel-win-run hot path)
#   RVWIN_SKIP_AOT=1   — Makefile already produced RVWIN_BLOB; only objcopy+ld
#   RVWIN_BLOB=path    — pre-linked HolyC blob (incremental AOT)
#   RVWIN_OUT=path     — override output ELF path
#   RVWIN_DISPLAY=…   — none | cocoa | sdl | auto (hold path)
#
# CI-safe default: -display none + hash/UART expects (no human staring at cocoa).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$ROOT/tests/exec/harness"
OUTDIR="$ROOT/build/exec"
COMPILER="$ROOT/holyc-riscv"
SRC_I="$ROOT/tests/exec/cases/kernel_win_interactive.hc"
SRC_HOLD="$ROOT/tests/exec/cases/kernel_win_hold.hc"
EXPECT_HASH_PREFIX="RVWinMgr interactive hash="
EXPECT_DONE_PREFIX="RVWinMgr interactive DONE"
EXPECT_INPUT="input_ok=1"
EXPECT_PUT="put=1"
EXPECT_MOUNT="RVWinMgr interactive: mount ok"
EXPECT_SERIAL="RVWinSerial ready"
EXPECT_EXEPUBS="ExePutS REPL"
EXPECT_PROBE="ExePutS probe ans=2"
EXPECT_TERM_ANS="ans=7"
EXPECT_TERM_CMDS="Term ExePutS cmds="
EXPECT_ADAM_CMDS="Adam ExePutS cmds="
EXPECT_HOME_SCROLL="HOME scrolls="
EXPECT_HOME_DOC="RVDoc HOME entries="
EXPECT_MOVE="interactive move"
EXPECT_MENU="interactive menu hits="
EXPECT_LAYOUT="interactive layout ops="
EXPECT_SCROLL="interactive ctrl-scroll"
EXPECT_CLOSE="interactive close term"
EXPECT_TASK_BIND="interactive task binds="
EXPECT_MSG_KEYS="interactive msg keys="
EXPECT_TERM_LIVE="interactive term live_msg"
EXPECT_DOC_WRITE="RVDoc Write ok"
EXPECT_MENU_FILE="RVMenuFile n="
EXPECT_OPEN_LINK="RVDoc OpenLink"
EXPECT_FORM_LEX="RVDoc FormLex"
EXPECT_DOC_BIN="RVDoc bin hits="
EXPECT_DEMO_DOC="RVDoc DemoInPage entries="
EXPECT_DOC_SPRITE="RVDoc DocSprite paints="
EXPECT_FILEMGR_DOC="RVDoc FileMgr"
EXPECT_FILEMGR_OPEN="RVFileMgr open idx="
EXPECT_CTRL_ALT="interactive ctrl_alt hits="
EXPECT_HOME_LIVE="interactive home live_msg"
EXPECT_USER_SPAWN="interactive user spawn"
EXPECT_USER_CMDS="interactive user cmds="
EXPECT_USER_KILL="interactive user kill"
EXPECT_POPUP_JOBRES="interactive popup JobRes sys_spawns="
EXPECT_POPUP_PRINT="interactive PopUpPrint sys_spawns="

GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"
LD="${RISCV_LD:-riscv64-unknown-elf-ld}"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

HOLD="${RVWIN_HOLD:-0}"
RUN_QEMU="${RVWIN_RUN:-1}"
BUILD_ONLY="${RVWIN_BUILD_ONLY:-0}"
SKIP_BUILD="${RVWIN_SKIP_BUILD:-0}"
SKIP_AOT="${RVWIN_SKIP_AOT:-0}"
PREBUILT_BLOB="${RVWIN_BLOB:-}"
# kernel-win-run sets RVWIN_HOLD=1 RVWIN_DISPLAY=auto (→ cocoa on Darwin, sdl else)
DISPLAY_KIND="${RVWIN_DISPLAY:-none}"

if [ "$HOLD" = "1" ]; then
  COMPILE_SRC="$SRC_HOLD"
  DEFAULT_ELF="$OUTDIR/win_hold.elf"
else
  COMPILE_SRC="$SRC_I"
  DEFAULT_ELF="$OUTDIR/win_i.elf"
fi
ELF="${RVWIN_OUT:-$DEFAULT_ELF}"

launch_hold_qemu() {
  if [ "$DISPLAY_KIND" = "cocoa" ] || [ "$DISPLAY_KIND" = "auto" ]; then
    case "$(uname -s)" in
      Darwin) DISPLAY_KIND=cocoa ;;
      *) DISPLAY_KIND=sdl ;;
    esac
  fi
  echo "Kernel-win-interactive: using $ELF"
  echo "Launching QEMU display=$DISPLAY_KIND (Tab/click/type; ESC quits)…"
  echo "Serial+monitor on stdio (-serial mon:stdio); Ctrl-A then C for QEMU monitor."
  exec "$QEMU" -M virt -m 256M -bios none -kernel "$ELF" \
    -device ramfb -serial mon:stdio \
    -device virtio-keyboard-device -device virtio-tablet-device \
    -display "$DISPLAY_KIND"
}

if [ "$SKIP_BUILD" = "1" ]; then
  [ -f "$ELF" ] || { echo "FAIL kernel-win-interactive — no $ELF (build first)" >&2; exit 1; }
  echo "Kernel-win-interactive: reused $ELF (skip AOT)" >&2
else
  for t in "$GCC" "$OBJCOPY" "$LD"; do
    command -v "$t" >/dev/null 2>&1 || { echo "SKIP kernel-win-interactive — missing $t" >&2; exit 0; }
  done

  mkdir -p "$OUTDIR"
  if [ ! -f "$OUTDIR/crt0.o" ] || [ ! -f "$OUTDIR/oracle_out.o" ] || \
     [ "$HARNESS/crt0.S" -nt "$OUTDIR/crt0.o" ] || [ "$HARNESS/oracle_out.c" -nt "$OUTDIR/oracle_out.o" ] || \
     [ "$ROOT/bootstrap/holy_rt.h" -nt "$OUTDIR/oracle_out.o" ]; then
    "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
      -c "$HARNESS/oracle_out.c" -o "$OUTDIR/oracle_out.o" || { echo "FAIL kernel-win-interactive — harness compile" >&2; exit 1; }
    "$GCC" -march=rv64imafdc -mabi=lp64d -mcmodel=medany -O2 -g -nostdlib -ffreestanding -fno-builtin \
      -c "$HARNESS/crt0.S" -o "$OUTDIR/crt0.o" || { echo "FAIL kernel-win-interactive — crt0" >&2; exit 1; }
  fi

  T="$(mktemp -d)"
  trap 'rm -rf "$T"' EXIT

  if [ "$SKIP_AOT" = "1" ]; then
    [ -n "$PREBUILT_BLOB" ] && [ -f "$PREBUILT_BLOB" ] || {
      echo "FAIL kernel-win-interactive — RVWIN_SKIP_AOT needs RVWIN_BLOB" >&2
      exit 1
    }
    echo "Kernel-win-interactive: linking prebuilt blob → $(basename "$ELF")…" >&2
    cp "$PREBUILT_BLOB" "$T/blob.bin"
  else
    # Legacy monolithic AOT (fallback when Makefile incremental path not used).
    echo "Kernel-win-interactive: AOT compiling Kernel+Compiler_RV → blob (often ~10s)…" >&2
    if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$COMPILE_SRC" -o "$T/blob.bin" >/dev/null; then
      echo "FAIL kernel-win-interactive — compile error" >&2
      HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$COMPILE_SRC" -o "$T/blob.bin" >&2 || true
      exit 1
    fi
    echo "Kernel-win-interactive: AOT ok — linking $(basename "$ELF")…" >&2
  fi
  # Kernel+Compiler_RV blob needs exepubs link (stack @ 0x87F00000, exec blob section).
  ( cd "$T" && "$OBJCOPY" -I binary -O elf64-littleriscv \
      --rename-section .data=.data,alloc,load,code,contents,readonly \
      blob.bin blob_in.o && \
    "$LD" -T "$HARNESS/link_exepubs.ld" -nostdlib --no-warn-mismatch -o out.elf \
      "$OUTDIR/crt0.o" "$OUTDIR/oracle_out.o" blob_in.o ) \
    >/dev/null 2>&1 || { echo "FAIL kernel-win-interactive — link error" >&2; exit 1; }

  cp "$T/out.elf" "$ELF"
  # Compat alias: serial smoke historically used win_serial.elf (same HOLD image).
  if [ "$HOLD" = "1" ]; then
    case "$(basename "$ELF")" in
      win_hold.elf|win_serial.elf) cp "$ELF" "$OUTDIR/win_serial.elf" ;;
    esac
  fi
fi

if [ "$BUILD_ONLY" = "1" ]; then
  echo "Kernel-win-interactive: built $ELF (RVWIN_BUILD_ONLY=1)"
  exit 0
fi

if [ "$HOLD" = "1" ]; then
  launch_hold_qemu
fi

# Headless proof (default / CI)
command -v "$QEMU" >/dev/null 2>&1 || { echo "SKIP kernel-win-interactive — missing $QEMU" >&2; exit 0; }

if [ "$RUN_QEMU" != "1" ]; then
  echo "Kernel-win-interactive: built $ELF (RVWIN_RUN=0 — skip QEMU)"
  echo "Run:"
  echo "  qemu-system-riscv64 -M virt -m 256M -bios none -kernel $ELF -device ramfb -serial mon:stdio -device virtio-keyboard-device -device virtio-tablet-device -display cocoa"
  exit 0
fi

# Headless CI keeps plain -serial stdio for UART capture.
QEMU_BASE=( -M virt -m 256M -bios none -kernel "$ELF"
  -device ramfb -serial stdio
  -device virtio-keyboard-device -device virtio-tablet-device )

# LC_ALL=C: DocLite/ST_ERR UART can emit non-UTF8 bytes; macOS tr otherwise
# exits mid-stream (Illegal byte sequence) → SIGPIPE guest before hash/DONE.
out="$($TIMEOUT 90 "$QEMU" "${QEMU_BASE[@]}" -display none </dev/null 2>&1 | LC_ALL=C tr -d '\r')"

if ! printf '%s\n' "$out" | grep -qF "$EXPECT_HASH_PREFIX"; then
  echo "FAIL kernel-win-interactive — no hash line:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
  exit 1
fi
line="$(printf '%s\n' "$out" | grep -F "$EXPECT_HASH_PREFIX" | tail -1)"
if ! printf '%s\n' "$line" | grep -qF "$EXPECT_PUT"; then
  echo "FAIL kernel-win-interactive — DocPut missing:" >&2
  echo "  got: $line" >&2
  exit 1
fi
hash="$(printf '%s\n' "$line" | sed -n 's/.*hash=\(0x[0-9A-Fa-f]\{1,8\}\).*/\1/p')"
if [ -z "$hash" ] || [ "$hash" = "0x00000000" ]; then
  echo "FAIL kernel-win-interactive — bad hash: $line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_DONE_PREFIX"; then
  echo "FAIL kernel-win-interactive — no DONE line (hung in VirtioInput/pump?):" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | tail -30 | sed 's/^/  got: /' >&2
  exit 1
fi
done_line="$(printf '%s\n' "$out" | grep -F "$EXPECT_DONE_PREFIX" | tail -1)"
if ! printf '%s\n' "$done_line" | grep -qF "$EXPECT_INPUT"; then
  echo "FAIL kernel-win-interactive — virtio-input not ready:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_MOUNT"; then
  echo "FAIL kernel-win-interactive — no Mount/RedSea (mount ok):" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -E 'mount|Mount|kernel ok|FAIL' | head -10 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_PROBE"; then
  echo "FAIL kernel-win-interactive — no ExePutS probe ans=2:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -E 'ExePutS|CInit|FAIL' | head -10 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SERIAL"; then
  echo "FAIL kernel-win-interactive — no UART serial TTY banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -25 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_EXEPUBS"; then
  echo "FAIL kernel-win-interactive — serial not ExePutS HolyC REPL:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F RVWinSerial | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_TERM_ANS"; then
  echo "FAIL kernel-win-interactive — Term ExePutS missing ans=7 (3+4;):" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -E 'ans=|Term ExePutS|FAIL' | head -10 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_TERM_CMDS"; then
  echo "FAIL kernel-win-interactive — no Term ExePutS cmds banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F Term | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'term_cmds=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE term_cmds not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_ADAM_CMDS"; then
  echo "FAIL kernel-win-interactive — no Adam ExePutS cmds banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F Adam | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'adam_cmds=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE adam_cmds not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_HOME_SCROLL"; then
  echo "FAIL kernel-win-interactive — no HOME scrolls banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F HOME | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'home_scrolls=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE home_scrolls not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_HOME_DOC"; then
  echo "FAIL kernel-win-interactive — no RVDoc HOME entries banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F RVDoc | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'home_link_hits=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE home_link_hits not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'home_tree_toggles=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE home_tree_toggles not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'home_form_hits=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE home_form_hits not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "RVDoc Term entries="; then
  echo "FAIL kernel-win-interactive — no RVDoc Term entries banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F RVDoc | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "RVDoc Adam entries="; then
  echo "FAIL kernel-win-interactive — no RVDoc Adam entries banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F RVDoc | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_MOVE"; then
  echo "FAIL kernel-win-interactive — no title-bar move banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F move | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'move_drags=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE move_drags not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_MENU"; then
  echo "FAIL kernel-win-interactive — no MENU stub banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F menu | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVPopUp stock JobRes res=[1-9]'; then
  echo "FAIL kernel-win-interactive — stock PopUp JobRes not seen:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -FiE 'PopUp|popup|JobRes' | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF 'interactive PopUpPrint done'; then
  echo "FAIL kernel-win-interactive — PopUpPrint done not seen:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -Fi PopUpPrint | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'menu_hits=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE menu_hits not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_LAYOUT"; then
  echo "FAIL kernel-win-interactive — no WinMax/Tile layout banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F layout | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'layout_ops=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE layout_ops not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_SCROLL"; then
  echo "FAIL kernel-win-interactive — no Ctrl-scroll banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F scroll | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'scroll_drags=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE scroll_drags not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_CLOSE"; then
  echo "FAIL kernel-win-interactive — no [X] close banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F close | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'close_hits=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE close_hits not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_TASK_BIND"; then
  echo "FAIL kernel-win-interactive — no P1 task bind banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F task | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'task_binds=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE task_binds not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_MSG_KEYS"; then
  echo "FAIL kernel-win-interactive — no P1 msg keys banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F msg | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_TERM_LIVE"; then
  echo "FAIL kernel-win-interactive — no Term live_msg banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F live_msg | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_DOC_WRITE"; then
  echo "FAIL kernel-win-interactive — no DocWrite ok banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F RVDoc | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_OPEN_LINK"; then
  echo "FAIL kernel-win-interactive — no RVDoc OpenLink banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F RVDoc | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_FORM_LEX"; then
  echo "FAIL kernel-win-interactive — no RVDoc FormLex banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F FormLex | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_DOC_BIN"; then
  echo "FAIL kernel-win-interactive — no RVDoc bin hits banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F bin | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_DEMO_DOC"; then
  echo "FAIL kernel-win-interactive — no RVDoc DemoInPage banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F DemoInPage | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVDoc DemoInPage entries=[1-9][0-9]* html=[1-9]'; then
  echo "FAIL kernel-win-interactive — DemoInPage html hits not >=1:" >&2
  printf '%s\n' "$out" | grep -F DemoInPage | head -3 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVDoc DemoInPage entries=[1-9][0-9]*.*hx=1.*song=1.*hc=1'; then
  echo "FAIL kernel-win-interactive — DemoInPage missing HX/SO/HC hits:" >&2
  printf '%s\n' "$out" | grep -F DemoInPage | head -3 | sed 's/^/  got: /' >&2
  exit 1
fi
# DocInit_RV HashFind lex (doldoc.hash) — required for DemoInPage.
if ! printf '%s\n' "$out" | grep -qE 'RVDoc DemoInPage entries=[1-9][0-9]*.*lex=[1-9]'; then
  echo "FAIL kernel-win-interactive — DemoInPage DocInit_RV hash lex not >=1:" >&2
  printf '%s\n' "$out" | grep -F DemoInPage | head -3 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_DOC_SPRITE"; then
  echo "FAIL kernel-win-interactive — no RVDoc DocSprite paints banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F DocSprite | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVDoc DocSprite paints=[1-9]'; then
  echo "FAIL kernel-win-interactive — DocSprite paints not >=1:" >&2
  printf '%s\n' "$out" | grep -F DocSprite | head -3 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_FILEMGR_DOC"; then
  echo "FAIL kernel-win-interactive — no RVDoc FileMgr banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F FileMgr | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
# Full FilesFind/DirFileDoc shape (ffind=1) — soft-skip no longer accepted.
if ! printf '%s\n' "$out" | grep -qE 'RVDoc FileMgr entries=[1-9].*trees=[1-9].*mus=[1-9].*user=[1-9].*ffind=1'; then
  echo "FAIL kernel-win-interactive — FileMgr FilesFind/DirFileDoc shape mismatch:" >&2
  printf '%s\n' "$out" | grep -F FileMgr | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
# Stock FileMgr CRVWin open (beyond probe-only).
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_FILEMGR_OPEN"; then
  echo "FAIL kernel-win-interactive — no RVFileMgr open banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F FileMgr | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVFileMgr open idx=[0-9].*ffind=1'; then
  echo "FAIL kernel-win-interactive — FileMgr open ffind!=1:" >&2
  printf '%s\n' "$out" | grep -F RVFileMgr | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
# MenuActivate About must exercise stock Job PopUp (extra spawn beyond pre-probe).
if ! printf '%s\n' "$out" | grep -qE 'interactive popup hits=[1-9].*spawn=[2-9]'; then
  echo "FAIL kernel-win-interactive — MenuActivate About soft-skipped (spawn too low):" >&2
  printf '%s\n' "$out" | grep -Fi popup | head -8 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_CTRL_ALT"; then
  echo "FAIL kernel-win-interactive — no Ctrl-Alt hits banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -Fi ctrl | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'ctrl_alt=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE ctrl_alt not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_HOME_LIVE"; then
  echo "FAIL kernel-win-interactive — no HOME live_msg banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F live_msg | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_MENU_FILE"; then
  echo "FAIL kernel-win-interactive — no RVMenuFile banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F RVMenu | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'msg_keys=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE msg_keys not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'msg_consumed=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE msg_consumed not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_USER_SPAWN"; then
  echo "FAIL kernel-win-interactive — no P1 user spawn banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F user | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'user_spawns=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE user_spawns not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_USER_CMDS"; then
  echo "FAIL kernel-win-interactive — no P1 user cmds banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F user | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'user_cmds=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE user_cmds not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -qF "$EXPECT_USER_KILL"; then
  echo "FAIL kernel-win-interactive — no P1 user kill banner:" >&2
  printf '%s\n' "$out" | grep -v 'import unresolved' | grep -F kill | head -5 | sed 's/^/  got: /' >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'zbuf_updates=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE zbuf_updates not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi
if ! printf '%s\n' "$done_line" | grep -qE 'zbuf_hi=[1-9]'; then
  echo "FAIL kernel-win-interactive — DONE zbuf_hi not >=1:" >&2
  echo "  got: $done_line" >&2
  exit 1
fi

echo "Kernel-win-interactive: OK ($line)"
echo "  $done_line"
echo "  mount: $EXPECT_MOUNT"
echo "  serial: $EXPECT_SERIAL ($EXPECT_EXEPUBS; $EXPECT_PROBE)"
echo "  term: $EXPECT_TERM_ANS ($EXPECT_TERM_CMDS)"
echo "  adam/home/move: $EXPECT_ADAM_CMDS / $EXPECT_HOME_SCROLL / $EXPECT_MOVE"
echo "  p0 chrome: $EXPECT_MENU / $EXPECT_LAYOUT / $EXPECT_SCROLL / $EXPECT_CLOSE"
echo "  p1 task: $EXPECT_TASK_BIND / $EXPECT_MSG_KEYS / $EXPECT_USER_SPAWN / $EXPECT_USER_KILL"

# QMP virtio-input proof on HOLD image (ESC must quit with events>0; serial still works).
HOLD_ELF="$OUTDIR/win_hold.elf"
if [ -f "$HOLD_ELF" ] && command -v python3 >/dev/null 2>&1; then
  SOCK="$(mktemp -u /tmp/rvwin_qmp.XXXXXX)"
  UART="$(mktemp /tmp/rvwin_uart.XXXXXX)"
  rm -f "$SOCK"
  "$QEMU" -M virt -m 256M -bios none -kernel "$HOLD_ELF" \
    -device ramfb -serial "file:$UART" \
    -device virtio-keyboard-device -device virtio-tablet-device \
    -display none -qmp "unix:$SOCK,server,nowait" >/dev/null 2>&1 &
  QPID=$!
  qmp_ok=0
  for _ in $(seq 1 80); do
    if grep -qF "$EXPECT_SERIAL" "$UART" 2>/dev/null; then
      qmp_ok=1
      break
    fi
    sleep 0.25
  done
  if [ "$qmp_ok" = 1 ]; then
    python3 - "$SOCK" <<'PY'
import json, socket, sys, time
sock = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for _ in range(50):
  try:
    s.connect(sock)
    break
  except Exception:
    time.sleep(0.05)
else:
  raise SystemExit("qmp connect failed")
buf = b""
def recv():
  global buf
  while True:
    if b"\n" in buf:
      line, buf = buf.split(b"\n", 1)
      if line.strip():
        return json.loads(line)
    chunk = s.recv(4096)
    if not chunk:
      raise SystemExit("qmp eof")
    buf += chunk
recv()
s.sendall(b'{"execute":"qmp_capabilities"}\n')
recv()
time.sleep(0.3)
for round in range(12):
  ev = []
  for name in ("a", "tab", "esc"):
    ev.append({"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": name}}})
    ev.append({"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": name}}})
  s.sendall((json.dumps({"execute": "input-send-event", "arguments": {"events": ev}}) + "\n").encode())
  recv()
  time.sleep(0.2)
time.sleep(1.5)
PY
  fi
  wait_loops=0
  while [ "$wait_loops" -lt 40 ]; do
    if grep -qF "$EXPECT_DONE_PREFIX" "$UART" 2>/dev/null; then
      break
    fi
    sleep 0.25
    wait_loops=$((wait_loops + 1))
  done
  kill "$QPID" 2>/dev/null || true
  wait "$QPID" 2>/dev/null || true
  hold_out="$(LC_ALL=C tr -d '\r' <"$UART" 2>/dev/null || true)"
  rm -f "$SOCK" "$UART"
  hold_done="$(printf '%s\n' "$hold_out" | grep -F "$EXPECT_DONE_PREFIX" | tail -1 || true)"
  if [ -z "$hold_done" ]; then
    echo "FAIL kernel-win-interactive — QMP ESC did not quit win_hold:" >&2
    printf '%s\n' "$hold_out" | grep -v 'import unresolved' | tail -20 | sed 's/^/  got: /' >&2
    exit 1
  fi
  ev_n="$(printf '%s\n' "$hold_done" | sed -n 's/.*events=\([0-9][0-9]*\).*/\1/p')"
  if [ -z "$ev_n" ] || [ "$ev_n" -lt 1 ]; then
    echo "FAIL kernel-win-interactive — virtio QMP inject events=0:" >&2
    echo "  got: $hold_done" >&2
    exit 1
  fi
  echo "  qmp-input: OK ($hold_done)"
else
  echo "  qmp-input: skipped (need win_hold.elf + python3)"
fi

echo "Human cocoa (one command): make kernel-win-run"
exit 0
