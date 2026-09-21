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

# 5. a default argument inside a control header. The pushed string that carries default-argument
# text used to leak its brackets into the calling file, so `if (Blink || x)` -- Blink being a
# bare call to a function with a default -- lost the header's bracket tracking, the newline after
# `)` ended the `if` as an empty statement, and the `else` under it was orphaned. Found in
# tos/Apps/Psalmody/PsalmodyDraw.HC:65. Must compile with the rule ON, and be identical to OFF.
if ! HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_defarg.hc" -o "$T/defarg_on.bin" >"$T/defarg.log" 2>&1; then
  echo "FAIL newline-semi -- a default argument in a control header does not compile" >&2
  sed 's/^/  /' "$T/defarg.log" >&2
  fail=1
else
  HOLYC_NL_SEMI=0 HOLYC_INCLUDE_ROOT="$ROOT" "$COMPILER" "$CASES/newline_semi_defarg.hc" -o "$T/defarg_off.bin" >/dev/null 2>&1
  if ! cmp -s "$T/defarg_on.bin" "$T/defarg_off.bin"; then
    echo "FAIL newline-semi -- the rule changed code around a default argument" >&2
    fail=1
  fi
fi

[ "$fail" -ne 0 ] && exit 1
echo "Newline-semi smoke: OK (on by default; the two spellings compile byte-identical; default args safe)"
