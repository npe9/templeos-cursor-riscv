#!/usr/bin/env bash
# QEMU PTY round-trip: FileWrite a memfs file, ZmodemSend it, decode on the host.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
OUT="$(mktemp -d /tmp/zm-export.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT

if ! command -v "$QEMU" >/dev/null 2>&1; then
  echo "SKIP zmodem-smoke — $QEMU not found" >&2
  exit 0
fi

python3 "$ROOT/tools/uart_recv_zmodem.py" --selftest

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

python3 "$ROOT/tools/uart_recv_zmodem.py" \
  --qemu "$BOOT/repl.elf" \
  --qemu-bin "$QEMU" \
  -o "$OUT" \
  --cmd 'FsSnap;FileWrite("zm_t.txt","hello-zmodem\n",13);ZmodemSend("zm_t.txt");'

got="$OUT/zm_t.txt"
if [[ ! -f "$got" ]]; then
  echo "FAIL zmodem-smoke — no $got" >&2
  ls -la "$OUT" >&2 || true
  exit 1
fi
if ! grep -qx 'hello-zmodem' "$got"; then
  echo "FAIL zmodem-smoke — content mismatch:" >&2
  od -An -tx1 "$got" >&2
  exit 1
fi

python3 "$ROOT/tools/uart_recv_zmodem.py" \
  --qemu "$BOOT/repl.elf" \
  --qemu-bin "$QEMU" \
  -o "$OUT" \
  --cmd 'FsSnap;FileWrite("zm_c.txt","chg\n",4);ZmodemSendChanges;'

got2="$OUT/zm_c.txt"
if [[ ! -f "$got2" ]]; then
  echo "FAIL zmodem-smoke — no $got2 (ZmodemSendChanges)" >&2
  ls -la "$OUT" >&2 || true
  exit 1
fi
if ! grep -qx 'chg' "$got2"; then
  echo "FAIL zmodem-smoke — ZmodemSendChanges content mismatch:" >&2
  od -An -tx1 "$got2" >&2
  exit 1
fi
echo "OK   zmodem-smoke ($got + $got2)"
