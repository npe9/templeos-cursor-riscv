#!/bin/bash
# REPL 9p smoke: Run ninep.hc NinepSmoke under QEMU with host virtfs attached.
set -u
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
  echo "SKIP repl-9p smoke — need timeout" >&2
  exit 0
fi

make -C "$ROOT" repl-blob >/dev/null
make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/share"
printf 'hello from 9p' >"$T/share/test.txt"

input=$'Run("ninep.hc");\nNinepSmoke();\n4919;\n'
log="$(mktemp)"
printf '%s' "$input" | $TIMEOUT_CMD 90 "$QEMU" -M virt -m 256M -bios none -kernel "$BOOT/repl.elf" -nographic \
  -fsdev local,id=fsdev0,path="$T/share",security_model=none \
  -device virtio-9p-device,fsdev=fsdev0,mount_tag=hostshare >"$log" 2>&1 &
qpid=$!
for ((t = 0; t < 900; t++)); do
  if grep -q 'ans=0x0000000000000000' "$log" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
out="$(tr -d '\r' <"$log")"
rm -f "$log"
if printf '%s\n' "$out" | grep -q 'ans=0x0000000000000000'; then
  echo "REPL-9p smoke: OK"
  exit 0
fi
echo "FAIL REPL-9p smoke — NinepSmoke did not return 0" >&2
printf '%s\n' "$out" | tail -20 >&2
exit 1
