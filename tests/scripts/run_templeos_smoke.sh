#!/bin/bash
# Smoke-test TempleOS/RISC-V images (QEMU UART ORACLE line).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOS="$ROOT/templeos-riscv"
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
make -C "$TOS" image selfhost >/dev/null

check_elf() {
  local elf="$1"
  local want="$2"
  local name="$3"
  local out
  out="$($TIMEOUT_CMD 5 "$QEMU" -M virt -bios none -kernel "$elf" -nographic </dev/null 2>&1 | tr -d '\r' || true)"
  if ! echo "$out" | grep -q "ORACLE $want"; then
    echo "FAIL $name — expected ORACLE $want in:" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "OK   $name → ORACLE $want"
}

check_elf "$TOS/build/tos-rv.elf" "000000000000002a" "default guest (42)"
check_elf "$TOS/build/tos-rv-selfhost.elf" "000000000000000e" "selfhost guest (2+3*4)"
echo "TempleOS/RISC-V smoke: OK"
