#!/bin/bash
# Test compiling actual TempleOS files

echo "Testing TempleOS source files..."
echo ""

for file in Demo/NullCase.HC Demo/OnceDemo.HC Demo/ParenWarn.HC Demo/Print.HC; do
    echo "=== Testing: $file ==="
    timeout 5 ./cicl-riscv "$file" 2>&1 | head -20
    echo ""
done
