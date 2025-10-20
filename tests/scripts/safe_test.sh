#!/bin/bash
echo "Testing 10 random files with strict timeout..."
PASS=0; FAIL=0

for file in Demo/Carry.HC Demo/RadixSort.HC Demo/NullCase.HC Demo/ClassMeta.HC Demo/MultiCore/Palindrome.HC; do
  printf "%-40s " "$file"
  if timeout 1s ./holyc-riscv "$file" -o /tmp/t.bin 2>/dev/null; then
    s=$(stat -f%z /tmp/t.bin 2>/dev/null || stat -c%s /tmp/t.bin 2>/dev/null)
    [ "$s" -gt 0 ] && echo "✅ $s bytes" && PASS=$((PASS+1)) || echo "⚠️ 0 bytes"
  else
    echo "❌ FAIL"; FAIL=$((FAIL+1))
  fi
done
echo "PASSED: $PASS/5"
