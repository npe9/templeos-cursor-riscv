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
static void print_hex(uint32_t val) {
    put('0'); put('x');
    for (int i = 7; i >= 0; i--) {
        uint8_t nibble = (val >> (i * 4)) & 0xF;
        put(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    }
}
extern unsigned char _binary_simple_read_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  CICL DEVICE READ - Simple Test\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0x00000042;  // Set PLIC to known value
    
    puts("C code set PLIC[0x0C000004] = 0x00000042\n\n");
    puts("Running Cicl: val = *addr (where addr = 0x0C000004)...\n\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_simple_read_bin_start))();
    
    puts("Cicl returned: ");
    print_hex((uint32_t)result);
    puts("\n\n");
    
    if (result == 0x42) {
        puts("✅ CICL DEVICE READ WORKS!\n");
        puts("  Cicl read from PLIC register\n");
        puts("  Returned correct value: 0x42\n\n");
    } else {
        puts("❌ Wrong value: ");
        print_hex((uint32_t)result);
        puts("\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
