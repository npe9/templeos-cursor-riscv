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
extern unsigned char _binary_test_uart_direct_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  UART WRITE FROM HOLYC TEST\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("HolyC code:\n");
    puts("  U8 *uart = 0x10000000;\n");
    puts("  *uart = 72;  // 'H'\n\n");
    puts("Output from HolyC: ");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_test_uart_direct_bin_start))();
    
    puts("\n\nMain() returned: ");
    put('0' + (result / 10));
    put('0' + (result % 10));
    puts("\n\n");
    
    if (result == 42) {
        puts("✅ HOLYC EXECUTED!\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
