#!/bin/bash
# Compile every TempleOS .HC file under the given dirs with holyc-riscv and tally the outcome:
# how far the compiler is from accepting the tree. Usage: coverage_templeos.sh [dir...]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOLYC="$ROOT/holyc-riscv"
[ -x "$HOLYC" ] || make -C "$ROOT" holyc-riscv >/dev/null
# Project-mode builds first (how TempleOS actually compiles): all errors, tallied.
export HOLYC_INCLUDE_ROOT="$ROOT" HOLYC_ALL_ERRORS=1
for prj in Kernel/Kernel_RV.PRJ Compiler/Compiler_RV.PRJ Compiler/Compiler.PRJ Adam/MakeAdam_RV.PRJ Kernel/Kernel.PRJ Adam/MakeAdam.HC; do
  [ -f "$ROOT/$prj" ] || continue
  out="$(cd "$ROOT" && timeout 120 "$HOLYC" "$prj" -o /dev/null 2>&1 >/dev/null)"
  n="$(echo "$out" | grep -o '([0-9]* error' | grep -o '[0-9]*')"
  echo "== project $prj: ${n:-0} error(s) =="
  echo "$out" | grep -E '^  [^ ]' | sed 's/^  [^:]*:[0-9]*: //' | sort | uniq -c | sort -rn | head -8
done
echo
dirs=("$@"); [ ${#dirs[@]} -eq 0 ] && dirs=(Kernel Adam Compiler Demo tos/Apps)
total=0; ok=0
tally="$(mktemp)"; trap 'rm -f "$tally"' EXIT
for d in "${dirs[@]}"; do
  while IFS= read -r f; do
    total=$((total + 1))
    out="$(cd "$ROOT" && timeout 10 "$HOLYC" "$f" -o /dev/null 2>&1)"
    rc=$?
    if [ $rc -eq 0 ]; then ok=$((ok + 1)); echo "OK   $f"; continue; fi
    msg="$(echo "$out" | grep -m1 -o 'Error: .*' | cut -c8-80)"
    [ -z "$msg" ] && msg="(exit $rc, no message)"
    echo "FAIL $f — $msg"
    echo "$msg" >>"$tally"
  done < <(cd "$ROOT" && find "$d" -name '*.HC' | sort)
done
echo
echo "== $ok / $total compile =="
echo "== first-error tally =="
sort "$tally" | uniq -c | sort -rn | head -25
