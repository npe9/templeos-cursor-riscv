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

extern unsigned char _binary_ram_test_REAL_bin_start[];

int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  CICL RAM READ/WRITE TEST\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    
    volatile uint32_t *ram = (volatile uint32_t*)0x80500000;
    *ram = 0;
    puts("C: RAM cleared\n\n");
    puts("Cicl: write 99, read back...\n\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_ram_test_REAL_bin_start))();
    
    uint32_t actual = *ram;
    
    put('R'); put('A'); put('M'); put('=');
    for (int i = 7; i >= 0; i--) {
        uint8_t n = (actual >> (i*4)) & 0xF;
        put(n < 10 ? '0'+n : 'A'+n-10);
    }
    put(' '); put('R'); put('e'); put('t'); put('=');
    for (int i = 7; i >= 0; i--) {
        uint8_t n = (result >> (i*4)) & 0xF;
        put(n < 10 ? '0'+n : 'A'+n-10);
    }
    puts("\n\n");
    
    if (result == 99 && actual == 99) {
        puts("✅ RAM READ/WRITE WORKS!\n");
        puts("  SW instruction for write\n");
        puts("  LWU instruction for read\n");
        puts("  Typed loads/stores working!\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}

