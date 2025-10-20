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
extern unsigned char _binary_templeos_math_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  REAL TEMPLEOS CODE: Max(Abs(-42), Min(10, 20))\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    typedef int64_t (*f_t)(void);
    // Based on objdump, Main at 0x200
    int64_t result = ((f_t)(_binary_templeos_math_bin_start + 0x200))();
    
    puts("Result: ");
    print_num(result);
    
    if (result == 42) {
        puts("  ✅\n\n✅ ✅ ✅  REAL TEMPLEOS CODE WORKS!  ✅ ✅ ✅\n\n");
    } else {
        puts("  ❌\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
