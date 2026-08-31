#!/usr/bin/env bash
# Format or check HolyC under the enforced path list (see holyc_fmt_paths.sh).
# Usage:
#   run_fmt.sh              # rewrite in place (make fmt)
#   run_fmt.sh --check      # list files that differ; exit 1 if any (make fmt-check)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${HOLYC_BIN:-$ROOT/holyc-riscv}"
PATHS_SCRIPT="$ROOT/tests/scripts/holyc_fmt_paths.sh"
MODE=write
if [[ "${1:-}" == "--check" ]]; then
  MODE=check
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

if [[ ! -x "$BIN" ]]; then
  echo "error: missing $BIN (run make / make holyc-riscv)" >&2
  exit 1
fi
if [[ ! -f "$PATHS_SCRIPT" ]]; then
  echo "error: missing $PATHS_SCRIPT" >&2
  exit 1
fi

TMP="${TMPDIR:-/tmp}/holyc_fmt_$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

LIST="$TMP/list"
bash "$PATHS_SCRIPT" >"$LIST"
if [[ ! -s "$LIST" ]]; then
  echo "error: holyc_fmt_paths.sh produced no files" >&2
  exit 1
fi

fail=0
changed=0
ok=0
need=0

while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  abs="$ROOT/$f"
  if [[ ! -f "$abs" ]]; then
    echo "MISSING $f" >&2
    fail=1
    continue
  fi
  out="$TMP/out"
  err="$TMP/err"
  : >"$err"
  if ! "$BIN" --fmt --stdout "$abs" >"$out" 2>"$err"; then
    echo "FAIL $f (formatter error)" >&2
    if [[ -s "$err" ]]; then
      cat "$err" >&2
    fi
    fail=1
    continue
  fi
  if grep -q 'Fmt failed' "$err" 2>/dev/null; then
    echo "FAIL $f (formatter rejected)" >&2
    cat "$err" >&2
    fail=1
    continue
  fi
  # Second pass must match (gofmt-style idempotency).
  out2="$TMP/out2"
  if ! "$BIN" --fmt --stdout "$out" >"$out2" 2>"$err"; then
    echo "FAIL $f (formatter error on 2nd pass)" >&2
    fail=1
    continue
  fi
  if ! cmp -s "$out" "$out2"; then
    echo "FAIL $f (fmt not idempotent)" >&2
    fail=1
    continue
  fi
  if cmp -s "$abs" "$out"; then
    ok=$((ok + 1))
    continue
  fi
  if [[ "$MODE" == "check" ]]; then
    echo "$f"
    need=$((need + 1))
    fail=1
  else
    # Prefer compiler in-place write; fall back to cp. On macOS, uchg blocks both.
    if ! "$BIN" --fmt "$abs" >/dev/null 2>"$err"; then
      if [[ "$(uname -s)" == "Darwin" ]] && ls -lO "$abs" 2>/dev/null | grep -q ' uchg '; then
        chflags nouchg "$abs" 2>/dev/null || true
        if "$BIN" --fmt "$abs" >/dev/null 2>"$err"; then
          echo "fmt $f (cleared uchg)"
          changed=$((changed + 1))
          continue
        fi
      fi
      if cp "$out" "$abs" 2>"$err"; then
        echo "fmt $f"
        changed=$((changed + 1))
      else
        echo "FAIL $f (cannot write; uchg/locked?)" >&2
        cat "$err" >&2 || true
        fail=1
      fi
    else
      echo "fmt $f"
      changed=$((changed + 1))
    fi
  fi
done <"$LIST"

if [[ "$MODE" == "check" ]]; then
  if [[ "$fail" -ne 0 ]]; then
    echo "fmt-check: $need file(s) need formatting (run: make fmt)" >&2
    exit 1
  fi
  echo "✓ fmt-check ($ok files)"
  exit 0
fi

if [[ "$fail" -ne 0 ]]; then
  echo "fmt: FAILED" >&2
  exit 1
fi
echo "✓ fmt ($changed rewritten, $ok already clean)"
