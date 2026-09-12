#!/bin/bash
# Smoke: boot TempleOS firmware (pflash @ 0x20000000) and expect the payload to run.
# The wrapped payload is the Kconfig kernel plat image (Makefile.firmware PAYLOAD=plat).
# It used to be the legacy C guest repl.elf, and this script grepped for the REPL prompt
# and "1+1" — that guest was deleted in 080f729, so the needles are the plat smoke lines.
# Re-point these at build/repl-holyc.elf if a HolyC REPL flash payload is ever wired up.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FW_BIN="$ROOT/build/firmware/templeos-fw.bin"
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

make -C "$ROOT/bootstrap" -f Makefile.firmware firmware >/dev/null

if [ ! -f "$FW_BIN" ]; then
  echo "FAIL firmware smoke — missing $FW_BIN" >&2
  exit 1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

$TIMEOUT_CMD 45 "$QEMU" -M virt -m 128M -bios none \
  -drive if=pflash,format=raw,file="$FW_BIN" -nographic >"$log" 2>&1 </dev/null || true

if ! grep -q 'plat-smoke: uart_ok' "$log"; then
  echo "FAIL firmware smoke — payload did not reach the UART" >&2
  tail -40 "$log" >&2
  exit 1
fi
if ! grep -q 'plat-smoke: PASS' "$log"; then
  echo "FAIL firmware smoke — plat payload did not pass" >&2
  tail -40 "$log" >&2
  exit 1
fi

echo "PASS firmware smoke (pflash boot, kernel plat payload)"
