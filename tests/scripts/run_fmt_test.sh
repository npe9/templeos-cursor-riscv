#!/usr/bin/env bash
# Golden tests for holyc-riscv --fmt (AST/CST formatter).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${HOLYC_BIN:-$ROOT/holyc-riscv}"
CASES="$ROOT/tests/fmt/cases"
GOLDEN="$ROOT/tests/fmt/golden"
TMP="${TMPDIR:-/tmp}/holyc_fmt_test_$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

if [[ ! -x "$BIN" ]]; then
  echo "Building holyc-riscv..." >&2
  make -C "$ROOT" holyc-riscv >/dev/null || {
    echo "error: missing $BIN (run make holyc-riscv)" >&2
    exit 1
  }
fi

fail=0
found=0
for src in "$CASES"/*; do
  [[ -f "$src" ]] || continue
  found=1
  base="$(basename "$src")"
  g="$GOLDEN/$base"
  if [[ ! -f "$g" ]]; then
    echo "FAIL $base (missing golden $g)" >&2
    fail=1
    continue
  fi
  out="$TMP/$base"
  "$BIN" --fmt --stdout "$src" >"$out"
  if ! diff -u "$g" "$out"; then
    echo "FAIL $base (differs from golden)" >&2
    fail=1
    continue
  fi
  out2="$TMP/${base}.2"
  "$BIN" --fmt --stdout "$out" >"$out2"
  if ! diff -q "$out" "$out2" >/dev/null; then
    echo "FAIL $base (not idempotent)" >&2
    diff -u "$out" "$out2" || true
    fail=1
    continue
  fi
  echo "OK $base"
done

if [[ "$found" -eq 0 ]]; then
  echo "error: no fixtures in $CASES" >&2
  exit 1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "fmt-test: FAILED" >&2
  exit 1
fi
echo "✓ fmt-test"
