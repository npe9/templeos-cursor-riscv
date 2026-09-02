#!/bin/bash
# Smoke: boot bare-metal REPL flat bin @ RAM via qemu -bios none -kernel.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN="$ROOT/build/baremetal/repl.bin"
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

make -C "$ROOT" baremetal >/dev/null

if [ ! -f "$BIN" ]; then
  echo "FAIL baremetal smoke — missing $BIN" >&2
  exit 1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

input='1+1;'$'\n'
printf '%s' "$input" | $TIMEOUT_CMD 45 "$QEMU" -M virt -m 128M -bios none \
  -kernel "$BIN" -nographic >"$log" 2>&1 || true

if ! grep -q '> ' "$log"; then
  echo "FAIL baremetal smoke — no REPL prompt" >&2
  tail -40 "$log" >&2
  exit 1
fi
if ! grep -q 'ans=0x0000000000000002' "$log"; then
  echo "FAIL baremetal smoke — 1+1 answer missing" >&2
  tail -40 "$log" >&2
  exit 1
fi

echo "PASS baremetal smoke (-kernel repl.bin @ RAM, REPL 1+1)"
