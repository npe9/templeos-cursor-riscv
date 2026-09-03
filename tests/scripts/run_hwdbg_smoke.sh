#!/bin/bash
# Hardware debugger smoke: QEMU gdbstub + Sdtrig CSR probe + guest HwTrigProbe.
# Needs: qemu-system-riscv64, riscv64-elf-gdb | riscv64-unknown-elf-gdb | gdb-multiarch
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
GDB_SCRIPT="$ROOT/tests/gdb/hwdbg_virt.gdb"
PORT="${HWDBG_GDB_PORT:-3333}"

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "error: need timeout or gtimeout" >&2
  exit 2
fi

pick_gdb() {
  local c
  for c in riscv64-elf-gdb riscv64-unknown-elf-gdb gdb-multiarch; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

GDB="$(pick_gdb || true)"
if [[ -z "${GDB}" ]]; then
  echo "error: need riscv64-elf-gdb, riscv64-unknown-elf-gdb, or gdb-multiarch" >&2
  exit 2
fi

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null
ELF="$BOOT/repl.elf"

pkill -f "qemu-system-riscv64.*${ELF}" 2>/dev/null || true
sleep 0.2

tmp_qemu="$(mktemp)"
tmp_gdb="$(mktemp)"
tmp_uart="$(mktemp)"
cleanup() {
  if [[ -n "${QPID:-}" ]]; then
    kill "$QPID" 2>/dev/null || true
    wait "$QPID" 2>/dev/null || true
  fi
  rm -f "$tmp_qemu" "$tmp_gdb" "$tmp_uart"
}
trap cleanup EXIT

# --- Phase A: host gdbstub ---
"$QEMU" -machine virt -cpu rv64 -m 128M -nographic -bios none \
  -kernel "$ELF" -S -gdb "tcp:127.0.0.1:${PORT}" \
  >"$tmp_qemu" 2>&1 &
QPID=$!
sleep 1
if ! kill -0 "$QPID" 2>/dev/null; then
  echo "FAIL hwdbg-smoke — QEMU failed to start" >&2
  cat "$tmp_qemu" >&2
  exit 1
fi

set +e
$TIMEOUT_CMD 30s "$GDB" -batch -nx \
  -ex "file $ELF" \
  -x "$GDB_SCRIPT" \
  >"$tmp_gdb" 2>&1
gdb_rc=$?
set -e

kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true
QPID=""

fail=0
need_gdb() {
  if ! grep -qE -- "$1" "$tmp_gdb"; then
    echo "FAIL hwdbg-smoke (gdb) — missing: $1" >&2
    fail=1
  fi
}

need_gdb 'hwdbg: at _start'
need_gdb 'tinfo=0x44'
need_gdb 'after stepi'
need_gdb 'armed mcontrol'
need_gdb 'hit break'
need_gdb 'hit hbreak'

if [[ $gdb_rc -ne 0 && $fail -eq 0 ]]; then
  echo "FAIL hwdbg-smoke — gdb exit $gdb_rc" >&2
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "---- gdb out (tail) ----" >&2
  tail -n 60 "$tmp_gdb" >&2
  exit 1
fi

echo "OK   hwdbg-smoke gdb: attach, stepi, tinfo, hbreak, mcontrol WARL"

# --- Phase B: guest HwTrigProbe via UART (boot blob includes hwdbg.hc) ---
input=$'HwTrigProbe;\nHwHelp;\nq\n'
set +e
$TIMEOUT_CMD 90s "$QEMU" -machine virt -cpu rv64 -m 128M -nographic -bios none \
  -kernel "$ELF" <<<"$input" >"$tmp_uart" 2>&1
uart_rc=$?
set -e

need_uart() {
  if ! grep -qF -- "$1" "$tmp_uart"; then
    echo "FAIL hwdbg-smoke (uart) — missing: $1" >&2
    fail=1
  fi
}

need_uart 'HWDBG_PROBE_OK'
need_uart 'tinfo=0x'
need_uart 'match trigger present'
need_uart 'HWDBG_HELP_OK'

if [[ $fail -ne 0 ]]; then
  echo "---- uart (tail) ----" >&2
  tail -n 80 "$tmp_uart" >&2
  exit 1
fi

echo "OK   hwdbg-smoke uart: HwTrigProbe + HwHelp"
echo "OK   hwdbg-smoke (gdbstub + guest Sdtrig probe)"
