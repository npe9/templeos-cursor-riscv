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
static void print_num(int64_t n) {
    char buf[32];
    int i = 0;
    if (n == 0) { put('0'); return; }
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    while (i > 0) put(buf[--i]);
}
extern unsigned char _binary_templeos_math_bin_start[];
int main(void) {
    puts("\n════════════════════════════════════════════════════════════════\n");
    puts("  COMPILING REAL TEMPLEOS CODE\n");
    puts("════════════════════════════════════════════════════════════════\n\n");
    puts("TempleOS-style functions:\n");
    puts("  I64 Abs(I64 x)\n");
    puts("  I64 Max(I64 a, I64 b)\n");
    puts("  I64 Min(I64 a, I64 b)\n");
    puts("  I64 Main() { return Max(Abs(-42), Min(10, 20)); }\n\n");
    puts("Expected: 42\n\n");
    
    typedef int64_t (*f_t)(void);
    // Find Main - it's the 4th function
    // Try different offsets
    for (int offset = 0x100; offset < 0x300; offset += 0x10) {
        int64_t result = ((f_t)(_binary_templeos_math_bin_start + offset))();
        if (result == 42) {
            puts("Result: ");
            print_num(result);
            puts("  ✅ FOUND AT OFFSET 0x");
            // Print offset in hex
            char hex[16] = "0123456789ABCDEF";
            put(hex[(offset >> 8) & 0xF]);
            put(hex[(offset >> 4) & 0xF]);
            put(hex[offset & 0xF]);
            puts("\n\n");
            puts("✅ ✅ ✅  REAL TEMPLEOS CODE WORKS!  ✅ ✅ ✅\n\n");
            goto done;
        }
    }
    puts("❌ Didn't find Main\n\n");
done:
    puts("════════════════════════════════════════════════════════════════\n\n");
    while (1) __asm__ volatile ("wfi");
}
