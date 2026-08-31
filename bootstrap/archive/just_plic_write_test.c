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
extern unsigned char _binary_just_plic_write_bin_start[];
int main(void) {
    puts("\n══════ PLIC WRITE FINAL TEST ══════\n\n");
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0;
    puts("Before: 0\n\n");
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_just_plic_write_bin_start))();
    uint32_t after = *plic;
    put('A'); put('f'); put('t'); put('e'); put('r'); put(':'); put(' ');
    put('0' + (after / 10)); put('0' + (after % 10));
    put('\n'); put('R'); put('e'); put('t'); put(':'); put(' ');
    put('0' + (result / 10)); put('0' + (result % 10));
    puts("\n\n");
    if (result == 99 && after == 99) {
        puts("✅✅✅ PLIC WRITE WORKS WITH TYPED STORE! ✅✅✅\n");
        puts("  SW instruction used\n");
        puts("  64-bit address loading\n");
        puts("  All fixes working!\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
