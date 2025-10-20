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
extern unsigned char _binary_test_ret_only_bin_start[];
int main(void) {
    puts("\n✅ Testing return only\n\n");
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_test_ret_only_bin_start))();
    puts("Result: ");
    if (result >= 10) {
        put('0' + (result / 10));
        put('0' + (result % 10));
    } else {
        put('0' + result);
    }
    puts("\n\n");
    while (1) __asm__ volatile ("wfi");
}
