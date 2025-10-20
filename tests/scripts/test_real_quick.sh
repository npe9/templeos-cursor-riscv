#!/bin/bash
PASS=0
FAIL=0
for file in Demo/*.HC Adam/*.HC Kernel/*.HC; do
  [ -f "$file" ] || continue
  if timeout 1s ./holyc-riscv "$file" -o /dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "✅ $file"
  else
    FAIL=$((FAIL + 1))
  fi
done
echo ""
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
TOTAL=$((PASS + FAIL))
[ $TOTAL -gt 0 ] && echo "Rate: $((PASS * 100 / TOTAL))%"
