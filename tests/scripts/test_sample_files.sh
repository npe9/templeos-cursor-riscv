#!/bin/bash
PASS=0
FAIL=0
# Test just 50 random files with timeout
FILES=$(find Demo Adam Kernel -name "*.HC" -type f 2>/dev/null | shuf | head -50)
for file in $FILES; do
  if timeout 2s ./holyc-riscv "$file" -o /dev/null 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done
echo "Sample of 50 files:"
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
echo "  Rate: $((PASS * 100 / 50))%"
