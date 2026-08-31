#!/bin/bash

# Test script for the simple REPL
echo "Testing Simple TempleOS RISC-V REPL..."

# Create a test input file
cat > test_simple_input.txt << EOF
42;
1+2+3;
quit
EOF

echo "Running Simple REPL with test input..."
timeout 15s qemu-system-riscv64 -M virt -bios none -kernel simple_repl.elf -nographic < test_simple_input.txt > test_simple_output.txt 2>&1

echo "Simple REPL output:"
cat test_simple_output.txt

echo ""
echo "Simple REPL test completed."
