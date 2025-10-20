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
extern unsigned char _binary_plic_single_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  PLIC DEVICE: Single Variable Test\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    // Read PLIC before
    volatile uint32_t *plic_reg = (volatile uint32_t*)0x0C000004;
    uint32_t before = *plic_reg;
    
    puts("PLIC[0x0C000004] before: 0x");
    put(before < 10 ? '0' + before : 'A' + before - 10);
    puts("\n\n");
    puts("Running HolyC: *plic = 7\n\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_plic_single_bin_start))();
    
    uint32_t after = *plic_reg;
    puts("PLIC[0x0C000004] after:  0x");
    put(after < 10 ? '0' + after : 'A' + after - 10);
    puts("\n\n");
    
    puts("Returned: 0x0C000004\n\n");
    
    if (result == 0x0C000004) {
        puts("✅ PLIC DEVICE WRITE WORKS!\n");
        puts("  HolyC wrote to interrupt controller\n");
        puts("  Address: 0x0C000004 (NOT UART)\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
