#!/bin/bash

# Test files that are pure language tests (no runtime dependencies)
files=(
  "Demo/Carry.HC"
  "Demo/RadixSort.HC"
  "Demo/NullCase.HC"
  "Demo/DateTime.HC"
  "Demo/Print.HC"
  "Demo/Define.HC"
  "Demo/SubIntAccess.HC"
  "Demo/SubSwitch.HC"
  "Demo/Directives.HC"
  "Demo/ParenWarn.HC"
  "Demo/Prompt.HC"
  "Demo/RandDemo.HC"
  "Demo/StkGrow.HC"
  "Demo/MultiCore/Palindrome.HC"
  "Demo/MultiCore/TreeThroughPut.HC"
  "Demo/Exceptions.HC"
  "Demo/GlblVars.HC"
  "Demo/MemDemo.HC"
  "Demo/LastClass.HC"
  "Adam/ADefine.HC"
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
echo "PURE LANGUAGE TEST RESULTS"
echo "═══════════════════════════════════════"
echo "Passed: $passed"
echo "Failed: $failed"
echo "Success Rate: $((passed * 100 / (passed + failed)))%"
