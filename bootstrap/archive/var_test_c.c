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
extern unsigned char _binary_var_test_bin_start[];
int main(void) {
    puts("\n══ VAR TEST ══\n\n");
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_var_test_bin_start))();
    put('R'); put('=');
    for (int i = 7; i >= 0; i--) {
        uint8_t n = (result >> (i*4)) & 0xF;
        put(n < 10 ? '0'+n : 'A'+n-10);
    }
    puts("\n\n");
    if (result == 42) {
        puts("✅ Variables work!\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
