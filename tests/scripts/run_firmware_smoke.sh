#!/bin/bash
# Smoke: boot TempleOS firmware (pflash @ 0x20000000) and expect REPL prompt.
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

input='1+1;'$'\n'
printf '%s' "$input" | $TIMEOUT_CMD 45 "$QEMU" -M virt -m 128M -bios none \
  -drive if=pflash,format=raw,file="$FW_BIN" -nographic >"$log" 2>&1 || true

if ! grep -q '> ' "$log"; then
  echo "FAIL firmware smoke — no REPL prompt" >&2
  tail -40 "$log" >&2
  exit 1
fi
if ! grep -q 'ans=0x0000000000000002' "$log"; then
  echo "FAIL firmware smoke — 1+1 answer missing" >&2
  tail -40 "$log" >&2
  exit 1
fi

echo "PASS firmware smoke (pflash boot, REPL 1+1)"
