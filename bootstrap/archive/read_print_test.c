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
extern unsigned char _binary_read_and_print_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  CICL READ & PRINT TEST\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0x00000099;
    
    puts("C set PLIC[0x0C000004] = 0x99\n\n");
    puts("Running Cicl (reads PLIC, prints to UART):\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_read_and_print_bin_start))();
    
    puts("\n\nCicl returned: ");
    put('0'); put('x');
    uint8_t h = (result >> 4) & 0xF;
    put(h < 10 ? '0' + h : 'A' + h - 10);
    uint8_t l = result & 0xF;
    put(l < 10 ? '0' + l : 'A' + l - 10);
    puts("\n\n");
    
    if ((result & 0xFF) == 0x99) {
        puts("✅ CICL READ WORKS! Cicl read 0x99 from PLIC!\n\n");
    } else {
        puts("Read value mismatch\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
