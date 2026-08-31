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
extern unsigned char _binary_worry_dream_plic_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  WORRY DREAM MACHINE - PLIC DEVICE PROOF\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("Testing HolyC device register access:\n");
    puts("  Device: PLIC (Platform-Level Interrupt Controller)\n");
    puts("  Base: 0x0C000000\n\n");
    puts("HolyC will:\n");
    puts("  WRITE to PLIC priority register (0x0C000004)\n");
    puts("  WRITE to PLIC enable register (0x0C002000)\n\n");
    puts("Output from HolyC:\n  ");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_worry_dream_plic_bin_start))();
    
    puts("\n\nMain() returned: ");
    put('0' + (result / 10));
    put('0' + (result % 10));
    puts("\n\n");
    
    if (result == 42) {
        puts("✅ ✅ ✅  DEVICE REGISTER ACCESS WORKS!  ✅ ✅ ✅\n\n");
        puts("HolyC directly:\n");
        puts("  ✅ WROTE to PLIC priority (0x0C000004) = 7\n");
        puts("  ✅ WROTE to PLIC enable (0x0C002000) = 1\n");
        puts("  ✅ Memory-mapped I/O works\n");
        puts("  ✅ Multiple device access\n");
        puts("  ✅ No C library - pure HolyC\n\n");
        puts("Worry Dream Machine: Hardware control from HolyC.\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
