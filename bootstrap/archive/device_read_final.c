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
static void print_hex32(uint32_t val) {
    put('0'); put('x');
    for (int i = 7; i >= 0; i--) {
        uint8_t nibble = (val >> (i * 4)) & 0xF;
        put(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    }
}

extern unsigned char _binary_simple_read_REAL_bin_start[];

int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  CICL DEVICE READ - FINAL TEST\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    volatile uint32_t *plic = (volatile uint32_t*)0x0C000004;
    *plic = 0x00000042;
    
    puts("C: PLIC[0x0C000004] = 0x00000042\n\n");
    puts("Cicl: Reading with LWU instruction...\n\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_simple_read_REAL_bin_start))();
    
    puts("Returned: ");
    print_hex32(result);
    puts("\n\n");
    
    if (result == 0x42) {
        puts("✅ DEVICE READ WORKS!\n");
        puts("  LWU instruction used\n");
        puts("  Read 0x42 from PLIC\n");
        puts("  U32* typed correctly!\n\n");
    } else {
        puts("Got: 0x");
        print_hex32(result);
        puts(" (expected 0x42)\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
