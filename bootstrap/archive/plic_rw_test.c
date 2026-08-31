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
extern unsigned char _binary_plic_rw_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  CICL PLIC READ & WRITE TEST\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0;  // Clear first
    
    puts("Running Cicl: write 42, read back, print to UART\n");
    puts("Expected output from Cicl: PLIC=0x2A\n\n");
    puts("Cicl output: ");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_plic_rw_bin_start))();
    
    puts("\n\nCicl returned: ");
    print_hex(result);
    puts("\n\n");
    
    // Verify
    uint32_t actual = *plic;
    puts("C reads PLIC after Cicl: ");
    print_hex(actual);
    puts("\n\n");
    
    if (actual == 42) {
        puts("✅ PLIC READ/WRITE WORKS!\n");
        puts("  Cicl wrote 42\n");
        puts("  Cicl read it back\n");
        puts("  C verified it\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
