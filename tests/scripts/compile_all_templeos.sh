#!/bin/bash
# Actually compile every .HC file in the TempleOS source tree

set +e  # Don't exit on errors

PASS=0
FAIL=0
mkdir -p build/all_tests

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║     COMPILING EVERY TEMPLEOS .HC FILE - ACTUAL RESULTS               ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Find all .HC files
HC_FILES=$(find . -name "*.HC" -type f | grep -v "Compiler/" | sort)
TOTAL=$(echo "$HC_FILES" | wc -l | tr -d ' ')

echo "Found $TOTAL HolyC files (excluding Compiler/)"
echo "Starting compilation..."
echo ""

> build/all_tests/pass.log
> build/all_tests/fail.log
> build/all_tests/errors.log

COUNT=0
for file in $HC_FILES; do
  COUNT=$((COUNT + 1))
  
  # Show progress every 10 files
  if [ $((COUNT % 10)) -eq 0 ]; then
    echo "Progress: $COUNT/$TOTAL (Pass: $PASS, Fail: $FAIL)"
  fi
  
  # Try to compile
  if ./holyc-riscv "$file" -o /dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "$file" >> build/all_tests/pass.log
  else
    FAIL=$((FAIL + 1))
    echo "$file" >> build/all_tests/fail.log
    ./holyc-riscv "$file" -o /dev/null 2>&1 | grep "Error" | head -1 >> build/all_tests/errors.log
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
echo ""

PERCENT=$((PASS * 100 / TOTAL))
echo "Success rate: $PERCENT%"
echo ""

echo "Top 10 passing files:"
head -10 build/all_tests/pass.log
echo ""

echo "Top 10 failing files:"
head -10 build/all_tests/fail.log
echo ""

echo "Common errors:"
cat build/all_tests/errors.log | sort | uniq -c | sort -rn | head -10
echo ""

echo "═══════════════════════════════════════════════════════════════════════"
