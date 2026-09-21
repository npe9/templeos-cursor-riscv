#!/usr/bin/env bash
# DumpChanges UART manifest + DumpFile bodies; P4 rename; P5 wrap honesty.
# Runs on the product HolyC image (build/repl-holyc.elf). This used to boot the legacy C
# guest bootstrap/repl.elf, deleted in 080f729. The P5 fill loop is wrapped in a function
# because the thin JIT rejects a top-level `for` statement ("JIT: unknown fun for").
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

make -C "$ROOT" hc-repl >/dev/null

# Paced, one line at a time. The product REPL's line editor drops and reorders characters on
# unpaced input -- run_asm_repl_smoke.sh carries the same note -- which showed up here as Rename
# running before the file it renames existed while FsChanges already reported seq=521 from the
# fill loop further down the script. DcFill520 gets a long pause because it is 520 writes.
feed() {
  perl -e '
    $|=1;
    select(undef,undef,undef,4);
    my @l = (
      [q{FileWrite("Home/dc.hc","p2body",6);}, 1.5],
      [q{DumpChanges;}, 2.0],
      [q{Rename("Home/dc.hc","Home/dc2.hc");}, 1.5],
      [q{FsChanges;}, 1.5],
      [q{U0 DcFill520() { I64 wi; for (wi = 0; wi < 520; wi++) FileWrite("Home/wrap.hc", "x", 1); }}, 2.0],
      [q{DcFill520;}, 12.0],
      [q{FsLog(32);}, 2.0],
      [q{FileWrite("Home/p6.hc","p6",2);}, 1.5],
      [q{FsReplay;}, 3.0],
      [q{Recover;}, 3.0],
      [q{FsChanges;}, 2.0],
      [q{4919;}, 2.0],
    );
    for my $e (@l) {
      print $e->[0], "\n";
      select(undef,undef,undef,$e->[1]);
    }
    select(undef,undef,undef,3);
  '
}

feed | $TIMEOUT_CMD 180 "$QEMU" -M virt -m 256M -bios none \
  -kernel "$ROOT/build/repl-holyc.elf" -nographic >"$LOG" 2>&1 &
qpid=$!
for ((t = 0; t < 900; t++)); do
  if grep -qE 'ans=(4919|0x0*1337)$' "$LOG" 2>/dev/null; then break; fi
  kill -0 "$qpid" 2>/dev/null || break
  sleep 0.1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true

# 4919 = 0x1337. The guest Compiler_RV REPL prints it in decimal; the hex spelling belonged to
# the thin JIT image retired in 080f729. Accept either.
if ! grep -qE 'ans=(4919|0x0*1337)$' "$LOG"; then
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
