#!/bin/bash
# Names that must be RESOLVED INSIDE the kernel blob, not left to the C runtime.
#
# Why this exists: a dropped asm{} block does not fail a build. The symbol simply becomes an
# unresolved host-import, and every gate that links tests/exec/harness/oracle_out.c fills it from
# bootstrap/holy_rt_names.h. `Abs` was in that state — Kernel/KUtilsRV.HC's block used the `fabsd`
# PSEUDO-instruction, the assembler rejected the block, and the C Abs answered every test
# correctly. Behaviour cannot see this. The blob's HOFYIMP1 trailer can.
#
# This list is deliberately short: only names proven to have been silently substituted. Adding a
# name that a multi-module link resolves across units would make the gate fail for no reason.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MUST_BE_IN_BLOB=(Abs Sqr Floor Trunc Round)

SRC="$ROOT/tests/exec/cases/e_kernel_fabs.hc"
OUT="$ROOT/build/exec/blob_imports_check.bin"
mkdir -p "$ROOT/build/exec"
[ -x "$ROOT/holyc-riscv" ] || make -C "$ROOT" holyc-riscv >/dev/null

if ! HOLYC_INCLUDE_ROOT="$ROOT" "$ROOT/holyc-riscv" "$SRC" -o "$OUT" >/dev/null 2>&1; then
  echo "FAIL blob-imports — $SRC did not compile" >&2
  exit 1
fi

if ! python3 "$ROOT/tools/blob_imports.py" "$OUT" --absent "${MUST_BE_IN_BLOB[@]}"; then
  echo "" >&2
  echo "Each name above is CALLED by the kernel and PROVIDED by no unit in the blob. Usually the" >&2
  echo "asm{} block that defines it was dropped: HOLYC_ASM_SKIPS=1 holyc-riscv <src> names the file" >&2
  echo "and line. Full inventory: tools/blob_imports.py $OUT" >&2
  exit 1
fi

echo "blob-imports: ${#MUST_BE_IN_BLOB[@]} name(s) resolved inside the blob  OK"
