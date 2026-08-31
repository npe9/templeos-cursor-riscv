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
extern unsigned char _binary_ram_test_SD_bin_start[];
int main(void) {
    puts("\n══════ RAM R/W TEST (SD ONLY) ══════\n\n");
    volatile uint32_t *ram = (volatile uint32_t*)0x80500000;
    *ram = 0;
    puts("Before: 0\n\n");
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_ram_test_SD_bin_start))();
    uint32_t after = *ram;
    put('R'); put('A'); put('M'); put('=');
    for (int i = 7; i >= 0; i--) {
        uint8_t n = (after >> (i*4)) & 0xF;
        put(n < 10 ? '0'+n : 'A'+n-10);
    }
    put('\n'); put('R'); put('e'); put('t'); put('=');
    for (int i = 1; i >= 0; i--) {
        uint8_t n = (result >> (i*4)) & 0xF;
        put(n < 10 ? '0'+n : 'A'+n-10);
    }
    puts("\n\n");
    if (result == 99 && after == 99) {
        puts("✅✅✅ RAM R/W WORKS! ✅✅✅\n");
        puts("  Typed LOADS working (LWU)\n");
        puts("  SD stores working\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
