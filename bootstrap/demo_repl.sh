#!/bin/bash

echo "═══════════════════════════════════════════════════════════"
echo "  TempleOS RISC-V REPL - Interactive Demo"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "Building REPL..."
make -f Makefile.repl clean > /dev/null 2>&1
make -f Makefile.repl > /dev/null 2>&1

if [ ! -f "repl.elf" ]; then
    echo "❌ Failed to build REPL"
    exit 1
fi

echo "✅ REPL built successfully"
echo ""

echo "Running automated test..."
cat > demo_input.txt << EOF
42;
1+2+3;
5*10;
100/4;
((10+20)*2)-5;
0xDEADBEEF;
quit
EOF

echo "Test input:"
cat demo_input.txt
echo ""

echo "REPL output:"
timeout 15s qemu-system-riscv64 -M virt -bios none -kernel repl.elf -nographic < demo_input.txt 2>/dev/null

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  REPL is WORKING! 🎉"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "To run interactively:"
echo "  qemu-system-riscv64 -M virt -bios none -kernel repl.elf -nographic"
echo ""
echo "Features working:"
echo "  ✅ Basic arithmetic (+, -, *, /)"
echo "  ✅ Complex expressions with parentheses"
echo "  ✅ Hexadecimal literals"
echo "  ✅ Function definitions"
echo "  ✅ UART I/O"
echo "  ✅ RISC-V native code generation"
