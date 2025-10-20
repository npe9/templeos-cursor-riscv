#include <stdint.h>
#define UART_BASE 0x10000000
static void uart_putc(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20));
    *(volatile uint8_t*)UART_BASE = c;
}
static void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}
static void print_num(int64_t n) {
    char buf[32];
    int i = 0;
    if (n == 0) { uart_putc('0'); return; }
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    while (i > 0) uart_putc(buf[--i]);
}
extern unsigned char _binary_simple_math_bin_start[];
int main(void) {
    uart_puts("\n");
    uart_puts("═══════════════════════════════════════════════════════════\n");
    uart_puts("  HolyC→RISC-V Compiler Demonstration\n");
    uart_puts("═══════════════════════════════════════════════════════════\n\n");
    
    typedef int64_t (*f_t)(void);
    uart_puts("Calling Main()...\n");
    int64_t result = ((f_t)(_binary_simple_math_bin_start + 0x44))();
    
    uart_puts("Result: ");
    print_num(result);
    uart_puts("\n");
    
    if (result == 42) {
        uart_puts("\n✅  SUCCESS! Compiled HolyC works on RISC-V!\n\n");
    }
    
    uart_puts("═══════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
