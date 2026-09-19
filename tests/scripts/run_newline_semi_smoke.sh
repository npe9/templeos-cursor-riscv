#!/bin/bash
# The BCPL rule: a newline ends a statement that has plainly finished (host/lexer.c,
# NewlineEndsStatement). Three properties, and the third is the one that matters:
#
#   1. ON by default, and a source file still compiles exactly as it did before it existed —
#      the whole kernel image is byte-identical with it, which is what earned it the default.
#   2. The rule does something: the semicolon-free program fails when it is turned OFF.
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

# 2. the same program without semicolons must FAIL when the rule is turned OFF...
if HOLYC_NL_SEMI=0 HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_bare.hc" -o "$T/bare_off.bin" >/dev/null 2>&1; then
  echo "FAIL newline-semi — the semicolon-free version compiled with the rule OFF, so the" >&2
  echo "     rule is not what makes it work and this test proves nothing" >&2
  fail=1
fi

# ...and compile with it on, which is the default
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_bare.hc" -o "$T/bare_on.bin" >"$T/bare.log" 2>&1; then
  echo "FAIL newline-semi — the semicolon-free version does not compile" >&2
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

# 4. and turning it OFF does not change a file that has its semicolons already
if [ -f "$T/semis.bin" ]; then
  HOLYC_NL_SEMI=0 HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_semis.hc" -o "$T/semis_off.bin" >/dev/null 2>&1
  if ! cmp -s "$T/semis.bin" "$T/semis_off.bin"; then
    echo "FAIL newline-semi — the rule changed a file that needs nothing from it" >&2
    fail=1
  fi
fi

[ "$fail" -ne 0 ] && exit 1
echo "Newline-semi smoke: OK (on by default; the two spellings compile byte-identical)"
