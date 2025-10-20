#!/bin/bash
PASS=0; FAIL=0; TOTAL=0
for file in $(find Demo Adam Kernel Apps -name "*.HC" -type f 2>/dev/null); do
  TOTAL=$((TOTAL + 1))
  [ $((TOTAL % 50)) -eq 0 ] && echo "$TOTAL files tested..."
  timeout 1s ./holyc-riscv "$file" -o /dev/null 2>/dev/null && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))
done
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║          REAL TEMPLEOS COMPILATION RESULTS                            ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Total files: $TOTAL"
echo "PASSED:      $PASS"
echo "FAILED:      $FAIL"
echo ""
echo "SUCCESS RATE: $((PASS * 100 / TOTAL))%"
echo ""
