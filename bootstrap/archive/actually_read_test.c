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
extern unsigned char _binary_actually_read_bin_start[];
int main(void) {
    puts("\n══════ ACTUAL READ TEST (U8*) ══════\n\n");
    volatile uint8_t *plic = (volatile uint8_t*)0x0C000004;
    *plic = 42;
    puts("C: PLIC[byte] = 42\n\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_actually_read_bin_start))();
    
    put('C'); put('i'); put('c'); put('l'); put(':'); put(' ');
    put('0' + (result / 10)); put('0' + (result % 10));
    puts("\n\n");
    
    if (result == 42) {
        puts("✅ U8 READ WORKS!\n\n");
    } else {
        puts("Wrong value\n\n");
    }
    
    while (1) __asm__ volatile ("wfi");
}
