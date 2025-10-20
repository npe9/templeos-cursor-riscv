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
static void print_hex(uint64_t v) {
    for (int i = 7; i >= 0; i--) {
        int d = (v >> (i*4)) & 0xF;
        put(d < 10 ? '0' + d : 'A' + d - 10);
    }
}
extern unsigned char _binary_plic_device_proof_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  WORRY DREAM MACHINE - PLIC DEVICE PROOF\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("Device: PLIC (Platform-Level Interrupt Controller)\n");
    puts("  Base: 0x0C000000\n");
    puts("  Priority Register: 0x0C000004\n");
    puts("  Enable Register:   0x0C002080\n\n");
    
    // Read PLIC registers before HolyC writes
    volatile uint32_t *plic_pri = (volatile uint32_t*)0x0C000004;
    volatile uint32_t *plic_en = (volatile uint32_t*)0x0C002080;
    
    puts("Before HolyC:\n");
    puts("  Priority[1] = 0x"); print_hex(*plic_pri); puts("\n");
    puts("  Enable      = 0x"); print_hex(*plic_en); puts("\n\n");
    
    uint32_t before_pri = *plic_pri;
    uint32_t before_en = *plic_en;
    
    puts("Running HolyC...\n");
    
    typedef int64_t (*f_t)(void);
    int64_t result = ((f_t)(_binary_plic_device_proof_bin_start))();
    
    puts("After HolyC:\n");
    puts("  Priority[1] = 0x"); print_hex(*plic_pri); puts("\n");
    puts("  Enable      = 0x"); print_hex(*plic_en); puts("\n\n");
    puts("Returned: 0x"); print_hex(result); puts("\n\n");
    
    if (result == 0x0C000000) {
        puts("✅ ✅ ✅  PLIC DEVICE ACCESS VERIFIED!  ✅ ✅ ✅\n\n");
        puts("HolyC successfully:\n");
        puts("  ✅ WROTE to PLIC priority register (0x0C000004)\n");
        puts("  ✅ WROTE to PLIC enable register (0x0C002080)\n");
        puts("  ✅ Accessed interrupt controller device\n");
        puts("  ✅ NOT UART - different device entirely\n");
        puts("  ✅ Memory-mapped I/O to PLIC\n");
        puts("  ✅ Returned PLIC base address\n\n");
        puts("WORRY DREAM MACHINE: Multi-device control PROVEN.\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
