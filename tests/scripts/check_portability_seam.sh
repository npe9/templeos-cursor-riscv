#!/bin/bash
# The linked image's unresolved-import set must equal tests/portability_seam.tsv, exactly.
#
# A name appearing here means the image calls it and no HolyC unit defines it. That is sometimes
# the design (the platform layer) and sometimes a silent hole (a dropped asm{} block, or a unit
# excluded for collisions while its callers stayed in). Either way it must be a DECISION, so the
# set is pinned: a new name fails, and implementing one fails too, with a re-pin instruction.
#
# Uses comm, not a `while read` inside a pipeline — that pattern cannot set the parent's exit flag
# and once printed FAIL while exiting 0.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BLOB="${SEAM_BLOB:-$ROOT/build/aot/win/win_tos.blob.bin}"
PIN="$ROOT/tests/portability_seam.tsv"

if [ ! -f "$BLOB" ]; then
  echo "SKIP portability-seam — $BLOB not built (make build/aot/win/win_tos.blob.bin)" >&2
  exit 0
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
python3 "$ROOT/tools/blob_imports.py" "$BLOB" | sort -u > "$T/got"
grep -v '^#' "$PIN" | grep . | cut -f1 | sort -u > "$T/want"

new="$(comm -23 "$T/got" "$T/want")"
gone="$(comm -13 "$T/got" "$T/want")"
rc=0
if [ -n "$new" ]; then
  echo "FAIL portability-seam — the image now calls names nothing defines, and they are not pinned:" >&2
  printf '  %s\n' $new >&2
  echo "  Either implement them, or add a row to $PIN saying which category they are." >&2
  rc=1
fi
if [ -n "$gone" ]; then
  echo "FAIL portability-seam — pinned names are no longer unresolved (good — re-pin):" >&2
  printf '  %s\n' $gone >&2
  echo "  Remove those rows from $PIN." >&2
  rc=1
fi
[ $rc -eq 0 ] && echo "portability-seam: $(wc -l < "$T/got" | tr -d ' ') unresolved import(s), all pinned  OK"
exit $rc
