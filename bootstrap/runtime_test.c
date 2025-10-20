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
extern unsigned char _binary_minimal_templeos_runtime_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  TEMPLEOS RUNTIME TEST\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("Calling HolyC Main() with full runtime...\n\n");
    
    typedef int64_t (*f_t)(void);
    // Main is last function, try finding it
    // Runtime has ~10 functions, each ~200-300 bytes
    // Try offset 0xA00
    int64_t result = ((f_t)(_binary_minimal_templeos_runtime_bin_start + 0xA00))();
    
    put('R');
    put('=');
    put('0' + (result / 10));
    put('0' + (result % 10));
    put('\n');
    puts("\n════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
