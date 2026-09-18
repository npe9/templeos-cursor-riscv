#!/bin/bash
# The BCPL rule: a newline ends a statement that has plainly finished (host/lexer.c,
# NewlineEndsStatement). Three properties, and the third is the one that matters:
#
#   1. OFF by default — a source file compiles exactly as it did before the rule existed.
#   2. The rule does something: the semicolon-free program fails without it.
#   3. The rule inserts exactly the semicolons a person would: the same program written both
#      ways compiles to IDENTICAL BYTES.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPILER="$ROOT/holyc-riscv"
CASES="$ROOT/tests/exec/cases"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

make -C "$ROOT" holyc-riscv >/dev/null || { echo "FAIL newline-semi — compiler build" >&2; exit 1; }
fail=0

# 1. the ordinary file, rule off
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_semis.hc" -o "$T/semis.bin" >"$T/semis.log" 2>&1; then
  echo "FAIL newline-semi — the semicolon version does not compile" >&2
  sed 's/^/  /' "$T/semis.log" >&2
  fail=1
fi

# 2. the same program without semicolons must FAIL with the rule off...
if HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_bare.hc" -o "$T/bare_off.bin" >/dev/null 2>&1; then
  echo "FAIL newline-semi — the semicolon-free version compiled with the rule OFF, so the" >&2
  echo "     flag is not what makes it work and this test proves nothing" >&2
  fail=1
fi

# ...and compile with it on
if ! HOLYC_NL_SEMI=1 HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_bare.hc" -o "$T/bare_on.bin" >"$T/bare.log" 2>&1; then
  echo "FAIL newline-semi — the semicolon-free version does not compile with HOLYC_NL_SEMI=1" >&2
  sed 's/^/  /' "$T/bare.log" >&2
  fail=1
fi

# 3. identical bytes: the rule put the semicolons exactly where the hand-written ones are
if [ -f "$T/semis.bin" ] && [ -f "$T/bare_on.bin" ]; then
  if ! cmp -s "$T/semis.bin" "$T/bare_on.bin"; then
    echo "FAIL newline-semi — the two spellings compiled to DIFFERENT code" >&2
    ls -l "$T/semis.bin" "$T/bare_on.bin" | sed 's/^/  /' >&2
    fail=1
  fi
fi

# 4. and with the rule ON, a file that already has its semicolons is unchanged by it
if [ -f "$T/semis.bin" ]; then
  HOLYC_NL_SEMI=1 HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_semis.hc" -o "$T/semis_on.bin" >/dev/null 2>&1
  if ! cmp -s "$T/semis.bin" "$T/semis_on.bin"; then
    echo "FAIL newline-semi — turning the rule on changed a file that needs nothing from it" >&2
    fail=1
  fi
fi

[ "$fail" -ne 0 ] && exit 1
echo "Newline-semi smoke: OK (off by default; on, the two spellings compile byte-identical)"
