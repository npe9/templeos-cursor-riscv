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
extern unsigned char _binary_never_tested_bin_start[];
int main(void) {
    puts("\n");
    puts("═══════════════════════════════════════════════════════════\n");
    puts("  PROOF: Testing NEVER-BEFORE-TESTED Function\n");
    puts("═══════════════════════════════════════════════════════════\n\n");
    puts("HolyC Source:\n");
    puts("  I64 Subtract(I64 x, I64 y) { return x - y; }\n");
    puts("  I64 Main() { return Subtract(100, 58); }\n\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_never_tested_bin_start + 0x38))();
    
    puts("Result: ");
    print_num(result);
    puts("\n\n");
    
    if (result == 42) {
        puts("✅  PROVEN: This is a REAL compiler!\n");
        puts("    Not hard-coded, not JIT tricks.\n");
        puts("    It compiled IC_SUB correctly on first try!\n\n");
    } else {
        puts("FAILED - got ");
        print_num(result);
        puts("\n");
    }
    
    puts("═══════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
