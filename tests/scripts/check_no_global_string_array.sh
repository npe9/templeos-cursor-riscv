#!/bin/bash
# NO TRANSLATED SOURCE MAY DECLARE A FILE-SCOPE CHAR ARRAY INITIALISED FROM A STRING LITERAL.
#
# docs/HOLYC_STRUCT_LIMITS.md #19: the compiler accepts four spellings of that construct and
# miscompiles three of them, with no diagnostic. The two FILE-SCOPE spellings are the dangerous
# ones -- one writes the string literal's ADDRESS into the array bytes, the other leaves the
# array all zeros -- and they are also the natural translation of NASA's
#
#     static const char FRAGMENT_TAG[] = "<<FRAGMENT>> ";
#
# so they are the ones that will be reintroduced. The working substitute is a `U8 *` to the
# literal plus the length written out as a constant, which is what cfe_es_syslog.HC does.
#
# The LOCAL unbranched form is correct and is deliberately NOT flagged; the pattern below is
# anchored at column 0, so an indented declaration inside a function body does not match.
# tests/exec/cases/e_char_array_string_init.hc is the measurement this gate protects.
#
# This gate exists because the documentation alone could not have found a live instance -- the
# tree was grepped once, by hand, and came back empty. An empty hand-grep is a fact about one
# afternoon; this is the same fact asserted every build.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
rc=0

# U8 NAME[...] = "..."  or  = {"..."}  at column 0, in any translated cFS source.
PAT='^(U8|I8)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\[[^]]*\][[:space:]]*=[[:space:]]*\{?[[:space:]]*"'

hits=$(grep -rnE "$PAT" "$ROOT/Kernel/Cfs" 2>/dev/null)
if [ -n "$hits" ]; then
  echo "FAIL no-global-string-array — a file-scope char array is initialised from a string literal;" >&2
  echo "     the compiler miscompiles that silently (docs/HOLYC_STRUCT_LIMITS.md #19)." >&2
  echo "     Use a 'U8 *' to the literal and write the length out, as cfe_es_syslog.HC does." >&2
  printf '  %s\n' "$hits" >&2
  rc=1
fi

# NEGATIVE CONTROL: the gate must fail on a planted instance, or it is asserting nothing.
# This is the rule from docs -- a gate that cannot be made to fail on purpose is not a gate.
tmp="$ROOT/Kernel/Cfs/.check_global_string_array_control.HC"
printf 'U8 PlantedTag[20] = "SHOULD FAIL";\n' > "$tmp"
if ! grep -rnE "$PAT" "$ROOT/Kernel/Cfs" >/dev/null 2>&1; then
  echo "FAIL no-global-string-array — the gate did NOT flag a planted instance; the pattern is dead" >&2
  rc=1
fi
rm -f "$tmp"

if [ $rc -eq 0 ]; then
  echo "no-global-string-array: OK (no file-scope string-initialised arrays; pattern verified against a planted one)"
fi
exit $rc
