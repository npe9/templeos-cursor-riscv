#!/bin/bash
# Demonstration script for TempleOS RISC-V UART Shell
# Shows example HolyC programs that can be entered interactively

cd "$(dirname "$0")"

echo "═══════════════════════════════════════════════════════════"
echo "  TempleOS RISC-V UART Shell - Example Programs"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "To run the UART shell:"
echo "  qemu-system-riscv64 -machine virt -bios none \\"
echo "    -device loader,file=stepping_debugger.elf,addr=0x80000000 \\"
echo "    -monitor none -serial mon:stdio -nographic"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 1: Basic Arithmetic"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE1'
42;
1 + 2 + 3;
10 * 5;
100 / 4;
EXAMPLE1

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 2: Function Definition"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE2'
I64 Answer() {
    return 42;
}
EXAMPLE2

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 3: Fibonacci Function"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE3'
I64 Fib(I64 n) {
    if (n <= 1) return n;
    return Fib(n - 1) + Fib(n - 2);
}
EXAMPLE3

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 4: Array Operations"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE4'
I64 SumArray(I64 *arr, I64 len) {
    I64 sum = 0;
    I64 i;
    for (i = 0; i < len; i++) {
        sum = sum + arr[i];
    }
    return sum;
}
EXAMPLE4

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 5: Preprocessor Macros"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE5'
#define MAX(a, b) ((a) > (b) ? (a) : (b))
I64 TestMax() {
    return MAX(10, 20);
}
EXAMPLE5

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 6: Enum Types"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE6'
enum Color {
    RED,
    GREEN,
    BLUE
};
I64 GetColor() {
    return BLUE;
}
EXAMPLE6

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 7: Class Definition"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE7'
class Point {
    I64 x;
    I64 y;
};
I64 PointDistance(Point *p1, Point *p2) {
    I64 dx = p1->x - p2->x;
    I64 dy = p1->y - p2->y;
    return dx * dx + dy * dy;
}
EXAMPLE7

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 8: sizeof Operator"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE8'
I64 TestSizeof() {
    return sizeof(I64) + sizeof(U8) + sizeof(F64);
}
EXAMPLE8

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 9: Control Flow"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE9'
I64 Factorial(I64 n) {
    if (n <= 1) return 1;
    return n * Factorial(n - 1);
}
EXAMPLE9

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Example 10: Bitwise Operations"
echo "═══════════════════════════════════════════════════════════"
cat << 'EXAMPLE10'
I64 BitwiseTest() {
    return (0x1234 & 0x5678) | (0xABCD ^ 0xEF00);
}
EXAMPLE10

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  To exit the REPL, type: quit"
echo "═══════════════════════════════════════════════════════════"

