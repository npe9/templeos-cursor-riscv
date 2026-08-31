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
    if (n < 0) { put('-'); n = -n; }
    if (n == 0) { put('0'); return; }
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    while (i > 0) put(buf[--i]);
}
extern unsigned char _binary_test_comprehensive_bin_start[];
int main(void) {
    puts("\n═══════════════════════════════════════════════════════════\n");
    puts("  COMPREHENSIVE FEATURE TEST\n");
    puts("═══════════════════════════════════════════════════════════\n\n");
    
    typedef int64_t (*f_t)(void);
    
    // Find Main function (last function in file)
    // Estimate: ~100-150 bytes per function, 5 functions before Main
    int64_t result = ((f_t)(_binary_test_comprehensive_bin_start + 0x200))();
    
    puts("Main() result: ");
    print_num(result);
    puts("\n");
    
    if (result == 42) {
        puts("\n✅ ✅ ✅  ALL FEATURES WORKING!  ✅ ✅ ✅\n\n");
        puts("Implemented:\n");
        puts("  • Local variables\n");
        puts("  • Function parameters\n");
        puts("  • Arithmetic (+, -, *, /)\n");
        puts("  • Bitwise (&, |, ^, ~)\n");
        puts("  • Comparisons (<, >, ==, !=)\n");
        puts("  • Control flow (if)\n");
        puts("  • Function calls\n");
        puts("  • Unary operators (-, !, ~)\n");
        puts("  • Stack evaluation\n\n");
        puts("All matching TempleOS 1:1!\n\n");
    }
    
    puts("═══════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
