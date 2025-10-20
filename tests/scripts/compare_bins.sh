#!/bin/bash
echo "=== Comparing OLD (working) vs NEW (crashing) ==="
echo ""
echo "OLD (before typed loads fix):"
riscv64-unknown-elf-objdump -D -b binary -m riscv:rv64 bootstrap/plic_single.bin 2>&1 | sed -n '50,80p' | head -20
echo ""
echo "NEW (after typed loads fix):"
riscv64-unknown-elf-objdump -D -b binary -m riscv:rv64 plic_single_NEWEST.bin 2>&1 | sed -n '50,80p' | head -20
