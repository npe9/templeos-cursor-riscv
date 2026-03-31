#!/bin/bash
# Print suggested manifest_templeos_tree.tsv lines for .HC files under a directory.
# Usage: ./tests/scripts/gen_compliance_candidates.sh Demo 8
# Review output before appending — not all “compiles” implies semantic parity.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
DIR="${1:-Demo}"
MIN="${2:-8}"
HOLYC="$ROOT/holyc-riscv"
[ -x "$HOLYC" ] || make -C "$ROOT" holyc-riscv >/dev/null

find "$DIR" -name '*.HC' -type f 2>/dev/null | sort | while read -r f; do
  out="$("$HOLYC" "$f" -o /tmp/hccand$$.bin 2>&1)" || continue
  sz="$(echo "$out" | sed -n 's/.*Code size: \([0-9][0-9]*\).*/\1/p' | tail -1)"
  [ -n "$sz" ] || sz=0
  if [ "$sz" -ge "$MIN" ]; then
    echo "$f	demo	pass	$MIN"
  fi
done
