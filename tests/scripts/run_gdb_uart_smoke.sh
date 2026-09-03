#!/bin/bash
# Guest GDB RSP over UART smoke (GdbStub + tools/uart_gdb_proxy.py).
# Does not use QEMU -gdb (that is hwdbg-smoke). Soft dbg-smoke untouched.
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

python3 "$ROOT/tools/uart_gdb_proxy.py" --selftest

set +e
$TIMEOUT_CMD 120s python3 "$ROOT/tools/uart_gdb_proxy.py" --qemu "$BOOT/repl.elf" --qemu-bin "$QEMU"
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL gdb-uart-smoke (exit $rc)" >&2
  exit 1
fi

echo "OK   gdb-uart-smoke (guest GdbStub RSP over UART)"
