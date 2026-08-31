#!/bin/bash
# Simple test to verify QEMU UART output

cd "$(dirname "$0")"

echo "Testing QEMU UART output..."
echo "Sending: 42;"
echo ""

# Create input file
cat > /tmp/qemu_input.txt <<EOF
42;
quit
EOF

# Run QEMU with input redirection and capture output
timeout 5s qemu-system-riscv64 \
  -machine virt \
  -bios none \
  -kernel stepping_debugger.elf \
  -monitor none \
  -serial mon:stdio \
  -nographic \
  < /tmp/qemu_input.txt 2>&1 | tee /tmp/qemu_output.txt

echo ""
echo "=== QEMU Output ==="
cat /tmp/qemu_output.txt
echo ""

rm -f /tmp/qemu_input.txt /tmp/qemu_output.txt




