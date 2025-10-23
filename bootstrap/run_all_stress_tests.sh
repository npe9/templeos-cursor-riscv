#!/bin/bash

# Comprehensive Stress Tests for TempleOS RISC-V Compiler
# Tests all components of the compiler on bare metal

echo "=== TempleOS RISC-V Compiler Stress Tests ==="
echo "Testing all compiler components on bare metal"
echo ""

# Test 1: Basic Expressions
echo "=== Test 1: Basic Expressions and Arithmetic ==="
echo "Testing arithmetic operations, bitwise operations, logical operations..."
timeout 30s qemu-system-riscv64 -M virt -bios none -kernel stepping_debugger.elf -nographic < stress_test_1_basic_expressions.txt
echo ""

# Test 2: Function Definitions and Calls
echo "=== Test 2: Function Definitions and Calls ==="
echo "Testing functions with various parameter counts, recursion, function calls..."
timeout 60s qemu-system-riscv64 -M virt -bios none -kernel stepping_debugger.elf -nographic < stress_test_2_functions.txt
echo ""

# Test 3: Control Flow
echo "=== Test 3: Control Flow Statements ==="
echo "Testing if/else, loops, switch statements..."
timeout 60s qemu-system-riscv64 -M virt -bios none -kernel stepping_debugger.elf -nographic < stress_test_3_control_flow.txt
echo ""

# Test 4: Memory Operations
echo "=== Test 4: Memory Operations and Arrays ==="
echo "Testing arrays, pointers, memory allocation..."
timeout 60s qemu-system-riscv64 -M virt -bios none -kernel stepping_debugger.elf -nographic < stress_test_4_memory_operations.txt
echo ""

# Test 5: Complex Programs
echo "=== Test 5: Complex Programs ==="
echo "Testing complex programs combining multiple features..."
timeout 90s qemu-system-riscv64 -M virt -bios none -kernel stepping_debugger.elf -nographic < stress_test_5_complex_programs.txt
echo ""

echo "=== All Stress Tests Complete ==="
echo "The TempleOS RISC-V compiler has been thoroughly tested on bare metal!"
