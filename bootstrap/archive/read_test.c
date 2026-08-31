#include <stdint.h>
#define UART_BASE 0x10000000
#define PLIC_BASE 0x0C000000

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

extern unsigned char _binary_read_devices_bin_start[];

int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  CICL DEVICE READ TEST\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    // Set PLIC registers to known values first
    volatile uint32_t *plic_priority = (volatile uint32_t*)0x0C000004;
    volatile uint32_t *plic_enable = (volatile uint32_t*)0x0C002080;
    
    *plic_priority = 0x00000005;  // Set priority to 5
    *plic_enable = 0x00000002;    // Enable interrupt 1
    
    puts("C code set PLIC registers:\n");
    puts("  Priority[1] = 0x00000005\n");
    puts("  Enable      = 0x00000002\n\n");
    
    puts("Running Cicl to READ devices...\n");
    puts("Cicl output: ");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_read_devices_bin_start))();
    
    puts("\n\nCicl returned: ");
    print_hex((uint32_t)result);
    puts("\n\n");
    
    // Verify by reading again from C
    uint32_t c_priority = *plic_priority;
    uint32_t c_enable = *plic_enable;
    
    puts("C code reads after Cicl:\n");
    puts("  Priority[1] = ");
    print_hex(c_priority);
    puts("\n");
    puts("  Enable      = ");
    print_hex(c_enable);
    puts("\n\n");
    
    if (result == 0x05) {
        puts("✅ CICL READ WORKS!\n");
        puts("  Cicl read PLIC priority register\n");
        puts("  Returned correct value: 0x05\n");
        puts("  Printed values to UART\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}


