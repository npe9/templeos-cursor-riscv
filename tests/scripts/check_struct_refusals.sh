#!/bin/bash
# The compiler must REFUSE what it cannot compile correctly, and must not over-refuse.
#
# Both halves matter. A diagnostic nobody checks gets deleted by the next person who finds it
# inconvenient; a diagnostic that is too broad quietly blocks working code. See
# docs/HOLYC_STRUCT_LIMITS.md for what is actually broken and why the boundary sits at 8 bytes.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPILER="$ROOT/holyc-riscv"
D="$ROOT/tests/holyc/refused"
rc=0

if "$COMPILER" "$D/struct_return_too_big.hc" -o /dev/null >/dev/null 2>&1; then
  echo "FAIL struct-refusals — a >8-byte class return was ACCEPTED; it miscompiles silently" >&2
  rc=1
else
  msg=$("$COMPILER" "$D/struct_return_too_big.hc" -o /dev/null 2>&1 | head -1)
  case "$msg" in
    *"by value needs"*) ;;
    *) echo "FAIL struct-refusals — refused, but not with the expected diagnostic: $msg" >&2; rc=1 ;;
  esac
fi

if ! "$COMPILER" "$D/struct_return_ok.hc" -o /dev/null >/dev/null 2>&1; then
  echo "FAIL struct-refusals — an 8-byte class return or a pointer return was refused" >&2
  "$COMPILER" "$D/struct_return_ok.hc" -o /dev/null 2>&1 | head -3 | sed 's/^/  /' >&2
  rc=1
fi

# An all-upper-case name at statement start that NOTHING DECLARED is a typo, not an opcode with
# an operand: `FOO++;` must be diagnosed and not silently skipped as a bare x86 instruction. This
# is the only gate that fails when the operator list in parser.c's x86-statement branch is removed
# on its own -- the symbol-table check beside it cannot fire on a name no one declared, and the
# exec case e_upper_name_stmt.hc passes with either half of the fix present. docs/HOLYC_STRUCT_LIMITS.md #14.
if "$COMPILER" "$D/upper_name_undeclared.hc" -o /dev/null >/dev/null 2>&1; then
  echo "FAIL struct-refusals — a bare \`FOO++;\` on an undeclared name was ACCEPTED; it is being" >&2
  echo "  taken for an x86 instruction and the whole line discarded" >&2
  rc=1
fi

[ "$rc" = 0 ] && echo "struct-refusals: >8-byte class return refused, <=8-byte and pointer returns accepted, undeclared ALL-CAPS statement refused"
exit $rc
