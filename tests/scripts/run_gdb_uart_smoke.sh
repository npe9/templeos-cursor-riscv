#!/bin/bash
# Guest GDB RSP over UART smoke (GdbStub + tools/uart_gdb_proxy.py) on the HolyC
# AOT REPL. seed/gdbstub.hc is AOT-#included by bootstrap/hc_repl/repl.hc, so
# `GdbHelp; GdbStub;` work post-seal without Run() (a JIT Run of that file hangs).
# Does not use QEMU -gdb (that is hwdbg-smoke). Soft dbg-smoke untouched.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

# GdbStub/GdbHelp live in bootstrap/hc_repl/repl.hc (it #includes seed/gdbstub.hc). The
# top-level `make hc-repl` now ALIASES build/repl-holyc.elf to the guest-Compiler repl-cmp
# image ("thin JIT retired", Makefile), which has no GdbStub — pointing the smoke there made it
# answer "Undefined identifier" and time out. Build the image the stub is actually in.
# Porting GdbStub into the guest-Compiler image is the real fix (debugger plan D-5).
make -C "$ROOT/bootstrap/hc_repl" all >/dev/null
ELF="$ROOT/build/hc_repl.elf"
if [[ ! -f $ELF ]]; then
  echo "FAIL gdb-uart-smoke — missing $ELF (make -C bootstrap/hc_repl all)" >&2
  exit 1
fi

python3 "$ROOT/tools/uart_gdb_proxy.py" --selftest

set +e
$TIMEOUT_CMD 120s python3 "$ROOT/tools/uart_gdb_proxy.py" --qemu "$ELF" --qemu-bin "$QEMU"
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "FAIL gdb-uart-smoke (exit $rc)" >&2
  exit 1
fi

echo "OK   gdb-uart-smoke (guest GdbStub RSP over UART)"
