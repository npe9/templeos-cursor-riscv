#!/bin/bash
PASS=0; FAIL=0
for file in $(find Demo Adam Kernel Apps -name "*.HC" -type f 2>/dev/null); do
  timeout 2s ./holyc-riscv "$file" -o /dev/null 2>/dev/null && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))
done
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
echo "RATE: $((PASS * 100 / (PASS + FAIL)))%"
