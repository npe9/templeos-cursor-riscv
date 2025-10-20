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
extern unsigned char _binary_plic_read_LD_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  CICL PLIC READ - LD ONLY\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0x00000042;
    puts("C: PLIC = 0x42\n\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_plic_read_LD_bin_start))();
    
    put('R'); put(':'); put(' '); put('0'); put('x');
    for (int i = 7; i >= 0; i--) {
        uint8_t n = (result >> (i*4)) & 0xF;
        put(n < 10 ? '0'+n : 'A'+n-10);
    }
    puts("\n\n");
    
    if (result == 0x42) {
        puts("✅ DEVICE READ WORKS WITH LD!\n\n");
    } else {
        puts("Still wrong\n\n");
    }
    
    while (1) __asm__ volatile ("wfi");
}
