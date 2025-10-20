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
extern unsigned char _binary_fresh_read_FINAL_bin_start[];
int main(void) {
    puts("\n══════ CICL TYPED READ TEST ══════\n\n");
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0x00000042;
    puts("C: PLIC = 0x42\n\n");
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_fresh_read_FINAL_bin_start))();
    put('R'); put(':'); put(' '); put('0'); put('x');
    put(((result>>4)&0xF) < 10 ? '0'+((result>>4)&0xF) : 'A'+((result>>4)&0xF)-10);
    put((result&0xF) < 10 ? '0'+(result&0xF) : 'A'+(result&0xF)-10);
    puts("\n\n");
    if (result == 0x42) {
        puts("✅ DEVICE READ WORKS!\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
