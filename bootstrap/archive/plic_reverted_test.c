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
extern unsigned char _binary_plic_single_REVERTED_bin_start[];
int main(void) {
    puts("\n══════ PLIC TEST (SD REVERTED) ══════\n\n");
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0;
    puts("Before: 0\n\n");
    puts("Cicl: U8 *plic = 0x0C000004; *plic = 7; (using SD)\n\n");
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_plic_single_REVERTED_bin_start))();
    uint32_t after = *plic;
    put('A'); put('f'); put('t'); put('e'); put('r'); put(':'); put(' ');
    put('0' + after); puts("\n\n");
    if (after == 7) {
        puts("✅ SD WORKS!\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
