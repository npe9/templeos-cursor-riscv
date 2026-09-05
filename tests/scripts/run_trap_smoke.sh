#!/usr/bin/env bash
# G2 trap/Break + CONSOLE #9 CrashMon on product HolyC REPL (no worry_dream C trapvec).
# CrashMon → Fault dump → crash> → go → after-fault; Break; SetTrap(ZapTrap)/Ecall; Ctrl-C.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/hc_repl.elf"
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

make -C "$ROOT" holyc-riscv >/dev/null
make -C "$ROOT/bootstrap/hc_repl" all

input=""
add() { input+="$1"$'\n'; }

# CONSOLE #9 CrashMon (SetTrapFn bound at boot; no mtvec until first Fault/Break/SetTrap)
add 'CrashHelp;'
add 'CrashMon;'
add 'pc'
add 'md'
add 'regs'
add 'bt'
add 'go'
add 'Print("after-crashmon\n");'

# Fault dump + CrashMon (dump → crash> → go → abort-to-prompt)
add 'Fault;'
add 'regs'
add 'bt'
add 'go'
add 'Print("after-fault\n");'

# Break → Interrupted (thin JIT has no try/catch)
add 'Break;'
add 'Print("after-break\n");'

# SetTrap AOT handler + ecall (ZapTrap in crash.hc — not thin-JIT "str";)
add 'SetTrap("ZapTrap");'
add 'Ecall();'
add 'Print("after-ecall\n");'
add 'SetTrap("CrashOnTrap");'

# Busy loop + Ctrl-C
add 'I64 __brk; for(__brk=0;;__brk++) {}'
input+=$'\x03'
add 'Print("after-ctrlc\n");'

log="$(mktemp)"
fifo="$(mktemp -u)"
cleanup() { rm -f "$log" "$fifo"; }
trap cleanup EXIT
mkfifo "$fifo"
$TIMEOUT_CMD 300s "$QEMU" -M virt -m 128M -bios none -kernel "$ELF" -nographic \
  <"$fifo" >"$log" 2>&1 &
qpid=$!
(
  # Help text also contains "Try: Dir" mid-paint — wait for post-boot markers.
  for _ in $(seq 1 240); do
    if grep -qF '=== VT end ===' "$log" 2>/dev/null; then
      break
    fi
    if grep -qE '^> $' "$log" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  sleep 2
  printf '%s' "$input"
  while kill -0 "$qpid" 2>/dev/null; do
    sleep 0.05
  done
) >"$fifo" &
feeder=$!
wait "$qpid" 2>/dev/null || true
kill "$feeder" 2>/dev/null || true
wait "$feeder" 2>/dev/null || true

fail=0
need() {
  if ! grep -qF -- "$1" "$log"; then
    echo "FAIL trap-smoke -- missing: $1" >&2
    fail=1
  fi
}

need 'G2: HolyC TrapDispatch + Ctrl-C Break'
need 'CrashHelp'
need 'Md @'
need 'crash: leave monitor'
need 'after-crashmon'
need 'illegal instruction'
need '*** FAULT'
need 'crash>'
need 'eval aborted'
need 'after-fault'
need 'Interrupted'
need 'after-break'
need 'ZAP-HIT'
need 'after-ecall'
need 'after-ctrlc'

if [[ "$fail" -ne 0 ]]; then
  echo "---- uart (tail) ----" >&2
  tail -n 120 "$log" >&2
  exit 1
fi

echo "OK   trap-smoke: Fault/CrashMon, Break, SetTrap/Ecall, Ctrl-C on repl-holyc"
