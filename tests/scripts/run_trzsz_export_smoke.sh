#!/usr/bin/env bash
# QEMU stdio round-trip: FileWrite a memfs file, TrzszSend it, decode on the host.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
OUT="$(mktemp -d /tmp/tz-export.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT

if ! command -v "$QEMU" >/dev/null 2>&1; then
  echo "SKIP trzsz-smoke — $QEMU not found" >&2
  exit 0
fi

python3 "$ROOT/tools/uart_recv_trzsz.py" --selftest

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

python3 "$ROOT/tools/uart_recv_trzsz.py" \
  --qemu "$BOOT/repl.elf" \
  --qemu-bin "$QEMU" \
  -o "$OUT" \
  --cmd 'FsSnap;FileWrite("tz_t.txt","hello-trzsz\n",12);TrzszSend("tz_t.txt");'

got="$OUT/tz_t.txt"
if [[ ! -f "$got" ]]; then
  echo "FAIL trzsz-smoke — no $got" >&2
  ls -la "$OUT" >&2 || true
  exit 1
fi
if ! grep -qx 'hello-trzsz' "$got"; then
  echo "FAIL trzsz-smoke — content mismatch:" >&2
  od -An -tx1 "$got" >&2
  exit 1
fi

python3 "$ROOT/tools/uart_recv_trzsz.py" \
  --qemu "$BOOT/repl.elf" \
  --qemu-bin "$QEMU" \
  -o "$OUT" \
  --cmd 'FsSnap;FileWrite("tz_c.txt","chg\n",4);TrzszSendChanges;'

got2="$OUT/tz_c.txt"
if [[ ! -f "$got2" ]]; then
  echo "FAIL trzsz-smoke — no $got2 (TrzszSendChanges)" >&2
  ls -la "$OUT" >&2 || true
  exit 1
fi
if ! grep -qx 'chg' "$got2"; then
  echo "FAIL trzsz-smoke — TrzszSendChanges content mismatch:" >&2
  od -An -tx1 "$got2" >&2
  exit 1
fi
echo "OK   trzsz-smoke ($got + $got2)"
