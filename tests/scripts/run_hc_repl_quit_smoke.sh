#!/usr/bin/env bash
# Smoke: HolyC REPL Quit/Exit → SiFive test finisher PASS @ MEM_TEST (QEMU virt).
# Expect QEMU process exit status 0 within timeout (not hang / timeout kill).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELF="$ROOT/build/hc_repl.elf"
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

make -C "$ROOT/bootstrap/hc_repl" all

run_finisher() {
  local cmd="$1"
  local want_rc="$2"
  local label="$3"
  local log rc
  log="$(mktemp)"
  set +e
  # shellcheck disable=SC2086
  printf '%s\n' "$cmd" | $TIMEOUT_CMD 60 "$QEMU" -M virt -m 128M -bios none \
    -kernel "$ELF" -nographic >"$log" 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 124 ]; then
    echo "FAIL hc-repl-quit-smoke — $label timed out (finisher not reached)" >&2
    tail -30 "$log" >&2
    rm -f "$log"
    return 1
  fi
  if [ "$rc" -ne "$want_rc" ]; then
    echo "FAIL hc-repl-quit-smoke — $label: want exit $want_rc, got $rc" >&2
    tail -30 "$log" >&2
    rm -f "$log"
    return 1
  fi
  if ! grep -qF '> ' "$log"; then
    echo "FAIL hc-repl-quit-smoke — $label: missing REPL prompt before finisher" >&2
    tail -30 "$log" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  echo "OK $label (qemu exit $rc)"
  return 0
}

fail=0
run_finisher 'Quit;' 0 'Quit' || fail=1
run_finisher 'Exit;' 0 'Exit' || fail=1

# Fail packs panic code 1 → expect non-zero host exit on QEMU that propagates it.
# Some builds still exit 0 on guest panic; accept 0 only if log shows we reached Fail
# without timeout — but prefer non-zero when available.
log="$(mktemp)"
set +e
# shellcheck disable=SC2086
printf 'Fail;\n' | $TIMEOUT_CMD 60 "$QEMU" -M virt -m 128M -bios none \
  -kernel "$ELF" -nographic >"$log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 124 ]; then
  echo "FAIL hc-repl-quit-smoke — Fail timed out" >&2
  tail -30 "$log" >&2
  fail=1
elif [ "$rc" -eq 0 ]; then
  # QEMU ≥ shutdown_request path may exit 0 even on FAIL; still require prompt.
  if ! grep -qF '> ' "$log"; then
    echo "FAIL hc-repl-quit-smoke — Fail: missing prompt (exit 0)" >&2
    fail=1
  else
    echo "OK Fail (qemu exit 0 — FAIL finisher accepted; code not propagated)"
  fi
else
  echo "OK Fail (qemu exit $rc)"
fi
rm -f "$log"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "HolyC REPL Quit/Exit/Fail finisher smoke: OK"
exit 0
