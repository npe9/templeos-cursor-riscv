#!/bin/bash
# Smoke: HolyC bootloader (jump) @ pflash → HolyC REPL blob @ ENTRY_POINT; expect 1+1.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT_BIN="$ROOT/build/bootloader/boot.bin"
REPL_BIN="$ROOT/build/hc_repl.blob.bin"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
ENTRY_POINT="${ENTRY_POINT:-0x80000000}"
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
make -C "$ROOT" bootloader-repl BOOT_MODE=jump >/dev/null

if [ ! -f "$BOOT_BIN" ]; then
  echo "FAIL bootloader smoke — missing $BOOT_BIN" >&2
  exit 1
fi
if [ ! -f "$REPL_BIN" ]; then
  echo "FAIL bootloader smoke — missing $REPL_BIN" >&2
  exit 1
fi

kcfg="$ROOT/templeos-riscv/include/generated/kconfig.mk"
if [ -f "$kcfg" ]; then
  # shellcheck source=/dev/null
  . "$kcfg"
  ENTRY_POINT="${ENTRY_POINT:-0x80000000}"
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

input='1+1;'$'\n'
printf '%s' "$input" | $TIMEOUT_CMD 45 "$QEMU" -M virt -m 128M -bios none \
  -drive if=pflash,format=raw,file="$BOOT_BIN" \
  -device "loader,file=$REPL_BIN,addr=$ENTRY_POINT" \
  -nographic >"$log" 2>&1 || true

if ! grep -q '> ' "$log"; then
  echo "FAIL bootloader smoke — no REPL prompt" >&2
  tail -40 "$log" >&2
  exit 1
fi
if ! grep -q 'ans=0x0000000000000002' "$log"; then
  echo "FAIL bootloader smoke — 1+1 answer missing" >&2
  tail -40 "$log" >&2
  exit 1
fi

echo "PASS bootloader smoke (HolyC pflash jump → REPL blob @ $ENTRY_POINT, 1+1)"
