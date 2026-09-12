#!/bin/bash
# Smoke: boot TempleOS via qemu -bios (RAM-loaded payload) and expect the payload to run.
# Payload is the Kconfig kernel plat image (Makefile.firmware PAYLOAD=plat). The legacy C
# guest repl.elf this used to grep for ("> " prompt, 1+1) was deleted in 080f729.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIOS_ELF="$ROOT/build/firmware/templeos-bios.elf"
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

if [ ! -f "$BIOS_ELF" ]; then
  echo "FAIL bios smoke — missing $BIOS_ELF" >&2
  exit 1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

$TIMEOUT_CMD 45 "$QEMU" -M virt -m 128M -bios "$BIOS_ELF" \
  -nographic >"$log" 2>&1 </dev/null || true

if ! grep -q 'plat-smoke: uart_ok' "$log"; then
  echo "FAIL bios smoke — payload did not reach the UART" >&2
  tail -40 "$log" >&2
  exit 1
fi
if ! grep -q 'plat-smoke: PASS' "$log"; then
  echo "FAIL bios smoke — plat payload did not pass" >&2
  tail -40 "$log" >&2
  exit 1
fi

echo "PASS bios smoke (-bios RAM payload, kernel plat)"
