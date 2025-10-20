#!/bin/bash
echo "═══════════════════════════════════════════════════════════"
echo "FINAL INTEGRATION TEST - TempleOS Source Compilation"
echo "═══════════════════════════════════════════════════════════"
echo ""

PASS=0
FAIL=0
TOTAL=0

# Test a variety of TempleOS files
TEST_FILES=(
  "Demo/Carry.HC"
  "Demo/LastClass.HC"
  "Demo/RadixSort.HC"
  "Demo/MultiCore/Palindrome.HC"
  "Demo/MultiCore/MPAdd.HC"
  "Demo/AcctExample/HomeWrappers.HC"
  "Adam/ADefine.HC"
  "Adam/AMath.HC"
  "Apps/Span/Span.HC"
)

for file in "${TEST_FILES[@]}"; do
  if [ -f "$file" ]; then
    TOTAL=$((TOTAL + 1))
    printf "Testing %-50s " "$file"
    if timeout 2s ./holyc-riscv "$file" -o /tmp/test.bin 2>/dev/null; then
      size=$(stat -f%z /tmp/test.bin 2>/dev/null || stat -c%s /tmp/test.bin 2>/dev/null)
      if [ "$size" -gt 0 ]; then
        echo "✅ PASS ($size bytes)"
        PASS=$((PASS + 1))
      else
        echo "⚠️  SKIP (0 bytes)"
        FAIL=$((FAIL + 1))
      fi
    else
      echo "❌ FAIL"
      FAIL=$((FAIL + 1))
    fi
  fi
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "RESULTS:"
echo "  Total:  $TOTAL"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Rate:   $((PASS * 100 / TOTAL))%"
echo "═══════════════════════════════════════════════════════════"
