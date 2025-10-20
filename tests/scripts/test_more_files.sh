#!/bin/bash

# Test on more TempleOS files
files=(
  "Demo/Exceptions.HC"
  "Demo/DateTime.HC"
  "Demo/GlblVars.HC"
  "Demo/MemDemo.HC"
  "Demo/Print.HC"
  "Demo/Define.HC"
  "Demo/LastClass.HC"
  "Demo/SubIntAccess.HC"
  "Demo/Templates/ClassMeta.HC"
  "Adam/ADefine.HC"
)

passed=0
failed=0

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo -n "Testing $file ... "
    if timeout 2s ./holyc-riscv "$file" -o "/tmp/test_$$.bin" 2>&1 | grep -q "Compiled successfully"; then
      echo "✅ PASS"
      ((passed++))
    else
      echo "❌ FAIL"
      timeout 2s ./holyc-riscv "$file" -o "/tmp/test_$$.bin" 2>&1 | head -3
      ((failed++))
    fi
  fi
done

echo ""
echo "Results: $passed passed, $failed failed"
