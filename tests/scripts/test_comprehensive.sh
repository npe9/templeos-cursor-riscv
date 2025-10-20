#!/bin/bash

# Test on comprehensive set of TempleOS files
files=(
  Demo/Carry.HC
  Demo/RadixSort.HC
  Demo/NullCase.HC
  Demo/MultiCore/Palindrome.HC
  Demo/Exceptions.HC
  Demo/DateTime.HC
  Demo/GlblVars.HC
  Demo/MemDemo.HC
  Demo/Print.HC
  Demo/Define.HC
  Demo/LastClass.HC
  Demo/SubIntAccess.HC
  Demo/ClassMeta.HC
  Demo/Directives.HC
  Demo/ExtChars.HC
  Demo/KeyBitMap.HC
  Demo/MagicPairs.HC
  Demo/OnceDemo.HC
  Demo/ParenWarn.HC
  Demo/Prompt.HC
  Demo/RandDemo.HC
  Demo/StkGrow.HC
  Demo/SubSwitch.HC
  Adam/ADefine.HC
  Adam/AHash.HC
  Adam/AMath.HC
  Adam/AMem.HC
)

passed=0
failed=0
failed_files=""

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    if timeout 2s ./holyc-riscv "$file" -o "/tmp/test_$$.bin" 2>&1 | grep -q "Compiled successfully"; then
      ((passed++))
    else
      ((failed++))
      failed_files="$failed_files\n  $file"
    fi
  fi
done

echo "═══════════════════════════════════════"
echo "COMPREHENSIVE TEST RESULTS"
echo "═══════════════════════════════════════"
echo "Passed: $passed"
echo "Failed: $failed"
echo "Success Rate: $((passed * 100 / (passed + failed)))%"
echo ""
if [ $failed -gt 0 ]; then
  echo "Failed files:$failed_files"
fi
