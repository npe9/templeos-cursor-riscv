#!/bin/bash
set +e
PASS=0
FAIL=0
TIMEOUT=0

for file in $(find Demo Adam Kernel Apps -name "*.HC" -type f 2>/dev/null | sort); do
  if timeout 1s ./holyc-riscv "$file" -o /dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    EXIT=$?
    if [ $EXIT -eq 124 ]; then
      TIMEOUT=$((TIMEOUT + 1))
    else
      FAIL=$((FAIL + 1))
    fi
  fi
done

TOTAL=$((PASS + FAIL + TIMEOUT))
echo "═══════════════════════════════════════════════════════════════════════"
echo "REAL RESULTS - ALL TEMPLEOS SOURCE FILES"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "Total files tested: $TOTAL"
echo "PASSED:             $PASS"
echo "FAILED:             $FAIL"
echo "TIMEOUT:            $TIMEOUT"
echo ""
[ $TOTAL -gt 0 ] && echo "SUCCESS RATE: $((PASS * 100 / TOTAL))%"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
