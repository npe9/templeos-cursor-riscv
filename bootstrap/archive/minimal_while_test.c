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
extern unsigned char _binary_test_minimal_while_bin_start[];
int main(void) {
    puts("\n✅ Testing minimal while loop\n\n");
    typedef int64_t (*f_t)(void);
    // Main at 0x0
    int64_t result = ((f_t)(_binary_test_minimal_while_bin_start))();
    puts("Result: ");
    put('0' + result);
    if (result == 3) {
        puts("  ✅ ✅ ✅  WHILE LOOPS WORK!\n\n");
        puts("This is a MAJOR breakthrough!\n");
        puts("While loops are fundamental for:\n");
        puts("  • String output\n");
        puts("  • Runtime functions\n");
        puts("  • All iterative algorithms\n\n");
    } else {
        puts("  ❌\n\n");
    }
    while (1) __asm__ volatile ("wfi");
}
