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
extern unsigned char _binary_just_ptr_write_bin_start[];
int main(void) {
    puts("\n══ PTR WRITE TEST ══\n\n");
    volatile uint32_t *ram = (volatile uint32_t*)0x80500000;
    *ram = 0;
    puts("Before: 0\n");
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_just_ptr_write_bin_start))();
    uint32_t after = *ram;
    put('A'); put('f'); put('t'); put(':'); put(' ');
    put((after < 100) ? '0'+after : 'X');
    if (after >= 10) put('0' + (after % 10));
    put('\n'); put('R'); put('=');
    put((result < 100) ? '0'+result : 'X');
    if (result >= 10) put('0' + (result % 10));
    puts("\n\n");
    if (result == 99 && after == 99) {
        puts("✅ PTR WRITE WORKS!\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
