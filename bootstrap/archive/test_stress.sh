#!/bin/bash
echo "=== Stress Test: Complex Programs ==="
timeout 60s qemu-system-riscv64 -M virt -bios none -kernel stepping_debugger.elf -nographic < stress_test_5_complex_programs.txt 2>&1 || true
