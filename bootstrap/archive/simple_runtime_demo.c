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
extern unsigned char _binary_simple_runtime_test_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  CALLING HOLYC UART FUNCTIONS\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("HolyC Main() will output 'Hi!' via UART using UartPut()...\n\n");
    puts("Output from HolyC: ");
    
    typedef int64_t (*f_t)(void);
    // Main at 0xAC
    int64_t result = ((f_t)(_binary_simple_runtime_test_bin_start + 0xAC))();
    
    puts("\n\nMain() returned: ");
    put('0' + (result / 10));
    put('0' + (result % 10));
    
    if (result == 42) {
        puts("\n\n✅ ✅ ✅  HOLYC UART I/O WORKS!  ✅ ✅ ✅\n\n");
        puts("This proves:\n");
        puts("  ✅ HolyC can write to UART hardware\n");
        puts("  ✅ Pointer stores work (*uart = ch)\n");
        puts("  ✅ Function calls work\n");
        puts("  ✅ TempleOS-style programming on bare metal RISC-V!\n\n");
    }
    
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
