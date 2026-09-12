#!/bin/bash
# UART HolyC ExePutS REPL while WinMgr/FB runs: feed 1+1; / fault→go / q on -serial.
# Reuses build/exec/win_hold.elf when Make deps are current (same image as kernel-win-run).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTDIR="$ROOT/build/exec"
ELF="$OUTDIR/win_hold.elf"
QEMU="${QEMU_SYSTEM:-qemu-system-riscv64}"
TIMEOUT="timeout"; command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout"

EXPECT_READY="RVWinSerial ready"
EXPECT_EXEPUBS="ExePutS REPL"
EXPECT_ANS_LOOP="ans=42"
EXPECT_ANS_FOR="ans=10"
EXPECT_CRASH_DUMP="*** UART crash dump"
EXPECT_QUIT="RVWinSerial: quit WinMgr"
EXPECT_DONE="RVWinMgr interactive DONE"
EXPECT_REGS="Regs (kernel soft)"
EXPECT_GPR_A0="x10/a0 ="
EXPECT_REG_A0='Reg("a0")=0x'
EXPECT_PRINT_HI="hi from win serial"
EXPECT_MCAUSE_NONE="(none — no fault snap)"
EXPECT_DIR_SOFT="Dir (soft):"
EXPECT_DIR_ENTRY="WINDIR.TXT"
EXPECT_BT_LIVE="bt live fp="
# Dig-down bt must print a code-range PC (#0 0x80…), never stack (0x87E…).
EXPECT_BT_CODE='#0 0x80'
# Soft static sym map (not HashFind) — at least one dig-down frame named.
EXPECT_BT_SYM="RVWinSerial"
# PersonalMenu MenuFile of A:/Adam/PersonalMenu.DD (not static-table-only).
EXPECT_MENU_FILE_INIT="RVMenuPersonalInit MenuFile ok"
EXPECT_MENU_ADAM_PATH="path=A:/Adam/PersonalMenu.DD"
EXPECT_FILEMGR_PICK="FileMgr pick ok"
EXPECT_POPUP_PICK="PopUpPickFile ok:"
EXPECT_POPUP_SERVANT="PopUpPickFile DocPopUp begin"

command -v "$QEMU" >/dev/null 2>&1 || { echo "SKIP kernel-win-serial — missing $QEMU" >&2; exit 0; }

# Make owns AOT deps for win_hold.elf (Kernel/Compiler/holyc-riscv/…).
make -C "$ROOT" build/exec/win_hold.elf || exit 1
[ -f "$ELF" ] || { echo "FAIL kernel-win-serial — no $ELF" >&2; exit 1; }

# HolyC eval + dig-down bt + crash mon round-trip + quit.
# Pace lines so soft-RX/PutS cannot steal crash> input from host CrashMon.
# Also prove Regs;/Reg("a0");/Dir;/Print (ExePubs wire) — not only 40+2 arithmetic.
# for-loop JIT heap stores (global i++) must not illegal-insn / hang.
out="$( {
  sleep 2.5
  printf '40+2;\n'
  sleep 0.4
  printf 'I64 fi;\n'
  sleep 0.35
  printf 'I64 fs;\n'
  sleep 0.35
  printf 'fs=0;\n'
  sleep 0.35
  printf 'for (fi=0; fi<5; fi++) fs=fs+fi;\n'
  sleep 0.6
  printf 'fs;\n'
  sleep 0.4
  printf 'Regs;\n'
  sleep 0.8
  printf 'Reg("a0");\n'
  sleep 0.4
  printf 'Dir;\n'
  sleep 0.6
  printf 'Print("hi from win serial\\n");\n'
  sleep 0.5
  printf 'bt\n'
  sleep 0.5
  printf 'fault\n'
  sleep 0.6
  printf 'bt\n'
  sleep 0.4
  printf 'go\n'
  sleep 0.4
  printf 'q\n'
  sleep 0.5
} | $TIMEOUT 90 "$QEMU" \
  -M virt -m 256M -bios none -kernel "$ELF" \
  -device ramfb -display none -serial stdio \
  -device virtio-keyboard-device -device virtio-tablet-device 2>&1 | LC_ALL=C tr -d '\r')"

fail=0
# Mount/RedSea required (tS→rdtime fix); Dir; must list WINDIR.TXT.
for needle in "$EXPECT_READY" "$EXPECT_EXEPUBS" "$EXPECT_ANS_LOOP" "$EXPECT_ANS_FOR" \
    "$EXPECT_REGS" "$EXPECT_GPR_A0" "$EXPECT_REG_A0" "$EXPECT_MCAUSE_NONE" \
    "$EXPECT_PRINT_HI" "$EXPECT_DIR_SOFT" "$EXPECT_DIR_ENTRY" \
    "$EXPECT_BT_LIVE" "$EXPECT_BT_CODE" "$EXPECT_BT_SYM" \
    "$EXPECT_CRASH_DUMP" "$EXPECT_QUIT" "$EXPECT_MENU_FILE_INIT" "$EXPECT_MENU_ADAM_PATH" \
    "$EXPECT_FILEMGR_PICK" "$EXPECT_POPUP_PICK" "$EXPECT_POPUP_SERVANT"; do
  if ! printf '%s\n' "$out" | grep -qF "$needle"; then
    echo "FAIL kernel-win-serial — missing: $needle" >&2
    fail=1
  fi
done
# Prove MenuFile path (emb=0), not silent table fallback under live RVKSpawn.
if printf '%s\n' "$out" | grep -qF 'RVMenuPersonalInit MenuFile miss'; then
  echo "FAIL kernel-win-serial — PersonalMenu fell back to static table" >&2
  fail=1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVWinMgr MENU PersonalMenu .* emb=0'; then
  echo "FAIL kernel-win-serial — MENU PersonalMenu emb!=0 (file load?)" >&2
  fail=1
fi
# FileMgr pick must not mepc=0; JobRes path still green earlier in the same UART.
if printf '%s\n' "$out" | grep -qE 'mepc=0000000000000000'; then
  echo "FAIL kernel-win-serial — mepc=0 (FileMgr pick / JobRes?)" >&2
  fail=1
fi
if ! printf '%s\n' "$out" | grep -qE 'RVPopUp stock JobRes res=[1-9]|interactive popup JobRes done'; then
  echo "FAIL kernel-win-serial — JobRes regress after FileMgr pick:" >&2
  fail=1
fi
if printf '%s\n' "$out" | grep -qF "$EXPECT_DIR_ENTRY"; then
  echo "Kernel-win-serial: Dir/WINDIR present (Mount green)"
fi
# Soft GPR path must not still advertise CSR-only stub.
if printf '%s\n' "$out" | grep -qF 'GPR soft snap not in kernel'; then
  echo "FAIL kernel-win-serial — Reg still CSR-only stub" >&2
  fail=1
fi
# Dig-down / crash bt must not print stack addrs as frames (old SP-scan bug).
if printf '%s\n' "$out" | grep -E '^\s+#[0-9]+ 0x87E' >/dev/null; then
  echo "FAIL kernel-win-serial — bt printed stack addr as frame (0x87E…)" >&2
  fail=1
fi
# Crash> bt is trap-mepc only (honest; no fp freeze).
if ! printf '%s\n' "$out" | grep -qF 'bt (trap mepc only'; then
  echo "FAIL kernel-win-serial — missing crash> trap-mepc bt" >&2
  fail=1
fi
# Dir; must resolve (ExePubs wire) — not Undefined identifier.
if printf '%s\n' "$out" | grep -qF 'Undefined identifier'; then
  echo "FAIL kernel-win-serial — Undefined identifier (Dir/ExePubs?)" >&2
  fail=1
fi
# Reject FFFF-flood mstatus (StrPrint %X arithmetic-shift bug).
if printf '%s\n' "$out" | grep -qE 'mstatus=0xF{20,}'; then
  echo "FAIL kernel-win-serial — mstatus hex flood (bad %X width)" >&2
  fail=1
fi
# mstatus should be a short hex (≤16 digits after 0x).
if ! printf '%s\n' "$out" | grep -qE 'mstatus=0x[0-9A-Fa-f]{1,16} '; then
  echo "FAIL kernel-win-serial — mstatus hex length not sane" >&2
  fail=1
fi
if [ "$fail" -ne 0 ]; then
  printf '%s\n' "$out" | grep -v 'import unresolved' | head -120 | sed 's/^/  got: /' >&2
  exit 1
fi
echo "Kernel-win-serial: OK ($EXPECT_READY + ExePutS ans=42 + for→ans=10 + Regs/Reg GPR + Dir/WINDIR.TXT + Print + bt/sym + crash dump + quit + PersonalMenu MenuFile + FileMgr pick GetMsg)"
if printf '%s\n' "$out" | grep -qF "$EXPECT_DONE"; then
  echo "  $EXPECT_DONE present"
fi
exit 0
