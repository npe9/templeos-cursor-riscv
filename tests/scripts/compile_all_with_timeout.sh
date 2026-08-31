#!/bin/bash
# Compile all TempleOS .HC files with timeout

set +e

PASS=0
FAIL=0
TIMEOUT=0
mkdir -p build/all_tests

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║     COMPILING ALL TEMPLEOS .HC FILES (WITH TIMEOUT)                   ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Find all .HC files (exclude Compiler/)
HC_FILES=$(find Demo Adam Kernel tos/Apps -name "*.HC" -type f 2>/dev/null | sort)
TOTAL=$(echo "$HC_FILES" | wc -l | tr -d ' ')

echo "Found $TOTAL HolyC files"
echo "Compiling with 2-second timeout per file..."
echo ""

> build/all_tests/pass.log
> build/all_tests/fail.log
> build/all_tests/timeout.log
> build/all_tests/errors.log

COUNT=0
for file in $HC_FILES; do
  COUNT=$((COUNT + 1))
  
  # Show progress every 20 files
  if [ $((COUNT % 20)) -eq 0 ]; then
    echo "Progress: $COUNT/$TOTAL (Pass: $PASS, Fail: $FAIL, Timeout: $TIMEOUT)"
  fi
  
  # Try to compile with timeout
  timeout 2s ./holyc-riscv "$file" -o /dev/null 2>&1 > /tmp/compile_result.txt
  EXIT_CODE=$?
  
  if [ $EXIT_CODE -eq 0 ]; then
    # Success
    PASS=$((PASS + 1))
    echo "$file" >> build/all_tests/pass.log
  elif [ $EXIT_CODE -eq 124 ]; then
    # Timeout
    TIMEOUT=$((TIMEOUT + 1))
    echo "$file" >> build/all_tests/timeout.log
  else
    # Failed
    FAIL=$((FAIL + 1))
    echo "$file" >> build/all_tests/fail.log
    grep "Error" /tmp/compile_result.txt | head -1 >> build/all_tests/errors.log
  fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "FINAL RESULTS"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "Total files:  $TOTAL"
echo "PASSED:       $PASS"
echo "FAILED:       $FAIL"
echo "TIMEOUT:      $TIMEOUT"
echo ""

if [ $TOTAL -gt 0 ]; then
  PERCENT=$((PASS * 100 / TOTAL))
  echo "Success rate: $PERCENT%"
else
  echo "Success rate: 0%"
fi
echo ""

if [ $PASS -gt 0 ]; then
  echo "Files that PASSED:"
  cat build/all_tests/pass.log | head -20
  echo ""
fi

if [ $FAIL -gt 0 ]; then
  echo "Top 10 files that FAILED:"
  head -10 build/all_tests/fail.log
  echo ""
  
  echo "Most common errors:"
  cat build/all_tests/errors.log | sort | uniq -c | sort -rn | head -10
  echo ""
fi

if [ $TIMEOUT -gt 0 ]; then
  echo "Files that TIMED OUT (infinite loop in parser?):"
  head -10 build/all_tests/timeout.log
  echo ""
fi

echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "HONEST TRUTH:"
echo "  The compiler can compile $PASS out of $TOTAL TempleOS files."
echo "  That's $PERCENT% of the source tree."
echo ""
echo "═══════════════════════════════════════════════════════════════════════"


