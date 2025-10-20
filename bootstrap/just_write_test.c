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
extern unsigned char _binary_just_write_bin_start[];
int main(void) {
    puts("\n══════ WRITE TEST ══════\n\n");
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0;
    puts("Before: 0\n");
    typedef int64_t (*f_t)(void);
    ((f_t)(_binary_just_write_bin_start))();
    puts("After: ");
    uint32_t val = *plic;
    put((val < 10) ? '0'+val : 'A'+val-10);
    puts("\n\n");
    if (val == 123) {
        puts("✅ Write still works!\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
