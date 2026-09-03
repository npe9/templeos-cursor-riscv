#!/usr/bin/env bash
# DumpChanges UART manifest + DumpFile bodies; P4 rename; P5 wrap honesty.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOT="$ROOT/bootstrap"
QEMU="${QEMU_SYSTEM_RISCV:-qemu-system-riscv64}"
OUT="$(mktemp -d /tmp/dump-changes.XXXXXX)"
LOG="$(mktemp /tmp/dump-changes-log.XXXXXX)"
trap 'rm -rf "$OUT"; rm -f "$LOG"' EXIT

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "error: need timeout or gtimeout" >&2
  exit 2
fi

if ! command -v "$QEMU" >/dev/null 2>&1; then
  echo "SKIP dump-changes-smoke — $QEMU not found" >&2
  exit 0
fi

python3 "$ROOT/tools/uart_recv_dump.py" --selftest

make -C "$BOOT" -f Makefile.repl repl.elf >/dev/null

input='FileWrite("Home/dc.hc","p2body",6);
DumpChanges;
Rename("Home/dc.hc","Home/dc2.hc");
FsChanges;
I64 wi;
for (wi=0; wi<520; wi++) FileWrite("Home/wrap.hc","x",1);
FsLog(32);
FileWrite("Home/p6.hc","p6",2);
FsReplay;
Recover;
FsChanges;
4919;
'

printf '%s' "$input" | $TIMEOUT_CMD 90 "$QEMU" -M virt -bios none \
  -kernel "$BOOT/repl.elf" -nographic >"$LOG" 2>&1 &
qpid=$!
for ((t = 0; t < 900; t++)); do
  if grep -q 'ans=0x0000000000001337' "$LOG" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true

if ! grep -q 'ans=0x0000000000001337' "$LOG"; then
  echo "FAIL dump-changes-smoke — no sentinel" >&2
  tail -n 80 "$LOG" >&2
  exit 1
fi
if ! grep -qF '$HC_CHANGES' "$LOG"; then
  echo "FAIL dump-changes-smoke — no \$HC_CHANGES manifest" >&2
  tail -n 80 "$LOG" >&2
  exit 1
fi
if ! grep -qF 'renamed Home/dc.hc -> Home/dc2.hc' "$LOG"; then
  echo "FAIL dump-changes-smoke — rename print missing" >&2
  tail -n 80 "$LOG" >&2
  exit 1
fi
if ! grep -qF 'R  Home/dc.hc' "$LOG"; then
  echo "FAIL dump-changes-smoke — journal rename missing" >&2
  tail -n 80 "$LOG" >&2
  exit 1
fi
if ! grep -qF 'WRAP n=' "$LOG"; then
  echo "FAIL dump-changes-smoke — no FS_OP_WRAP after fill" >&2
  tail -n 80 "$LOG" >&2
  exit 1
fi
if ! grep -qF 'fs replay: ok' "$LOG"; then
  echo "FAIL dump-changes-smoke — FsReplay not ok" >&2
  tail -n 80 "$LOG" >&2
  exit 1
fi
if ! grep -qE 'epoch [0-9]+ sealed \(RECOVER' "$LOG"; then
  echo "FAIL dump-changes-smoke — Recover reseal missing" >&2
  tail -n 80 "$LOG" >&2
  exit 1
fi
if ! grep -qF 'FsRecover: dropped' "$LOG"; then
  echo "FAIL dump-changes-smoke — FsRecover drop missing" >&2
  tail -n 80 "$LOG" >&2
  exit 1
fi

python3 "$ROOT/tools/uart_recv_dump.py" --keep-path -o "$OUT" <"$LOG"
got="$OUT/Home/dc.hc"
if [[ ! -f "$got" ]]; then
  echo "FAIL dump-changes-smoke — no $got" >&2
  ls -laR "$OUT" >&2 || true
  exit 1
fi
if ! grep -qx 'p2body' "$got"; then
  echo "FAIL dump-changes-smoke — body mismatch:" >&2
  od -An -tx1 "$got" >&2
  exit 1
fi
if ! grep -qF 'W  Home/dc.hc' "$OUT/CHANGES"; then
  echo "FAIL dump-changes-smoke — CHANGES manifest missing W Home/dc.hc" >&2
  cat "$OUT/CHANGES" >&2
  exit 1
fi
echo "OK   dump-changes-smoke ($got + rename + WRAP + FsReplay/Recover)"
