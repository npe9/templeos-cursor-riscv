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
extern unsigned char _binary_test_params_bin_start[];
int main(void) {
    puts("\n═══════════════════════════════════════════════════════════\n");
    puts("  FUNCTION PARAMETERS TEST\n");
    puts("═══════════════════════════════════════════════════════════\n\n");
    puts("HolyC:\n");
    puts("  I64 Add(I64 a, I64 b) { return a + b; }\n");
    puts("  I64 Main() { return Add(5, 7); }\n\n");
    puts("Expected: 12\n\n");
    
    typedef int64_t (*f_t)(void);
    // Call Main() which is at offset 0x38
    int64_t result = ((f_t)(_binary_test_params_bin_start + 0x38))();
    
    puts("Result: ");
    print_num(result);
    puts("\n\n");
    
    if (result == 12) {
        puts("✅ ✅ ✅  SUCCESS!  ✅ ✅ ✅\n\n");
        puts("Function parameters work!\n");
        puts("RISC-V calling convention correct!\n\n");
    }
    
    puts("═══════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
