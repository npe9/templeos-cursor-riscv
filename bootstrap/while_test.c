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
extern unsigned char _binary_test_while_simple_bin_start[];
int main(void) {
    puts("\n✅ Testing while loop: count to 5\n\n");
    typedef int64_t (*f_t)(void);
    // Main at 0x11C
    int64_t result = ((f_t)(_binary_test_while_simple_bin_start + 0x11C))();
    puts("Result: ");
    put('0' + result);
    if (result == 5) puts("  ✅ WHILE LOOPS WORK!\n\n");
    else puts("  ❌\n\n");
    while (1) __asm__ volatile ("wfi");
}
