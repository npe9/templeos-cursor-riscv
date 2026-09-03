#!/usr/bin/env bash
# G7 A3 flip readiness gate (scaffolding only — does NOT change CI dual-run).
# Runs HolyC product honesty targets and prints READY / NOT READY.
# Clear REMAINING_BLOCKERS below only when SELF_HOST.md G7 rows are green or waived.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

# --- G7 checklist (keep in sync with docs/SELF_HOST.md + docs/GAPS.md) ---
# Waived for A3 (not flip blockers): ZMODEM/trzsz (G11), Fmt host rewrite, Demo/*.HC UART batch.
# Remaining blockers — remove a line only when that row is green on HolyC or explicitly waived.
REMAINING_BLOCKERS=(
)

echo "=== G7 A3 flip checklist ==="
echo "Waived (not blockers): ZMODEM/trzsz (DumpFile+9P), Fmt (fmt-test/fmt-check), Demo UART batch (compliance curated six)"
echo "Remaining blockers:"
if [ "${#REMAINING_BLOCKERS[@]}" -eq 0 ]; then
  echo "  (none)"
else
  for b in "${REMAINING_BLOCKERS[@]}"; do
    echo "  - $b"
  done
fi
echo ""
echo "Gates: repl-holyc-smoke + repl-holyc-regression + repl-cmp-smoke"
echo "(bootloader-smoke is also an A3 criterion — run separately before applying the flip draft.)"
echo ""

fail=0
run_gate() {
  local name="$1"
  echo "---- $name ----"
  if make "$name"; then
    echo "OK   $name"
  else
    echo "FAIL $name" >&2
    fail=1
  fi
  echo ""
}

run_gate repl-holyc-smoke
run_gate repl-holyc-regression
run_gate repl-cmp-smoke

echo "=== G7 A3 flip result ==="
if [ "$fail" -ne 0 ]; then
  echo "NOT READY — one or more HolyC gates failed"
  exit 1
fi
if [ "${#REMAINING_BLOCKERS[@]}" -ne 0 ]; then
  echo "NOT READY — gates green locally may still be pending; ${#REMAINING_BLOCKERS[@]} G7 blocker(s) listed above"
  echo "          Clear REMAINING_BLOCKERS in this script only after SELF_HOST G7 rows are green/waived,"
  echo "          then apply docs/A3_FLIP_DRAFT.md (Makefile/CI) in a separate change."
  exit 1
fi

echo "READY — HolyC smoke+regression+repl-cmp green and G7 blocker list empty"
echo "         Next: apply docs/A3_FLIP_DRAFT.md (drop dual-run); do not set SKIP_REPL_LEGACY in CI."
exit 0
