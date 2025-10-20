#!/bin/bash
PASS=0
FAIL=0
ZERO=0
TOTAL=0

echo "Testing all TempleOS .HC files..."
echo ""

for file in $(find Demo Adam Kernel Apps -name "*.HC" -type f 2>/dev/null | head -100); do
  TOTAL=$((TOTAL + 1))
  [ $((TOTAL % 20)) -eq 0 ] && echo "$TOTAL files tested..."
  
  if timeout 1s ./holyc-riscv "$file" -o /tmp/test.bin 2>/dev/null; then
    size=$(stat -f%z /tmp/test.bin 2>/dev/null || stat -c%s /tmp/test.bin 2>/dev/null)
    if [ "$size" -gt 0 ]; then
      PASS=$((PASS + 1))
    else
      ZERO=$((ZERO + 1))
    fi
  else
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     COMPREHENSIVE TEMPLEOS COMPILATION TEST               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Files tested: $TOTAL"
echo "Passed with code: $PASS"
echo "Compiled but empty: $ZERO"
echo "Failed: $FAIL"
echo ""
echo "SUCCESS RATE (with code): $((PASS * 100 / TOTAL))%"
echo "PARSE RATE (no errors):   $(((PASS + ZERO) * 100 / TOTAL))%"
echo ""
