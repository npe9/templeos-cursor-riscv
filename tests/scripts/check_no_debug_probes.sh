#!/bin/bash
# Fail if a debug scratch-RAM probe was left in guest/kernel HolyC sources.
#
# Why this exists: these probes are the standard way to trace the AOT'd guest compiler, whose
# Print() does not reach the console. They are written as a cast-store through a literal
# address, e.g. `*(0x87F00C00)(I64 *) = 0xAA;`. Twice in one session a probe survived a
# backup/restore cycle and was present in a build that passed every gate — a debug write into
# the stack-base region, shipped. Nothing in the tree legitimately uses that idiom (MMIO goes
# through a named pointer, e.g. `U8 *uart = 0x10000000;`), so a grep is a sound check.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PAT='\*\(0x[0-9A-Fa-f]{6,}\)\((I64|U64|I32|U32|I8|U8|F64|Bool) \*\)'
HITS=$(grep -rnE "$PAT" Compiler/ Kernel/ Adam/ 2>/dev/null || true)

if [ -n "$HITS" ]; then
  echo "FAIL: debug scratch probe(s) left in source:"
  echo "$HITS"
  echo ""
  echo "Remove them before committing. If a literal-address store is genuinely intended,"
  echo "assign through a named pointer instead so it reads as real code."
  exit 1
fi
echo "probe-lint: OK (no debug scratch probes in Compiler/ Kernel/ Adam/)"
