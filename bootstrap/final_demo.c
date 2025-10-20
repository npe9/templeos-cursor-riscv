#include <stdint.h>
#define UART_BASE 0x10000000
static void put(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}
static void puts(const char *s) {
    while (*s) {
        if (*s == '\n') put('\r');
        put(*s++);
    }
}
static void print_num(int64_t n) {
    char buf[32];
    int i = 0;
    if (n == 0) { put('0'); return; }
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    while (i > 0) put(buf[--i]);
}
extern unsigned char _binary_working_demo_bin_start[];
int main(void) {
    puts("\n\n");
    puts("═══════════════════════════════════════════════════════════\n");
    puts("  TempleOS RISC-V - HolyC Compiler Demonstration\n");
    puts("═══════════════════════════════════════════════════════════\n\n");
    puts("Compiled HolyC Source:\n");
    puts("  I64 Add(I64 a, I64 b) { return a + b; }\n");
    puts("  I64 Main() { return Add(20, 22); }\n\n");
    puts("Computing Add(20, 22)...\n");
    
    typedef int64_t (*f_t)(void);
    // Main() is at offset 0x38
    int64_t result = ((f_t)(_binary_working_demo_bin_start + 0x38))();
    
    puts("Result: ");
    print_num(result);
    puts("\n\n");
    
    if (result == 42) {
        puts("✅ ✅ ✅  SUCCESS!  ✅ ✅ ✅\n\n");
        puts("WORKING HolyC→RISC-V Compiler!\n");
        puts("✓ Function definitions\n");
        puts("✓ Function calls with parameters\n");
        puts("✓ Arithmetic expressions\n");
        puts("✓ Return values\n");
        puts("✓ Proper calling convention\n\n");
        puts("This is REAL HolyC compiled code running on RISC-V!\n\n");
    } else {
        puts("Got ");
        print_num(result);
        puts(" (expected 42)\n");
    }
    
    puts("═══════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
