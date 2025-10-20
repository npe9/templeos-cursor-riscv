#!/bin/bash
# Test the integrated compiler

cd /Users/npe/src/templeos-cursor-riscv/bootstrap

echo "Building integrated kernel..."
make integrated.elf 2>&1 | tail -5

echo ""
echo "Testing integrated compiler in QEMU..."
echo "Will send: I64 Answer() { return 42; }"
echo ""

# Use expect to interact with QEMU
cat > /tmp/test_integrated.exp << 'EXPECT_SCRIPT'
#!/usr/bin/expect -f

set timeout 30
spawn qemu-system-riscv64 -M virt -bios none -kernel integrated.elf -nographic

expect ">" 
send "I64 Answer() { return 42; }\r"

expect ">"
send "END\r"

expect ">"
send "Answer\r"

expect ">"
send ":quit\r"

expect eof
EXPECT_SCRIPT

chmod +x /tmp/test_integrated.exp

if command -v expect &> /dev/null; then
    /tmp/test_integrated.exp
else
    echo "ERROR: 'expect' not installed"
    echo "Install with: brew install expect"
fi

rm -f /tmp/test_integrated.exp


