#!/bin/bash
# REPL 9p smoke: NinepSmoke on the HolyC AOT REPL under QEMU with host virtfs
# (import + export). seed/ninep.hc is AOT-#included by bootstrap/hc_repl/repl.hc and
# reachable through JitAdd — the thin JitTry evaluator cannot compile the driver, so
# this drives NinepSmoke directly instead of Run("ninep.hc").
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

# No `set -e` here (the poll loops below rely on non-zero greps), so the build
# has to be checked by hand — otherwise a failed `make` just leaves a stale ELF
# in place and the smoke reports on yesterday's image.
if ! make -C "$ROOT" hc-repl >/dev/null; then
  echo "FAIL REPL-9p smoke — make hc-repl failed" >&2
  exit 1
fi
ELF="$ROOT/build/repl-holyc.elf"
if [ ! -f "$ELF" ]; then
  echo "FAIL REPL-9p smoke — missing $ELF (make hc-repl)" >&2
  exit 1
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/share"
printf 'hello from 9p' >"$T/share/test.txt"

input=$'NinepSmoke();\n4919;\n'
log="$(mktemp)"
printf '%s' "$input" | $TIMEOUT_CMD 90 "$QEMU" -M virt -m 256M -bios none -kernel "$ELF" -nographic \
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
if ! printf '%s\n' "$out" | grep -q 'ans=0x0000000000000000'; then
  echo "FAIL REPL-9p smoke — NinepSmoke did not return 0" >&2
  printf '%s\n' "$out" | tail -20 >&2
  exit 1
fi
if [ ! -f "$T/share/export.txt" ] || ! grep -qF 'overwrite-9p' "$T/share/export.txt"; then
  echo "FAIL REPL-9p smoke — guest→host export.txt overwrite missing or wrong" >&2
  ls -la "$T/share" >&2 || true
  cat "$T/share/export.txt" 2>/dev/null | sed 's/^/  got: /' >&2 || true
  exit 1
fi
if [ ! -f "$T/share/Home/nest/out.hc" ] || ! grep -qF 'nested-9p' "$T/share/Home/nest/out.hc"; then
  echo "FAIL REPL-9p smoke — nested Home/nest/out.hc missing or wrong" >&2
  find "$T/share" -type f 2>/dev/null | sed 's/^/  /' >&2 || true
  exit 1
fi
echo "REPL-9p smoke: OK (read + export + overwrite + nested)"
exit 0
