#!/bin/bash
# Bootstrap Testing Script

set -e

echo "═══════════════════════════════════════════════════════════"
echo "TempleOS RISC-V Bootstrap Test Suite"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

COMPILER="../holyc-riscv"

# Check if compiler exists
if [ ! -f "$COMPILER" ]; then
    echo -e "${RED}✗ Compiler not found${NC}"
    echo "Run 'make' in parent directory first"
    exit 1
fi

echo -e "${GREEN}✓ Compiler found${NC}"
echo ""

# Test 1: Simple HolyC compilation
echo "Test 1: Simple HolyC file"
echo "─────────────────────────────────"
if $COMPILER test_simple.hc -o test_simple.bin > /dev/null 2>&1; then
    SIZE=$(stat -f%z test_simple.bin 2>/dev/null || stat -c%s test_simple.bin 2>/dev/null)
    echo -e "${GREEN}✓ Compiled successfully${NC} ($SIZE bytes)"
else
    echo -e "${RED}✗ Compilation failed${NC}"
    exit 1
fi
echo ""

# Test 2: Minimal runtime compilation
echo "Test 2: Minimal runtime library"
echo "─────────────────────────────────"
if $COMPILER minimal_runtime.hc -o minimal_runtime.bin 2>&1 | grep -q "Compiled successfully"; then
    SIZE=$(stat -f%z minimal_runtime.bin 2>/dev/null || stat -c%s minimal_runtime.bin 2>/dev/null)
    echo -e "${GREEN}✓ Compiled successfully${NC} ($SIZE bytes)"
else
    echo -e "${RED}✗ Compilation failed${NC}"
    exit 1
fi
echo ""

# Test 3: UART editor compilation
echo "Test 3: UART editor"
echo "─────────────────────────────────"
if $COMPILER uart_editor.hc -o uart_editor.bin 2>&1 | grep -q "Compiled successfully"; then
    SIZE=$(stat -f%z uart_editor.bin 2>/dev/null || stat -c%s uart_editor.bin 2>/dev/null)
    echo -e "${GREEN}✓ Compiled successfully${NC} ($SIZE bytes)"
else
    echo -e "${RED}✗ Compilation failed${NC}"
    exit 1
fi
echo ""

# Test 4: Self-hosting test (can compiler compile its own source?)
echo "Test 4: Self-hosting capability"
echo "─────────────────────────────────"
echo -e "${YELLOW}⚠ Self-hosting requires C→HC conversion${NC}"
echo "  Current: lexer.c, parser.c, compiler.c, hash_table.c"
echo "  Needed:  lexer.hc, parser.hc, compiler.hc, hash_table.hc"
echo ""
echo "  To test self-hosting:"
echo "  1. Convert C files to HolyC"
echo "  2. Compile with holyc-riscv"
echo "  3. Compare output with original compiler"
echo ""

# Test 5: Check RISC-V toolchain
echo "Test 5: RISC-V toolchain"
echo "─────────────────────────────────"
if command -v riscv64-unknown-elf-gcc &> /dev/null; then
    echo -e "${GREEN}✓ riscv64-unknown-elf-gcc found${NC}"
    HAS_TOOLCHAIN=true
elif command -v riscv64-linux-gnu-gcc &> /dev/null; then
    echo -e "${GREEN}✓ riscv64-linux-gnu-gcc found${NC}"
    HAS_TOOLCHAIN=true
else
    echo -e "${YELLOW}⚠ RISC-V toolchain not found${NC}"
    echo "  Install with: brew install riscv-gnu-toolchain (macOS)"
    echo "  Or: apt-get install gcc-riscv64-unknown-elf (Linux)"
    HAS_TOOLCHAIN=false
fi
echo ""

# Test 6: Check QEMU
echo "Test 6: QEMU emulator"
echo "─────────────────────────────────"
if command -v qemu-system-riscv64 &> /dev/null; then
    echo -e "${GREEN}✓ qemu-system-riscv64 found${NC}"
    HAS_QEMU=true
else
    echo -e "${YELLOW}⚠ QEMU RISC-V not found${NC}"
    echo "  Install with: brew install qemu (macOS)"
    echo "  Or: apt-get install qemu-system-misc (Linux)"
    HAS_QEMU=false
fi
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════"
echo "Bootstrap Test Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Core Functionality:"
echo -e "  ${GREEN}✓${NC} HolyC → RISC-V compiler works"
echo -e "  ${GREEN}✓${NC} Can compile runtime library"
echo -e "  ${GREEN}✓${NC} Can compile UART editor"
echo ""
echo "Next Steps for Full Bootstrap:"
echo ""
if [ "$HAS_TOOLCHAIN" = true ] && [ "$HAS_QEMU" = true ]; then
    echo "1. Build UART test:"
    echo "   cd bootstrap && make uart_test.elf"
    echo ""
    echo "2. Run in QEMU:"
    echo "   make qemu-test"
    echo ""
    echo "3. Build full bootstrap system (when ready):"
    echo "   make bootstrap.elf"
    echo ""
else
    echo "1. Install RISC-V toolchain (see Test 5 above)"
    echo "2. Install QEMU (see Test 6 above)"
    echo "3. Then run: cd bootstrap && make qemu-test"
    echo ""
fi
echo "4. Convert compiler C source to HolyC for self-hosting"
echo "5. Test full bootstrap on RISC-V hardware"
echo ""
echo "═══════════════════════════════════════════════════════════"


