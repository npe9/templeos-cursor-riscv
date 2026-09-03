#!/bin/bash
# Minimal QEMU UART REPL debugger smoke: Regs snap, Bt, Bp hit/continue, WatchChk.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "error: need timeout or gtimeout" >&2
  exit 2
fi

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

input=""
add() { input+="$1"$'\n'; }

add 'asm { li a0, 5 }; Reg("a0"); "asm_repl_a0=%d\n", Reg("a0");'
add 'asm { li a7, 5 }; Regs; "post_regs_a7=%d\n", Reg("a7");'
add 'Bt;'
add 'I64 Dg(I64 x,I64 y){return x+y;}'
add 'Bp(&Dg);'
add 'Dg(11,22);'
add 'I64 w;'
add 'Watch(&w);'
add 'w=7;'
add 'WatchChk;'
add 'TrapDump;'
add 'DbgHelp;'
add 'q'

tmpout="$(mktemp)"
tmperr="$(mktemp)"
cleanup() { rm -f "$tmpout" "$tmperr"; }
trap cleanup EXIT

set +e
$TIMEOUT_CMD 90s "$QEMU" -machine virt -cpu rv64 -m 128M -nographic -bios none \
  -kernel "$BOOT/repl.elf" <<<"$input" >"$tmpout" 2>"$tmperr"
rc=$?
set -e

out="$(cat "$tmpout"; cat "$tmperr")"
fail=0
need() {
  if ! grep -qF -- "$1" <<<"$out"; then
    echo "FAIL dbg-smoke — missing: $1" >&2
    fail=1
  fi
}

need '  x10/a0 = 0x0000000000000005'
need 'asm_repl_a0=5'
need 'post_regs_a7=5'
need 'stack:'
need 'breakpoint @'
need 'a0=0xB'
need 'ans=0x0000000000000021'
need 'watch hit'
need 'TrapDump'
need 'DbgHelp'

if [[ $fail -ne 0 ]]; then
  echo "---- uart (tail) ----" >&2
  tail -n 80 <<<"$out" >&2
  exit 1
fi

echo "OK   dbg-smoke: Regs restore, Bt/stack, Bp hit+continue, WatchChk, TrapDump"
