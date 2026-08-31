#!/bin/bash

# Test script for the REPL
echo "Testing TempleOS RISC-V REPL..."

# Create a test input file
cat > test_input.txt << EOF
42;
1+2+3;
5*10;
100/4;
quit
EOF

echo "Running REPL with test input..."
timeout 15s qemu-system-riscv64 -M virt -bios none -kernel repl.elf -nographic < test_input.txt > test_output.txt 2>&1

echo "REPL output:"
cat test_output.txt

echo ""
echo "Test completed."
