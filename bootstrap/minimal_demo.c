#include <stdint.h>
#define UART_BASE 0x10000000
static void uart_putc(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}
extern unsigned char _binary_minimal_bin_start[];
int main(void) {
    uart_putc('A');
    typedef int64_t (*f_t)(void);
    uart_putc('B');
    int64_t r = ((f_t)_binary_minimal_bin_start)();
    uart_putc('C');
    uart_putc('0' + (r & 0xF));
    uart_putc('\n');
    while (1) __asm__ volatile ("wfi");
}
